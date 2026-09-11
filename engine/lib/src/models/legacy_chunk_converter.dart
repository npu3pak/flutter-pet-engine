import 'dart:convert';

import 'model_scene.dart';

/// Legacy chunk marker kind: a data-only «мета:проход» marker (a door
/// opening on the chunk border). Never geometry.
const legacyMetaPassKind = 'meta_pass';

/// Formats accepted by [convertLegacyChunk].
const legacyChunkFormats = {chunkFormatV1, chunkFormatV2, chunkFormatV3};

bool isLegacyChunkFormat(Object? format) =>
    format is String && legacyChunkFormats.contains(format);

/// Converts a legacy chunk document (`chunk_v1/v2/v3`) into a `model_v1`
/// [ModelData] following the migration table (plan §3.14):
///
/// | legacy              | model_v1                                |
/// |---------------------|-----------------------------------------|
/// | `blocked` cells     | boxes named `unpassable` (cell centers) |
/// | `meta_pass` markers | boxes named `door` (passage ring cells) |
/// | `entries`           | [ModelData.entries]                     |
/// | `front`             | [ModelData.front]                       |
///
/// Objects and groups are carried over as-is; `meta_pass` markers are
/// data-only and never become geometry. Blocked cells outside the chunk
/// footprint are dropped (the legacy set may extend past `size`); a cell
/// opened by a door marker never becomes `unpassable`.
///
/// Self-contained on purpose: imports only the document model, never the
/// level layer (the format boundary stays below it).
ModelData convertLegacyChunk(String jsonStr, {required String id}) {
  final m = jsonDecode(jsonStr) as Map<String, Object?>;
  return convertLegacyChunkMap(m, id: id);
}

/// Map-based variant of [convertLegacyChunk] (used by `loadModelData` in
/// `scene_loader.dart` for legacy formats).
ModelData convertLegacyChunkMap(
  Map<String, Object?> m, {
  required String id,
}) {
  final size = ModelSize.fromJson(m['size']);
  final objects = <ModelObject>[];
  if (m['objects'] is List) {
    for (final o in m['objects'] as List) {
      final ob = ModelObject.fromJson(o);
      if (ob.id.isEmpty) ob.id = 'obj_${objects.length + 1}';
      if (ob.name.isEmpty) ob.name = ob.id;
      if (ob.kind == legacyMetaPassKind) continue; // → door boxes below
      objects.add(ob);
    }
  }
  final groups = <ModelGroup>[
    if (m['groups'] is List)
      for (final g in m['groups'] as List) ModelGroup.fromJson(g),
  ];
  final entries = <ModelSide>{};
  if (m['entries'] is List) {
    for (final v in m['entries'] as List) {
      final s = modelSideFrom(v);
      if (s != null) entries.add(s);
    }
  }
  final front = modelSideFrom(m['front']);

  final doors = legacyPassageCells(m['objects'], size);

  final metas = <ModelMeta>[];
  var metaIndex = 0;
  String nextId() => 'meta_${++metaIndex}';

  for (final (x, z) in doors) {
    metas.add(ModelMeta(
      id: nextId(),
      kind: metaKindBox,
      name: metaNameDoor,
      x: x.toDouble(),
      y: 0,
      z: z.toDouble(),
      dims: const {'w': 1, 'h': 1, 'd': 1},
    ));
  }

  if (m['blocked'] is List) {
    final blocked = <(int, int)>{};
    for (final v in m['blocked'] as List) {
      final cell = parseLegacyCell(v);
      if (cell == null) continue;
      final (x, z) = cell;
      // The legacy set may list cells outside the footprint — clip them.
      if (x < 0 || x >= size.w || z < 0 || z >= size.l) continue;
      // A door cell is a passage, never occupied (plan §3.14).
      if (doors.contains(cell)) continue;
      blocked.add(cell);
    }
    final sorted = blocked.toList()
      ..sort((a, b) => a.$2 == b.$2 ? a.$1 - b.$1 : a.$2 - b.$2);
    for (final (x, z) in sorted) {
      metas.add(ModelMeta(
        id: nextId(),
        kind: metaKindBox,
        name: metaNameUnpassable,
        x: x.toDouble(),
        y: 0,
        z: z.toDouble(),
        dims: const {'w': 1, 'h': 1, 'd': 1},
      ));
    }
  }

  // Optional markup/lighting keys (chunks do not carry them, but be safe).
  if (m['meta'] is List) {
    for (final x in m['meta'] as List) {
      metas.add(ModelMeta.fromJson(x));
    }
  }

  final model = ModelData(
    id: id,
    name: (m['name'] as String?) ?? id,
    size: size,
    objects: objects,
    groups: groups,
    metas: metas,
    entries: entries,
    front: front,
    lighting: ModelLighting.fromJson(m['lighting']),
  );
  model.pruneGroupMembers();
  model.pruneCsgNodes();
  return model;
}

/// Parses a legacy `"x,z"` blocked-cell key; null when malformed.
(int, int)? parseLegacyCell(Object? value) {
  if (value is! String) return null;
  final parts = value.split(',');
  if (parts.length != 2) return null;
  final x = int.tryParse(parts[0].trim());
  final z = int.tryParse(parts[1].trim());
  if (x == null || z == null) return null;
  return (x, z);
}

/// The chunk-local border ring cells opened by the document's `meta_pass`
/// markers — the port of the game's `ChunkData.passages` +
/// `chunkPassageCells`. Each marker spans along the wall it sits on; the
/// ring cells under its footprint become passages. Markers off the border
/// ring (or on the corners) are ignored.
Set<(int, int)> legacyPassageCells(Object? objectsJson, ModelSize size) {
  final cells = <(int, int)>{};
  if (objectsJson is! List) return cells;
  final w = size.w, l = size.l;
  for (final raw in objectsJson) {
    if (raw is! Map) continue;
    if (raw['kind'] != legacyMetaPassKind) continue;
    final pos = raw['pos'] is List
        ? (raw['pos'] as List).whereType<num>().toList()
        : const <num>[];
    final cx = pos.isNotEmpty ? pos[0].toDouble() : 0.0;
    final cz = pos.length > 2 ? pos[2].toDouble() : 0.0;
    final alongX = _legacyDim(raw, 'w', 1) >= _legacyDim(raw, 'd', 1);
    final inN = alongX && cz >= -0.5 && cz < 0.5;
    final inS = alongX && cz > l - 1.5 && cz <= l - 0.5;
    final inW = !alongX && cx >= -0.5 && cx < 0.5;
    final inE = !alongX && cx > w - 1.5 && cx <= w - 0.5;
    if (!inN && !inS && !inW && !inE) continue;
    final side = inN
        ? ModelSide.north
        : inS
            ? ModelSide.south
            : inW
                ? ModelSide.west
                : ModelSide.east;
    final northSouth = inN || inS;
    final along = northSouth ? cx : cz;
    final extent = northSouth ? _legacyDim(raw, 'w', 1) : _legacyDim(raw, 'd', 1);
    final maxIdx = northSouth ? w - 1 : l - 1;
    const eps = 0.05;
    final half = extent / 2 + eps;
    int? c0, c1;
    for (var i = 0; i <= maxIdx; i++) {
      if ((along - i).abs() <= half) {
        c0 ??= i;
        c1 = i;
      }
    }
    if (c0 == null) continue;
    switch (side) {
      case ModelSide.north:
        for (var i = c0; i <= c1!; i++) {
          cells.add((i, 0));
        }
      case ModelSide.south:
        for (var i = c0; i <= c1!; i++) {
          cells.add((i, l - 1));
        }
      case ModelSide.west:
        for (var i = c0; i <= c1!; i++) {
          cells.add((0, i));
        }
      case ModelSide.east:
        for (var i = c0; i <= c1!; i++) {
          cells.add((w - 1, i));
        }
    }
  }
  return cells;
}

/// A legacy `size` entry: the map form (`{'w': …}`) or the list form
/// (`[w, h, d]`).
double _legacyDim(Map raw, String key, double fallback) {
  final s = raw['size'];
  if (s is Map && s[key] is num) return (s[key] as num).toDouble();
  if (s is List) {
    final i = switch (key) {
      'w' => 0,
      'h' => 1,
      'd' => 2,
      _ => -1,
    };
    if (i >= 0 && s.length > i && s[i] is num) return (s[i] as num).toDouble();
  }
  return fallback;
}
