import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FilterQuality, Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../engine/game_resource_manager.dart';
import '../engine/project_source.dart';
import '../engine_compat/coords.dart' show chunkWorld, screenParallelYaw;
import '../level/construction_model.dart';
import '../level/level_baker.dart';
import '../level/level_loader.dart';
import '../models/model_scene.dart';
import '../models/project_meta.dart';
import '../render/engine_node.dart';
import '../scene/model_renderer.dart';
import '../services/gltf_asset_store.dart';
import '../services/texture_cache.dart';
import 'controllers/camera_controller.dart';
import 'controllers/first_person_camera_controller.dart';
import 'controllers/fly_camera_controller.dart';
import 'controllers/orbit_camera_controller.dart';
import 'dynamics/dynamic_nodes.dart';
import 'geometry/line_geometry.dart';
import 'geometry/wireframe.dart';
import 'level_bake_options.dart';
import 'materials/scene_material.dart';
import 'materials/shader_material.dart';
import 'nodes/group_node.dart';
import 'nodes/gizmo.dart';
import 'nodes/light_node.dart';
import 'nodes/mechanisms.dart';
import 'nodes/model_node.dart';
import 'nodes/primitives.dart';
import 'nodes/scene_node.dart';
import 'nodes/skybox_node.dart';
import 'picking.dart';
import 'quality/quality_controller.dart';
import 'quality/quality_settings.dart';
import 'resources/scene_resources.dart';
import 'scene_fog.dart';
import 'scene_layer.dart';
import 'scene_load_status.dart';

/// A frame callback: [elapsed] is the total time since the first frame,
/// [deltaSeconds] the time since the previous one.
typedef SceneFrameListener = void Function(
  Duration elapsed,
  double deltaSeconds,
);

/// The scene controller: owns the node registry, the resource session, the
/// document, the active camera and the frame loop.
///
/// Applications create one controller, `open` a project into it, add nodes
/// and place a `SceneViewport` in the widget tree. The controller is a
/// [ChangeNotifier] for interface updates.
class SceneController extends ChangeNotifier implements SceneNodeHost {
  SceneController({this.mergeStatic = true}) {
    cameraNode.attachToHost(this);
  }

  /// Whether static document geometry is merged by material when the scene is
  /// built (games) or kept per face (the editor).
  final bool mergeStatic;

  /// The node the camera is attached to; effect nodes may be parented to it.
  final GroupNode cameraNode = GroupNode(id: 'camera', name: 'camera');

  final ShaderLibrary _shaders = ShaderLibrary();

  /// The `.fmat` shader library of this controller.
  ShaderLibrary get shaders => _shaders;

  // ── session ──────────────────────────────────────────────────────────

  SceneResources? _resources;
  ProjectStore? _project;
  GameResourceManager? _manager;
  SceneLoadStatus _status = const SceneLoadStatus();
  ModelData? _model;
  String? _modelId;
  int _revision = 0;

  /// The current loading status (phase, progress, errors).
  SceneLoadStatus get status => _status;

  /// The opened resource session, or null before [open].
  SceneResources? get resources => _resources;

  /// Model write operations of the project (create, save, delete, rename).
  ProjectStore get project => _project ??= ProjectStore(_resources);

  /// The current document, or null when no model is loaded.
  ModelData? get model => _model;

  /// The id of the current document, or null.
  String? get modelId => _modelId;

  /// Grows on every [rebuild]; the editor uses it to know when to re-sync.
  int get revision => _revision;

  /// Opens a project: reads `project.json`, `models/*.json`, the resource
  /// catalogs and the glTF catalog. Errors are collected in [status].
  Future<void> open(ProjectSource source) async {
    _setStatus(SceneLoadPhase.project, 0.1, 'Проект');
    final manager = GameResourceManager(source);
    try {
      await manager.open();
      _manager = manager;
      _resources = SceneResources(manager);
      _project = ProjectStore(_resources);
      await _project!.loadMeta();
      _shaders.dispose();
      _finishLoad();
    } catch (error) {
      _fail(source.label, error);
    }
  }

  /// Creates a `project_v1` folder at [directory] (writes `project.json`)
  /// and opens it. Returns true when the project opened successfully.
  Future<bool> createProject(
    Directory directory, {
    required String name,
  }) async {
    try {
      directory.createSync(recursive: true);
      final source = DirectoryProjectSource(directory);
      final clean = name.trim();
      final json = <String, Object?>{
        'format': projectFormatV1,
        'name': clean.isEmpty ? 'project' : clean,
        'created': DateTime.now().toUtc().toIso8601String(),
      };
      await source.writeText(
        'project.json',
        const JsonEncoder.withIndent('  ').convert(json),
      );
      await open(source);
      return _status.isReady;
    } catch (error) {
      _fail(directory.path, error);
      return false;
    }
  }

  /// Re-reads `project.json` and the resource catalogs of the opened project.
  Future<void> openProject() async {
    final manager = _manager;
    if (manager == null) return;
    _setStatus(SceneLoadPhase.project, 0.1, 'Проект');
    try {
      await manager.openProject();
      _finishLoad();
    } catch (error) {
      _fail(manager.source.label, error);
    }
  }

  /// Re-reads `models/*.json` of the opened project.
  Future<void> openModels() async {
    final manager = _manager;
    if (manager == null) return;
    _setStatus(SceneLoadPhase.models, 0.3, 'Модели');
    try {
      await manager.openModels();
      _finishLoad();
    } catch (error) {
      _fail(manager.source.label, error);
    }
  }

  /// Loads the model with [id] from the catalog into the document.
  Future<bool> loadModel(String id) async {
    final data = _resources?.model(id);
    if (data == null) return false;
    loadModelData(data, id: id);
    return true;
  }

  /// Loads an in-memory document. The scene rebuilds synchronously.
  void loadModelData(ModelData data, {String? id}) {
    _model = data;
    _modelId = id ?? data.id;
    rebuild();
  }

  /// Clears the current document.
  void unloadModel() {
    _model = null;
    _modelId = null;
    rebuild();
  }

  /// Drops cached textures and glTF imports and re-reads the model catalog.
  void reloadResources() {
    final resources = _resources;
    if (resources == null) return;
    resources.invalidate();
    unawaited(resources.manager.reloadModels().then((_) => rebuild()));
    rebuild();
  }

  /// Marks the scene content as rebuilt and bumps [revision]. Rebuilds the
  /// document renderer when the render scene exists.
  void rebuild() {
    final model = _model;
    final renderer = _renderer;
    if (model != null && renderer != null) {
      renderer.rebuild(model);
    }
    _syncDocumentNodes();
    _refreshWireframes();
    _revision++;
    notifyListeners();
  }

  /// Refreshes the render transforms of the document's solid objects without
  /// rebuilding their geometry — the fast path for move/rotate drags. Baked
  /// content (csg, rounded cuboids, model/gltf instances, sprites) keeps its
  /// old placement until the next [rebuild]; callers that may drag such
  /// objects should call [rebuild] instead. Bumps [revision].
  void refreshObjectTransforms() {
    final model = _model;
    final renderer = _renderer;
    if (model == null || renderer == null) return;
    renderer.updateObjectTransforms(model);
    // Wireframes are built in world space: they must follow the moved
    // objects too.
    _refreshWireframes();
    _revision++;
    notifyListeners();
  }

  /// The live `ModelNode` wrappers of the current document, keyed by object
  /// id. Document objects are rendered by the renderer, so their nodes are
  /// virtual: they take part in picking and `nodesOfType` but carry no
  /// engine content of their own.
  final Map<String, ModelNode> _documentNodes = {};

  /// Reconciles the document-object wrappers with the current model: keeps
  /// the node identity while the object instance stays, drops the rest.
  void _syncDocumentNodes() {
    final model = _model;
    if (model == null) {
      if (_documentNodes.isEmpty) return;
      final stale = _documentNodes.values.toList();
      _documentNodes.clear();
      for (final node in stale) {
        node.dispose();
      }
      return;
    }
    final alive = <String>{};
    for (final object in model.objects) {
      alive.add(object.id);
      final existing = _documentNodes[object.id];
      if (existing != null && identical(existing.object, object)) continue;
      existing?.dispose();
      _documentNodes[object.id] = ModelNode(this, model, object);
    }
    _documentNodes.removeWhere((id, node) {
      if (alive.contains(id)) return false;
      node.dispose();
      return true;
    });
  }

  void _setStatus(SceneLoadPhase phase, double fraction, String label) {
    _status = SceneLoadStatus(
      phase: phase,
      fraction: fraction,
      label: label,
      errors: _status.errors,
    );
    notifyListeners();
  }

  void _finishLoad() {
    final errors = <SceneLoadError>[
      for (final reason in _manager?.loadErrors ?? const <String>[])
        SceneLoadError(resource: 'models', reason: reason),
    ];
    _status = SceneLoadStatus(
      phase: SceneLoadPhase.ready,
      fraction: 1,
      label: 'Готово',
      errors: errors,
    );
    notifyListeners();
  }

  void _fail(String resource, Object error) {
    _status = SceneLoadStatus(
      phase: SceneLoadPhase.error,
      label: 'Ошибка загрузки',
      errors: [
        ..._status.errors,
        SceneLoadError(resource: resource, reason: '$error'),
      ],
    );
    notifyListeners();
  }

  // ── nodes ────────────────────────────────────────────────────────────

  final List<SceneNode> _roots = [];
  final Map<String, SceneNode> _byId = {};

  /// The root nodes of the controller.
  List<SceneNode> get nodes => List.unmodifiable(_roots);

  /// Whether any attached node renders on the [SceneLayer.overlay] layer.
  /// The viewport uses it to add a service view automatically.
  bool get hasOverlayContent => _hasLayerContent(SceneLayer.overlay);

  /// Whether any attached node renders on the [SceneLayer.top] layer (gizmos,
  /// wireframes). The viewport uses it to add a service view automatically.
  bool get hasTopContent => _hasLayerContent(SceneLayer.top);

  bool _hasLayerContent(int layer) {
    for (final node in _byId.values) {
      if (node.layer & layer != 0) return true;
    }
    return false;
  }

  // ── wireframe ────────────────────────────────────────────────────────

  WireframeStyle? _wireframeStyle;

  /// The scene-wide wireframe style, or null when it is off. Individual
  /// nodes override it with [SceneNode.wireframe]; document faces add their
  /// own edges through [ModelNode.setFaceWireframe].
  WireframeStyle? get wireframeStyle => _wireframeStyle;

  /// Shows or hides the whole-scene wireframe ([style] null turns it off).
  /// The lines render with a constant screen-pixel thickness on the top
  /// layer, so they stay visible through the scene.
  void setWireframe(WireframeStyle? style) {
    if (_wireframeStyle == style) return;
    _wireframeStyle = style;
    _refreshWireframes();
    notifyListeners();
  }

  static const String _wireframeNodePrefix = 'wireframe:';
  final Map<String, LineNode> _wireframeNodes = {};
  GroupNode? _wireframeRoot;

  bool _isWireframeNode(SceneNode node) =>
      node.id.startsWith(_wireframeNodePrefix);

  void _refreshWireframes() {
    // Document `ModelNode`s are virtual (no host), so their disposal never
    // reaches `_dropNodeWireframe`; prune every tracked id that is not part
    // of the current scene here — otherwise wireframes of objects from
    // previous scenes stay on screen forever.
    final live = <String>{
      for (final node in nodesOfType<SceneNode>())
        if (!_isWireframeNode(node)) node.id,
    };
    for (final id in List.of(_wireframeNodes.keys)) {
      if (!live.contains(id)) {
        _wireframeNodes.remove(id)?.remove();
      }
    }
    for (final node in nodesOfType<SceneNode>()) {
      if (_isWireframeNode(node)) continue;
      _refreshNodeWireframe(node);
    }
    _pruneWireframeRoot();
  }

  /// Rebuilds the wireframe overlay of [node] from its current style and
  /// geometry. Plumbing for nodes and document edits.
  @internal
  void refreshWireframe(SceneNode node) => _refreshNodeWireframe(node);

  void _refreshNodeWireframe(SceneNode node) {
    final style = node.wireframe ?? _wireframeStyle;
    final segments = style == null && !node.hasWireframe
        ? const <vm.Vector3>[]
        : node.wireframeSegments(
            creaseAngleDegrees: style?.creaseAngle,
            all: style != null,
          );
    final existing = _wireframeNodes[node.id];
    if (segments.isEmpty) {
      if (existing != null) {
        _wireframeNodes.remove(node.id);
        existing.remove();
        _pruneWireframeRoot();
      }
      return;
    }
    final effective = style ?? const WireframeStyle();
    // World-space endpoints: document parts are already world-space, API
    // nodes carry their own transform.
    final transform = node.globalTransform;
    final world = <vm.Vector3>[
      for (final point in segments) transform.transform3(point),
    ];
    existing?.remove();
    final line = LineNode(
      id: '$_wireframeNodePrefix${node.id}',
      geometry: LineGeometry(world, widthPx: effective.thickness),
      color: effective.color,
    );
    line.layer = effective.throughGeometry
        ? SceneLayer.top
        : SceneLayer.base;
    _wireframeNodes[node.id] = line;
    _ensureWireframeRoot().add(line);
  }

  GroupNode _ensureWireframeRoot() {
    final existing = _wireframeRoot;
    if (existing != null) return existing;
    final root = GroupNode(id: 'wireframes', layer: SceneLayer.top);
    _wireframeRoot = root;
    add(root);
    return root;
  }

  void _pruneWireframeRoot() {
    if (_wireframeNodes.isNotEmpty) return;
    final root = _wireframeRoot;
    if (root == null) return;
    _wireframeRoot = null;
    root.remove();
  }

  void _dropNodeWireframe(SceneNode node) {
    final line = _wireframeNodes.remove(node.id);
    if (line == null) return;
    line.remove();
    _pruneWireframeRoot();
  }

  // ── gizmos ───────────────────────────────────────────────────────────

  final List<GizmoNode> _gizmos = [];
  GizmoNode? _activeGizmo;

  /// The gizmos attached to the scene.
  List<GizmoNode> get gizmos => List.unmodifiable(_gizmos);

  /// Adds [gizmo] to the scene (it draws on the top layer and is hit-tested
  /// before every scene object).
  T addGizmo<T extends GizmoNode>(T gizmo) {
    _gizmos.add(gizmo);
    return add(gizmo);
  }

  /// Removes and disposes [gizmo].
  void removeGizmo(GizmoNode gizmo) {
    _gizmos.remove(gizmo);
    if (identical(_activeGizmo, gizmo)) _activeGizmo = null;
    gizmo.remove();
  }

  /// The gizmo handle under [screenPoint], or null. Gizmos take priority
  /// over every scene object: the test is screen-space and depth-independent,
  /// so an object in front of the gizmo never steals the tap.
  GizmoHit? hitGizmo(Offset screenPoint) {
    for (final gizmo in _gizmos.reversed) {
      final hit = gizmo.hitTest(screenPoint);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Starts dragging the gizmo handle under [screenPoint]; returns the hit
  /// (null when no handle is under the pointer).
  GizmoHit? beginGizmoDrag(Offset screenPoint) {
    final hit = hitGizmo(screenPoint);
    if (hit == null) return null;
    _activeGizmo = hit.gizmo;
    hit.gizmo.beginDrag(hit.axis, screenPoint);
    return hit;
  }

  /// Advances the active gizmo drag to [screenPoint].
  void updateGizmoDrag(Offset screenPoint) {
    _activeGizmo?.updateDrag(screenPoint);
  }

  /// Ends the active gizmo drag.
  void endGizmoDrag() {
    _activeGizmo?.endDrag();
    _activeGizmo = null;
  }

  /// Keeps every gizmo at its constant screen size for the current camera.
  void _updateGizmos() {
    if (_gizmos.isEmpty) return;
    final camera = _renderCamera;
    final size = _viewportSize;
    if (camera == null || size.isEmpty) return;
    final pixelScale = _screenPixelScale();
    final cameraPosition = camera.position;
    for (final gizmo in _gizmos) {
      gizmo.followTarget();
      final distance = (gizmo.anchor - cameraPosition).length;
      gizmo.applyScreenScale(
        gizmo.style.length * pixelScale * math.max(distance, 1e-3),
      );
    }
  }

  /// Adds [node] to the scene and returns it.
  T add<T extends SceneNode>(T node) {
    node.attachToHost(this);
    return node;
  }

  /// Removes and disposes [node].
  void remove(SceneNode node) => node.remove();

  /// The node with [id], or null. Document objects resolve to their
  /// `ModelNode` wrappers too.
  SceneNode? byId(String id) => _byId[id] ?? _documentNodes[id];

  /// Every attached node of type [T] (document `ModelNode`s included).
  Iterable<T> nodesOfType<T extends SceneNode>() {
    final seen = <String>{};
    final all = <SceneNode>[
      ..._byId.values,
      ..._documentNodes.values,
    ].where((node) => seen.add(node.id));
    return all.whereType<T>();
  }

  @override
  void onNodeAttached(SceneNode node) {
    // A feature's async build may attach nodes after the controller was
    // disposed (scene switch); the frame must not abort on it.
    if (_disposed) return;
    _byId[node.id] = node;
    if (node.parent == null && !_roots.contains(node)) {
      _roots.add(node);
    }
    final scene = _scene;
    if (scene != null) {
      node.syncToEngine();
      if (node.parent == null && !identical(node, cameraNode)) {
        scene.add(node.engine.raw);
      }
      if (node is LightNode) _applyLightBudget();
    }
    if (!_isWireframeNode(node) &&
        (node.hasWireframe || _wireframeStyle != null)) {
      _refreshNodeWireframe(node);
    }
    notifyListeners();
  }

  @override
  void onNodeDetached(SceneNode node) {
    if (_disposed) return;
    _byId.remove(node.id);
    _roots.remove(node);
    _dropNodeWireframe(node);
    // Only the subtree root is mounted directly under the render scene;
    // descendants stay attached to their parent's engine node. Detaching
    // every descendant here would desync the engine mirror from the API
    // tree (the parent keeps the child in `children`) and the next
    // `unlinkChild` would throw «Child is not attached to this node».
    if (_scene != null &&
        node.parent == null &&
        node.engine.raw.parent != null) {
      node.engine.raw.detach();
    }
    notifyListeners();
  }

  @override
  void onNodeChanged(SceneNode node) {
    if (_disposed) return;
    if (_scene != null) {
      node.syncToEngine();
      if (node is LightNode) _applyLightBudget();
    }
    if (!_isWireframeNode(node) &&
        (node.hasWireframe || _wireframeStyle != null)) {
      _refreshNodeWireframe(node);
    }
    notifyListeners();
  }

  @override
  void onNodeDisposed(SceneNode node) {
    if (_disposed) return;
    _byId.remove(node.id);
    _roots.remove(node);
    _dropNodeWireframe(node);
    notifyListeners();
  }

  // ── document ─────────────────────────────────────────────────────────

  /// Adds [object] to the current document and the scene.
  ModelNode addObject(ModelObject object) {
    final model = _model;
    if (model == null) {
      throw StateError(
        'Документ не загружен: сначала вызовите loadModel/loadModelData.',
      );
    }
    model.objects.add(object);
    rebuild();
    return _documentNodes[object.id] ?? ModelNode(this, model, object);
  }

  /// Removes [object] from the document and the scene (cascading CSG
  /// operands are pruned).
  void removeObject(ModelObject object) {
    final model = _model;
    if (model == null) return;
    model.objects.remove(object);
    model.pruneCsgNodes();
    rebuild();
  }

  /// The live node of a document object, or null.
  ModelNode? objectNode(String objectId) {
    final model = _model;
    if (model == null) return null;
    final registered = _documentNodes[objectId];
    if (registered != null) return registered;
    final object = model.objectById(objectId);
    return object == null ? null : ModelNode(this, model, object);
  }

  /// Adds a markup meta-object to the document.
  ModelMeta? addMeta(ModelMeta meta) {
    final model = _model;
    if (model == null) return null;
    model.metas.add(meta);
    rebuild();
    return meta;
  }

  /// Removes a markup meta-object from the document.
  void removeMeta(ModelMeta meta) {
    final model = _model;
    if (model == null) return;
    model.metas.remove(meta);
    rebuild();
  }

  /// Adds a document light source.
  ModelLight? addDocumentLight(ModelLight light) {
    final model = _model;
    if (model == null) return null;
    model.lighting.lights.add(light);
    rebuild();
    return light;
  }

  /// Removes a document light source.
  void removeDocumentLight(ModelLight light) {
    final model = _model;
    if (model == null) return;
    model.lighting.lights.remove(light);
    rebuild();
  }

  /// Adds an object group to the document.
  ModelGroup? addGroup(ModelGroup group) {
    final model = _model;
    if (model == null) return null;
    model.groups.add(group);
    rebuild();
    return group;
  }

  /// Removes an object group from the document.
  void removeGroup(ModelGroup group) {
    final model = _model;
    if (model == null) return;
    model.groups.remove(group);
    model.pruneGroupMembers();
    rebuild();
  }

  // ── lighting ─────────────────────────────────────────────────────────

  final List<LightNode> _documentLights = [];

  /// Builds the scene light from the document's `ModelLighting`: the authored
  /// sources, or the default engine rig (key sun + camera lamp) when the
  /// document has none. Replaces the light built by a previous call; lights
  /// added by the application are not touched.
  void applyLighting() {
    final model = _model;
    if (model == null) return;
    clearLighting();
    final cfg = model.lighting;
    if (!cfg.isDefault) {
      _environmentIntensity = cfg.ambient;
    }
    if (cfg.lights.isEmpty) {
      _documentLights.add(add(LightNode.defaultSun(castsShadow: true)));
      final lamp = LightNode.defaultCameraLamp();
      cameraNode.add(lamp);
      _documentLights.add(lamp);
    } else {
      for (final light in cfg.lights) {
        _documentLights.add(add(_lightFromDocument(light, model)));
      }
    }
    _applySettingsToScene();
    notifyListeners();
  }

  /// Removes the light built by [applyLighting].
  void clearLighting() {
    if (_documentLights.isEmpty) return;
    final lights = List.of(_documentLights);
    _documentLights.clear();
    for (final light in lights) {
      light.remove();
    }
    notifyListeners();
  }

  LightNode _lightFromDocument(ModelLight light, ModelData model) {
    final anchor = chunkWorld(light.x, light.z, model.size.w, model.size.l);
    final color = _srgbToLinear(light.r, light.g, light.b);
    final name = light.name.isEmpty ? 'light:${light.id}' : light.name;
    if (light.isPoint) {
      final node = LightNode.pointLinear(
        id: 'light_${light.id}',
        name: name,
        color: color,
        intensity: light.intensity,
        range: light.range,
      );
      node.position = vm.Vector3(anchor.x, light.y, anchor.z);
      return node;
    }
    final node = LightNode.directionalLinear(
      id: 'light_${light.id}',
      name: name,
      color: color,
      direction: vm.Vector3(light.dirX, light.dirY, light.dirZ),
      intensity: light.intensity,
      castsShadow: true,
    );
    node.position = vm.Vector3(anchor.x, light.y, anchor.z);
    return node;
  }

  void _applyLightSettings() {
    for (final node in nodesOfType<LightNode>()) {
      node.applyShadowSettings(
        shadows: _settings.shadows,
        cascades: _settings.shadowCascades,
        distance: _settings.shadowDistance,
      );
    }
    _applyLightBudget();
  }

  void _applyLightBudget() {
    final points = [
      for (final node in nodesOfType<LightNode>())
        if (node.isPoint) node,
    ];
    final selected = LightNode.selectForBudget(
      points,
      _settings.maxPointLights,
    ).toSet();
    for (final node in points) {
      node.setBudgetEnabled(selected.contains(node));
    }
  }

  // ── render scene ─────────────────────────────────────────────────────

  fs.Scene? _scene;
  fs.NodeCamera? _renderCamera;

  /// The compiled render scene, or null before the first viewport attaches.
  /// Plumbing only.
  @internal
  fs.Scene? get renderScene => _scene;

  /// The compiled camera bound to [cameraNode], or null. Plumbing only.
  @internal
  fs.Camera? get renderCamera => _renderCamera;

  ModelRenderer? _renderer;

  /// The glTF store of the open project (listened to for import completion).
  GltfAssetStore? _gltfAssets;

  bool _disposed = false;

  void _onContentReady() {
    if (_disposed) return;
    rebuild();
  }

  void _onGltfAssetsChanged() {
    if (_disposed) return;
    rebuild();
  }

  /// Caches the fitted footprint of a loaded gltf instance on its document
  /// object ([ModelObject.gltfBounds]), so the fuchsia placeholder and the
  /// footprint proxy survive a later catalog deletion.
  void _onGltfFootprint(String modelId, String objId, List<double> bounds) {
    final model = _model;
    if (model == null || model.id != modelId) return;
    final object = model.objectById(objId);
    if (object == null) return;
    object.gltfBounds = List<double>.from(bounds);
  }

  /// The document renderer (objects of the current `model_v1`), or null
  /// before the render scene exists. Plumbing only.
  @internal
  ModelRenderer? get renderer => _renderer;

  /// The live wrapper node of a loaded glTF object, or null. Plumbing.
  @internal
  EngineNode? liveNode(String objectId) {
    final node = _renderer?.gltfWrappers[objectId];
    return node == null ? null : EngineNode.wrap(node);
  }

  /// Creates (once) the fork render scene, mounts every root node, the
  /// document root and binds the camera. Requires a rendering device;
  /// headless tests never call it.
  @internal
  fs.Scene ensureRenderScene() {
    final existing = _scene;
    if (existing != null) return existing;
    final scene = fs.Scene();
    _scene = scene;
    _applySettingsToScene();
    _rebuildRenderCamera();
    scene.add(cameraNode.engine.raw);

    final manager = _resources?.manager;
    final renderer = ModelRenderer(
      manager?.textures ?? TextureCache(),
      gltfAssets: manager?.gltfAssets ?? GltfAssetStore(),
      mergeStatic: mergeStatic,
    );
    if (manager != null) {
      renderer.modelCatalog = (id) => manager.models[id];
      renderer.gltfCatalog = manager.gltfEntry;
      renderer.gltfCatalogReady = () => manager.gltfCatalogReady;
      _gltfAssets = manager.gltfAssets;
      _gltfAssets!.addListener(_onGltfAssetsChanged);
    }
    renderer.onTextureReady = _onContentReady;
    renderer.onGltfFootprint = _onGltfFootprint;
    _renderer = renderer;
    scene.add(renderer.root);

    for (final node in _roots) {
      if (identical(node, cameraNode)) {
        continue;
      }
      _syncSubtree(node);
      scene.add(node.engine.raw);
    }
    if (_model != null) renderer.rebuild(_model!);
    _updateScreenSpaceLines();
    return scene;
  }

  /// Syncs a node and its whole subtree to the render side: children attached
  /// before the render scene existed must build their engine content now.
  void _syncSubtree(SceneNode node) {
    node.syncToEngine();
    for (final child in node.children) {
      _syncSubtree(child);
    }
  }

  /// Rebuilds the fork camera from the active camera controller.
  void _rebuildRenderCamera() {
    final scene = _scene;
    if (scene == null) return;
    final projection = _camera.projection;
    final camera = fs.NodeCamera(
      cameraNode.engine.raw,
      fs.PerspectiveProjection(
        fovRadiansY: projection.fovY,
        near: projection.near,
        far: projection.far,
      ),
    );
    _renderCamera = camera;
    scene.camera = camera;
  }

  // ── camera and viewport ──────────────────────────────────────────────

  CameraController _camera = MatrixCameraController();

  /// The active camera controller.
  CameraController get camera => _camera;
  set camera(CameraController value) {
    if (identical(_camera, value)) return;
    final old = _camera;
    old.removeListener(_onCameraChanged);
    _camera = value;
    _camera.addListener(_onCameraChanged);
    _applyCamera();
    _rebuildRenderCamera();
    old.dispose();
    notifyListeners();
  }

  void _onCameraChanged() {
    _applyCamera();
    _rebuildRenderCamera();
    notifyListeners();
  }

  void _applyCamera() {
    final camera = _camera;
    if (camera is MatrixCameraController) {
      cameraNode.transform = camera.matrix;
    } else if (camera is FlyCameraController) {
      cameraNode.transform = camera.matrix;
    } else if (camera is FirstPersonCameraController) {
      cameraNode.transform = camera.matrix;
    } else if (camera is OrbitCameraController) {
      cameraNode.transform = camera.matrix;
    }
  }

  Size _viewportSize = Size.zero;
  double _pixelRatio = 1.0;

  /// The last reported viewport size.
  Size get viewportSize => _viewportSize;

  /// The last reported viewport pixel ratio.
  double get pixelRatio => _pixelRatio;

  /// Reports the viewport geometry (called by the viewport widget).
  @internal
  void setViewport(Size size, double pixelRatio) {
    _viewportSize = size;
    _pixelRatio = pixelRatio;
  }

  // ── picture settings ─────────────────────────────────────────────────

  QualitySettings _settings = const QualitySettings();
  QualityController? _quality;
  SceneFog? _fog;
  double _environmentIntensity = 1.0;

  /// The current picture-quality settings (the source of truth for shadows
  /// and SSAO; the document's `ModelLighting` is only an art hint).
  QualitySettings get settings => _settings;

  /// The attached quality controller, or null.
  QualityController? get quality => _quality;

  /// Attaches a quality controller (called by `QualityController.attach`).
  @internal
  set quality(QualityController? value) => _quality = value;

  /// Applies [settings] to the scene (and to the renderer when it exists).
  void applySettings(QualitySettings settings) {
    _settings = settings;
    _applySettingsToScene();
    notifyListeners();
  }

  /// Toggles shadows through [QualitySettings] (the document is not touched).
  void setShadows(bool enabled) =>
      applySettings(_settings.copyWith(shadows: enabled));

  /// Toggles SSAO through [QualitySettings].
  void setSsao(bool enabled) =>
      applySettings(_settings.copyWith(ssao: enabled));

  /// Sets the number of shadow cascades.
  void setShadowCascades(int count) =>
      applySettings(_settings.copyWith(shadowCascades: count));

  /// Sets the shadow distance.
  void setShadowDistance(double distance) =>
      applySettings(_settings.copyWith(shadowDistance: distance));

  /// Sets the render scale.
  void setRenderScale(double scale, {FilterQuality? filterQuality}) =>
      applySettings(
        _settings.copyWith(renderScale: scale, filterQuality: filterQuality),
      );

  /// Sets the anti-aliasing mode.
  void setAntiAliasing(SceneAntiAliasing mode) =>
      applySettings(_settings.copyWith(antiAliasing: mode));

  /// Sets the environment (IBL) intensity.
  void setEnvironmentIntensity(double value) {
    _environmentIntensity = value;
    _applySettingsToScene();
    notifyListeners();
  }

  /// Sets the distance fog (null disables it).
  void setFog(SceneFog? fog) {
    _fog = fog;
    _applySettingsToScene();
    notifyListeners();
  }

  /// The render scale of the current settings.
  double get renderScale => _settings.renderScale;

  /// The anti-aliasing that actually runs (resolved against the backend when
  /// the render scene exists).
  SceneAntiAliasing get effectiveAntiAliasing {
    final scene = _scene;
    if (scene != null) {
      return switch (scene.effectiveAntiAliasingMode) {
        fs.AntiAliasingMode.none => SceneAntiAliasing.none,
        fs.AntiAliasingMode.msaa => SceneAntiAliasing.msaa,
        fs.AntiAliasingMode.fxaa => SceneAntiAliasing.fxaa,
        fs.AntiAliasingMode.auto => SceneAntiAliasing.auto,
      };
    }
    return _settings.antiAliasing;
  }

  /// The configured shadow cascade count.
  int? get shadowCascades => _settings.shadowCascades;

  /// The configured shadow distance.
  double? get shadowDistance => _settings.shadowDistance;

  /// The environment (IBL) intensity.
  double get environmentIntensity => _environmentIntensity;

  /// The distance fog, or null.
  SceneFog? get fog => _fog;

  void _applySettingsToScene() {
    _applyLightSettings();
    final scene = _scene;
    if (scene == null) return;
    scene.renderScale = _settings.renderScale;
    scene.filterQuality = _settings.filterQuality;
    scene.antiAliasingMode = switch (_settings.antiAliasing) {
      SceneAntiAliasing.none => fs.AntiAliasingMode.none,
      SceneAntiAliasing.msaa => fs.AntiAliasingMode.msaa,
      SceneAntiAliasing.fxaa => fs.AntiAliasingMode.fxaa,
      SceneAntiAliasing.auto => fs.AntiAliasingMode.auto,
    };
    scene.ambientOcclusion.enabled = _settings.ssao;
    scene.environmentIntensity = _environmentIntensity;
    final fog = _fog;
    final renderFog = scene.fog;
    if (fog == null) {
      renderFog.enabled = false;
    } else {
      renderFog
        ..enabled = true
        ..mode = fs.FogMode.linear
        ..color = vm.Vector3(
          math.pow(fog.color.r, 2.2).toDouble(),
          math.pow(fog.color.g, 2.2).toDouble(),
          math.pow(fog.color.b, 2.2).toDouble(),
        )
        ..start = fog.start
        ..end = fog.end
        ..minOpacity = fog.minOpacity
        ..maxOpacity = fog.maxOpacity
        ..skyColorInfluence = 0.0
        ..cutoffDistance = 0.0
        ..heightFalloff = 0.0
        ..sunInScatter = 0.0;
    }
  }

  // ── picking and projection ───────────────────────────────────────────

  /// The world ray from the camera through a viewport point.
  vm.Ray screenPointToRay(Offset screenPoint) {
    final size = _viewportSize;
    final origin = cameraNode.globalTransform.getTranslation();
    if (size.width <= 0 || size.height <= 0) {
      return vm.Ray.originDirection(origin, _camera.forwardH);
    }
    final view = cameraNode.globalTransform.clone()..invert();
    final aspect = size.width / size.height;
    final ndcX = 2 * screenPoint.dx / size.width - 1;
    final ndcY = 1 - 2 * screenPoint.dy / size.height;
    final tanHalf = math.tan(_camera.projection.fovY / 2);
    final direction = vm.Vector3(ndcX * tanHalf * aspect, ndcY * tanHalf, 1);
    view.rotate3(direction);
    if (direction.length2 > 1e-18) direction.normalize();
    return vm.Ray.originDirection(origin, direction);
  }

  /// Projects a world point to viewport coordinates, or null when it is
  /// behind the camera.
  Offset? worldToScreen(vm.Vector3 worldPoint) {
    final size = _viewportSize;
    if (size.width <= 0 || size.height <= 0) return null;
    final view = cameraNode.globalTransform.clone()..invert();
    final local = view.transform3(worldPoint.clone());
    if (local.z <= _camera.projection.near) return null;
    final aspect = size.width / size.height;
    final tanHalf = math.tan(_camera.projection.fovY / 2);
    final ndcX = local.x / (local.z * tanHalf * aspect);
    final ndcY = local.y / (local.z * tanHalf);
    return Offset((ndcX + 1) / 2 * size.width, (1 - ndcY) / 2 * size.height);
  }

  /// The viewport rectangle covering world-space [worldBounds], or null when
  /// any corner is behind the camera.
  Rect? screenRect(vm.Aabb3 worldBounds) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i < 8; i++) {
      final corner = vm.Vector3(
        (i & 1) == 0 ? worldBounds.min.x : worldBounds.max.x,
        (i & 2) == 0 ? worldBounds.min.y : worldBounds.max.y,
        (i & 4) == 0 ? worldBounds.min.z : worldBounds.max.z,
      );
      final screen = worldToScreen(corner);
      if (screen == null) return null;
      if (screen.dx < minX) minX = screen.dx;
      if (screen.dy < minY) minY = screen.dy;
      if (screen.dx > maxX) maxX = screen.dx;
      if (screen.dy > maxY) maxY = screen.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Casts a ray through a viewport point and returns the nearest hit.
  SceneHit? raycast(
    Offset screenPoint, {
    RaycastOptions options = const RaycastOptions(),
  }) => raycastRay(screenPointToRay(screenPoint), options: options);

  /// Casts a world [ray] and returns the nearest hit.
  SceneHit? raycastRay(
    vm.Ray ray, {
    RaycastOptions options = const RaycastOptions(),
  }) {
    final hits = raycastAll(ray, options: options);
    return hits.isEmpty ? null : hits.first;
  }

  /// Casts a world [ray] and returns every hit, nearest first.
  List<SceneHit> raycastAll(
    vm.Ray ray, {
    RaycastOptions options = const RaycastOptions(),
  }) {
    final hits = <SceneHit>[];
    for (final node in _pickableNodes()) {
      if (!options.includeInvisible && !node.visible) continue;
      if (options.skipNodeIds.contains(node.id)) continue;
      if (options.where != null && !options.where!(node)) continue;
      final parts = node.pickParts;
      if (parts.isEmpty) continue;

      final world = node.globalTransform;
      final inverse = world.clone()..invert();
      final localOrigin = inverse.transform3(ray.origin.clone());
      final localDirection = inverse.rotate3(ray.direction.clone());
      if (localDirection.length2 > 1e-18) localDirection.normalize();

      for (final part in parts) {
        final hit = intersectGeometry(
          part.geometry,
          localOrigin,
          localDirection,
          side: options.respectCulling ? part.side : 'double',
        );
        if (hit == null) continue;
        final worldPoint = world.transform3(hit.point.clone());
        final worldNormal = world.rotate3(hit.normal.clone());
        if (worldNormal.length2 > 1e-18) worldNormal.normalize();
        final faceKey = part.faceKey;
        hits.add(
          SceneHit(
            node: node,
            face: faceKey == null
                ? null
                : FaceRef(
                    key: faceKey,
                    node: node,
                    material: node is ModelNode
                        ? node.object.faces[faceKey]
                        : null,
                  ),
            distance: (worldPoint - ray.origin).length,
            worldPoint: worldPoint,
            localPoint: hit.point,
            worldNormal: worldNormal,
          ),
        );
      }
    }
    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits;
  }

  /// Every node that takes part in picking: attached API nodes plus the
  /// document-object wrappers (deduplicated by identity).
  Iterable<SceneNode> _pickableNodes() {
    final seen = <SceneNode>{};
    return <SceneNode>[
      ..._byId.values,
      ..._documentNodes.values,
    ].where(seen.add);
  }

  /// The nearest node whose projected bounds center is within [maxDistance]
  /// viewport pixels of [screenPoint].
  SceneNode? nearestNode(Offset screenPoint, {double maxDistance = 140}) {
    SceneNode? best;
    var bestDistance = maxDistance;
    for (final node in _pickableNodes()) {
      if (!node.visible) continue;
      if (node is ModelNode && node.isCsgOperand) continue;
      final bounds = node.worldBounds;
      if (bounds == null) continue;
      final screen = worldToScreen(bounds.center);
      if (screen == null) continue;
      final distance = (screen - screenPoint).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = node;
      }
    }
    return best;
  }

  // ── dynamics and sky ─────────────────────────────────────────────────

  DynamicNodes? _dynamics;

  /// The dynamic-object registry (spawn/despawn/sync with lifetimes).
  DynamicNodes get dynamics => _dynamics ??= DynamicNodes(this);

  /// The active sky node, or null when the scene has none.
  SkyboxNode? get skybox {
    for (final node in _byId.values) {
      if (node is SkyboxNode) return node;
    }
    return null;
  }

  // ── levels ───────────────────────────────────────────────────────────

  LevelNode? _level;

  /// The mounted level, or null.
  LevelNode? get level => _level;

  /// Loads a level from [model]: preloads the resource closure, bakes the
  /// geometry and reports progress/errors through [status]. Never throws.
  ///
  /// [baker] is a plumbing seam for headless tests.
  Future<LevelLoadResult> loadLevel(
    ConstructionModel model, {
    List<LevelExtraResource> extraResources = const [],
    LevelBakeOptions? options,
    @internal LevelBaker? baker,
  }) async {
    final manager = _manager;
    if (manager == null) {
      return const LevelLoadResult(
        baked: null,
        errors: [
          SceneLoadError(resource: 'уровень', reason: 'проект не открыт'),
        ],
        elapsed: Duration.zero,
      );
    }
    final bakeOptions = options ?? const LevelBakeOptions();
    final hook = bakeOptions.onMaterial;
    final loader = LevelLoader(
      resources: manager,
      model: model,
      extraResources: extraResources,
      collectStats: bakeOptions.collectStats,
      baker: baker,
      onEvent: _onLevelEvent,
      onMaterial: hook == null
          ? null
          : (material, {required sprite, required tags}) {
              hook(
                SceneMaterial.fromEngine(material),
                sprite: sprite,
                tags: tags.toList(),
              );
            },
    );
    _setStatus(SceneLoadPhase.project, 0, 'Уровень');
    return loader.load();
  }

  /// Mounts a baked level, replacing the previous one. [offset] places the
  /// level in world space (the centered engine frame → game frame).
  LevelNode mountLevel(LevelBakeResult baked, {vm.Matrix4? offset}) {
    unmountLevel();
    final node = LevelNode(result: baked);
    if (offset != null) {
      node.engine.raw.localTransform = offset;
    }
    _level = add(node);
    return _level!;
  }

  /// Removes the mounted level; the baked result stays reusable.
  void unmountLevel() {
    final node = _level;
    if (node == null) return;
    _level = null;
    node.remove();
    notifyListeners();
  }

  void _onLevelEvent(LevelLoadEvent event) {
    // An async load may finish after the controller was disposed (scene
    // switch); touching a disposed ChangeNotifier would abort the frame.
    if (_disposed) return;
    switch (event.kind) {
      case LevelLoadEventKind.started:
        _setStatus(SceneLoadPhase.project, 0, 'Уровень');
      case LevelLoadEventKind.progress:
        _setStatus(
          event.phase ?? SceneLoadPhase.resources,
          event.fraction,
          event.label,
        );
      case LevelLoadEventKind.finished:
        final result = event.result;
        if (result == null) return;
        _status = SceneLoadStatus(
          phase: result.baked != null
              ? SceneLoadPhase.ready
              : SceneLoadPhase.error,
          fraction: 1,
          label: result.baked != null ? 'Готово' : 'Ошибка уровня',
          errors: result.errors,
        );
        notifyListeners();
    }
  }

  // ── frame ────────────────────────────────────────────────────────────

  final List<SceneFrameListener> _frameListeners = [];
  Duration _elapsed = Duration.zero;

  /// The total time since the first frame.
  Duration get elapsed => _elapsed;

  /// Advances the scene by [dt] seconds: camera, billboards, then the frame
  /// listeners in registration order.
  void update(double dt) {
    // A disposed controller may still be ticked for a frame or two by a
    // viewport that is being replaced (project switch): touching its nodes
    // would notify disposed listenables and abort the frame.
    if (_disposed) return;
    _elapsed += Duration(microseconds: (dt * 1000000).round());
    _camera.update(dt);
    _applyCamera();
    _updateScreenSpaceLines();
    _updateGizmos();
    _dynamics?.update(dt);
    for (final node in List.of(_byId.values)) {
      node.frameTick(_elapsed, dt);
    }
    reorientBillboards();
    for (final listener in List.of(_frameListeners)) {
      listener(_elapsed, dt);
    }
  }

  /// Registers a frame callback (called after the engine update).
  void addFrameListener(SceneFrameListener listener) =>
      _frameListeners.add(listener);

  /// Removes a frame callback.
  void removeFrameListener(SceneFrameListener listener) =>
      _frameListeners.remove(listener);

  /// Refreshes one screen-pixel line node for the current camera: the CPU
  /// backend expands it, the shader backend updates its pixel scale.
  /// Plumbing for `LineNode`.
  @internal
  void refreshScreenSpaceLine(LineNode node) {
    final size = _viewportSize;
    if (size.isEmpty || node.geometry.widthPx == null) return;
    if (lineWidthBackend == LineWidthBackend.shader) {
      node.geometry.setPixelScale(_screenPixelScale());
      return;
    }
    final camera = _renderCamera;
    if (camera == null) return;
    node.geometry.updateForCamera(
      camera.getViewTransform(size),
      camera.position,
      size,
    );
  }

  /// The world size of one screen pixel at distance 1 for the active camera.
  double _screenPixelScale() => fs.LineSegmentsGeometry.pixelScaleFor(
    fovY: _camera.projection.fovY,
    viewportHeight: _viewportSize.height,
  );

  /// Per-frame upkeep of screen-pixel line widths: the shader backend only
  /// needs the current pixel scale, the CPU backend re-expands its ribbons.
  void _updateScreenSpaceLines() {
    final size = _viewportSize;
    if (size.isEmpty) return;
    if (lineWidthBackend == LineWidthBackend.shader) {
      final scale = _screenPixelScale();
      for (final node in nodesOfType<LineNode>()) {
        if (node.geometry.widthPx != null) {
          node.geometry.setPixelScale(scale);
        }
      }
      return;
    }
    final camera = _renderCamera;
    if (camera == null) return;
    final viewProjection = camera.getViewTransform(size);
    final position = camera.position;
    for (final node in nodesOfType<LineNode>()) {
      node.geometry.updateForCamera(viewProjection, position, size);
    }
  }

  /// Reorients every billboard sprite towards the active camera.
  void reorientBillboards() {
    final forward = _camera.forwardH;
    final yaw = screenParallelYaw(forward.x, forward.z);
    for (final node in nodesOfType<SpriteNode>()) {
      if (node.billboard) node.reorientBillboard(yaw);
    }
    // Document sprites and sprites nested in model instances (the renderer
    // owns their nodes).
    _renderer?.reorientBillboards(forward.x, forward.z);
    _level?.result.reorientBillboards(forward.x, forward.z);
    if (yaw != _lastBillboardYaw) {
      _lastBillboardYaw = yaw;
      _refreshBillboardWireframes();
    }
  }

  double? _lastBillboardYaw;

  /// Refreshes the wireframes of billboard sprites when the camera turns
  /// (their world-space frames follow the live yaw).
  void _refreshBillboardWireframes() {
    for (final node in nodesOfType<ModelNode>()) {
      if (node.object.kind != 'sprite') continue;
      if (node.wireframe != null || _wireframeStyle != null) {
        _refreshNodeWireframe(node);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gltfAssets?.removeListener(_onGltfAssetsChanged);
    _gltfAssets = null;
    _renderer?.onTextureReady = null;
    _level = null;
    _gizmos.clear();
    _activeGizmo = null;
    for (final node in List.of(_roots)) {
      node.remove();
    }
    _documentLights.clear();
    _scene?.removeAll();
    _scene = null;
    _renderCamera = null;
    _renderer = null;
    _dynamics?.dispose();
    _dynamics = null;
    _frameListeners.clear();
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _shaders.dispose();
    super.dispose();
  }
}

/// sRGB (0..1) → linear, for engine light colors.
vm.Vector3 _srgbToLinear(double r, double g, double b) {
  double x(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return vm.Vector3(x(r), x(g), x(b));
}
