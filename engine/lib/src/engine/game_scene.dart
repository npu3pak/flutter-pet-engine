import 'dart:math' as math;
import 'dart:ui' show FilterQuality, Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../dynamic/dynamic_world.dart';
import '../camera/camera_controller.dart';
import '../level/level_baker.dart';
import '../models/model_scene.dart';
import '../scene/model_renderer.dart';
import '../services/gltf_asset_store.dart';
import 'game_camera.dart';
import 'game_quality.dart';
import 'game_resource_manager.dart';
import 'picking.dart';
import 'picture_settings.dart';

/// The runtime face of one editable 3D scene: owns the flutter_scene [Scene]
/// graph (objects via [ModelRenderer], the light rig and the camera) and
/// exposes the object API games drive (animation, materials, placement).
///
/// [GameNode] handles are cheap views over the live [ModelData]: every mutator
/// updates the document AND the graph (gltf instances move live through their
/// wrapper node; structural/material changes rebuild the content pass).
class GameScene {
  final GameResourceManager resources;

  /// The engine scene graph; attach a [SceneView] to it in the UI.
  final Scene scene = Scene();

  final Node cameraNode = Node(name: 'game-camera');
  late final NodeCamera camera;

  /// The free-fly controller driving [cameraNode] by default ([GameScene.update]
  /// applies the active [cameraController] every tick).
  final GameCamera view = GameCamera();

  late CameraController _cameraController;

  /// The active camera controller; defaults to a [FreeCameraController] over
  /// [view]. Assigning one applies its projection and transform immediately.
  CameraController get cameraController => _cameraController;
  set cameraController(CameraController value) {
    _cameraController = value;
    camera.projection = value.projection;
    value.applyTo(cameraNode);
  }

  final ModelRenderer renderer;

  /// Default home of dynamic objects (enemies, items, effects): spawned nodes
  /// live outside the model content, so a spawn/despawn never triggers a
  /// content rebuild. Games may create their own [DynamicWorld] and attach it
  /// to [scene].
  late final DynamicWorld dynamics;

  /// Screen projection and picking over [camera] (world → screen, screen
  /// distance and ray picks).
  late final ScreenPicking picking = ScreenPicking(camera);

  /// Model-light sources live here ([Node]s with light components).
  final Node lightsRoot = Node(name: 'game-lights');

  final Node _sunNode = Node(name: 'game-sun');
  final PointLightComponent _cameraLamp = PointLightComponent(
    PointLight(color: vm.Vector3(1, 0.9, 0.8), intensity: 4.0, range: 6.0),
  );
  bool _defaultRigAttached = true;
  bool _defaultRigShadows = false;

  ModelData? _model;
  String? _modelId;
  bool _disposed = false;

  ModelData? get model => _model;
  String? get modelId => _modelId;

  GameScene(this.resources, {bool mergeStatic = false})
      : renderer = ModelRenderer(
          resources.textures,
          gltfAssets: resources.gltfAssets,
          mergeStatic: mergeStatic,
        ) {
    _cameraController = FreeCameraController(view);
    camera = NodeCamera(cameraNode, _cameraController.projection);
    dynamics = DynamicWorld();
    _sunNode.addComponent(DirectionalLightComponent(DirectionalLight(
      direction: vm.Vector3(-0.4, -0.85, -0.35),
      intensity: 2.2,
      color: vm.Vector3(1, 0.96, 0.9),
    )));
    cameraNode.addComponent(_cameraLamp);
    scene.add(cameraNode);
    scene.add(_sunNode);
    // Objects live in the renderer's own root — it MUST be attached to the
    // scene or the whole object subtree renders nothing.
    scene.add(renderer.root);
    scene.add(lightsRoot);
    scene.add(dynamics.root);
    renderer.modelCatalog = (id) => resources.models[id];
    renderer.gltfCatalog = resources.gltfEntry;
    renderer.gltfCatalogReady = () => resources.gltfCatalogReady;
    renderer.onTextureReady = _onContentReady;
    renderer.onGltfFootprint = _onGltfFootprint;
    resources.gltfAssets.addListener(_onGltfAssetsChanged);
    _cameraController.applyTo(cameraNode);
  }

  // ── lifecycle ────────────────────────────────────────────────────────

  /// Loads [id] from the manager's model catalog and renders it (objects,
  /// lights; the camera is framed by [frameView] = the caller's choice).
  /// Returns false when the model id is unknown.
  bool loadModel(String id) {
    final m = resources.models[id];
    if (m == null) return false;
    _model = m;
    _modelId = id;
    rebuildContent();
    applyLighting();
    return true;
  }

  /// Shows an in-memory [ModelData] (e.g. a level construction model baked by
  /// the level layer) without going through the resource catalog. [id] only
  /// labels the scene; the object API works on [model] as usual.
  void loadModelData(ModelData model, {String? id}) {
    _model = model;
    _modelId = id ?? model.id;
    rebuildContent();
    applyLighting();
  }

  /// Clears the scene (stops showing any model).
  void unloadModel() {
    _model = null;
    _modelId = null;
    renderer.root.removeAll();
  }

  // ── baked level mount (подшаг 5.3) ───────────────────────────────────

  Node? _levelRoot;
  LevelBakeResult? _levelResult;
  final Map<String, Node> _levelNodes = {};

  /// The baked level root mounted by the level loader, or null.
  Node? get levelRoot => _levelRoot;

  /// The full bake result of the mounted level, or null. Kept so
  /// [update] can reorient the baked sprite billboards.
  LevelBakeResult? get levelResult => _levelResult;

  /// Separate baked nodes addressable by element id ([BakeMode.node] and
  /// single-element groups).
  Map<String, Node> get levelNodes => Map.unmodifiable(_levelNodes);

  /// Mounts a baked level into the scene alongside the model content. The
  /// previous baked level is unmounted first; the caller shows the level only
  /// after every resource is ready (подшаг 5.3).
  void mountLevel(LevelBakeResult baked) {
    unmountLevel();
    _levelRoot = baked.root;
    _levelResult = baked;
    _levelNodes.addAll(baked.nodes);
    scene.add(baked.root);
  }

  /// Detaches the baked level root (the result stays intact for reuse).
  void unmountLevel() {
    final root = _levelRoot;
    if (root != null) root.parent?.remove(root);
    _levelRoot = null;
    _levelResult = null;
    _levelNodes.clear();
  }

  /// A mounted baked node by element id, or null.
  Node? levelNode(String id) => _levelNodes[id];

  /// Per-frame tick: applies the camera controller, ticks the dynamic world
  /// and reorients sprite billboards (model content and baked levels). Call
  /// from [SceneView.onTick].
  void update(double deltaSeconds) {
    _cameraController.update(deltaSeconds);
    _cameraController.applyTo(cameraNode);
    final f = _cameraController.forwardH;
    dynamics.update(deltaSeconds, cameraForward: f);
    renderer.reorientBillboards(f.x, f.z);
    _levelResult?.reorientBillboards(f.x, f.z);
  }

  /// Rebuilds the whole object pass from the current [model] (structural
  /// edits, material/texture swaps, animation switches).
  void rebuildContent() {
    final m = _model;
    if (m == null) return;
    renderer.rebuild(m);
  }

  /// The wrapper node of a loaded gltf instance (kind 'gltf') — its content
  /// is a single node, so games move/rotate it live without a rebuild. Null
  /// for other kinds or while the instance is not loaded yet.
  Node? liveNode(String objectId) => renderer.gltfWrappers[objectId];

  void dispose() {
    _disposed = true;
    resources.gltfAssets.removeListener(_onGltfAssetsChanged);
    dynamics.dispose();
    _levelRoot = null;
    _levelResult = null;
    _levelNodes.clear();
    scene.removeAll();
  }

  // ── object API ───────────────────────────────────────────────────────

  /// Top-level visible objects of the current model (in model order), as
  /// handles for the UI/game logic.
  List<GameNode> get nodes {
    final m = _model;
    if (m == null) return const [];
    return [
      for (final o in m.visibleObjects()) GameNode(this, m, o),
    ];
  }

  /// A handle for the object [id] (null when absent or not in the model).
  GameNode? node(String id) {
    final m = _model;
    if (m == null) return null;
    final o = m.objectById(id);
    return o == null ? null : GameNode(this, m, o);
  }

  // ── light rig (model config ↔ engine scene) ──────────────────────────

  /// Applies the model's lighting config to the scene: the model's own light
  /// sources with its scene knobs (ambient/SSAO/shadows), or the default rig
  /// (key sun + camera lamp) when the config is default — identical to the
  /// editor, so scenes look the same in the editor and in the game.
  void applyLighting() {
    final m = _model;
    if (m == null) return;
    final cfg = m.lighting;
    final customized = !cfg.isDefault;
    scene.environmentIntensity = customized ? cfg.ambient : 1.0;
    scene.ambientOcclusion.enabled = customized && cfg.ssao;
    lightsRoot.removeAll();
    if (cfg.lights.isEmpty) {
      _ensureDefaultRig(shadows: customized && cfg.shadows);
      return;
    }
    _detachDefaultRig();
    for (final light in cfg.lights) {
      lightsRoot.add(_buildLightNode(light, m, shadows: cfg.shadows));
    }
  }

  /// Environment/IBL intensity knob (scene default 1.0). Mutates the model's
  /// config so a later save keeps the game's choice.
  void setAmbient(double value) {
    final m = _model;
    if (m == null) return;
    m.lighting.ambient = value;
    applyLighting();
  }

  /// Directional shadows knob (only directional sources / the default rig
  /// cast shadows in the engine).
  void setShadows(bool enabled) {
    final m = _model;
    if (m == null) return;
    m.lighting.shadows = enabled;
    applyLighting();
  }

  /// The cascade count of the first directional light, or null when none.
  int? get shadowCascades =>
      _directionalLights.isEmpty ? null : _directionalLights.first.light.shadowCascadeCount;

  /// The shadow distance (world units) of the first directional light, or
  /// null when none.
  double? get shadowDistance =>
      _directionalLights.isEmpty ? null : _directionalLights.first.light.shadowMaxDistance;

  /// Sets the cascade count on every directional light; returns false when
  /// the scene has none.
  bool setShadowCascades(int count) {
    if (_directionalLights.isEmpty) return false;
    for (final component in _directionalLights) {
      component.light.shadowCascadeCount = count;
    }
    return true;
  }

  /// Sets the shadow distance on every directional light; returns false when
  /// the scene has none.
  bool setShadowDistance(double distance) {
    if (_directionalLights.isEmpty) return false;
    for (final component in _directionalLights) {
      component.light.shadowMaxDistance = distance;
    }
    return true;
  }

  Iterable<DirectionalLightComponent> get _directionalLights sync* {
    yield* _sunNode.getComponents<DirectionalLightComponent>();
    for (final node in lightsRoot.children) {
      yield* node.getComponents<DirectionalLightComponent>();
    }
  }

  /// Screen-space ambient occlusion knob.
  void setSsao(bool enabled) {
    final m = _model;
    if (m == null) return;
    m.lighting.ssao = enabled;
    applyLighting();
  }

  /// Applies a recommended quality preset: render scale, SSAO and shadows.
  /// Call after [loadModel]; the [GameQualitySettings.sustainedPerformance]
  /// hint is applied by the app (the engine has no platform channel).
  void applyQualitySettings(GameQualitySettings settings) {
    setRenderScale(settings.renderScale);
    setSsao(settings.ssao);
    setShadows(settings.shadows);
  }

  // ── picture settings ─────────────────────────────────────────────────

  /// Applies distance fog (null disables it).
  void setFog(GameFog? fog) {
    final f = scene.fog;
    if (fog == null) {
      f.enabled = false;
      return;
    }
    fog.applyTo(f);
  }

  /// Sets the scene's anti-aliasing mode.
  void setAntiAliasing(GameAntiAliasing mode) =>
      scene.antiAliasingMode = antiAliasingModeOf(mode);

  /// Sets the render scale; [filterQuality] is applied only when given (the
  /// quality presets keep the engine default).
  void setRenderScale(double scale, {FilterQuality? filterQuality}) {
    scene.renderScale = scale;
    if (filterQuality != null) scene.filterQuality = filterQuality;
  }

  /// The current render scale.
  double get renderScale => scene.renderScale;
  set renderScale(double value) => scene.renderScale = value;

  /// The anti-aliasing technique that actually runs (resolved against the
  /// backend).
  GameAntiAliasing get effectiveAntiAliasing =>
      gameAntiAliasingOf(scene.effectiveAntiAliasingMode);

  /// The camera's horizontal forward direction (billboards reorient against
  /// it).
  vm.Vector3 get cameraForward {
    final f = camera.forward;
    return vm.Vector3(f.x, 0, f.z).normalized();
  }

  /// Applies the active camera controller to the camera node now (after a
  /// direct [GameCamera] edit through [view]).
  void applyCameraController() => _cameraController.applyTo(cameraNode);

  /// The screen-space ray through [position] for a view of [size].
  vm.Ray screenPointToRay(Offset position, Size size) =>
      camera.screenPointToRay(position, size);

  /// Sets the environment (IBL) light intensity.
  void setEnvironmentIntensity(double value) =>
      scene.environmentIntensity = value;

  /// Applies a full [GamePictureSettings] preset.
  void applyPictureSettings(GamePictureSettings settings) {
    setFog(settings.fog);
    setAntiAliasing(settings.antiAliasing);
    setRenderScale(settings.renderScale, filterQuality: settings.filterQuality);
    setEnvironmentIntensity(settings.environmentIntensity);
  }

  Node _buildLightNode(ModelLight light, ModelData m, {required bool shadows}) {
    final anchor = _lightAnchor(light, m);
    final color = _srgbToLinear(light.r, light.g, light.b);
    final node = Node(name: 'light-src:${light.id}')
      ..localTransform = vm.Matrix4.translation(anchor);
    if (light.isPoint) {
      node.addComponent(PointLightComponent(PointLight(
        color: color,
        intensity: light.intensity,
        range: light.range,
      )));
    } else {
      node.addComponent(DirectionalLightComponent(DirectionalLight(
        direction: _lightDirOf(light),
        color: color,
        intensity: light.intensity,
        castsShadow: shadows,
      )));
    }
    return node;
  }

  void _ensureDefaultRig({required bool shadows}) {
    if (!_defaultRigAttached) {
      _sunNode.addComponent(DirectionalLightComponent(DirectionalLight(
        direction: vm.Vector3(-0.4, -0.85, -0.35),
        intensity: 2.2,
        color: vm.Vector3(1, 0.96, 0.9),
        castsShadow: shadows,
      )));
      cameraNode.addComponent(_cameraLamp);
      _defaultRigAttached = true;
      _defaultRigShadows = shadows;
      return;
    }
    if (_defaultRigShadows != shadows) {
      _detachDefaultRig();
      _ensureDefaultRig(shadows: shadows);
    }
  }

  void _detachDefaultRig() {
    if (!_defaultRigAttached) return;
    final sun = _sunNode.getComponents<DirectionalLightComponent>();
    if (sun.isNotEmpty) _sunNode.removeComponent(sun.first);
    if (cameraNode.getComponents<PointLightComponent>().isNotEmpty) {
      cameraNode.removeComponent(_cameraLamp);
    }
    _defaultRigAttached = false;
  }

  // ── async content hooks ──────────────────────────────────────────────

  void _onContentReady() {
    if (_disposed) return;
    rebuildContent();
  }

  void _onGltfAssetsChanged() {
    if (_disposed) return;
    // An import finished (ready/failed) — re-render instances with real
    // content (or their error cubes). Guard: no full rebuild while a texture
    // pass is in flight (cheap guard: rebuild is idempotent anyway).
    rebuildContent();
  }

  void _onGltfFootprint(String modelId, String objId, List<double> bounds) {
    final obj = resources.models[modelId]?.objectById(objId);
    if (obj != null) obj.gltfBounds = bounds;
  }
}

/// The world anchor of a light source: mirrored chunkWorld of its (x, z)
/// cell + authored height (same math as the renderer's object anchors).
vm.Vector3 _lightAnchor(ModelLight light, ModelData m) {
  final w = chunkWorld(light.x, light.z, m.size.w, m.size.l);
  return vm.Vector3(w.x, light.y, w.z);
}

/// Direction of a directional light — the authored world-space direction.
vm.Vector3 _lightDirOf(ModelLight light) =>
    vm.Vector3(light.dirX, light.dirY, light.dirZ).normalized();

/// sRGB (0..1) → linear, for engine light colors.
vm.Vector3 _srgbToLinear(double r, double g, double b) {
  double x(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return vm.Vector3(x(r), x(g), x(b));
}

/// Runtime handle of one object of the loaded scene: animation, materials
/// and placement through the same [ModelData] document the editor edits.
///
/// Mutators keep the document and the visible graph consistent:
/// - kind 'gltf': animation switches and placement apply via the loaded
///   wrapper node — no content rebuild;
/// - everything else: placement and material edits update the document and
///   rebuild the object pass ([GameScene.rebuildContent]).
///
/// Coordinates are the MODEL/EDITOR space (x/z cells, y = base height) —
/// the same values saved to JSON; the mirrored world frame is the renderer's
/// internal concern.
class GameNode {
  final GameScene scene;
  final ModelData model;
  final ModelObject object;

  GameNode(this.scene, this.model, this.object);

  String get id => object.id;
  String get name => object.name;
  String get kind => object.kind;
  ModelObject get data => object;

  // ── placement (model/editor coordinates) ─────────────────────────────

  double get x => object.x;
  double get y => object.y;
  double get z => object.z;
  double get rotY => object.rotY;

  /// The object's world-space anchor in the mirrored render frame — the same
  /// position the renderer places it at (picking, effects, UI anchoring).
  vm.Vector3 get worldPosition {
    final w = chunkWorld(x, z, model.size.w, model.size.l);
    return vm.Vector3(w.x, y, w.z);
  }

  /// World-space AABB in the mirrored render frame: the model-space box
  /// mapped through [chunkWorld]. Used for screen picking and overlays.
  vm.Aabb3 get worldBounds {
    final (minX, minY, minZ) = object.minCorner();
    final (maxX, maxY, maxZ) = object.maxCorner();
    final a = chunkWorld(minX, minZ, model.size.w, model.size.l);
    final b = chunkWorld(maxX, maxZ, model.size.w, model.size.l);
    return vm.Aabb3.minMax(
      vm.Vector3(math.min(a.x, b.x), minY, math.min(a.z, b.z)),
      vm.Vector3(math.max(a.x, b.x), maxY, math.max(a.z, b.z)),
    );
  }

  /// Sets the object's placement (position anchor x/y/z and/or rotY around
  /// its own axis, degrees). When the object is a loaded gltf instance, the
  /// wrapper node is updated live — no rebuild.
  void setPlacement({double? x, double? y, double? z, double? rotY}) {
    if (x != null) object.x = x;
    if (y != null) object.y = y;
    if (z != null) object.z = z;
    if (rotY != null) object.rotY = rotY;
    final wrapper = scene.liveNode(id);
    if (wrapper != null) {
      wrapper.localTransform = _instanceWorld(model, object);
      return;
    }
    scene.rebuildContent();
  }

  /// Sets the placement from the mirrored world frame (the frame of the
  /// camera, picking and the navigation service): [x]/[z] are converted to
  /// model coordinates through the inverse [chunkWorld]; [rotY] is
  /// frame-agnostic (a rotation about Y) and applied as is.
  void setWorldPlacement({double? x, double? z, double? rotY}) {
    setPlacement(
      x: x == null ? null : modelXFromWorld(x, model.size.w),
      z: z == null ? null : modelZFromWorld(z, model.size.l),
      rotY: rotY,
    );
  }

  /// The instance placement matrix (world space) — mirrors the renderer's
  /// `_modelRefWorld` composition exactly, so live transforms and rebuilt
  /// content coincide.
  static vm.Matrix4 _instanceWorld(ModelData m, ModelObject o) {
    final w = chunkWorld(o.x, o.z, m.size.w, m.size.l);
    return vm.Matrix4.translation(vm.Vector3(w.x, o.y, w.z)) *
        objectRotation(o) *
        vm.Matrix4.diagonal3Values(o.scale, o.scale, o.scale);
  }

  // ── glTF animations ──────────────────────────────────────────────────

  bool get isGltf => object.isGltfRef;

  /// Animation descriptors of the gltf resource this object references
  /// (empty until the resource loads — build the scene first).
  List<GltfAnimInfo> get animationClips {
    if (!isGltf) return const [];
    final loaded = scene.resources.gltfAssets.ready(object.gltfName);
    return loaded?.animInfos ?? const [];
  }

  /// The currently selected glTF animation (full name; '' = rest pose).
  String get animation => object.anim;

  /// Plays [fullName] looped ('' or an unknown name stops to the rest pose).
  void playAnimation(String fullName) {
    if (!isGltf) return;
    object.anim = fullName;
    scene.rebuildContent();
  }

  // ── materials / textures ─────────────────────────────────────────────

  /// Swaps the texture of [faceKey] (default: the whole object material) to
  /// the resource [key] ('wallpaper_beige.png' from textures/, or
  /// 'window_4.png' from sprites/ — the family is chosen by [fromSprites]).
  /// Existing stretch/tile/UV settings are kept.
  void setTexture(String key, {String? faceKey, bool fromSprites = false}) {
    final spec = _specOf(faceKey);
    spec.type = fromSprites ? MaterialType.sprite : MaterialType.texture;
    spec.key = key;
    scene.rebuildContent();
  }

  /// Paints [faceKey] (default: the whole object) with a flat color.
  void setColor(int r, int g, int b, {String? faceKey}) {
    final spec = _specOf(faceKey);
    spec.type = MaterialType.color;
    spec.color = [r, g, b];
    scene.rebuildContent();
  }

  ModelMaterial _specOf(String? faceKey) {
    if (faceKey != null) {
      return object.faces.putIfAbsent(faceKey, () => ModelMaterial());
    }
    return object.material ??= ModelMaterial();
  }
}
