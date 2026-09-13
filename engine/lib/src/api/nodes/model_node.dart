import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart' as vm;

import '../../engine_compat/coords.dart';
import '../../models/model_scene.dart';
import '../../scene/model_renderer.dart' show objectRotation;
import '../../services/gltf_asset_store.dart' show GltfAnimInfo;
import '../geometry/wireframe.dart';
import '../materials/scene_material.dart';
import '../pick_geometry.dart';
import '../picking.dart';
import '../scene_controller.dart';
import 'scene_node.dart';

/// A live document object (`model_v1`) placed in the scene.
///
/// The node owns the object's current parameters: moving it moves the object,
/// changing its material repaints it. Coordinates are the MODEL/EDITOR space
/// (x/z cells, y = base height, rotY in degrees) — the same values saved to
/// JSON; the mirrored world frame is the renderer's concern.
class ModelNode extends SceneNode {
  ModelNode(this.controller, this.model, this.object)
    : super(id: object.id, name: object.name);

  /// The controller the object belongs to.
  final SceneController controller;

  /// The document the object belongs to.
  final ModelData model;

  /// The live document object.
  final ModelObject object;

  /// The object kind (`cuboid`, `trapezoid`, `cylinder`, `plane`, `sprite`,
  /// `csg`, `model`, `gltf`).
  String get kind => object.kind;

  // ── placement (model/editor coordinates) ─────────────────────────────

  double get x => object.x;
  double get y => object.y;
  double get z => object.z;
  double get rotY => object.rotY;

  /// The object's world-space anchor in the mirrored render frame.
  vm.Vector3 get worldPosition {
    final w = chunkWorld(x, z, model.size.w, model.size.l);
    return vm.Vector3(w.x, y, w.z);
  }

  /// The world-space AABB in the mirrored render frame.
  @override
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

  /// Sets the placement (anchor x/y/z and/or rotY in degrees). A loaded glTF
  /// instance updates live; other objects rebuild the content.
  void setPlacement({double? x, double? y, double? z, double? rotY}) {
    if (x != null) object.x = x;
    if (y != null) object.y = y;
    if (z != null) object.z = z;
    if (rotY != null) object.rotY = rotY;
    _pickDirty = true;
    final wrapper = controller.liveNode(id);
    if (wrapper != null) {
      wrapper.transform = _instanceWorld(model, object);
      // Live glTF placement skips the full rebuild; keep the overlays (and
      // the wireframe) in sync with the new transform.
      controller.refreshObjectTransforms();
      return;
    }
    controller.rebuild();
  }

  /// Sets the placement from the mirrored world frame.
  void setWorldPlacement({double? x, double? z, double? rotY}) {
    setPlacement(
      x: x == null ? null : modelXFromWorld(x, model.size.w),
      z: z == null ? null : modelZFromWorld(z, model.size.l),
      rotY: rotY,
    );
  }

  static vm.Matrix4 _instanceWorld(ModelData m, ModelObject o) {
    final w = chunkWorld(o.x, o.z, m.size.w, m.size.l);
    return vm.Matrix4.translation(vm.Vector3(w.x, o.y, w.z)) *
        objectRotation(o) *
        vm.Matrix4.diagonal3Values(o.scale, o.scale, o.scale);
  }

  // ── glTF ─────────────────────────────────────────────────────────────

  /// Whether the object references a glTF resource.
  bool get isGltf => object.isGltfRef;

  /// The glTF catalog name of the object (empty for non-glTF objects).
  String get gltfName => object.gltfName;

  /// The fitted bounds of the glTF resource, or null until it loads.
  vm.Aabb3? get gltfBounds {
    final bounds = object.gltfBounds;
    if (bounds == null || bounds.length < 6) return null;
    return vm.Aabb3.minMax(
      vm.Vector3(bounds[0], bounds[1], bounds[2]),
      vm.Vector3(bounds[3], bounds[4], bounds[5]),
    );
  }

  /// The animation clips of the glTF resource (empty until it loads).
  List<GltfAnimInfo> get animationClips {
    if (!isGltf) return const [];
    final loaded = controller.resources?.manager.gltfAssets.ready(gltfName);
    return loaded?.animInfos ?? const [];
  }

  /// Whether the glTF resource import is still in flight (the UI shows a
  /// loading state instead of «no animations»).
  bool get gltfLoading {
    if (!isGltf) return false;
    return controller.resources?.manager.gltfAssets.isLoading(gltfName) ??
        false;
  }

  /// Whether the glTF resource import failed (corrupt/unreadable file).
  bool get gltfFailed {
    if (!isGltf) return false;
    return controller.resources?.manager.gltfAssets.failed(gltfName) ?? false;
  }

  /// The current animation (full name; '' is the rest pose).
  String get animation => object.anim;

  /// Plays [clipFullName] looped ('' or an unknown name returns to rest).
  void play(String clipFullName) {
    if (!isGltf) return;
    object.anim = clipFullName;
    controller.rebuild();
  }

  // ── materials ────────────────────────────────────────────────────────

  /// The document faces of the object (empty for csg/model/gltf objects).
  List<FaceRef> get faces => [
    for (final key in facesOf(object))
      FaceRef(key: key, node: this, material: object.faces[key]),
  ];

  // ── picking ──────────────────────────────────────────────────────────

  List<PickPart>? _pickParts;
  int _pickRevision = -1;
  double _pickYaw = 0;
  bool _pickDirty = true;

  /// Whether the object is a csg operand consumed by a result node (hidden
  /// and rendered through that result).
  bool get isCsgOperand => model.csgParentOf(object.id) != null;

  /// The object's CPU pick pieces in the world (render) frame, cached per
  /// controller revision and camera yaw. Plumbing for the controller's
  /// raycast.
  @override
  Iterable<PickPart> get pickParts {
    if (isCsgOperand) return const [];
    final revision = controller.revision;
    // Billboard sprites are reoriented to the camera every frame, so their
    // pick quad must follow the live yaw rather than the authored rotY.
    final yaw = object.kind == 'sprite'
        ? screenParallelYaw(
            controller.camera.forwardH.x,
            controller.camera.forwardH.z,
          )
        : 0.0;
    if (_pickDirty ||
        _pickParts == null ||
        _pickRevision != revision ||
        _pickYaw != yaw) {
      _pickParts = buildObjectPickParts(
        model,
        object,
        billboardYaw: yaw,
        modelOf: (id) => controller.resources?.model(id),
      );
      _pickRevision = revision;
      _pickYaw = yaw;
      _pickDirty = false;
    }
    return _pickParts!;
  }

  /// The object's true edges in the world as flat endpoint pairs: the
  /// evaluated CSG/rounded result, the per-face primitives, or the instance
  /// footprint box. Used by selection outlines and wireframes; the editor
  /// gets the CSG result outline here instead of raw operands.
  List<vm.Vector3> edges({double? creaseAngleDegrees}) =>
      wireframeSegments(creaseAngleDegrees: creaseAngleDegrees);

  final Set<String> _wireframeFaces = {};

  /// Document nodes are virtual (no host), so the inherited setter must
  /// rebuild the scene for the controller to refresh their overlay.
  @override
  set wireframe(WireframeStyle? value) {
    if (wireframe == value) return;
    super.wireframe = value;
    controller.rebuild();
  }

  /// Whether [faceKey]'s edges are drawn as a wireframe overlay.
  bool faceWireframe(String faceKey) => _wireframeFaces.contains(faceKey);

  @override
  bool get hasWireframe => wireframe != null || _wireframeFaces.isNotEmpty;

  /// Shows or hides the wireframe of one document face. Independent of the
  /// object-level [wireframe].
  void setFaceWireframe(String faceKey, bool enabled) {
    if (enabled) {
      if (!_wireframeFaces.add(faceKey)) return;
    } else {
      if (!_wireframeFaces.remove(faceKey)) return;
    }
    controller.rebuild();
  }

  /// The wireframe edges of the object: every pick piece when the
  /// object-level [wireframe] (or the scene-wide style, passed as [all]) is
  /// on, plus the pieces of the faces selected with [setFaceWireframe]. The
  /// parts are already in the world frame.
  @override
  List<vm.Vector3> wireframeSegments({
    double? creaseAngleDegrees,
    bool all = true,
  }) {
    final includeAll = all || wireframe != null;
    if (!includeAll && _wireframeFaces.isEmpty) return const [];
    final out = <vm.Vector3>[];
    for (final part in pickParts) {
      final key = part.faceKey;
      if (!includeAll && (key == null || !_wireframeFaces.contains(key))) {
        continue;
      }
      appendWireframeEdges(
        out,
        part.geometry,
        creaseAngleDegrees: creaseAngleDegrees,
      );
    }
    return dedupeWireframeSegments(out);
  }

  /// Overrides the runtime material of one face (or the whole object with
  /// `*`). Not saved to the document; pass null to restore the document
  /// material.
  void setFaceMaterial(String faceKey, SceneMaterial? material) {
    final renderer = controller.renderer;
    if (renderer == null) return;
    final key = '$id:$faceKey';
    if (material == null) {
      renderer.materialOverrides.remove(key);
    } else {
      renderer.materialOverrides[key] = material.raw;
    }
    controller.rebuild();
  }

  /// Swaps the texture of [faceKey] (default: the whole object material) to
  /// the resource [key] (`wallpaper_beige.png` from textures/, or
  /// `window_4.png` from sprites/ — the family is chosen by [fromSprites]).
  void setTexture(String key, {String? faceKey, bool fromSprites = false}) {
    final spec = _specOf(faceKey);
    spec.type = fromSprites ? MaterialType.sprite : MaterialType.texture;
    spec.key = key;
    controller.rebuild();
  }

  /// Paints [faceKey] (default: the whole object) with a flat color.
  void setColor(Color color, {String? faceKey}) {
    final spec = _specOf(faceKey);
    spec.type = MaterialType.color;
    spec.color = [
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
    ];
    controller.rebuild();
  }

  ModelMaterial _specOf(String? faceKey) {
    if (faceKey != null) {
      return object.faces.putIfAbsent(faceKey, () => ModelMaterial());
    }
    return object.material ??= ModelMaterial();
  }
}
