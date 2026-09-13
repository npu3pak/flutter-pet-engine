import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../engine_compat/materials.dart';
import '../models/model3d_entry.dart';
import '../models/model_scene.dart';
import '../render/static_merge.dart';
import '../services/app_log.dart';
import '../services/gltf_asset_store.dart';
import '../services/texture_cache.dart';
import 'csg.dart';

/// Node-name prefixes used by picking.
const objectNodePrefix = 'obj:';
const faceNodePrefix = 'face:';
const gizmoNodePrefix = 'gizmo:';

/// The object's rotation matrix about its anchor: Rz(rotZ)·Rx(rotX)·Ry(rotY)
/// (Euler degrees). rotY is the legacy axis; [extraY] adds a rotation
/// applied together with rotY (the game adds the placed model's rotY).
vm.Matrix4 objectRotation(ModelObject obj, {double extraY = 0}) {
  final rx = obj.rotX * math.pi / 180;
  final ry = (obj.rotY + extraY) * math.pi / 180;
  final rz = obj.rotZ * math.pi / 180;
  return vm.Matrix4.rotationZ(rz) * vm.Matrix4.rotationX(rx) * vm.Matrix4.rotationY(ry);
}

/// The screen-parallel billboard rotation: the −X mirror (so the texture is
/// not reflected) followed by the yaw around Y. The sacred convention from
/// `docs/conventions.md`; the renderer, the pick geometry and the editor
/// outline all share it.
vm.Matrix4 spriteBillboardRotation(double yaw) =>
    vm.Matrix4.diagonal3Values(-1, 1, 1) * vm.Matrix4.rotationY(yaw);

/// The full billboard transform of a document sprite: [spriteBillboardRotation]
/// about the anchor.
vm.Matrix4 spriteBillboardMatrix(vm.Vector3 anchor, double yaw) =>
    vm.Matrix4.translation(anchor) * spriteBillboardRotation(yaw);

/// The effective face side for a part: face override first, then the object
/// material, defaulting to 'outer'. Applies to every face key, including
/// the cylinder side and the sprite ('side'/'*').
String sideFor(ModelObject obj, String faceKey) {
  final spec = obj.faces[faceKey] ?? obj.material;
  return spec?.side ?? 'outer';
}

/// 'both' renders both sides (no culling for opaque materials).
bool sideDoubleSided(String side) => side == 'both';

/// The union AABB of a list of objects (model-local): (minX, minY, minZ,
/// maxX, maxY, maxZ). Empty list throws.
(double, double, double, double, double, double) unionAabb(
    List<ModelObject> objects) {
  var (minX, minY, minZ, maxX, maxY, maxZ) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  var first = true;
  for (final o in objects) {
    final (ax, ay, az) = o.minCorner();
    final (bx, by, bz) = o.maxCorner();
    if (first) {
      (minX, minY, minZ, maxX, maxY, maxZ) = (ax, ay, az, bx, by, bz);
      first = false;
    } else {
      minX = ax < minX ? ax : minX;
      minY = ay < minY ? ay : minY;
      minZ = az < minZ ? az : minZ;
      maxX = bx > maxX ? bx : maxX;
      maxY = by > maxY ? by : maxY;
      maxZ = bz > maxZ ? bz : maxZ;
    }
  }
  if (first) throw StateError('unionAabb: empty object list');
  return (minX, minY, minZ, maxX, maxY, maxZ);
}

/// The center of the union AABB of [objects] (model-local (x, y, z)).
(double, double, double) groupCenter(List<ModelObject> objects) {
  final (minX, minY, minZ, maxX, maxY, maxZ) = unionAabb(objects);
  return ((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
}

/// The matrix placing a model instance (kind 'model') into its containing
/// model's local space: translation to (x, y, z) · Rz·Rx·Ry rotation ·
/// uniform scale (the scale is uniform, so order with the rotation is
/// irrelevant). The outer chunkWorld mirror happens only at the very end.
vm.Matrix4 instanceTransformOf(ModelObject o) =>
    vm.Matrix4.translation(vm.Vector3(o.x, o.y, o.z)) *
    objectRotation(o) *
    vm.Matrix4.diagonal3Values(o.scale, o.scale, o.scale);

/// The world-space anchor of an object inside a model whose grid is
/// [w]×[l] (the model rendered standalone): its cell (x, z) mapped through
/// the mirrored, centered chunkWorld frame of that grid, y as authored.
/// Renders content of a model instance in the source's own standalone
/// frame — every object of the referenced model lands exactly where it
/// would stand in the model's standalone scene (top-level CSG/rounded
/// content bakes this same mapping into its vertices).
vm.Vector3 sourceAnchor(int w, int l, ModelObject o) {
  final a = chunkWorld(o.x, o.z, w, l);
  return vm.Vector3(a.x, o.y, a.z);
}

/// The fuchsia placeholder cuboid standing in for a model instance whose
/// source model was deleted: it covers the cached source footprint (the
/// grid of the missing model), so the hole is visible on the scene.
ModelObject modelRefCubeProxy(ModelObject ref) {
  final w = (ref.refSize?.w ?? 1).toDouble();
  final l = (ref.refSize?.l ?? 1).toDouble();
  final h = (ref.refSize?.h ?? 1).toDouble();
  return ModelObject(
    id: ref.id,
    name: '${ref.name} (удалена)',
    kind: 'cuboid',
    x: (w - 1) / 2,
    y: 0,
    z: (l - 1) / 2,
    dims: {'w': w, 'h': h, 'd': l},
    material: ModelMaterial(type: MaterialType.color, color: const [255, 0, 255]),
  );
}

/// The world-frame footprint box of a model instance's source content: a
/// cuboid CENTERED on the instance anchor with the cached source grid
/// dimensions. This is where the referenced model's standalone content
/// actually lands (anchored by [sourceAnchor]), so picking, wireframe edges
/// and the missing-source placeholder all agree with the render.
///
/// [modelRefCubeProxy] stays the authoring-cell variant (its cells are
/// offset to the source grid centre) used by [unionAabbResolved] and the
/// legacy nested-missing branch.
ModelObject modelRefFootprintBox(ModelObject ref) {
  final w = (ref.refSize?.w ?? 1).toDouble();
  final l = (ref.refSize?.l ?? 1).toDouble();
  final h = (ref.refSize?.h ?? 1).toDouble();
  return ModelObject(
    id: ref.id,
    name: ref.name,
    kind: 'cuboid',
    x: 0,
    y: 0,
    z: 0,
    dims: {'w': w, 'h': h, 'd': l},
    material: ModelMaterial(type: MaterialType.color, color: const [255, 0, 255]),
  );
}

/// The synthetic cuboid standing in for a gltf instance's footprint: the
/// box its content occupies in the instance's own frame — fitted so minY =
/// 0 (the anchor's floor) with X/Z centered ([ModelObject.gltfBounds]; a
/// 1×1×1 cube when unknown). Placeholder/fuchsia visuals render this box,
/// and outlines/AABBs resolve it under the instance transform.
ModelObject gltfFootprintBox(ModelObject ref) {
  final b = ref.gltfBounds;
  final w = b == null ? 1.0 : (b[3] - b[0]).abs();
  final h = b == null ? 1.0 : (b[4] - b[1]).abs();
  final d = b == null ? 1.0 : (b[5] - b[2]).abs();
  return ModelObject(
    id: ref.id,
    name: '${ref.name} (gltf)',
    kind: 'cuboid',
    x: 0,
    y: 0,
    z: 0,
    dims: {'w': w, 'h': h, 'd': d},
  );
}

/// The fuchsia placeholder cuboid standing in for a gltf instance whose
/// resource (`3d_models/`) was deleted: it covers the cached footprint of
/// the missing model ([gltfFootprintBox] colored fuchsia).
ModelObject gltfRefCubeProxy(ModelObject ref) {
  final box = gltfFootprintBox(ref);
  return ModelObject(
    id: ref.id,
    name: '${ref.name} (удалена)',
    kind: 'cuboid',
    x: box.x,
    y: box.y,
    z: box.z,
    dims: {'w': box.dim('w', 1), 'h': box.dim('h', 1), 'd': box.dim('d', 1)},
    material: ModelMaterial(type: MaterialType.color, color: const [255, 0, 255]),
  );
}

/// The x-mirror of the model→world conventions (also part of the
/// chunkWorld frame inversion used by the CPU-side folding helpers below).
final _kMirrorX = vm.Matrix4.diagonal3Values(-1, 1, 1);

/// The map of a model instance's CONTENT cells into the containing model's
/// authoring space under the standalone-frame convention: a source cell
/// [gridW]×[gridL] is first reflected about the source grid center
/// (chunkWorld), then rotated/scaled about the instance anchor with the
/// X-mirror undone — the authoring cell whose chunkWorld display equals the
/// rendered world position. Pure; mirrors the renderer's nested emission
/// (`_buildNestedScene`: content anchored via [sourceAnchor], csg/rounded
/// vertices carrying the same reflection).
vm.Matrix4 instanceContentCells(ModelObject o, int gridW, int gridL) {
  final ox = (gridW - 1) / 2, oz = (gridL - 1) / 2;
  return vm.Matrix4.translation(vm.Vector3(o.x, o.y, o.z)) *
      _kMirrorX *
      objectRotation(o) *
      vm.Matrix4.diagonal3Values(o.scale, o.scale, o.scale) *
      vm.Matrix4.translation(vm.Vector3(ox, 0, -oz)) *
      _kMirrorX;
}

/// The map of an instance's own-cell boxes (gltf footprint, fuchsia cube of
/// a missing source) into the authoring space: the box cells (centered on
/// the instance cell) mirror-rotate-scale about the anchor. Matches the
/// renderer's placeholder emission (`_modelRefWorld` · box).
vm.Matrix4 instanceBoxCells(ModelObject o) =>
    vm.Matrix4.translation(vm.Vector3(o.x, o.y, o.z)) *
    _kMirrorX *
    objectRotation(o) *
    vm.Matrix4.diagonal3Values(o.scale, o.scale, o.scale);

/// The union AABB of [objects] in the containing model's authoring-cell
/// coordinates, resolving model instances through [modelOf]: instance
/// content folds in with the standalone-frame mapping
/// ([instanceContentCells]), so the bounds match what the instance renders
/// (its grid center at the anchor, content mirrored about the source grid
/// center). A missing source falls back to the cached cube footprint; csg
/// nodes keep their plain box (callers normally pre-expand them). Rotation
/// of instances is honored by transforming their content corners. Pure.
(double, double, double, double, double, double) unionAabbResolved(
  List<ModelObject> objects, {
  ModelData? Function(String id)? modelOf,
}) {
  var (minX, minY, minZ, maxX, maxY, maxZ) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
  var first = true;
  void extend(double x0, double y0, double z0, double x1, double y1, double z1) {
    if (x0 > x1) {
      final t = x0;
      x0 = x1;
      x1 = t;
    }
    if (y0 > y1) {
      final t = y0;
      y0 = y1;
      y1 = t;
    }
    if (z0 > z1) {
      final t = z0;
      z0 = z1;
      z1 = t;
    }
    if (first) {
      (minX, minY, minZ, maxX, maxY, maxZ) = (x0, y0, z0, x1, y1, z1);
      first = false;
    } else {
      minX = x0 < minX ? x0 : minX;
      minY = y0 < minY ? y0 : minY;
      minZ = z0 < minZ ? z0 : minZ;
      maxX = x1 > maxX ? x1 : maxX;
      maxY = y1 > maxY ? y1 : maxY;
      maxZ = z1 > maxZ ? z1 : maxZ;
    }
  }

  // The 8 corners of an object's box, transformed by [m] (the chain into
  // the local space of the caller).
  void walkBox(ModelObject o, vm.Matrix4 m) {
    final (ax, ay, az) = o.minCorner();
    final (bx, by, bz) = o.maxCorner();
    final corners = [
      vm.Vector3(ax, ay, az),
      vm.Vector3(bx, ay, az),
      vm.Vector3(ax, by, az),
      vm.Vector3(ax, ay, bz),
      vm.Vector3(bx, by, az),
      vm.Vector3(bx, ay, bz),
      vm.Vector3(ax, by, bz),
      vm.Vector3(bx, by, bz),
    ];
    for (final c in corners) {
      final p = m.transform3(c);
      extend(p.x, p.y, p.z, p.x, p.y, p.z);
    }
  }

  // [guard] is the ancestry path of model ids: a model already on the path
  // would mean a reference cycle (only possible in hand-edited files).
  void walk(ModelObject o, vm.Matrix4 m, Set<String> guard) {
    if (o.isGltfRef) {
      // A gltf instance folds in its cached footprint box (the fitted local
      // bounds; a 1×1×1 cube when unknown), centered on its own cell.
      walkBox(gltfFootprintBox(o), m * instanceBoxCells(o));
      return;
    }
    if (!o.isModelRef) {
      walkBox(o, m);
      return;
    }
    final target = modelOf?.call(o.refModelId);
    if (target == null) {
      walkBox(modelRefCubeProxy(o), m * instanceBoxCells(o));
      return;
    }
    if (!guard.add(target.id)) return;
    final refM = m * instanceContentCells(o, target.size.w, target.size.l);
    for (final v in target.visibleObjects()) {
      if (v.isCsg) {
        for (final leaf in target.csgLeavesOf(v.id)) {
          walkBox(leaf, refM);
        }
        continue;
      }
      walk(v, refM, guard);
    }
    guard.remove(target.id);
  }

  for (final o in objects) {
    walk(o, vm.Matrix4.identity(), <String>{});
  }
  if (first) throw StateError('unionAabbResolved: empty object list');
  return (minX, minY, minZ, maxX, maxY, maxZ);
}

/// The engine's front face is the side OPPOSITE the winding's cross product
/// (left-handed projection w'=z + NDC y-flip). Our cuboid/trapezoid/plane
/// quads are wound with an OUTWARD cross → their front is inside, so outer
/// faces need the flip; 'inner' faces render as-is (visible from inside).
bool quadFlipFor(String side) => side != 'inner';

/// The cylinder strip is wound with an INWARD cross → its front is outside;
/// only 'inner' faces need the flip.
bool stripFlipFor(String side) => side == 'inner';

/// Cap discs are wound facing +Y. For the top cap that is the outside, for
/// the bottom cap it is the inside — so the bottom cap flips for 'outer'.
bool capFlipFor(String side, String faceKey) =>
    faceKey == '-y' ? side != 'inner' : side == 'inner';

/// The trapezoid's bottom face follows the cuboid convention (cross
/// outward → flip for 'outer'), while its top and sloped sides are wound
/// outside-facing as-is (like the cylinder strip) → flip for 'inner'.
bool trapezoidFlipFor(String side, String faceKey) =>
    faceKey == '-y' ? quadFlipFor(side) : stripFlipFor(side);

/// The four corners of a cuboid face, wound outward (so raycast normals
/// face out of the solid). Each face varies two axes and fixes the third;
/// the corners are 4 distinct points on the face's plane. Y spans 0..h —
/// the object's BASE sits at the anchor (the model convention).
List<vm.Vector3> cuboidFaceCorners(String faceKey, double w, double h, double d) {

  final hx = w / 2, hz = d / 2;
  final f = faceKey;
  if (f == '+z') {
    return [
      vm.Vector3(-hx, 0, hz),
      vm.Vector3(hx, 0, hz),
      vm.Vector3(hx, h, hz),
      vm.Vector3(-hx, h, hz),
    ];
  }
  if (f == '-z') {
    return [
      vm.Vector3(hx, 0, -hz),
      vm.Vector3(-hx, 0, -hz),
      vm.Vector3(-hx, h, -hz),
      vm.Vector3(hx, h, -hz),
    ];
  }
  if (f == '+x') {
    return [
      vm.Vector3(hx, 0, hz),
      vm.Vector3(hx, 0, -hz),
      vm.Vector3(hx, h, -hz),
      vm.Vector3(hx, h, hz),
    ];
  }
  if (f == '-x') {
    return [
      vm.Vector3(-hx, 0, -hz),
      vm.Vector3(-hx, 0, hz),
      vm.Vector3(-hx, h, hz),
      vm.Vector3(-hx, h, -hz),
    ];
  }
  if (f == '+y') {
    return [
      vm.Vector3(-hx, h, hz),
      vm.Vector3(hx, h, hz),
      vm.Vector3(hx, h, -hz),
      vm.Vector3(-hx, h, -hz),
    ];
  }
  // -y
  return [
    vm.Vector3(-hx, 0, -hz),
    vm.Vector3(hx, 0, -hz),
    vm.Vector3(hx, 0, hz),
    vm.Vector3(-hx, 0, hz),
  ];
}

/// The four model-local corners of a trapezoid face: bottom and top edges
/// (top is inset — the sloped silhouette). Same winding as the parts.
List<vm.Vector3> trapezoidFaceCorners(
  String faceKey,
  double bw,
  double bd,
  double tw,
  double td,
  double h,
) {
  final bhx = bw / 2, bhz = bd / 2;
  final thx = tw / 2, thz = td / 2;
  final b = [
    vm.Vector3(-bhx, 0, -bhz),
    vm.Vector3(bhx, 0, -bhz),
    vm.Vector3(bhx, 0, bhz),
    vm.Vector3(-bhx, 0, bhz),
  ];
  final t = [
    vm.Vector3(-thx, h, -thz),
    vm.Vector3(thx, h, -thz),
    vm.Vector3(thx, h, thz),
    vm.Vector3(-thx, h, thz),
  ];
  return switch (faceKey) {
    '-y' => [b[0], b[1], b[2], b[3]],
    '+y' => [t[0], t[1], t[2], t[3]],
    '-z' => [b[0], b[1], t[1], t[0]],
    '+x' => [b[1], b[2], t[2], t[1]],
    '+z' => [b[2], b[3], t[3], t[2]],
    _ => [b[3], b[0], t[0], t[3]],
  };
}

/// The four model-local corners of a plane's quad (vertical = upright
/// +z-facing quad, horizontal = flat on the ground).
List<vm.Vector3> planeFaceCorners(bool vertical, double w, double d) =>
    vertical
        ? [
            vm.Vector3(-w / 2, 0, 0),
            vm.Vector3(w / 2, 0, 0),
            vm.Vector3(w / 2, d, 0),
            vm.Vector3(-w / 2, d, 0),
          ]
        : [
            vm.Vector3(-w / 2, 0, d / 2),
            vm.Vector3(w / 2, 0, d / 2),
            vm.Vector3(w / 2, 0, -d / 2),
            vm.Vector3(-w / 2, 0, -d / 2),
          ];

/// The four model-local corners of a sprite quad (vertical, +z facing;
/// the node transform carries the billboard yaw).
List<vm.Vector3> spriteFaceCorners(double w, double h) => [
      vm.Vector3(-w / 2, 0, 0),
      vm.Vector3(w / 2, 0, 0),
      vm.Vector3(w / 2, h, 0),
      vm.Vector3(-w / 2, h, 0),
    ];

/// The four model-local corners of a flat face for any kind (empty for the
/// cylinder, whose parts are rings handled separately, and for the curved
/// 'round' zones of a rounded cuboid).
List<vm.Vector3> faceCorners(ModelObject obj, String faceKey) => switch (obj.kind) {
      'cuboid' => faceKey == roundFaceKey
          ? const []
          : cuboidFaceCorners(
              faceKey, obj.dim('w', 1), obj.dim('h', 1), obj.dim('d', 1)),
      'trapezoid' => trapezoidFaceCorners(
          faceKey,
          obj.dim('bottomW', 1),
          obj.dim('bottomD', 1),
          obj.dim('topW', 0.5),
          obj.dim('topD', 0.5),
          obj.dim('h', 0.5),
        ),
      'plane' => planeFaceCorners(obj.flag('vertical'), obj.dim('w', 1), obj.dim('d', 1)),
      'sprite' => spriteFaceCorners(obj.dim('w', 1), obj.dim('h', 1)),
      _ => const [],
    };

/// The centered u-inset of a narrowing face/ring: a texture keeps a uniform
/// texel density when its u span shrinks to [ratio] (the top width relative
/// to the bottom), centered — the narrowing shape CLIPS the texture instead
/// of squeezing it. ratio 1 → 0 (no inset); ratio 0 → 0.5 (a point).
double centeredInset(double ratio) => (1 - ratio) / 2;

/// The u at ring vertex [s] (of [segments]) for a ring that is [ringRatio]×
/// the strip's WIDEST ring: the u span shrinks to [ringRatio], centered —
/// the same uniform-density/clip principle as [centeredInset]. A cylinder
/// (ringRatio 1) reproduces the classic wrap (u = s/segments); a cone
/// (ringRatio 0) converges to the slice's center at the apex.
double sideRingU(int s, int segments, double ringRatio) =>
    (s + (1 - ringRatio) / 2) / segments;

/// The four base (u, v) pairs of [_quadPart]'s quad: the bottom edge sits
/// at v = 1 with u 0..1, the top edge at v = 0 with the u span shrunk to
/// (topInsetU, 1−topInsetU) — the narrowing face CLIPS the texture instead
/// of squeezing it. [uScale]/[vScale] scale the spans (tiling). Pure —
/// unit-tested without a GPU.
List<(double, double)> quadBaseUv({
  required double topInsetU,
  required double uScale,
  required double vScale,
}) =>
    [
      (0.0 * uScale, 1.0 * vScale),
      (1.0 * uScale, 1.0 * vScale),
      ((1.0 - topInsetU) * uScale, 0.0 * vScale),
      (topInsetU * uScale, 0.0 * vScale),
    ];

/// One textured part of a solid: geometry + which face it belongs to.
class SolidPart {
  final String faceKey; // '+x'..'-z', or 'side'/'*' for non-face parts
  final Geometry geometry;

  /// Local offset applied on top of the object transform (e.g. cylinder
  /// caps sit at ±h/2, while the side is centered on the origin).
  final vm.Vector3? offset;

  SolidPart(this.faceKey, this.geometry, {this.offset});
}

/// Alpha mode for a part's texture material: sprite primitives keep blend
/// (transparent billboards); solid faces use mask so they draw in the opaque
/// pass with correct per-fragment depth instead of the depth-sorted
/// translucent pass (which sorts per node and lets equi-distant faces
/// overlap in the wrong order).
AlphaMode faceAlphaMode(String kind) =>
    kind == 'sprite' ? AlphaMode.blend : AlphaMode.mask;

/// Builds the scene graph for one [ModelData] and renders it into [root].
/// Materials resolve through [TextureCache]; parts whose texture is still
/// loading render as the default gray and call [onTextureReady] once loaded
/// so the caller can rebuild.
class ModelRenderer {
  final Node root = Node(name: 'model-root');

  ModelData? _model;
  TextureCache textures;
  void Function()? onTextureReady;

  /// Global object opacity: 1.0 normally, 0.25 in the walkability mode
  /// (ghosted objects, the grid must stay visible). Applied per material
  /// on every rebuild.
  double opacity = 1.0;

  ModelRenderer(this.textures, {this.gltfAssets, this.mergeStatic = false});

  /// Whether static solid/csg geometry is merged by material into one mesh
  /// per group at the end of a rebuild. Games enable it to cut draw calls
  /// (a room drops from ~100 nodes to a handful); the editor keeps the
  /// per-face nodes for picking. Dynamic content (sprites, glTF, nested
  /// instances) is never merged.
  final bool mergeStatic;

  /// Static nodes collected during a rebuild as merge candidates (only when
  /// [mergeStatic]); cleared at the start of every rebuild.
  final List<Node> _mergeCandidates = [];

  /// Per-rebuild material cache: identical specs share one [Material]
  /// instance, so merge groups key on material identity. Cleared on rebuild
  /// because texture readiness changes the resolved material.
  final Map<String, Material> _materialCache = {};

  /// Catalog of the project's models (by id) for resolving model instances
  /// (kind 'model'). Set by the editor; without it instances render as their
  /// fuchsia placeholder cube.
  ModelData? Function(String id)? modelCatalog;

  ModelData? _resolveModel(String id) => modelCatalog?.call(id);

  /// Runtime cache of the imported `3d_models/` resources (gltf instances,
  /// kind 'gltf'). Set by the editor; without it gltf instances never load —
  /// they render their footprint placeholder only.
  final GltfAssetStore? gltfAssets;

  /// Catalog of the project's `3d_models/` entries (by catalog name) for
  /// resolving gltf instances. Set by the editor; a null entry means the
  /// resource is gone (fuchsia cube).
  Model3dEntry? Function(String name)? gltfCatalog;

  /// Whether the gltf catalog scan has completed. While it hasn't (false),
  /// instances are «unknown yet»: they show their neutral placeholder and
  /// do not decide on missing/fuchsia until the scan settles.
  bool Function()? gltfCatalogReady;

  /// Reports the fitted footprint of a loaded gltf instance
  /// ([modelId], [objId], bounds in the instance's frame) so the caller can
  /// cache it on the model object (the fuchsia cube's box after a delete).
  void Function(String modelId, String objId, List<double> bounds)?
      onGltfFootprint;

  /// Objects keyed by node name (`obj:<id>` or `face:<id>:<key>`).
  final Map<String, String> nodeObjectId = {};
  final Map<String, String> nodeFaceKey = {};
  final Map<String, Node> allNodes = {};

  /// Billboard sprites inside model instances: (node, chain without yaw).
  /// Reoriented per frame together with the top-level sprite billboards.
  final List<(Node, vm.Matrix4)> instanceBillboards = [];

  /// Element id → the nodes it produced in the current rebuild, across every
  /// kind (top-level faces, csg/rounded parts, nested model content, gltf
  /// wrappers). The level baker groups these per element, so a multi-part
  /// element bakes as one movable unit.
  final Map<String, List<Node>> elementNodes = {};

  /// Reverse index of [elementNodes]: node → its owning element id. Identity
  /// keyed — nested parts share node names and would collide in a name map.
  final Map<Node, String> elementOfNode = {};

  /// The local part offset applied after the object's base transform
  /// (solid primitives with per-face parts); used by
  /// [updateObjectTransforms] to refresh a moved object without rebuilding.
  final Map<Node, vm.Matrix4> _nodePartOffset = {};

  /// Whole-object wrapper nodes of attached gltf instances, by object id
  /// (kind 'gltf'). A gltf instance is the only object kind whose content
  /// mounts under ONE node — games move/rotate it live without a rebuild
  /// ([GameNode]). Nested instances inside model refs share the container's
  /// object id; the last one wins (top-level objects are the runtime target).
  final Map<String, Node> gltfWrappers = {};

  /// Persistent per-instance runtimes of gltf instances (kind 'gltf'),
  /// keyed by `'<modelPath>/<objId>/<gltfName>'`. They survive scene rebuilds
  /// so loaded content is not re-imported and clip playback continues.
  final Map<String, _GltfRuntime> _gltfRuntimes = {};

  /// Runtime keys used by the current rebuild (the prune pass keeps only
  /// those).
  final Set<String> _gltfUsedKeys = {};

  ModelData? get model => _model;

  void rebuild(ModelData model) {
    _model = model;
    syncTextureRoot(textures);
    root.removeAll();
    nodeObjectId.clear();
    nodeFaceKey.clear();
    allNodes.clear();
    instanceBillboards.clear();
    elementNodes.clear();
    elementOfNode.clear();
    _nodePartOffset.clear();
    gltfWrappers.clear();
    _pendingCounts.clear();
    _mergeCandidates.clear();
    _materialCache.clear();
    _builtParts = 0;
    _missingParts = 0;
    _gltfUsedKeys.clear();
    final sw = Stopwatch()..start();
    _buildObjects(model);
    if (mergeStatic) _mergeStaticNodes();
    // Drop runtimes of gltf instances that no longer exist in this model
    // (deleted/undone objects, replaced sources, model switches).
    _gltfRuntimes.removeWhere((key, rt) {
      if (_gltfUsedKeys.contains(key)) return false;
      rt.dispose();
      return true;
    });
    logStage(
      'renderer',
      'rebuild ${model.id} objects=${model.objects.length} '
          'parts=$_builtParts nodes=${root.children.length} '
          'pending=$_pendingCounts missing=$_missingParts '
          'gltf=${_gltfRuntimes.length}',
      ms: sw.elapsedMilliseconds,
    );
  }

  // ── objects ──────────────────────────────────────────────────────────

  /// Drops the current model content: removes every built node, clears the
  /// tracking maps and disposes the persistent glTF runtimes. Used when the
  /// document is unloaded — without it the previous model's geometry would
  /// stay in the render scene.
  void clear() {
    _model = null;
    root.removeAll();
    nodeObjectId.clear();
    nodeFaceKey.clear();
    allNodes.clear();
    instanceBillboards.clear();
    elementNodes.clear();
    elementOfNode.clear();
    _nodePartOffset.clear();
    gltfWrappers.clear();
    _pendingCounts.clear();
    _mergeCandidates.clear();
    _materialCache.clear();
    _builtParts = 0;
    _missingParts = 0;
    _gltfUsedKeys.clear();
    for (final runtime in _gltfRuntimes.values) {
      runtime.dispose();
    }
    _gltfRuntimes.clear();
  }

  /// Refreshes the local transforms of the already-built nodes of [model]'s
  /// solid objects (cuboid, trapezoid, cylinder, plane) without touching
  /// their geometry — the fast path for move/rotate drags. Content whose
  /// vertices bake the placement (csg, rounded cuboids, model/gltf
  /// instances, sprites) is left to a full [rebuild]; returns true when at
  /// least one node was refreshed.
  ///
  /// [translated] maps element ids to a WORLD translation applied since the
  /// previous call (one drag step). Every node of those elements gets the
  /// translation prepended to its current local transform — no geometry,
  /// CSG, material or instance-chain work. This is the fast path for moving
  /// baked content: model instances, CSG results, rounded cuboids and gltf
  /// wrappers. The caller passes the actual (snapped) step per element, so
  /// snapping stays consistent with the document.
  bool updateObjectTransforms(
    ModelData model, {
    Map<String, vm.Vector3>? translated,
  }) {
    _model = model;
    var updated = false;
    for (final entry in elementNodes.entries) {
      final obj = model.objectById(entry.key);
      if (obj == null) continue;
      final delta = translated?[entry.key];
      if (delta != null && delta.length2 > 1e-18) {
        final step = vm.Matrix4.translation(delta);
        for (final node in entry.value) {
          node.localTransform = step * node.localTransform;
          updated = true;
        }
        // Billboard sprites nested in an instance re-orient every frame from
        // a chain snapshotted at build: shift the chain too, otherwise the
        // per-frame reorient would snap them back to the old placement.
        if (instanceBillboards.isNotEmpty) {
          for (var i = 0; i < instanceBillboards.length; i++) {
            final (node, chain) = instanceBillboards[i];
            if (elementOfNode[node] != entry.key) continue;
            instanceBillboards[i] = (node, step * chain);
          }
        }
        continue;
      }
      if (obj.isCsg ||
          obj.isModelRef ||
          obj.isGltfRef ||
          obj.kind == 'sprite' ||
          (obj.kind == 'cuboid' && isRoundedCuboid(obj))) {
        continue;
      }
      final base = _objTransform(obj);
      for (final node in entry.value) {
        final offset = _nodePartOffset[node];
        node.localTransform = offset == null ? base : base * offset;
        updated = true;
      }
    }
    return updated;
  }

  void _buildObjects(ModelData model) {
    // Hidden csg operands render through their result nodes only.
    for (final obj in model.visibleObjects()) {
      if (obj.isCsg) {
        _buildCsgObject(model, obj);
      } else if (obj.isModelRef) {
        _buildModelRef(model, obj);
      } else if (obj.isGltfRef) {
        final world = _modelRefWorld(model, obj);
        _buildGltfInstance(
          model.id,
          obj,
          ownerId: obj.id,
          world: world,
          key: '${model.id}/${obj.id}/${obj.gltfName}',
        );
      } else {
        _buildObject(model, obj);
      }
    }
  }

  /// Merges static candidate nodes by shared material into one mesh per
  /// material, baking each node's local transform into the vertices (and
  /// reversing triangle winding for mirroring transforms, matching the
  /// renderer's per-node winding parity). Nodes that have no sibling with
  /// the same material stay as they are. Called at the end of a rebuild when
  /// [mergeStatic] is on.
  void _mergeStaticNodes() {
    if (_mergeCandidates.length < 2) return;
    final result = mergeStaticNodes(_mergeCandidates);
    for (final merged in result.merged) {
      root.add(merged);
    }
    for (final node in result.consumed) {
      root.remove(node);
      allNodes.remove(node.name);
      nodeObjectId.remove(node.name);
      nodeFaceKey.remove(node.name);
      final owner = elementOfNode.remove(node);
      if (owner != null) elementNodes[owner]?.remove(node);
    }
  }

  /// Registers [node] as a part of the element [id] (both directions).
  void _registerElementNode(String id, Node node) {
    elementOfNode[node] = id;
    elementNodes.putIfAbsent(id, () => []).add(node);
  }

  /// Billboard sprites of the current rebuild: top-level sprites (chain null —
  /// their transform carries the anchor) and sprites nested in model
  /// instances (chain without yaw). The level baker snapshots this list so a
  /// baked level keeps its sprites camera-facing.
  List<(Node, vm.Matrix4?)> get billboards {
    final out = <(Node, vm.Matrix4?)>[];
    final model = _model;
    if (model != null) {
      for (final entry in nodeObjectId.entries) {
        final obj =
            model.objects.where((o) => o.id == entry.value).firstOrNull;
        if (obj == null || obj.kind != 'sprite') continue;
        final node = allNodes[entry.key];
        if (node == null) continue;
        out.add((node, null));
      }
    }
    for (final (node, chain) in instanceBillboards) {
      out.add((node, chain));
    }
    return out;
  }

  /// Builds one model instance (kind 'model'): renders the referenced
  /// model's whole scene under the instance transform — as one pickable
  /// unit (`obj:<id>` nodes). The referenced content recursively renders
  /// its own instances and csg operations; a missing source model renders
  /// as a fuchsia cube of the cached source size so the break is visible.
  void _buildModelRef(ModelData model, ModelObject ref) {
    final target = _resolveModel(ref.refModelId);
    final chain = _modelRefWorld(model, ref);
    if (target == null) {
      // The placeholder covers exactly where the source content would land:
      // centered on the instance anchor.
      _emitInstanceObject(ref.id, modelRefFootprintBox(ref), chain);
      return;
    }
    _buildNestedScene(
      target,
      ref.id,
      chain,
      {model.id, target.id},
      keyPath: '${model.id}/${ref.id}',
    );
  }

  /// The world transform mapping a referenced model's STANDALONE frame into
  /// the container's world: anchor (mirrored chunkWorld of the container
  /// grid) · rotation · uniform scale. Mirroring happens only through this
  /// outer translation — nested content is emitted in the source's own
  /// standalone frame (anchors [sourceAnchor], csg/rounded vertices carry
  /// the source-frame mirror) and rides this det > 0 chain unchanged.
  vm.Matrix4 _modelRefWorld(ModelData model, ModelObject ref) {
    final w = chunkWorld(ref.x, ref.z, model.size.w, model.size.l);
    return vm.Matrix4.translation(vm.Vector3(w.x, ref.y, w.z)) *
        objectRotation(ref) *
        vm.Matrix4.diagonal3Values(ref.scale, ref.scale, ref.scale);
  }

  /// Recursively builds every object of [src] (a model placed as an
  /// instance) under the accumulated [localToWorld] chain, which maps the
  /// source model's STANDALONE frame (its grid centered and X-mirrored
  /// through [chunkWorld]) into the container world. Every direct object is
  /// placed exactly as in [src]'s own standalone scene — cell anchors via
  /// [sourceAnchor], csg/rounded content with the source-frame mirror baked
  /// into its vertices — so the instance looks like the source rendered
  /// standalone. All part nodes carry the owner instance's id so picking
  /// returns the whole instance. [keyPath] is the ancestor-instance path
  /// used to key gltf runtimes uniquely (the same gltf object under two
  /// instances gets two runtimes).
  void _buildNestedScene(
    ModelData src,
    String ownerId,
    vm.Matrix4 localToWorld,
    Set<String> guard, {
    String keyPath = '',
  }) {
    for (final obj in src.visibleObjects()) {
      if (obj.isCsg) {
        _buildNestedCsg(src, obj, ownerId, localToWorld);
        continue;
      }
      if (obj.isModelRef) {
        final inner = _resolveModel(obj.refModelId);
        if (inner == null) {
          // A missing inner source renders its fuchsia footprint cube where
          // the nested content would land (the source-frame anchor).
          _emitInstanceObject(
            ownerId,
            modelRefFootprintBox(obj),
            localToWorld *
                vm.Matrix4.translation(
                  sourceAnchor(src.size.w, src.size.l, obj),
                ) *
                objectRotation(obj) *
                vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale),
          );
        } else if (guard.add(inner.id)) {
          final chain = localToWorld *
              vm.Matrix4.translation(sourceAnchor(src.size.w, src.size.l, obj)) *
              objectRotation(obj) *
              vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
          _buildNestedScene(inner, ownerId, chain, guard,
              keyPath: '$keyPath/${obj.id}');
          guard.remove(inner.id);
        }
        continue;
      }
      if (obj.isGltfRef) {
        final chain = localToWorld *
            vm.Matrix4.translation(sourceAnchor(src.size.w, src.size.l, obj)) *
            objectRotation(obj) *
            vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
        _buildGltfInstance(
          src.id,
          obj,
          ownerId: ownerId,
          world: chain,
          key: '$keyPath/${obj.id}/${obj.gltfName}',
        );
        continue;
      }
      if (obj.kind == 'cuboid' && isRoundedCuboid(obj)) {
        // A rounded cuboid inside an instance renders like a csg result of
        // the source, emitted with the source-frame mirror exactly like the
        // top-level path — under the instance chain.
        _buildNestedCsg(src, obj, ownerId, localToWorld);
        continue;
      }
      _emitInstanceObject(ownerId, obj, localToWorld,
          anchor: sourceAnchor(src.size.w, src.size.l, obj));
    }
  }

  /// Builds one glTF/GLB instance (kind 'gltf'): the imported resource tree
  /// (a clone of the asset-store cache) is attached under an `obj:<id>`
  /// wrapper at [world] — as one pickable unit. While the resource loads it
  /// shows a neutral footprint placeholder; a missing/deleted resource (or a
  /// failed import) renders as the fuchsia footprint cube. The chosen glTF
  /// animation ([ModelObject.anim]) plays looped on the attached content.
  void _buildGltfInstance(
    String srcId,
    ModelObject obj, {
    required String ownerId,
    required vm.Matrix4 world,
    required String key,
  }) {
    _gltfUsedKeys.add(key);
    final catalogReady = gltfCatalogReady?.call() ?? true;
    final entry = gltfCatalog?.call(obj.gltfName);
    final assets = gltfAssets;
    // The catalog scan has not settled yet — the entry may simply not be
    // visible. Show the neutral placeholder until a rebuild after the scan.
    if (!catalogReady) {
      _emitGltfCube(ownerId, obj, world,
          color: const [150, 150, 150], suffix: '');
      return;
    }
    if (entry == null || assets == null) {
      // Resource deleted (or no runtime): fuchsia cube of the cached
      // footprint. Drop the runtime so a later re-import starts fresh.
      _gltfRuntimes.remove(key)?.dispose();
      _emitGltfCube(ownerId, obj, world,
          color: const [255, 0, 255], suffix: ' (удалена)');
      return;
    }
    final rt = _gltfRuntimes.putIfAbsent(
        key, () => _GltfRuntime(obj.id));
    rt.wrapper.name = '$objectNodePrefix$ownerId';
    final loaded = assets.ready(entry.name);
    if (loaded == null) {
      if (assets.failed(entry.name)) {
        // A corrupt/unreadable import renders like a missing resource.
        _gltfRuntimes.remove(key)?.dispose();
        _emitGltfCube(ownerId, obj, world,
            color: const [255, 0, 255], suffix: ' (ошибка)');
        return;
      }
      if (!assets.isLoading(entry.name)) {
        // Kick off the import; its completion bumps the app revision and
        // this instance re-renders with the real content. Failures are
        // cached by the store (the instance turns into a fuchsia cube).
        assets.load(entry).ignore();
      }
      _emitGltfCube(ownerId, obj, world,
          color: const [150, 150, 150], suffix: '');
      return;
    }
    rt.wrapper.localTransform = world;
    if (!rt.contentBuilt || !identical(rt.loaded, loaded)) {
      _mountGltfContent(rt, loaded, srcId);
    }
    root.add(rt.wrapper);
    gltfWrappers[ownerId] = rt.wrapper;
    _registerElementNode(ownerId, rt.wrapper);
    _syncGltfAnim(rt, obj);
  }

  /// Emits the footprint box of a gltf instance as a whole-object pick node
  /// ([ownerId]) under [world] — the neutral loading placeholder or the
  /// fuchsia cube for a missing/failed resource.
  void _emitGltfCube(
    String ownerId,
    ModelObject ref,
    vm.Matrix4 world, {
    required List<int> color,
    required String suffix,
  }) {
    final box = gltfFootprintBox(ref);
    final cube = ModelObject(
      id: ref.id,
      name: '${ref.name}$suffix',
      kind: 'cuboid',
      x: box.x,
      y: box.y,
      z: box.z,
      dims: {'w': box.dim('w', 1), 'h': box.dim('h', 1), 'd': box.dim('d', 1)},
      material: ModelMaterial(type: MaterialType.color, color: color),
    );
    _emitInstanceObject(ownerId, cube, world);
  }

  /// Attaches the clone of a loaded resource to [rt]'s wrapper and prepares
  /// its animation clips (all paused, weight 0 — [syncGltfAnim] starts the
  /// chosen one). Reports the fitted footprint once so the caller can cache
  /// it on the model object.
  void _mountGltfContent(_GltfRuntime rt, LoadedGltf loaded, String srcId) {
    rt.loaded = loaded;
    rt.wrapper.removeAll(); // drop a previous content tree
    for (final c in rt.clips.values) {
      c.pause();
      c.weight = 0;
    }
    rt.clips.clear();
    final content = loaded.root.clone();
    rt.wrapper.add(content);
    for (final a in loaded.animations) {
      final clip = content.createAnimationClip(a)
        ..weight = 0
        ..loop = true
        ..pause();
      rt.clips[a.name] = clip;
    }
    rt.contentBuilt = true;
    rt.appliedAnim = null; // the next sync applies the stored choice
    final b = loaded.bounds;
    if (b != null) onGltfFootprint?.call(srcId, rt.objId, b);
  }

  /// Applies the instance's animation choice ([ModelObject.anim], '' = rest
  /// pose) to [rt]'s clips. When the choice did not change the clips keep
  /// their state — their playback survives rebuilds.
  void _syncGltfAnim(_GltfRuntime rt, ModelObject obj) {
    if (rt.clips.isEmpty) return;
    final wanted = obj.anim;
    if (rt.appliedAnim == wanted) return;
    rt.appliedAnim = wanted;
    if (wanted.isEmpty) {
      for (final c in rt.clips.values) {
        c.pause();
        c.weight = 0;
      }
      return;
    }
    final target = rt.clips[wanted];
    for (final c in rt.clips.values) {
      if (identical(c, target)) continue;
      c.pause();
      c.weight = 0;
    }
    if (target == null) return; // stale animation name — rest pose
    target
      ..weight = 1
      ..seek(0)
      ..loop = true
      ..play();
  }

  /// Emits the parts of one object of an instance's scene (or the fuchsia
  /// placeholder cuboid) as whole-instance nodes under [localToWorld].
  /// [ownerId] is the container object's id — the picking target. The base
  /// placement translates to [anchor] when given (the object already placed
  /// in the source's standalone frame), otherwise to the object's own cell
  /// (obj.x/y/z) — the top-level placeholder paths rely on the latter.
  void _emitInstanceObject(
    String ownerId,
    ModelObject obj,
    vm.Matrix4 localToWorld, {
    vm.Vector3? anchor,
  }) {
    final at = anchor ?? vm.Vector3(obj.x, obj.y, obj.z);
    if (obj.kind == 'sprite') {
      final parts = _solidParts(obj);
      if (parts.isEmpty) return;
      // The billboard yaw is set per frame ([reorientBillboards]): the node
      // starts facing +Z and the chain (without the yaw) is registered.
      final part = parts.single;
      final material = resolveMaterial(obj, part.faceKey);
      if (material == null) return;
      _builtParts++;
      final name = '$objectNodePrefix$ownerId';
      final chain = localToWorld * vm.Matrix4.translation(at);
      final node = Node(
        name: name,
        mesh: Mesh(part.geometry, material),
        localTransform:
            chain * vm.Matrix4.diagonal3Values(-1, 1, 1),
      );
      root.add(node);
      instanceBillboards.add((node, chain));
      _registerElementNode(ownerId, node);
      return;
    }
    final parts = _solidParts(obj);
    if (parts.isEmpty) return;
    final name = '$objectNodePrefix$ownerId';
    final base = vm.Matrix4.translation(at) * objectRotation(obj);
    for (final part in parts) {
      final material = resolveMaterial(obj, part.faceKey);
      if (material == null) continue; // texture not loaded yet
      _builtParts++;
      final transform = part.offset == null
          ? base
          : base * vm.Matrix4.translation(part.offset!);
      final node = Node(
        name: name,
        mesh: Mesh(part.geometry, material),
        localTransform: localToWorld * transform,
      )..shadowStatic = true;
      root.add(node);
      _registerElementNode(ownerId, node);
    }
  }

  /// Emits the pieces of a csg operation (or a rounded cuboid) inside an
  /// instance's scene. The pieces are model-local outward-wound polygons of
  /// the SOURCE model; the emission mirrors them into the source's world
  /// frame exactly like the top-level path (`_buildCsgObject` /
  /// `_buildRoundedObject`): X mirrored about the source grid center, fan
  /// kept, normals mirrored. The node then sits under the instance chain,
  /// whose det > 0 transform preserves the winding — the nested content
  /// reaches the rasterizer with the same world-space orientation as the
  /// same content rendered standalone.
  void _buildNestedCsg(
    ModelData src,
    ModelObject node,
    String ownerId,
    vm.Matrix4 localToWorld,
  ) {
    final pieces = csgEvaluate(node, src);
    if (csgLastAborted) {
      logStage('csg',
          'операция ${node.op ?? '?'} прервана (шторм дробления) — '
          'показан операнд A');
    }
    if (pieces.isEmpty) return;
    final originX = (src.size.w - 1) / 2;
    final originZ = (src.size.l - 1) / 2;
    final nodeSpec = node.material;
    final groups = <String, List<CsgPoly>>{};
    for (final p in pieces) {
      final round = p.surface.faceKey == roundFaceKey;
      final key = nodeSpec != null
          ? (round ? 'node:round' : 'node')
          : '${p.surface.objId}:${p.surface.faceKey}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    for (final e in groups.entries) {
      final group = e.value;
      final smooth = group.first.surface.faceKey == roundFaceKey;
      ModelMaterial? spec = nodeSpec;
      if (spec == null) {
        final first = group.first;
        final leaf = src.objectById(first.surface.objId);
        if (leaf != null) {
          spec = leaf.faces[first.surface.faceKey] ?? leaf.material;
        }
      }
      final material = _resolveSpecMaterial(spec,
          doubleSided: spec?.side == 'both');
      if (material == null) continue;
      final mesh = _polyGroupMesh(group, spec,
          originX: originX, originZ: originZ, smooth: smooth);
      if (mesh == null) continue;
      final name = '$objectNodePrefix$ownerId';
      final node = Node(
        name: name,
        mesh: Mesh(mesh, material),
        localTransform: localToWorld,
      )..shadowStatic = true;
      root.add(node);
      _registerElementNode(ownerId, node);
    }
  }

  /// Meshes one material group of outward-wound MODEL-space polygons into a
  /// node-ready [Geometry] (null when degenerate). [spec] drives the UV
  /// math. The model→world X mirror is baked into the vertices and normals
  /// (about ([originX], [originZ])) and the fan keeps the polygon's
  /// orientation: the reflection turns the outward CCW model loop into the
  /// world winding that faces the engine's front. Every caller (top-level
  /// csg/rounded objects and nested csg/rounded content of instances) uses
  /// this same convention; nested content additionally sits under the
  /// det > 0 instance chain, which preserves the baked winding.
  Geometry? _polyGroupMesh(
    List<CsgPoly> group,
    ModelMaterial? spec, {
    required double originX,
    required double originZ,
    bool smooth = false,
  }) {
    final b = GeometryBuilder(deduplicate: false);
    final vertexNormals = smooth ? _smoothNormals(group) : null;
    var base = 0;
    for (final p in group) {
      final n = p.normal;
      for (final v in p.vertices) {
        final vn = vertexNormals?[_vertexKey(v)] ?? n;
        b.normal(vm.Vector3(-vn.x, vn.y, vn.z));
        final (u, tv) = _csgPieceUv(p, spec, v);
        b.texCoord(vm.Vector2(u, tv)).addVertex(vm.Vector3(
          originX - v.x,
          v.y,
          v.z - originZ,
        ));
      }
      final m = p.vertices.length;
      for (var i = 1; i + 1 < m; i++) {
        b.addTriangle(base, base + i, base + i + 1);
      }
      base += m;
      _builtParts++;
    }
    if (base < 3) return null;
    return b.build();
  }

  /// Averaged normals of the vertices shared by the group's polygons (same
  /// position key). Used for rounded cuboids: their facets must shade as one
  /// smooth surface instead of a faceted star.
  Map<String, vm.Vector3> _smoothNormals(List<CsgPoly> group) {
    final accum = <String, vm.Vector3>{};
    for (final p in group) {
      final n = p.normal;
      for (final v in p.vertices) {
        final key = _vertexKey(v);
        final current = accum[key];
        if (current == null) {
          accum[key] = n.clone();
        } else {
          current.add(n);
        }
      }
    }
    for (final n in accum.values) {
      if (n.length2 > 1e-18) n.normalize();
    }
    return accum;
  }

  static String _vertexKey(vm.Vector3 v) => '${v.x}|${v.y}|${v.z}';

  /// Emits one rounded cuboid (roundR > 0) of the top-level scene as
  /// pickable per-face nodes: the six planar faces keep their keys, all
  /// edge/corner facets share the 'round' key ([roundFaceKey]). The
  /// geometry is exactly the csg leaf boolean operations cut — mirrored
  /// into world space like a csg result — so the visible shape and the
  /// shape of union/difference/intersect coincide.
  void _buildRoundedObject(ModelData model, ModelObject obj) {
    final pieces = csgLeafPolys(obj);
    if (pieces.isEmpty) return;
    final originX = (model.size.w - 1) / 2;
    final originZ = (model.size.l - 1) / 2;
    final groups = <String, List<CsgPoly>>{};
    for (final p in pieces) {
      groups
          .putIfAbsent('${p.surface.objId}:${p.surface.faceKey}', () => [])
          .add(p);
    }
    for (final e in groups.entries) {
      final group = e.value;
      final first = group.first;
      final leaf = model.objectById(first.surface.objId);
      final spec = leaf?.faces[first.surface.faceKey] ?? leaf?.material;
      final material = _resolveSpecMaterial(spec,
          doubleSided: spec?.side == 'both');
      if (material == null) continue;
      final mesh = _polyGroupMesh(group, spec,
          originX: originX, originZ: originZ, smooth: true);
      if (mesh == null) continue;
      final key = first.surface.faceKey;
      final name = '$faceNodePrefix${obj.id}:$key';
      final node = Node(name: name, mesh: Mesh(mesh, material))
        ..shadowStatic = true;
      root.add(node);
      nodeObjectId[name] = obj.id;
      nodeFaceKey[name] = key;
      allNodes[name] = node;
      _registerElementNode(obj.id, node);
      if (mergeStatic) _mergeCandidates.add(node);
    }
  }

  /// Emits the parts of one top-level (non-csg, non-instance) object. A
  /// rounded cuboid is rendered through [csgLeafPolys] instead — its curved
  /// surface cannot be a set of flat SolidParts.
  void _buildObject(ModelData model, ModelObject obj) {
    if (obj.kind == 'cuboid' && isRoundedCuboid(obj)) {
      _buildRoundedObject(model, obj);
      return;
    }
    final parts = _solidParts(obj);
    for (final part in parts) {
      final material = resolveMaterial(obj, part.faceKey);
      if (material == null) continue; // texture not loaded yet
      _builtParts++;
      // Every part is a face node so individual faces are always pickable
      // (textured or not) in the texturing mode.
      final name = '$faceNodePrefix${obj.id}:${part.faceKey}';
      final anchor = _anchorWorld(obj);
      final baseTransform = obj.kind == 'sprite'
          ? vm.Matrix4.translation(anchor) *
              vm.Matrix4.diagonal3Values(-1, 1, 1) *
              vm.Matrix4.rotationY(obj.rotY * math.pi / 180)
          : _objTransform(obj);
      final transform = part.offset == null
          ? baseTransform
          : baseTransform * vm.Matrix4.translation(part.offset!);
      final node = Node(
        name: name,
        mesh: Mesh(part.geometry, material),
        localTransform: transform,
      )..shadowStatic = obj.kind != 'sprite';
      if (part.offset != null) {
        _nodePartOffset[node] = vm.Matrix4.translation(part.offset!);
      }
      root.add(node);
      nodeObjectId[name] = obj.id;
      nodeFaceKey[name] = part.faceKey;
      allNodes[name] = node;
      _registerElementNode(obj.id, node);
      if (mergeStatic && obj.kind != 'sprite') _mergeCandidates.add(node);
    }
  }

  /// Builds one csg result node: evaluates its boolean subtree and renders
  /// the output pieces as whole-object pick nodes (`obj:<nodeId>`), grouped
  /// per material (the node's own whole-result material, or per source
  /// face otherwise).
  ///
  /// Pieces come from the CSG engine in MODEL space, wound outward. They are
  /// converted to WORLD space by mirroring X (the model↔world convention of
  /// every other part). Reflection flips the triangle orientation: a model
  /// CCW-outward loop turns CW in the world, i.e. its cross product points
  /// INWARD — and since the engine's front face is OPPOSITE the winding's
  /// cross, no extra winding flip is needed (unlike the unmirrored local
  /// geometry of the primitive parts).
  void _buildCsgObject(ModelData model, ModelObject node) {
    final pieces = csgEvaluate(node, model);
    if (csgLastAborted) {
      logStage('csg',
          'операция ${node.op ?? '?'} прервана (шторм дробления) — '
          'показан операнд A');
    }
    if (pieces.isEmpty) return;
    final originX = (model.size.w - 1) / 2;
    final originZ = (model.size.l - 1) / 2;
    final nodeSpec = node.material;
    final groups = <String, List<CsgPoly>>{};
    for (final p in pieces) {
      final round = p.surface.faceKey == roundFaceKey;
      final key = nodeSpec != null
          ? (round ? 'node:round' : 'node')
          : '${p.surface.objId}:${p.surface.faceKey}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    for (final e in groups.entries) {
      final group = e.value;
      // Скруглённые фасетки результата сглаживаются: у них общая гладкая
      // поверхность. Плоские грани и кромки реза остаются плоскими.
      final smooth = group.first.surface.faceKey == roundFaceKey;
      // The spec that decides texture/color, stretch/tile and UV settings:
      // the node's own material overrides every surface; otherwise each
      // piece keeps the material of the source face it was clipped from.
      ModelMaterial? spec = nodeSpec;
      if (spec == null) {
        final first = group.first;
        final leaf = model.objectById(first.surface.objId);
        if (leaf != null) {
          spec = leaf.faces[first.surface.faceKey] ?? leaf.material;
        }
      }
      // Result surfaces are exterior: a source's 'inner' side setting is
      // irrelevant, only 'both' keeps the surface double-sided.
      final material = _resolveSpecMaterial(spec,
          doubleSided: spec?.side == 'both');
      if (material == null) continue;
      final mesh = _polyGroupMesh(group, spec,
          originX: originX, originZ: originZ, smooth: smooth);
      if (mesh == null) continue;
      final name = '$objectNodePrefix${node.id}';
      final node2 = Node(name: name, mesh: Mesh(mesh, material))
        ..shadowStatic = true;
      root.add(node2);
      nodeObjectId[name] = node.id;
      nodeFaceKey.remove(name);
      allNodes[name] = node2;
      _registerElementNode(node.id, node2);
      if (mergeStatic) _mergeCandidates.add(node2);
    }
  }

  /// Texture coordinate of a csg output vertex: the raw projection of the
  /// model-space point into the source face's frame (the renderer's own
  /// parametrization), scaled per the material's tile/stretch semantics and
  /// the frame family (sides always tile; caps honor the material; discs
  /// keep their fixed circular UV).
  (double, double) _csgPieceUv(CsgPoly p, ModelMaterial? spec, vm.Vector3 v) {
    final ts = (spec?.tileScale ?? 1.0) <= 0 ? 1.0 : (spec?.tileScale ?? 1.0);
    final rotation = spec?.uvDir ?? 0;
    final flipX = spec?.flipX ?? false;
    final flipY = spec?.flipY ?? false;
    double u;
    double w;
    final tex = p.tex;
    switch (tex) {
      case CsgTexQuad q:
        final raw = q.frame.raw(v);
        final density = q.alwaysTile || spec?.stretch == 'tile';
        u = density ? raw.$1 * q.frame.spanU / ts : raw.$1;
        w = density ? (1 - raw.$2) * q.frame.spanV / ts : 1 - raw.$2;
        // Same rotation/flip pass as the primitive quad parts (about the
        // texture center 0.5/0.5).
        return _transformUv(u, w, rotation, flipX, flipY);
      case CsgTexRing ring:
        final raw = ring.frame.raw(v);
        final wrap = 2 * math.pi * ring.frame.maxR;
        u = raw.$1 * wrap / ts;
        w = (1 - raw.$2) * ring.height / ts;
        return _transformUv(u, w, rotation, flipX, flipY);
      case CsgTexBand band:
        // Edge fillets: u around the arc, v along the edge — both always
        // tiled at the tileScale (like the ring of a cylinder side).
        final raw = band.frame.raw(v);
        u = raw.$1 * band.arcLen / ts;
        w = (1 - raw.$2) * band.frame.spanV / ts;
        return _transformUv(u, w, rotation, flipX, flipY);
      case CsgTexOctant oct:
        // Corner octants: the spherical square unwraps onto the quarter-arc
        // length π/2·r along both axes, always tiled at the tileScale.
        final raw = oct.frame.raw(v);
        u = raw.$1 * oct.arcLen / ts;
        w = (1 - raw.$2) * oct.arcLen / ts;
        return _transformUv(u, w, rotation, flipX, flipY);
      case CsgTexDisc disc:
        // Disc caps keep their fixed UV; tileScale/uvDir/flips do nothing.
        return disc.frame.raw(v);
    }
  }

  (double, double) _transformUv(
    double u,
    double v,
    int rotation,
    bool flipX,
    bool flipY,
  ) {
    const c = 0.5;
    var nu = u - c, nv = v - c;
    final (ru, rv) = switch (rotation % 360) {
      90 => (nv, -nu),
      180 => (-nu, -nv),
      270 => (-nv, nu),
      _ => (nu, nv),
    };
    nu = ru + c;
    nv = rv + c;
    if (flipX) nu = 1 - nu;
    if (flipY) nv = 1 - nv;
    return (nu, nv);
  }

  /// Reorients billboard sprites (always — textured or not) to face the
  /// camera. Call per frame. Scans the node registry so every sprite node
  /// is covered regardless of its face/material state, and the anchor is
  /// always fresh (object moves are picked up without a rebuild).
  ///
  /// The transform mirrors the game's `reorientBillboard`: the −X scale
  /// keeps the quad's u axis tracking the camera's screen-right (the fork's
  /// kScreenParallel convention is `right = (−cos yaw, 0, −sin yaw)`, while a
  /// bare `rotationY(yaw)` would mirror the texture).
  void reorientBillboards(double fx, double fz) {
    if (allNodes.isEmpty && instanceBillboards.isEmpty) return;
    final yaw = screenParallelYaw(fx, fz);
    final model = _model;
    if (model == null) return;
    for (final entry in nodeObjectId.entries) {
      final obj = model.objects.where((o) => o.id == entry.value).firstOrNull;
      if (obj == null || obj.kind != 'sprite') continue;
      final node = allNodes[entry.key];
      if (node == null) continue;
      final anchor = _anchorWorld(obj);
      node.localTransform = spriteBillboardMatrix(anchor, yaw);
    }
    // Sprites inside model instances: the same billboard orientation applied
    // after their instance chain (the chain never carries the mirror — the
    // instance content keeps its own local frame).
    final mirrorYaw = spriteBillboardRotation(yaw);
    for (final (node, chain) in instanceBillboards) {
      node.localTransform = chain * mirrorYaw;
    }
  }

  vm.Vector3 _anchorWorld(ModelObject obj) {
    final size = _model!.size;
    final w = chunkWorld(obj.x, obj.z, size.w, size.l);
    return vm.Vector3(w.x, obj.y, w.z);
  }

  vm.Matrix4 _objTransform(ModelObject obj) =>
      vm.Matrix4.translation(_anchorWorld(obj)) * objectRotation(obj);

  List<SolidPart> _solidParts(ModelObject obj) {
    switch (obj.kind) {
      case 'cuboid':
        return _cuboidParts(
          obj,
          obj.dim('w', 1),
          obj.dim('h', 1),
          obj.dim('d', 1),
          _uvSpec(obj, forObject: true),
        );
      case 'trapezoid':
        return _trapezoidParts(
          obj,
          obj.dim('bottomW', 1),
          obj.dim('bottomD', 1),
          obj.dim('topW', 0.5),
          obj.dim('topD', 0.5),
          obj.dim('h', 0.5),
          _uvSpec(obj, forObject: true),
        );
      case 'cylinder':
        final bottomR = obj.dim('bottomR', 0.25);
        final topR = obj.dim('topR', bottomR);
        final h = obj.dim('h', 1);
        final segments = obj.dim('segments', 16).clamp(3, 64).toInt();
        final uv = _uvSpec(obj, forObject: true);
        return _cylinderParts(obj, bottomR, topR, h, segments, uv);
      case 'plane':
        final w = obj.dim('w', 1);
        final d = obj.dim('d', 1);
        final vertical = obj.flag('vertical');
        final uv = _uvSpec(obj, forObject: true);
        final faceKey = vertical ? '+z' : '+y';
        final flip = quadFlipFor(sideFor(obj, faceKey));
        // Vertical: an upright quad (x width, y = depth) at z = 0.
        // Horizontal: flat on the ground, wound so the +Y normal is outward.
        final corners = planeFaceCorners(vertical, w, d);
        return [
          SolidPart(
            faceKey,
            _quadPart(
              corners: corners,
              normal: vertical ? vm.Vector3(0, 0, 1) : vm.Vector3(0, 1, 0),
              uExtent: w,
              vExtent: d,
              uv: uv,
              flip: flip,
            ),
          ),
        ];
      case 'sprite':
        return [
          SolidPart('*', _spriteGeometry(obj)),
        ];
      default:
        return const [];
    }
  }

  Geometry _spriteGeometry(ModelObject obj) {
    final w = obj.dim('w', 1);
    final h = obj.dim('h', 1);
    // Vertical quad centered on X, anchored at the base (y = 0..h); the
    // node transform carries the yaw (billboard).
    //
    // Winding is flipped (like the cuboid/plane 'outer' faces) so the quad
    // survives the billboard mirror: `reorientBillboards` applies
    // diag(−1,1,1), which reverses the base CCW winding and makes the
    // engine's `windingFlipped` draw use Clockwise front-face. The unflipped
    // quad would end up facing AWAY from the camera and the sprite's blend
    // material (always back-face culled, even doubleSided) would be culled —
    // the texture never shows. The flip matches the game's `PlaneGeometry`
    // billboards (same winding after Rx(π/2)), whose front faces the camera.
    return _quadPart(
      corners: spriteFaceCorners(w, h),
      normal: vm.Vector3(0, 0, 1),
      uExtent: w,
      vExtent: h,
      uv: _uvSpec(obj, forObject: true),
      flip: true,
    );
  }

  List<SolidPart> _cuboidParts(
    ModelObject obj,
    double w,
    double h,
    double d,
    _UvSpec uv,
  ) {
    final parts = <(String, List<vm.Vector3>, vm.Vector3, double, double)>[
      // (faceKey, corners wound outward, normal, uExtent, vExtent)
      ('-z', cuboidFaceCorners('-z', w, h, d), vm.Vector3(0, 0, -1), w, h),
      ('+z', cuboidFaceCorners('+z', w, h, d), vm.Vector3(0, 0, 1), w, h),
      ('+x', cuboidFaceCorners('+x', w, h, d), vm.Vector3(1, 0, 0), d, h),
      ('-x', cuboidFaceCorners('-x', w, h, d), vm.Vector3(-1, 0, 0), d, h),
      ('+y', cuboidFaceCorners('+y', w, h, d), vm.Vector3(0, 1, 0), w, d),
      ('-y', cuboidFaceCorners('-y', w, h, d), vm.Vector3(0, -1, 0), w, d),
    ];
    return [
      for (final (key, corners, n, ue, ve) in parts)
        SolidPart(
          key,
          _quadPart(
            corners: corners,
            normal: n,
            uExtent: ue,
            vExtent: ve,
            uv: uv,
            flip: quadFlipFor(sideFor(obj, key)),
            // The side faces always tile at the tileScale (a stretched
            // texture on a short side would be squeezed) — the caps keep
            // the material's setting.
            alwaysTile: key != '+y' && key != '-y',
          ),
        ),
    ];
  }

  List<SolidPart> _trapezoidParts(
    ModelObject obj,
    double bw,
    double bd,
    double tw,
    double td,
    double h,
    _UvSpec uv,
  ) {
    final parts = <(String, List<vm.Vector3>, vm.Vector3, double, double, double)>[
      // (faceKey, corners, normal, uExtent, vExtent, topInsetU)
      ('-y', trapezoidFaceCorners('-y', bw, bd, tw, td, h), vm.Vector3(0, -1, 0), bw, bd, 0),
      ('+y', trapezoidFaceCorners('+y', bw, bd, tw, td, h), vm.Vector3(0, 1, 0), tw, td, 0),
      // Sloped sides: the top edge is narrower — the texture keeps a
      // uniform density and the slope CLIPS it (centered) instead of
      // squeezing the image toward the top.
      ('-z', trapezoidFaceCorners('-z', bw, bd, tw, td, h), vm.Vector3(0, 0, -1), bw, h, centeredInset(tw / bw)),
      ('+x', trapezoidFaceCorners('+x', bw, bd, tw, td, h), vm.Vector3(1, 0, 0), bd, h, centeredInset(td / bd)),
      ('+z', trapezoidFaceCorners('+z', bw, bd, tw, td, h), vm.Vector3(0, 0, 1), bw, h, centeredInset(tw / bw)),
      ('-x', trapezoidFaceCorners('-x', bw, bd, tw, td, h), vm.Vector3(-1, 0, 0), bd, h, centeredInset(td / bd)),
    ];
    return [
      for (final (key, corners, n, ue, ve, inset) in parts)
        SolidPart(
          key,
          _quadPart(
            corners: corners,
            normal: n,
            uExtent: ue,
            vExtent: ve,
            uv: uv,
            flip: trapezoidFlipFor(sideFor(obj, key), key),
            topInsetU: inset,
            // The sloped sides always tile at the tileScale (clipped by the
            // slope) — the stretch setting would warp the image.
            alwaysTile: inset > 0,
          ),
        ),
    ];
  }

  List<SolidPart> _cylinderParts(
    ModelObject obj,
    double bottomR,
    double topR,
    double h,
    int segments,
    _UvSpec uv,
  ) {
    final side = sideFor(obj, 'side');
    final sideFlip = stripFlipFor(side);
    // The strip geometry is centered on the origin (spans −h/2..+h/2), so
    // the whole cylinder is shifted up by h/2: its BASE sits at the anchor.
    final parts = <SolidPart>[
      SolidPart(
        'side',
        _cylinderSideGeometry(bottomR, topR, h, segments, uv, flip: sideFlip),
        offset: vm.Vector3(0, h / 2, 0),
      ),
    ];
    if (bottomR > 0) {
      final capFlip = capFlipFor(sideFor(obj, '-y'), '-y');
      parts.add(SolidPart(
        '-y',
        _discGeometry(bottomR, segments, flip: capFlip),
        offset: vm.Vector3(0, 0, 0),
      ));
    }
    if (topR > 0) {
      final capFlip = capFlipFor(sideFor(obj, '+y'), '+y');
      parts.add(SolidPart(
        '+y',
        _discGeometry(topR, segments, flip: capFlip),
        offset: vm.Vector3(0, h, 0),
      ));
    }
    return parts;
  }

  /// Cylinder side as a quad strip, wound outward (or flipped for inner
  /// faces). u wraps around the circumference (the POLAR wrap — the texture
  /// is anchored to the surface, so the pattern never slides from face to
  /// face), v = 0..1 height. The u span of each ring shrinks to its width
  /// relative to the WIDEST ring ([sideRingU]): a cylinder (bottomR == topR)
  /// wraps classically with vertical seams; a cone/frustum keeps the same
  /// wrap — the seams follow the cone's slant and converge to the apex (the
  /// natural look, like a painted cone), and the narrowing shape CLIPS the
  /// texture (centered) instead of squeezing it. The side ALWAYS tiles at
  /// the tileScale (2π·maxR/tileScale around, h/tileScale tall) — the
  /// material's stretch setting would warp the wrapped image.
  Geometry _cylinderSideGeometry(
    double bottomR,
    double topR,
    double h,
    int segments,
    _UvSpec uv, {
    required bool flip,
  }) {
    // No vertex deduplication: the strip owns 4 vertices per quad — the
    // seam ring vertices share position and texCoord, and the fork's
    // GeometryBuilder (deduplicate defaults to true) would merge them,
    // shrinking the vertex count under the base = s·4 triangle indices — a
    // RangeError on every rebuild.
    final b = GeometryBuilder(deduplicate: false);
    final maxR = math.max(bottomR, topR);
    final uScale = 2 * math.pi * maxR / uv.tileScale;
    final vScale = h / uv.tileScale;
    final bottomRatio = maxR > 0 ? bottomR / maxR : 1.0;
    final topRatio = maxR > 0 ? topR / maxR : 1.0;
    // Ring vertices: bottom ring first, then top ring.
    final ring = <vm.Vector3>[];
    for (var s = 0; s <= segments; s++) {
      final theta = 2 * math.pi * s / segments;
      final cos = math.cos(theta), sin = math.sin(theta);
      ring.add(vm.Vector3(bottomR * cos, -h / 2, bottomR * sin));
    }
    for (var s = 0; s <= segments; s++) {
      final theta = 2 * math.pi * s / segments;
      final cos = math.cos(theta), sin = math.sin(theta);
      ring.add(vm.Vector3(topR * cos, h / 2, topR * sin));
    }
    final n0 = segments + 1;
    for (var s = 0; s < segments; s++) {
      final i = s, j = s + 1;
      // Quad (b_i, b_j, t_j, t_i) wound so the outward normal = (p1−p0)×(p2−p0).
      final p0 = ring[i], p1 = ring[j], p2 = ring[n0 + j];
      final nrm = (p1 - p0).cross(p2 - p0).normalized();
      // v = 1 on the bottom ring, v = 0 on the top (upright textures).
      final (bu0, bv0) = uv.transform(sideRingU(i, segments, bottomRatio) * uScale, vScale);
      final (bu1, bv1) = uv.transform(sideRingU(j, segments, bottomRatio) * uScale, vScale);
      final (tu1, tv1) = uv.transform(sideRingU(j, segments, topRatio) * uScale, 0.0);
      final (tu0, tv0) = uv.transform(sideRingU(i, segments, topRatio) * uScale, 0.0);
      b.normal(nrm)
        ..texCoord(vm.Vector2(bu0, bv0)).addVertex(p0)
        ..texCoord(vm.Vector2(bu1, bv1)).addVertex(p1)
        ..texCoord(vm.Vector2(tu1, tv1)).addVertex(p2)
        ..texCoord(vm.Vector2(tu0, tv0)).addVertex(ring[n0 + i]);
      final base = s * 4;
      if (flip) {
        b.addTriangle(base, base + 2, base + 1);
        b.addTriangle(base, base + 3, base + 2);
      } else {
        b.addTriangle(base, base + 1, base + 2);
        b.addTriangle(base, base + 2, base + 3);
      }
    }
    return b.build();
  }

  /// A flat disc facing +Y, centered on the origin (wound CCW from +Y,
  /// or reversed when [flip]).
  Geometry _discGeometry(double radius, int segments, {required bool flip}) {
    final b = GeometryBuilder();
    b.normal(vm.Vector3(0, 1, 0));
    b.texCoord(vm.Vector2(0.5, 0.5)).addVertex(vm.Vector3(0, 0, 0));
    for (var s = 0; s <= segments; s++) {
      final theta = 2 * math.pi * s / segments;
      final cos = math.cos(theta), sin = math.sin(theta);
      b.texCoord(vm.Vector2(0.5 + 0.5 * cos, 0.5 + 0.5 * sin))
          .addVertex(vm.Vector3(radius * cos, 0, radius * sin));
    }
    for (var s = 0; s < segments; s++) {
      if (flip) {
        b.addTriangle(0, s + 2, s + 1);
      } else {
        b.addTriangle(0, s + 1, s + 2);
      }
    }
    return b.build();
  }

  /// Builds a quad with UVs 0..1 (scaled by [uv]); corners are ordered
  /// bottom-left → bottom-right → top-right → top-left, and v = 1 sits on
  /// the bottom edge (the game's cuboid convention, so images stand up).
  /// [topInsetU] insets BOTH top corners' u by that fraction — the top edge
  /// spans (topInsetU, 1−topInsetU) instead of (0, 1): the texture keeps a
  /// uniform texel density on a narrowing (trapezoid) face and the slope
  /// CLIPS it instead of squeezing it ([centeredInset]).
  /// [alwaysTile] forces the tile-scale projection (uExtent/tileScale,
  /// vExtent/tileScale) regardless of the material's stretch/tile setting —
  /// used by the narrowing side faces, whose textures must tile at the
  /// natural scale and be clipped by the shape, never stretched to fill.
  /// [flip] reverses the winding (for inner faces).
  Geometry _quadPart({
    required List<vm.Vector3> corners,
    required vm.Vector3 normal,
    required double uExtent,
    required double vExtent,
    required _UvSpec uv,
    bool flip = false,
    double topInsetU = 0,
    bool alwaysTile = false,
  }) {
    final b = GeometryBuilder();
    final scale = alwaysTile || uv.tile
        ? (uExtent / uv.tileScaleU, vExtent / uv.tileScaleV)
        : (1.0, 1.0);
    final uScale = scale.$1, vScale = scale.$2;
    final baseUv = quadBaseUv(topInsetU: topInsetU, uScale: uScale, vScale: vScale);
    b.normal(normal);
    for (var i = 0; i < 4; i++) {
      // quadBaseUv already applies the scale — no extra multiplication.
      final (u, v) = uv.transform(baseUv[i].$1, baseUv[i].$2);
      b.texCoord(vm.Vector2(u, v)).addVertex(corners[i]);
    }
    if (flip) {
      b.addTriangle(0, 2, 1);
      b.addTriangle(0, 3, 2);
    } else {
      b.addTriangle(0, 1, 2);
      b.addTriangle(0, 2, 3);
    }
    return b.build();
  }

  _UvSpec _uvSpec(ModelObject obj, {required bool forObject}) {
    final mat = obj.material ?? ModelMaterial();
    final ts = mat.tileScale <= 0 ? 1.0 : mat.tileScale;
    final tsu = mat.tileScaleU <= 0 ? ts : mat.tileScaleU;
    final tsv = mat.tileScaleV <= 0 ? ts : mat.tileScaleV;
    return _UvSpec(
      tile: mat.stretch == 'tile',
      tileScale: ts,
      tileScaleU: tsu,
      tileScaleV: tsv,
      rotation: mat.uvDir,
      flipX: mat.flipX,
      flipY: mat.flipY,
    );
  }

  // ── materials ────────────────────────────────────────────────────────

  /// Resolves the material for [obj]'s [faceKey] (public for unit tests —
  /// pure Dart, no GPU: gray while the texture loads, magenta when the
  /// texture is unresolvable, the real sprite/texture material when ready).
  ///
  /// The object's [ModelObject.tag] is part of the material identity: a game
  /// that tags parts with different material recipes (wall directions, skin)
  /// gets one material instance per tag, so a post-bake material hook can
  /// customize each variant independently. Untagged objects share as before.
  /// Runtime material overrides: `'<objId>:<faceKey>'` for one face or
  /// `'<objId>:*'` for the whole object. Consulted before the document
  /// material, so games/editors can repaint live nodes without touching the
  /// saved document. Cleared by the owner when a rebuild should forget them.
  final Map<String, Material> materialOverrides = {};

  /// Resolves the material of one face (or the whole object).
  Material? resolveMaterial(ModelObject obj, String faceKey) {
    final override = materialOverrides['${obj.id}:$faceKey'] ??
        materialOverrides['${obj.id}:*'];
    if (override != null) return override;
    // The per-face material overrides the object material for EVERY face
    // key — including the cylinder side ('side') and the sprite ('*').
    ModelMaterial? spec = obj.faces[faceKey] ?? obj.material;
    // Sprites are two-sided like the game's decor: the billboard flips its
    // visible face as the camera orbits, so culling would hide it.
    final doubleSided = obj.kind == 'sprite' ||
        sideDoubleSided(sideFor(obj, faceKey));
    return _resolveSpecMaterial(spec,
        doubleSided: doubleSided,
        kindSprite: obj.kind == 'sprite',
        variant: obj.tag ?? '');
  }

  /// Shared material resolution for an arbitrary [spec]: gray while the
  /// texture loads, magenta when unresolvable, the real material when ready.
  /// Identical specs with the same [variant] share one instance within a
  /// rebuild (see [_materialCache]) so merged geometry can key on material
  /// identity.
  Material? _resolveSpecMaterial(
    ModelMaterial? spec, {
    required bool doubleSided,
    bool kindSprite = false,
    String variant = '',
  }) {
    final isSprite = spec?.type == MaterialType.sprite;
    final readyKey = spec == null || spec.type == MaterialType.color
        ? ''
        : (isSprite ? 's:${spec.key}' : 't:${spec.key}');
    final key = spec == null
        ? 'gray:$doubleSided:$opacity:$variant'
        : spec.type == MaterialType.color
            ? 'c:${spec.color[0]},${spec.color[1]},${spec.color[2]}:'
                '$doubleSided:$opacity:$variant'
            : '$readyKey:$doubleSided:$kindSprite:$opacity:$variant:'
                '${_textureReady.containsKey(readyKey)}:'
                '${_missing.contains(readyKey)}';
    final cached = _materialCache[key];
    if (cached != null) return cached;
    final material =
        _buildSpecMaterial(spec, doubleSided: doubleSided, kindSprite: kindSprite);
    if (material != null) _materialCache[key] = material;
    return material;
  }

  Material? _buildSpecMaterial(
    ModelMaterial? spec, {
    required bool doubleSided,
    bool kindSprite = false,
  }) {
    if (spec == null) {
      return pbrColor(
        vm.Vector3(0.78, 0.78, 0.78),
        doubleSided: doubleSided,
        opacity: opacity,
      );
    }
    if (spec.type == MaterialType.color) {
      return pbrColor(
        vm.Vector3(
          spec.color[0] / 255,
          spec.color[1] / 255,
          spec.color[2] / 255,
        ),
        doubleSided: doubleSided,
        opacity: opacity,
      );
    }
    final isSprite = spec.type == MaterialType.sprite;
    final cacheKey = isSprite ? 's:${spec.key}' : 't:${spec.key}';
    // Empty key or known-missing — the renderer's async set or the texture
    // cache's synchronous one (the latter lets a bake render fuchsia for a
    // resource the loader has already settled as lost): bright magenta, no
    // file lookup.
    if (spec.key.isEmpty ||
        _missing.contains(cacheKey) ||
        (isSprite
            ? textures.isSpriteMissing(spec.key)
            : textures.isTextureMissing(spec.key))) {
      _missingParts++;
      return pbrColor(
        _missingColor,
        doubleSided: doubleSided,
        opacity: opacity,
      );
    }
    final future = isSprite ? textures.sprite(spec.key) : textures.texture(spec.key);
    var tex = _textureReady[cacheKey];
    if (tex == null) {
      // The cache may already hold the decoded texture (preloaded by the
      // level loader / mark-ready API): use it synchronously so the first
      // build of a baked level is never gray.
      final cached = isSprite
          ? textures.peekSprite(spec.key)
          : textures.peekTexture(spec.key);
      if (cached != null) {
        _textureReady[cacheKey] = cached;
        tex = cached;
      }
    }
    if (tex == null) {
      // Kick off the load; request a rebuild when it arrives. The callback
      // is registered ONCE per key (not per part per rebuild): the old
      // per-part registration made a texture load fire one full rebuild per
      // part using it, and every rebuild re-registered callbacks for the
      // still-loading keys — ∏(1+pᵢ) rebuilds for a textured house.
      _pendingCounts[cacheKey] = (_pendingCounts[cacheKey] ?? 0) + 1;
      if (_registered.add(cacheKey)) {
        future.then((t) {
          if (t == null) {
            _missing.add(cacheKey);
            logStage('renderer', 'texture missing $cacheKey');
            onTextureReady?.call();
            return;
          }
          if (_textureReady.containsKey(cacheKey)) return;
          _textureReady[cacheKey] = t;
          logStage('renderer', 'texture ready $cacheKey');
          onTextureReady?.call();
        });
      }
      return pbrColor(
        vm.Vector3(0.78, 0.78, 0.78),
        doubleSided: doubleSided,
        opacity: opacity,
      );
    }
    // Ghosted (walkability) mode needs real alpha blending: the solid
    // faces' mask alpha-mode would discard the dimmed texels.
    final alphaMode = opacity < 1.0
        ? AlphaMode.blend
        : (kindSprite ? AlphaMode.blend : AlphaMode.mask);
    return pbrSprite(
      tex,
      doubleSided: doubleSided,
      opacity: opacity,
      alphaMode: alphaMode,
    );
  }

  final Map<String, Texture2D> _textureReady = {};

  /// Keys whose texture-ready callback is already registered (reset with the
  /// texture cache on a project switch) — guarantees at most ONE rebuild per
  /// texture key instead of a rebuild-per-part amplification.
  final Set<String> _registered = {};

  /// Texture keys already resolved to «missing» (empty key, missing file,
  /// decode failure) — their parts render bright magenta so the problem is
  /// visible. Populated once per key by the deduped ready callback.
  final Set<String> _missing = {};

  /// Parts rendered with the missing-texture color in the current rebuild.
  int _missingParts = 0;

  /// Per-key counts of parts that still render gray in the current rebuild
  /// (logged with each rebuild summary; a repeated non-empty map across
  /// consecutive rebuilds reveals a rebuild storm).
  final Map<String, int> _pendingCounts = {};
  int _builtParts = 0;

  /// Bright magenta — the classic missing-texture color.
  static final _missingColor = vm.Vector3(1, 0, 1);

  String? _textureDir;

  /// Drops the loaded-texture cache when the asset root changes (a different
  /// project with the same file names would otherwise render stale textures).
  void syncTextureRoot(TextureCache cache) {
    final dir = cache.texturesDir;
    if (_textureDir != dir) {
      _textureDir = dir;
      _textureReady.clear();
      _registered.clear();
      _missing.clear();
    }
  }

  /// Marks a texture preloaded (used when the tool adds resources at runtime).
  void cacheTexture(String key, Texture2D tex) {
    _textureReady['t:$key'] = tex;
  }

  void cacheSprite(String key, Texture2D tex) {
    _textureReady['s:$key'] = tex;
  }
}

/// Persistent per-instance runtime of a gltf instance: the attached wrapper
/// node (holding the clone of the loaded resource) plus its animation clips.
/// It survives scene rebuilds so the loaded content is not re-imported and
/// clip playback is not restarted on every rebuild.
class _GltfRuntime {
  final String objId;
  final Node wrapper = Node();

  /// The loaded resource the wrapper currently holds (for identity checks
  /// after the asset store re-imports the same name).
  LoadedGltf? loaded;

  /// True once the content tree is attached ([wrapper] has children).
  bool contentBuilt = false;

  /// The animation configuration currently applied ('' or a full glTF name).
  String? appliedAnim;

  /// Per-full-name clips of the attached content, paused/weight 0 until the
  /// chosen animation starts.
  final Map<String, AnimationClip> clips = {};

  _GltfRuntime(this.objId);

  void dispose() {
    for (final c in clips.values) {
      c.pause();
      c.weight = 0;
    }
    clips.clear();
    wrapper.removeAll();
    loaded = null;
    contentBuilt = false;
    appliedAnim = null;
  }
}

class _UvSpec {
  final bool tile;
  final double tileScale;
  final double tileScaleU;
  final double tileScaleV;
  final int rotation; // 0/90/180/270
  final bool flipX, flipY;

  _UvSpec({
    required this.tile,
    required this.tileScale,
    required this.tileScaleU,
    required this.tileScaleV,
    required this.rotation,
    required this.flipX,
    required this.flipY,
  });

  /// Applies rotation (about the face center) + flips to a (u, v) pair.
  (double, double) transform(double u, double v) {
    const c = 0.5;
    var nu = u - c, nv = v - c;
    final (ru, rv) = switch (rotation % 360) {
      90 => (nv, -nu),
      180 => (-nu, -nv),
      270 => (-nv, nu),
      _ => (nu, nv),
    };
    nu = ru + c;
    nv = rv + c;
    if (flipX) nu = 1 - nu;
    if (flipY) nv = 1 - nv;
    return (nu, nv);
  }
}
