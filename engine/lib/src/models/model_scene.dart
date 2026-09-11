import 'dart:convert';

/// Model scene model — the JSON format `model_v1`. Legacy chunk formats
/// (`chunk_v1/v2/v3`) are not handled here: read files through
/// `loadModelData` (`scene_loader.dart`), which converts them (see
/// `legacy_chunk_converter.dart`).
///
/// Coordinates are model-local with the origin at the CENTER OF THE
/// BOTTOM-LEFT CELL — a fixed anchor: enlarging the model extends the grid
/// in +x/+z and the origin keeps its cell. Cell centers sit on the integers
/// (0, 1, 2, …) for ANY model size, so the step-1 snap grid always lands
/// inside cells. The model spans x ∈ [−0.5, w−0.5], z ∈ [−0.5, l−0.5],
/// y ∈ [0, h] (y = 0 is the floor); object position is the center of the
/// base rectangle at its y height. World mapping happens through
/// `cellWorld`/`chunkWorld` in `engine_compat/coords.dart`.

const modelFormatV1 = 'model_v1';
const chunkFormatV3 = 'chunk_v3'; // legacy, accepted on load as-is
const chunkFormatV2 = 'chunk_v2'; // legacy, accepted on load as-is
const chunkFormatV1 = 'chunk_v1'; // legacy, accepted on load as-is

/// Boolean-operation result object kind: a derived «live» solid computed by
/// a CSG operation over two operand objects (referenced by id, hidden while
/// consumed). Nestable: a csg object may itself be an operand.
const csgKind = 'csg';

/// Model-instance object kind: a whole other model of the same project placed
/// in this scene «as is» (kind `model` in JSON). The referenced model's own
/// coordinate system is copied into the container: its origin maps to the
/// instance's [ModelObject.pos], and every placement keeps the referenced
/// model's cell coordinates (resizing the source model never shifts existing
/// instances). The instance is not editable part-by-part — it only moves,
/// rotates and uniformly scales as a whole ([ModelObject.scale]); its content
/// follows the source model, so editing the source updates every instance.
/// A reference to a deleted model renders as a fuchsia cube of the cached
/// source size ([ModelObject.refSize]).
const modelRefKind = 'model';

/// glTF/GLB-instance object kind: a whole imported 3D model — a `3d_models/`
/// catalog resource of the project (glTF folder or GLB file) — placed in
/// this scene «as is» (kind `gltf` in JSON). Like a model instance it is not
/// editable part-by-part — it only moves, rotates and uniformly scales as a
/// whole ([ModelObject.scale]) and may play one of the resource's glTF
/// animations in a loop ([ModelObject.anim]). A reference to a deleted
/// resource renders as a fuchsia cube of the cached footprint
/// ([ModelObject.gltfBounds]).
const gltfRefKind = 'gltf';
const csgOpUnion = 'union';
const csgOpDifference = 'difference';
const csgOpIntersect = 'intersect';
const csgOps = [csgOpUnion, csgOpDifference, csgOpIntersect];

const faceKeys = ['+x', '-x', '+y', '-y', '+z', '-z'];

/// Compass sides of a scene: entry sides (`entries`), the facade (`front`)
/// and cell openings of the level layer. Stored in JSON as the legacy chunk
/// strings `north`/`east`/`south`/`west`.
enum ModelSide { north, east, south, west }

/// Parses a legacy side string; null for unknown/absent values.
ModelSide? modelSideFrom(Object? value) {
  if (value is! String) return null;
  for (final s in ModelSide.values) {
    if (s.name == value) return s;
  }
  return null;
}

/// The opposite side of [s] (north↔south, east↔west).
ModelSide oppositeSide(ModelSide s) => switch (s) {
      ModelSide.north => ModelSide.south,
      ModelSide.east => ModelSide.west,
      ModelSide.south => ModelSide.north,
      ModelSide.west => ModelSide.east,
    };

/// The face key of the curved (edge/corner) zones of a rounded cuboid
/// (roundR > 0): one selectable surface holding the material of the whole
/// rounding. Geometry in `scene/rounded_box.dart`.
const roundFaceKey = 'round';

/// Default tessellation of a cuboid's rounding arcs (like the cylinder's
/// `segments`).
const defaultRoundSegments = 16;

/// The effective rounding radius of [obj]: 0 when off, never more than half
/// of the smallest side (the inner box must not degenerate).
double cuboidRoundRadiusOf(ModelObject obj) {
  final r = obj.dim('roundR', 0);
  if (r <= 0) return 0;
  final w = obj.dim('w', 1), h = obj.dim('h', 1), d = obj.dim('d', 1);
  final m = w < h ? (w < d ? w : d) : (h < d ? h : d);
  return r < m / 2 ? r : m / 2;
}

/// Whether [obj] is a cuboid rendered/evaluated as a fully rounded box.
bool isRoundedCuboid(ModelObject obj) => cuboidRoundRadiusOf(obj) > 0;

/// Arc segments of a cuboid's rounding (clamped to 3..64).
int cuboidRoundSegments(ModelObject obj) {
  final v = obj.dim('roundSegments', defaultRoundSegments.toDouble());
  return v < 3 ? 3 : (v > 64 ? 64 : v).round();
}

/// The face keys an object actually has (per kind).
List<String> facesOf(ModelObject obj) => switch (obj.kind) {
      'cuboid' => [
          ...faceKeys,
          // A rounded cuboid's curved zones are one pickable surface.
          if (obj.dim('roundR', 0) > 0) roundFaceKey,
        ],
      'trapezoid' => faceKeys,
      'cylinder' => [
          'side',
          if (obj.dim('bottomR', 0.25) > 0) '-y',
          if (obj.dim('topR', 0) > 0) '+y',
        ],
      'plane' => [if (obj.flag('vertical')) '+z' else '+y'],
      'sprite' => ['*'],
      'csg' => const [], // a csg result is textured whole (no per-face keys)
      modelRefKind => const [], // a model instance is textured by its content
      gltfRefKind => const [], // a gltf instance is textured by its content
      _ => const [],
    };

/// Kinds that may take part in boolean operations: convex solids (cuboid,
/// trapezoid, cylinder/cone) plus csg nodes (evaluated recursively). Planes
/// and sprites are surface-only decorations and never operands; a model
/// instance or a gltf instance is an opaque non-editable sub-scene and never
/// an operand either.
bool isCsgEligible(ModelObject obj) =>
    !obj.isModelRef &&
    !obj.isGltfRef &&
    (obj.kind == 'cuboid' ||
        obj.kind == 'trapezoid' ||
        obj.kind == 'cylinder' ||
        obj.kind == 'csg');

class ModelSize {
  int w, l, h;
  ModelSize({this.w = 3, this.l = 3, this.h = 3});

  ModelSize.copy(ModelSize o) : this(w: o.w, l: o.l, h: o.h);

  Map<String, Object> toJson() => {'w': w, 'l': l, 'h': h};

  factory ModelSize.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    int asInt(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return ModelSize(
      w: asInt(m['w'], 3).clamp(1, 64),
      l: asInt(m['l'], 3).clamp(1, 64),
      h: asInt(m['h'], 3).clamp(1, 32),
    );
  }
}

enum MaterialType { texture, sprite, color }

MaterialType materialTypeFrom(String? s) =>
    MaterialType.values.firstWhere((e) => e.name == s, orElse: () => MaterialType.color);

class ModelMaterial {
  MaterialType type;
  String key; // file name inside textures/ (or sprites/ for sprite type)
  int uvDir; // 0/90/180/270
  bool flipX, flipY;
  String stretch; // stretch | tile
  double tileScale;

  /// Per-axis tile scale (world units per texture repeat) used when
  /// [stretch] is 'tile'. Defaults to [tileScale] — walls and foliage skins
  /// need different horizontal and vertical densities (one repeat per metre
  /// across, one repeat over the whole wall height).
  double tileScaleU;
  double tileScaleV;
  List<int> color; // [r, g, b]

  /// Which side of the face gets the material: 'outer' (default), 'inner',
  /// or 'both'. Opaque materials cull the other side; 'both' disables
  /// culling.
  String side;

  ModelMaterial({
    this.type = MaterialType.color,
    this.key = '',
    this.uvDir = 0,
    this.flipX = false,
    this.flipY = false,
    this.stretch = 'stretch',
    this.tileScale = 1.0,
    double? tileScaleU,
    double? tileScaleV,
    this.side = 'outer',
    List<int>? color,
  })  : tileScaleU = tileScaleU ?? tileScale,
        tileScaleV = tileScaleV ?? tileScale,
        color = color ?? const [200, 200, 200];

  ModelMaterial.copy(ModelMaterial o)
      : this(
          type: o.type,
          key: o.key,
          uvDir: o.uvDir,
          flipX: o.flipX,
          flipY: o.flipY,
          stretch: o.stretch,
          tileScale: o.tileScale,
          tileScaleU: o.tileScaleU,
          tileScaleV: o.tileScaleV,
          side: o.side,
          color: List.of(o.color),
        );

  bool get isDefault => type == MaterialType.color &&
      color[0] == 200 && color[1] == 200 && color[2] == 200 &&
      side == 'outer';

  Map<String, Object> toJson() {
    final m = <String, Object>{
      'type': type.name,
    };
    if (uvDir != 0) m['uvDir'] = uvDir;
    if (flipX) m['flipX'] = true;
    if (flipY) m['flipY'] = true;
    if (side != 'outer') m['side'] = side;
    if (stretch != 'stretch') m['stretch'] = stretch;
    if (stretch == 'tile' && tileScale != 1.0) m['tileScale'] = round3(tileScale);
    if (stretch == 'tile' && tileScaleU != tileScale) {
      m['tileScaleU'] = round3(tileScaleU);
    }
    if (stretch == 'tile' && tileScaleV != tileScale) {
      m['tileScaleV'] = round3(tileScaleV);
    }
    if (key.isNotEmpty) m['key'] = key;
    if (type == MaterialType.color) {
      m['color'] = List.of(color);
    }
    if (isDefault) return {'type': 'color', 'color': List.of(color)};
    return m;
  }

  factory ModelMaterial.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final tileScale =
        m['tileScale'] is num ? (m['tileScale'] as num).toDouble() : 1.0;
    return ModelMaterial(
      type: materialTypeFrom(m['type'] as String?),
      key: (m['key'] as String?) ?? '',
      uvDir: m['uvDir'] is num ? (m['uvDir'] as num).toInt() : 0,
      flipX: m['flipX'] == true,
      flipY: m['flipY'] == true,
      stretch: (m['stretch'] as String?) ?? 'stretch',
      tileScale: tileScale,
      tileScaleU:
          m['tileScaleU'] is num ? (m['tileScaleU'] as num).toDouble() : null,
      tileScaleV:
          m['tileScaleV'] is num ? (m['tileScaleV'] as num).toDouble() : null,
      side: (m['side'] as String?) ?? 'outer',
      color: m['color'] is List
          ? (m['color'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : null,
    );
  }
}

class ModelObject {
  String id;
  String name;
  String kind; // cuboid | trapezoid | cylinder | plane | sprite | csg

  /// csg only: the boolean operation ('union' | 'difference' | 'intersect').
  String? op;

  /// csg only: ids of the two operand objects (primitives or nested csg).
  /// Referenced operands are hidden while consumed by the result.
  List<String>? operands;

  /// modelRef only: id of the referenced model (a whole other `models/`
  /// scene placed here «as is»). Its origin maps to (x, y, z).
  String refModelId;

  /// modelRef only: uniform scale factor of the instance (1 = as built).
  /// Applied around the instance anchor together with the rotation.
  double scale;

  /// modelRef only: cached w×l×h of the referenced model — the size of the
  /// fuchsia cube shown when the referenced model no longer exists.
  ModelSize? refSize;

  /// gltfRef only: catalog name of the referenced glTF/GLB resource in the
  /// project's `3d_models/` (the folder name for a glTF, the file stem for
  /// a GLB).
  String gltfName;

  /// gltfRef only: cached local footprint of the referenced resource in the
  /// instance's own frame — `[minX, minY, minZ, maxX, maxY, maxZ]` of the
  /// box the content occupies around the anchor (the content is fitted so
  /// minY = 0 stands on the anchor's floor and X/Z are centered). Null =
  /// unknown (a skinned model without computed bounds, or not yet loaded).
  /// Used for the fuchsia cube shown when the resource is deleted and for
  /// outlines/bounds while it renders.
  List<double>? gltfBounds;

  /// gltfRef only: full glTF name of the animation played in a loop ('' =
  /// none — the model keeps its rest pose).
  String anim;

  /// Construction-model hint (level layer): how the element is baked —
  /// `'merge'` (default, null), `'batch'` or `'node'`. The editor renderer
  /// ignores it; the level baker consumes it. Part of `model_v1` so a
  /// construction model round-trips losslessly.
  String? bake;

  /// Construction-model hint (level layer): free-form role tag of the
  /// element (e.g. `floor`, `wall`, `door`, a region id). Opaque to the
  /// engine.
  String? tag;

  double x, y, z; // anchor: center of base at height y

  /// Euler rotations (degrees), applied around the anchor as
  /// Rz(rotZ)·Rx(rotX)·Ry(rotY) — rotY keeps the legacy semantics.
  double rotX, rotY, rotZ;

  /// Kind-specific dimensions. Keys:
  ///  cuboid:      w, h, d (+ roundR — скругление рёбер/углов, 0 = off;
  ///               roundSegments — фасетки дуг, 3..64)
  ///  trapezoid:   bottomW, bottomD, topW, topD, h
  ///  cylinder:    bottomR, topR, h, segments
  ///  plane:       w, d, vertical (bool)
  ///  sprite:      w, h, billboard (bool)
  final Map<String, num> dims;

  ModelMaterial? material;
  Map<String, ModelMaterial> faces;

  bool get isCsg => kind == csgKind;

  /// True for a model-instance object (kind [modelRefKind]): a whole other
  /// model placed here «as is» — moves/rotates/scales as one, content
  /// follows the referenced model.
  bool get isModelRef => kind == modelRefKind;

  /// True for a glTF/GLB-instance object (kind [gltfRefKind]): a whole
  /// imported 3D-model resource placed here «as is» — moves/rotates/scales
  /// as one, content follows the referenced resource.
  bool get isGltfRef => kind == gltfRefKind;

  ModelObject({
    required this.id,
    required this.name,
    required this.kind,
    this.op,
    List<String>? operands,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.rotX = 0,
    this.rotY = 0,
    this.rotZ = 0,
    Map<String, num>? dims,
    this.material,
    Map<String, ModelMaterial>? faces,
    this.refModelId = '',
    this.scale = 1,
    ModelSize? refSize,
    this.gltfName = '',
    List<double>? gltfBounds,
    this.anim = '',
    this.bake,
    this.tag,
  })  : // Normalize the runtime map type: a literal like {'w': 3, 'h': 0.05}
        // is a Map<String, double>, which would blow up on addAll with a
        // Map<String, num> argument during undo/redo restore.
        operands = operands == null ? null : List.of(operands),
        dims = Map<String, num>.from(dims ?? const {}),
        faces = faces ?? {},
        refSize = refSize == null ? null : ModelSize.copy(refSize),
        gltfBounds = gltfBounds == null ? null : List.of(gltfBounds);

  ModelObject.copy(ModelObject o)
      : this(
          id: o.id,
          name: o.name,
          kind: o.kind,
          op: o.op,
          operands: o.operands == null ? null : List.of(o.operands!),
          x: o.x,
          y: o.y,
          z: o.z,
          rotX: o.rotX,
          rotY: o.rotY,
          rotZ: o.rotZ,
          dims: Map.of(o.dims),
          material: o.material == null ? null : ModelMaterial.copy(o.material!),
          faces: {
            for (final e in o.faces.entries)
              e.key: ModelMaterial.copy(e.value),
          },
          refModelId: o.refModelId,
          scale: o.scale,
          refSize: o.refSize == null ? null : ModelSize.copy(o.refSize!),
          gltfName: o.gltfName,
          gltfBounds: o.gltfBounds == null ? null : List.of(o.gltfBounds!),
          anim: o.anim,
          bake: o.bake,
          tag: o.tag,
        );

  double dim(String key, double fallback) {
    final v = dims[key];
    return v == null ? fallback : v.toDouble();
  }

  bool flag(String key) => dims[key] == 1;

  void setDim(String key, num value) => dims[key] = value;

  void setFlag(String key, bool value) => dims[key] = value ? 1 : 0;

  Map<String, Object> toJson() {
    final m = <String, Object>{
      'id': id,
      'name': name,
      'kind': kind,
    };
    if (bake != null && bake!.isNotEmpty) m['bake'] = bake!;
    if (tag != null && tag!.isNotEmpty) m['tag'] = tag!;
    // A csg node stores no own geometry: op + operand ids (plus an optional
    // whole-result material). pos/size/rotation are meaningless for it.
    if (kind == csgKind) {
      if (op != null) m['op'] = op!;
      if (operands != null && operands!.isNotEmpty) {
        m['operands'] = List.of(operands!);
      }
      if (material != null && !material!.isDefault) m['material'] = material!.toJson();
      return m;
    }
    // A model instance stores the reference + its own placement only; it has
    // no dims/material/faces of its own.
    if (kind == modelRefKind) {
      m['pos'] = [round3(x), round3(y), round3(z)];
      m['rotY'] = round3(rotY);
      if (rotX != 0) m['rotX'] = round3(rotX);
      if (rotZ != 0) m['rotZ'] = round3(rotZ);
      m['modelId'] = refModelId;
      if (scale != 1) m['scale'] = round3(scale);
      // The cached source size: the fuchsia cube's dimensions when the
      // referenced model is gone.
      if (refSize != null) m['size'] = refSize!.toJson();
      return m;
    }
    // A glTF/GLB instance stores the resource reference + its own placement
    // (and optional animation choice); it has no dims/material/faces.
    if (kind == gltfRefKind) {
      m['pos'] = [round3(x), round3(y), round3(z)];
      m['rotY'] = round3(rotY);
      if (rotX != 0) m['rotX'] = round3(rotX);
      if (rotZ != 0) m['rotZ'] = round3(rotZ);
      m['gltf'] = gltfName;
      if (scale != 1) m['scale'] = round3(scale);
      // The cached local footprint: the fuchsia cube's box when the resource
      // is gone and the outline/bounds while it renders.
      if (gltfBounds != null) {
        m['bounds'] = [for (final v in gltfBounds!) round3(v)];
      }
      if (anim.isNotEmpty) m['anim'] = anim;
      return m;
    }
    m['pos'] = [round3(x), round3(y), round3(z)];
    m['rotY'] = round3(rotY);
    // Rotation is stored as three Euler angles (degrees, applied
    // Rz·Rx·Ry around the anchor). Non-zero X/Z are written only when set —
    // the JSON stays backward compatible with rotY-only models.
    if (rotX != 0) m['rotX'] = round3(rotX);
    if (rotZ != 0) m['rotZ'] = round3(rotZ);
    if (kind == 'cuboid') {
      // A plain cuboid keeps the compact legacy list [w, h, d]; a rounded
      // one needs the extra dims, so it switches to the map form (read back
      // by fromJson into the same w/h/d keys).
      final r = dims['roundR'];
      if (r != null && r.toDouble() > 0) {
        final size = <String, Object>{
          'w': round3(dim('w', 1)),
          'h': round3(dim('h', 1)),
          'd': round3(dim('d', 1)),
          'roundR': round3(r.toDouble()),
        };
        final seg = dims['roundSegments'];
        if (seg != null && seg.toDouble() != defaultRoundSegments) {
          size['roundSegments'] = seg is int ? seg : round3(seg.toDouble());
        }
        m['size'] = size;
      } else {
        m['size'] = [round3(dim('w', 1)), round3(dim('h', 1)), round3(dim('d', 1))];
      }
    } else {
      final d = <String, Object>{};
      for (final e in dims.entries) {
        final v = e.value;
        d[e.key] = v is int ? v : round3(v.toDouble());
      }
      m['size'] = d;
    }
    if (material != null && !material!.isDefault) m['material'] = material!.toJson();
    if (faces.isNotEmpty) {
      m['faces'] = {
        for (final e in faces.entries) e.key: e.value.toJson(),
      };
    }
    return m;
  }

  factory ModelObject.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final pos = m['pos'] is List
        ? (m['pos'] as List).whereType<num>().toList()
        : <num>[0, 0, 0];
    final sizeJson = m['size'];
    final dims = <String, num>{};
    if (sizeJson is List) {
      final l = sizeJson.whereType<num>().toList();
      if (l.isNotEmpty) dims['w'] = l[0].toDouble();
      if (l.length >= 2) dims['h'] = l[1].toDouble();
      if (l.length >= 3) dims['d'] = l[2].toDouble();
    } else if (sizeJson is Map) {
      for (final e in sizeJson.entries) {
        final v = e.value;
        if (v is num) dims[e.key] = v;
      }
    }
    final kind = (m['kind'] as String?) ?? 'cuboid';
    if (kind == 'plane' && dims.containsKey('vertical')) {
      dims['vertical'] = dims['vertical'] == 1 ? 1 : 0;
    }
    // csg operands: exactly two existing object ids (validated by
    // [ModelData.pruneCsgNodes]).
    final op = kind == csgKind ? (m['op'] as String?) ?? csgOpUnion : null;
    final operands = kind == csgKind && m['operands'] is List
        ? [
            for (final v in m['operands'] as List)
              if (v is String) v,
          ]
        : null;
    // Model instance: referenced model id + uniform scale (+ cached size).
    // A stale/broken reference is kept on purpose — it renders as a fuchsia
    // cube so the missing model is visible on the scene.
    final refId = kind == modelRefKind ? (m['modelId'] as String?) ?? '' : '';
    final scaleV = (kind == modelRefKind || kind == gltfRefKind) &&
            m['scale'] is num
        ? (m['scale'] as num).toDouble()
        : 1.0;
    final refSize = kind == modelRefKind && m['size'] != null
        ? ModelSize.fromJson(m['size'])
        : null;
    // glTF/GLB instance: catalog resource name + uniform scale + the cached
    // local footprint (fuchsia cube / outline box) + the chosen animation.
    // A stale/broken resource reference is kept on purpose — it renders as
    // a fuchsia cube so the missing resource is visible on the scene.
    final gltfName = kind == gltfRefKind ? (m['gltf'] as String?) ?? '' : '';
    final gltfBounds = kind == gltfRefKind && m['bounds'] is List
        ? [
            for (final v in m['bounds'] as List)
              if (v is num) v.toDouble(),
          ]
        : null;
    final anim = kind == gltfRefKind ? (m['anim'] as String?) ?? '' : '';
    final faces = <String, ModelMaterial>{};
    final facesJson = m['faces'];
    if (facesJson is Map) {
      for (final e in facesJson.entries) {
        faces[e.key] = ModelMaterial.fromJson(e.value);
      }
    }
    return ModelObject(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? (m['id'] as String?) ?? '',
      kind: kind,
      op: csgOps.contains(op) ? op : null,
      operands: operands,
      x: pos.isNotEmpty ? pos[0].toDouble() : 0.0,
      y: pos.length > 1 ? pos[1].toDouble() : 0.0,
      z: pos.length > 2 ? pos[2].toDouble() : 0.0,
      rotX: m['rotX'] is num ? (m['rotX'] as num).toDouble() : 0.0,
      rotY: m['rotY'] is num ? (m['rotY'] as num).toDouble() : 0.0,
      rotZ: m['rotZ'] is num ? (m['rotZ'] as num).toDouble() : 0.0,
      dims: dims,
      material: m['material'] == null ? null : ModelMaterial.fromJson(m['material']),
      faces: faces,
      refModelId: refId,
      scale: scaleV > 0 ? scaleV : 1.0,
      refSize: refSize,
      gltfName: gltfName,
      gltfBounds: gltfBounds,
      anim: anim,
      bake: m['bake'] is String ? m['bake'] as String : null,
      tag: m['tag'] is String ? m['tag'] as String : null,
    );
  }

  /// World-space AABB (model-local units, y = height above model floor).
  /// Computed per kind — cuboid dims only exist for cuboids.
  (double, double, double) minCorner() {
    final (hw, h, hd) = _halfExtents();
    return (x - hw, y, z - hd);
  }

  (double, double, double) maxCorner() {
    final (hw, h, hd) = _halfExtents();
    return (x + hw, y + h, z + hd);
  }

  /// (halfWidth, height, halfDepth) of the object's AABB.
  (double, double, double) _halfExtents() {
    switch (kind) {
      case 'cuboid':
        return (dim('w', 1) / 2, dim('h', 1), dim('d', 1) / 2);
      case 'trapezoid':
        final bw = dim('bottomW', 1), tw = dim('topW', bw);
        final bd = dim('bottomD', 1), td = dim('topD', bd);
        return (
          (bw > tw ? bw : tw) / 2,
          dim('h', 0.5),
          (bd > td ? bd : td) / 2,
        );
      case 'cylinder':
        final r = dim('bottomR', 0.25);
        return (r, dim('h', 1), r);
      case 'plane':
        if (flag('vertical')) return (dim('w', 1) / 2, dim('d', 1), 0.01);
        return (dim('w', 1) / 2, 0.01, dim('d', 1) / 2);
      case 'sprite':
        return (dim('w', 1) / 2, dim('h', 1), 0.01);
      default:
        return (0.5, 1.0, 0.5);
    }
  }
}

/// Meta-object kinds (markup mode): [comment], [marker], [box].
const metaKindComment = 'comment';
const metaKindMarker = 'marker';
const metaKindBox = 'box';

/// Conventional meta-box names of the level layer (migration plan §3.14):
/// occupied cells are marked by boxes named [metaNameUnpassable], doors and
/// windows by [metaNameDoor]/[metaNameWindow]. The engine does not interpret
/// the names — the level tools use these as defaults, games may use their
/// own (the names are free-form [ModelMeta.name]).
const metaNameUnpassable = 'unpassable';
const metaNameDoor = 'door';
const metaNameWindow = 'window';

/// A meta-object: an annotation object of the markup mode («Разметка»). Meta
/// objects are never part of the rendered scene — they exist in the editor to
/// mark up a model: comments (a green ball with a text bubble), markers (a
/// flag with a name/comment, e.g. a camera spot or a character spawn point),
/// and boxes (a blue cuboid marking an area, e.g. an impassable zone or a
/// jump target). Names may repeat so all boxes named «непроходимый» can be
/// found in code later.
///
/// Coordinates are model-local like [ModelObject]: [x]/[z] are the center
/// column coordinates, [y] is the height of the object's base (the ball's
/// center for a comment, the flag's pole base for a marker, the box's bottom
/// face for a box).
class ModelMeta {
  String id;
  String kind; // comment | marker | box
  String name;
  String comment;
  double x, y, z;

  /// z-order among overlapping meta objects (higher draws on top).
  int zIndex;

  /// Whether the bubble is collapsed (truncated); a click on the bubble
  /// toggles it.
  bool collapsed;

  /// Kind-specific dimensions (box: w/h/d).
  final Map<String, num> dims;

  ModelMeta({
    required this.id,
    required this.kind,
    required this.name,
    this.comment = '',
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.zIndex = 0,
    this.collapsed = false,
    Map<String, num>? dims,
  }) : dims = Map<String, num>.from(dims ?? const {});

  ModelMeta.copy(ModelMeta o)
      : this(
          id: o.id,
          kind: o.kind,
          name: o.name,
          comment: o.comment,
          x: o.x,
          y: o.y,
          z: o.z,
          zIndex: o.zIndex,
          collapsed: o.collapsed,
          dims: Map.of(o.dims),
        );

  double dim(String key, double fallback) {
    final v = dims[key];
    return v == null ? fallback : v.toDouble();
  }

  void setDim(String key, num value) => dims[key] = value;

  bool get isBox => kind == metaKindBox;

  /// Whether this meta kind shows a name line (marker/box) above the shape.
  bool get showsName => kind == metaKindMarker || kind == metaKindBox;

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        if (comment.isNotEmpty) 'comment': comment,
        'pos': [round3(x), round3(y), round3(z)],
        if (zIndex != 0) 'zIndex': zIndex,
        if (collapsed) 'collapsed': true,
        if (dims.isNotEmpty)
          'size': {
            for (final e in dims.entries)
              e.key: e.value is int ? e.value : round3(e.value.toDouble()),
          },
      };

  factory ModelMeta.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final pos = m['pos'] is List
        ? (m['pos'] as List).whereType<num>().toList()
        : <num>[0, 0, 0];
    final sizeJson = m['size'];
    final dims = <String, num>{};
    if (sizeJson is Map) {
      for (final e in sizeJson.entries) {
        final v = e.value;
        if (v is num) dims[e.key] = v;
      }
    }
    return ModelMeta(
      id: (m['id'] as String?) ?? '',
      kind: (m['kind'] as String?) ?? metaKindComment,
      name: (m['name'] as String?) ?? (m['id'] as String?) ?? '',
      comment: (m['comment'] as String?) ?? '',
      x: pos.isNotEmpty ? pos[0].toDouble() : 0.0,
      y: pos.length > 1 ? pos[1].toDouble() : 0.0,
      z: pos.length > 2 ? pos[2].toDouble() : 0.0,
      zIndex: m['zIndex'] is num ? (m['zIndex'] as num).toInt() : 0,
      collapsed: m['collapsed'] == true,
      dims: dims,
    );
  }
}

/// Light-source kinds (lighting mode «Освещение»).
const lightKindPoint = 'point';
const lightKindDirectional = 'directional';

/// The display name of a light-source [kind] (the default light name).
String lightKindLabel(String kind) =>
    kind == lightKindDirectional ? 'Направленный свет' : 'Точечный свет';

/// Default color of a new light source: a warm white (sRGB 0..1).
const kLightDefaultColor = [1.0, 0.97, 0.9];

/// Default aim of a new directional light (world-space unit vector, sRGB —
/// a soft diagonal like the editor key light).
const kLightDefaultDir = [-0.4, -0.85, -0.35];

/// Default intensity of a new light source of [kind] (roughly matches the
/// editor's key light / camera lamp brightness).
double lightDefaultIntensity(String kind) =>
    kind == lightKindDirectional ? 2.2 : 5.0;

/// Default range of a new point light, world units.
const kPointLightDefaultRange = 8.0;

/// A light source of the lighting mode («Освещение»): a point light (a small
/// colored sphere gizmo) or a directional light (a sphere with an aim
/// arrow). A source is not part of the model's solid geometry — like a meta
/// object it only configures how the scene is lit and is saved per model.
///
/// Coordinates are model-local like [ModelObject]/[ModelMeta]: [x]/[z] are
/// the center column coordinates, [y] is the height of the source's anchor
/// (for a directional light the anchor is only where its gizmo sits — the
/// light itself is infinitely far). [dir] is the directional light's aim in
/// WORLD coordinates (the engine consumes world-space vectors directly, no
/// mirrored-X conversion), so the rendered arrow always matches the light.
/// Colors are sRGB 0..1 in the JSON and in the UI; the renderer converts to
/// the engine's linear space.
class ModelLight {
  String id;
  String kind; // point | directional
  String name;
  double x, y, z;

  /// sRGB color 0..1 ([r], [g], [b]).
  double r, g, b;
  double intensity;

  /// Point light: distance where the influence fades to zero (world units).
  /// Directional lights ignore it.
  double range;

  /// Directional light aim (world-space unit vector). Point lights ignore it.
  double dirX, dirY, dirZ;

  ModelLight({
    required this.id,
    required this.kind,
    this.name = '',
    this.x = 0,
    this.y = 0,
    this.z = 0,
    double? r,
    double? g,
    double? b,
    double? intensity,
    double? range,
    double? dirX,
    double? dirY,
    double? dirZ,
  })  : r = r ?? kLightDefaultColor[0],
        g = g ?? kLightDefaultColor[1],
        b = b ?? kLightDefaultColor[2],
        intensity = intensity ?? lightDefaultIntensity(kind),
        range = range ?? kPointLightDefaultRange,
        dirX = dirX ?? kLightDefaultDir[0],
        dirY = dirY ?? kLightDefaultDir[1],
        dirZ = dirZ ?? kLightDefaultDir[2];

  ModelLight.copy(ModelLight o)
      : this(
          id: o.id,
          kind: o.kind,
          name: o.name,
          x: o.x,
          y: o.y,
          z: o.z,
          r: o.r,
          g: o.g,
          b: o.b,
          intensity: o.intensity,
          range: o.range,
          dirX: o.dirX,
          dirY: o.dirY,
          dirZ: o.dirZ,
        );

  bool get isPoint => kind == lightKindPoint;
  bool get isDirectional => kind == lightKindDirectional;

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind,
        if (name.isNotEmpty) 'name': name,
        'pos': [round3(x), round3(y), round3(z)],
        if (r != kLightDefaultColor[0] ||
            g != kLightDefaultColor[1] ||
            b != kLightDefaultColor[2])
          'color': [round3(r), round3(g), round3(b)],
        if (intensity != lightDefaultIntensity(kind))
          'intensity': round3(intensity),
        if (isPoint && range != kPointLightDefaultRange)
          'range': round3(range),
        if (isDirectional &&
            (dirX != kLightDefaultDir[0] ||
                dirY != kLightDefaultDir[1] ||
                dirZ != kLightDefaultDir[2]))
          'dir': [round3(dirX), round3(dirY), round3(dirZ)],
      };

  factory ModelLight.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final kind = (m['kind'] as String?) ?? lightKindPoint;
    final pos = m['pos'] is List
        ? (m['pos'] as List).whereType<num>().toList()
        : <num>[0, 0, 0];
    final color = m['color'] is List
        ? (m['color'] as List).whereType<num>().toList()
        : <num>[];
    final dir = m['dir'] is List
        ? (m['dir'] as List).whereType<num>().toList()
        : <num>[];
    return ModelLight(
      id: (m['id'] as String?) ?? '',
      kind: kind,
      name: (m['name'] as String?) ?? '',
      x: pos.isNotEmpty ? pos[0].toDouble() : 0.0,
      y: pos.length > 1 ? pos[1].toDouble() : 0.0,
      z: pos.length > 2 ? pos[2].toDouble() : 0.0,
      r: color.isNotEmpty ? color[0].toDouble() : null,
      g: color.length > 1 ? color[1].toDouble() : null,
      b: color.length > 2 ? color[2].toDouble() : null,
      intensity: m['intensity'] is num ? (m['intensity'] as num).toDouble() : null,
      range: m['range'] is num ? (m['range'] as num).toDouble() : null,
      dirX: dir.isNotEmpty ? dir[0].toDouble() : null,
      dirY: dir.length > 1 ? dir[1].toDouble() : null,
      dirZ: dir.length > 2 ? dir[2].toDouble() : null,
    );
  }
}

/// The lighting configuration of a model («Освещение» mode): the scene-wide
/// knobs (global ambient light, gizmo visibility, shadows, SSAO) plus the
/// model's own light sources. Serialized under the optional top-level key
/// `lighting` — a file without it loads the defaults and renders with the
/// editor's built-in lights exactly as before.
class ModelLighting {
  /// Global ambient light: the intensity of the engine's image-based
  /// environment (0 = no ambient — only the analytic sources light the
  /// scene, up to ~2).
  double ambient;

  /// Whether the light-source gizmos (spheres / spheres with arrows) are
  /// shown in the «Освещение» mode.
  bool gizmos;

  /// Whether the shadow-casting light sources cast shadows.
  bool shadows;

  /// Whether screen-space ambient occlusion is enabled.
  bool ssao;

  List<ModelLight> lights;

  /// True when nothing was customized: no sources and every scene knob at
  /// its default. Such a model renders with the editor's default lights
  /// (key sun + camera lamp), keeping the old behavior byte-identical.
  bool get isDefault =>
      lights.isEmpty &&
      ambient == 1.0 &&
      gizmos &&
      !shadows &&
      !ssao;

  ModelLighting({
    this.ambient = 1.0,
    this.gizmos = true,
    this.shadows = false,
    this.ssao = false,
    List<ModelLight>? lights,
  }) : lights = lights ?? [];

  ModelLighting.copy(ModelLighting o)
      : this(
          ambient: o.ambient,
          gizmos: o.gizmos,
          shadows: o.shadows,
          ssao: o.ssao,
          lights: [for (final l in o.lights) ModelLight.copy(l)],
        );

  ModelLight? lightById(String id) {
    for (final l in lights) {
      if (l.id == id) return l;
    }
    return null;
  }

  Map<String, Object> toJson() => {
        if (ambient != 1.0) 'ambient': round3(ambient),
        if (!gizmos) 'gizmos': false,
        if (shadows) 'shadows': true,
        if (ssao) 'ssao': true,
        if (lights.isNotEmpty)
          'lights': [for (final l in lights) l.toJson()],
      };

  factory ModelLighting.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final lights = <ModelLight>[
      if (m['lights'] is List)
        for (final x in m['lights'] as List) ModelLight.fromJson(x),
    ];
    return ModelLighting(
      ambient: m['ambient'] is num ? (m['ambient'] as num).toDouble() : 1.0,
      gizmos: m['gizmos'] != false,
      shadows: m['shadows'] == true,
      ssao: m['ssao'] == true,
      lights: lights,
    );
  }
}

/// A named persistent group in the objects tree: a container with member
/// object ids. An object belongs to at most one group.
class ModelGroup {
  String id;
  String name;
  List<String> members;

  ModelGroup({
    required this.id,
    required this.name,
    List<String>? members,
  }) : members = members ?? [];

  ModelGroup.copy(ModelGroup o)
      : this(id: o.id, name: o.name, members: List.of(o.members));

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'members': List.of(members),
      };

  factory ModelGroup.fromJson(Object? json) {
    final m = (json as Map?) ?? {};
    final members = <String>[
      if (m['members'] is List)
        for (final v in m['members'] as List)
          if (v is String) v,
    ];
    return ModelGroup(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? (m['id'] as String?) ?? '',
      members: members,
    );
  }
}

class ModelData {
  String id; // = file name
  String name;
  ModelSize size;
  List<ModelObject> objects;
  List<ModelGroup> groups;
  List<ModelMeta> metas;

  /// Entry sides of the scene (legacy chunk `entries`): the sides the level
  /// may connect through. The source of truth for connectivity — the level
  /// validator compares it against the door boxes (plan §3.14).
  Set<ModelSide> entries;

  /// Facade side of the scene (legacy chunk `front`), e.g. the side with the
  /// door. Null when the scene has no facade.
  ModelSide? front;

  /// The model's lighting configuration («Освещение»): scene knobs + the
  /// model's own light sources. Always present in memory (defaults when the
  /// file has no `lighting` key).
  ModelLighting lighting;

  /// Editor state: true when in-memory edits differ from the saved file.
  bool dirty = false;

  ModelData({
    required this.id,
    required this.name,
    ModelSize? size,
    List<ModelObject>? objects,
    List<ModelGroup>? groups,
    List<ModelMeta>? metas,
    Set<ModelSide>? entries,
    this.front,
    ModelLighting? lighting,
  })  : size = size ?? ModelSize(),
        objects = objects ?? [],
        groups = groups ?? [],
        metas = metas ?? [],
        entries = entries ?? {},
        lighting = lighting ?? ModelLighting();

  /// The format version this model was loaded/saved with.
  String get format => modelFormatV1;

  ModelData.copy(ModelData o)
      : this(
          id: o.id,
          name: o.name,
          size: ModelSize.copy(o.size),
          objects: [for (final ob in o.objects) ModelObject.copy(ob)],
          groups: [for (final g in o.groups) ModelGroup.copy(g)],
          metas: [for (final m in o.metas) ModelMeta.copy(m)],
          entries: Set.of(o.entries),
          front: o.front,
          lighting: ModelLighting.copy(o.lighting),
        );

  Map<String, Object> toJson() => {
        'format': modelFormatV1,
        'id': id,
        'name': name,
        'size': size.toJson(),
        'objects': [for (final o in objects) o.toJson()],
        if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
        if (metas.isNotEmpty) 'meta': [for (final m in metas) m.toJson()],
        if (entries.isNotEmpty) 'entries': [for (final s in entries) s.name],
        if (front != null) 'front': front!.name,
        if (!lighting.isDefault) 'lighting': lighting.toJson(),
      };

  factory ModelData.fromJson(String jsonStr, {required String id}) {
    final m = jsonDecode(jsonStr) as Map<String, Object?>;
    final objects = <ModelObject>[];
    if (m['objects'] is List) {
      for (final o in m['objects'] as List) {
        final ob = ModelObject.fromJson(o);
        if (ob.id.isEmpty) ob.id = 'obj_${objects.length + 1}';
        if (ob.name.isEmpty) ob.name = ob.id;
        objects.add(ob);
      }
    }
    final entries = <ModelSide>{};
    if (m['entries'] is List) {
      for (final v in m['entries'] as List) {
        final s = modelSideFrom(v);
        if (s != null) entries.add(s);
      }
    }
    final front = modelSideFrom(m['front']);
    final groups = <ModelGroup>[
      if (m['groups'] is List)
        for (final g in m['groups'] as List) ModelGroup.fromJson(g),
    ];
    // Optional markup meta-objects (unknown to older editors — ignored).
    final metas = <ModelMeta>[
      if (m['meta'] is List)
        for (final x in m['meta'] as List) ModelMeta.fromJson(x),
    ];
    // Optional lighting config (unknown to older editors — ignored).
    final lighting = ModelLighting.fromJson(m['lighting']);
    final model = ModelData(
      id: id,
      name: (m['name'] as String?) ?? id,
      size: ModelSize.fromJson(m['size']),
      objects: objects,
      groups: groups,
      metas: metas,
      entries: entries,
      front: front,
      lighting: lighting,
    );
    model.pruneGroupMembers();
    model.pruneCsgNodes();
    return model;
  }

  ModelObject? objectById(String id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  ModelMeta? metaById(String id) {
    for (final m in metas) {
      if (m.id == id) return m;
    }
    return null;
  }

  ModelLight? lightById(String id) => lighting.lightById(id);

  /// The csg node that consumes [objId] as an operand, if any (the operand
  /// is hidden and rendered only through the result).
  ModelObject? csgParentOf(String objId) {
    for (final o in objects) {
      if (o.isCsg && o.operands?.contains(objId) == true) return o;
    }
    return null;
  }

  /// Whether [objId] is currently hidden as a csg operand.
  bool isCsgOperand(String objId) => csgParentOf(objId) != null;

  /// The primitive (non-csg) leaves of the csg subtree rooted at [nodeId],
  /// in operand order (A's subtree first, then B's). Cycle-safe.
  List<ModelObject> csgLeavesOf(String nodeId) {
    final leaves = <ModelObject>[];
    final path = <String>{};
    void visit(String id) {
      final o = objectById(id);
      if (o == null || !path.add(id)) return;
      if (!o.isCsg) {
        leaves.add(o);
        return;
      }
      for (final mid in o.operands ?? const <String>[]) {
        visit(mid);
      }
    }

    visit(nodeId);
    return leaves;
  }

  /// The csg nodes that are not themselves consumed by another csg node
  /// (forest roots of the operation tree).
  List<ModelObject> csgRoots() => [
        for (final o in objects)
          if (o.isCsg && csgParentOf(o.id) == null) o,
      ];

  /// Objects rendered/listed directly: everything except hidden operands.
  List<ModelObject> visibleObjects() => [
        for (final o in objects)
          if (csgParentOf(o.id) == null) o,
      ];

  /// The objects that geometry-level operations (gizmo moves, AABBs,
  /// outlines) actually act on for a selection containing csg nodes: every
  /// selected csg node expands to its primitive leaves (the node itself has
  /// no own geometry), and an operand directly selected together with its
  /// own csg node is not duplicated. Result keeps the model object order.
  List<ModelObject> moveExpansion(Iterable<String> ids) {
    final sel = ids.toSet();
    final expanded = <ModelObject>[];
    final added = <String>{};
    for (final o in objects) {
      if (!sel.contains(o.id)) continue;
      if (o.isCsg) {
        for (final l in csgLeavesOf(o.id)) {
          if (added.add(l.id)) expanded.add(l);
        }
      } else {
        final parent = csgParentOf(o.id);
        if (parent != null && sel.contains(parent.id)) continue;
        if (added.add(o.id)) expanded.add(o);
      }
    }
    return expanded;
  }

  /// Removes group member ids that no longer reference existing objects.
  void pruneGroupMembers() {
    final ids = objects.map((o) => o.id).toSet();
    for (final g in groups) {
      g.members.removeWhere((mid) => !ids.contains(mid));
    }
  }

  /// Drops invalid csg nodes (wrong/absent op, not exactly two existing
  /// operands, self-reference, or a node reachable from its own operands —
  /// i.e. sitting inside its own subtree). Iterated to a fixpoint because
  /// dropping an inner node can invalidate its parents. Called on load.
  void pruneCsgNodes() {
    Set<String> ids() => objects.map((o) => o.id).toSet();
    bool reaches(String fromId, String targetId) {
      final seen = <String>{targetId};
      bool walk(String cur) {
        final o = objectById(cur);
        if (o == null || !o.isCsg) return false;
        for (final mid in o.operands ?? const <String>[]) {
          if (mid == targetId) return true;
          if (!seen.add(mid)) continue;
          if (walk(mid)) return true;
        }
        return false;
      }

      return walk(fromId);
    }

    var changed = true;
    while (changed) {
      changed = false;
      final existing = ids();
      final invalid = <ModelObject>[];
      for (final o in objects) {
        if (!o.isCsg) continue;
        final ops = o.operands ?? const <String>[];
        final badOp = !csgOps.contains(o.op);
        final badArity = ops.length != 2;
        final badRefs = ops.any((mid) => !existing.contains(mid) || mid == o.id);
        final cyclic = !badRefs && ops.any((mid) => reaches(mid, o.id));
        if (badOp || badArity || badRefs || cyclic) invalid.add(o);
      }
      if (invalid.isNotEmpty) {
        objects.removeWhere(invalid.contains);
        changed = true;
      }
    }
  }
}

double round3(double v) => (v * 1000).roundToDouble() / 1000;
