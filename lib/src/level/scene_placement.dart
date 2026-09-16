import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model_scene.dart';
import 'build_ops.dart';

/// Normalizes a rotation to one of 0/90/180/270.
int normalizeRotY(int rotY) => ((rotY % 360) + 360) % 360 ~/ 90 * 90;

/// Whether a meta object takes part in meta queries (plan §3.25.2): only
/// boxes and markers; comments never participate.
bool isQueryMeta(ModelMeta meta) =>
    meta.kind == metaKindBox || meta.kind == metaKindMarker;

/// A meta object together with the placement it belongs to (the result of
/// the level-wide queries of [SceneLayout]).
typedef PlacedMeta = ({ScenePlacement placement, ModelMeta meta});

/// A scene placed on a level grid: the engine port of the game's
/// `PlacedChunk` + `chunkLocalToMaze`/`chunkWorldOffset`/`chunkMapCellValue`
/// (migration plan §3.2). Placement is grid-exact; the mirrored-X convention
/// is sacred — world mapping always goes through `cellWorld`.
///
/// Cell semantics (both legacy styles, matching the game):
/// - door boxes open cells (they win over `unpassable`);
/// - a scene with door boxes uses the modern frame rule: interior cells are
///   passable, border cells are blocked except the doors;
/// - a scene without doors uses the legacy rule: border cells are passable
///   only on its entry sides, interior cells follow the `unpassable` boxes;
/// - window boxes are geometry only and never map to cells (plan §3.2);
/// - an explicit `unpassable` box always blocks, even under the modern rule
///   (the game's passage-marked chunks ignored authored `blockedCells`; in
///   the engine an explicit box is authoritative — review note 5).
class ScenePlacement {
  final ModelData scene;
  final int originRow;
  final int originCol;
  final int rotY;

  ScenePlacement({
    required this.scene,
    required this.originRow,
    required this.originCol,
    int rotY = 0,
  }) : rotY = normalizeRotY(rotY);

  int get _turns => (rotY ~/ 90) % 4;

  int get _w => scene.size.w;
  int get _l => scene.size.l;

  /// Footprint size on the level grid after [rotY] (90/270 swap w and l).
  int get footprintRows => _turns.isOdd ? _w : _l;
  int get footprintCols => _turns.isOdd ? _l : _w;

  /// Maps a scene-local cell (x = column, z = row) to level (row, col) —
  /// the port of `chunkLocalToMaze`.
  (int, int) cellToLevel(int x, int z) {
    final (r, c) = switch (_turns) {
      1 => (x, _l - 1 - z),
      2 => (_l - 1 - z, _w - 1 - x),
      3 => (_w - 1 - x, z),
      _ => (z, x),
    };
    return (originRow + r, originCol + c);
  }

  /// Continuous analogue of [cellToLevel] for the renderer — the port of
  /// `chunkWorldOffset`: scene-local (x, z) → level world (worldX, worldZ)
  /// with cell (0, 0) on the world center of (originRow, originCol).
  (double, double) localToLevelWorld(double x, double z) {
    final (r, c) = switch (_turns) {
      1 => (x, _l - 1 - z),
      2 => (_l - 1 - z, _w - 1 - x),
      3 => (_w - 1 - x, z),
      _ => (z, x),
    };
    final origin = cellWorld(originRow, originCol);
    return (origin.x - c, origin.z + r);
  }

  /// World position of the scene's local origin (cell 0, 0).
  vm.Vector3 get originWorld => cellWorld(originRow, originCol);

  /// Inverse of [cellToLevel]: level (row, col) → scene-local cell.
  (int, int) levelToCell(int row, int col) {
    final r = row - originRow;
    final c = col - originCol;
    return switch (_turns) {
      1 => (r, _l - 1 - c),
      2 => (_w - 1 - c, _l - 1 - r),
      3 => (_w - 1 - r, c),
      _ => (c, r),
    };
  }

  bool containsLevelCell(int row, int col) =>
      row >= originRow &&
      row < originRow + footprintRows &&
      col >= originCol &&
      col < originCol + footprintCols;

  /// Footprint cells in level coordinates (row-major).
  Iterable<(int, int)> get cells sync* {
    for (var z = 0; z < _l; z++) {
      for (var x = 0; x < _w; x++) {
        yield cellToLevel(x, z);
      }
    }
  }

  // ── meta boxes → cells ───────────────────────────────────────────────

  /// Cells whose center is inside a box meta named [name].
  Set<(int, int)> cellsUnderBoxes(String name) {
    final out = <(int, int)>{};
    for (final meta in scene.metas) {
      if (meta.kind != metaKindBox || meta.name != name) continue;
      final hw = meta.dim('w', 1) / 2;
      final hd = meta.dim('d', 1) / 2;
      for (var z = 0; z < _l; z++) {
        for (var x = 0; x < _w; x++) {
          final dx = x - meta.x;
          final dz = z - meta.z;
          if (dx > -hw && dx < hw && dz > -hd && dz < hd) {
            out.add((x, z));
          }
        }
      }
    }
    return out;
  }

  /// Occupied (impassable) scene-local cells: `unpassable` boxes.
  late final Set<(int, int)> unpassableCells =
      cellsUnderBoxes(metaNameUnpassable);

  /// Door passage cells: `door` boxes (a cell covered by a door is passable
  /// even when an `unpassable` box would cover it).
  late final Set<(int, int)> doorCells = cellsUnderBoxes(metaNameDoor);

  /// Window cells — geometry only, never mapped to passability (plan §3.2).
  late final Set<(int, int)> windowCells = cellsUnderBoxes(metaNameWindow);

  /// Whether the scene uses the modern frame rule (has door boxes).
  bool get hasDoors => doorCells.isNotEmpty;

  // ── meta queries (plan §3.25.2, подшаг 5.1) ──────────────────────────
  //
  // Only boxes and markers participate in queries; comments never do.
  // A box belongs to a cell when the box rectangle and the cell rectangle
  // intersect (a box «заезжает краешком» counts, a pure edge touch does
  // not). A marker belongs to a cell when its anchor is inside the cell.
  // In world coordinates a box matches when the point is inside the box
  // (no cell rounding), a marker — when its anchor lies in the same cell
  // as the point. Per-cell results are computed once and memoized; the
  // scene model is expected to stay unchanged (the same assumption the
  // cached `unpassableCells`/`doorCells` sets already make).

  final Map<(int, int), List<ModelMeta>> _cellQueries = {};
  final Map<String, List<ModelMeta>> _namedQueries = {};

  /// Metas of the scene that take part in queries (boxes and markers).
  List<ModelMeta> get queryMetas => List.unmodifiable(
      scene.metas.where((m) => isQueryMeta(m)));

  /// Metas at the scene-local cell (x = column, z = row). Cached.
  List<ModelMeta> metasAtCell(int x, int z) {
    if (x < 0 || x >= _w || z < 0 || z >= _l) return const [];
    return _cellQueries.putIfAbsent((x, z), () {
      final out = <ModelMeta>[];
      for (final meta in scene.metas) {
        if (!isQueryMeta(meta)) continue;
        final hit = meta.kind == metaKindBox
            ? _boxHitsCell(meta, x, z)
            : _markerCell(meta) == (x, z);
        if (hit) out.add(meta);
      }
      return List.unmodifiable(out);
    });
  }

  /// Metas at the level cell (row, col), rotation-aware. Cached per
  /// scene-local cell.
  List<ModelMeta> metasAtLevel(int row, int col) {
    if (!containsLevelCell(row, col)) return const [];
    final (x, z) = levelToCell(row, col);
    return metasAtCell(x, z);
  }

  /// Metas at the world point. A box matches when the point is inside the
  /// box rectangle, a marker — when its anchor is in the same cell as the
  /// point. Points outside the placement footprint match nothing.
  List<ModelMeta> metasAtWorld(double worldX, double worldZ) {
    final (x, z) = _localFromWorld(worldX, worldZ);
    if (x < -0.5 || x >= _w - 0.5 || z < -0.5 || z >= _l - 0.5) {
      return const [];
    }
    final pointCell = _localCellOf(x, z);
    final out = <ModelMeta>[];
    for (final meta in scene.metas) {
      if (!isQueryMeta(meta)) continue;
      final hit = meta.kind == metaKindBox
          ? _boxContainsPoint(meta, x, z)
          : _markerCell(meta) == pointCell;
      if (hit) out.add(meta);
    }
    return out;
  }

  /// Metas of the scene named [name] (boxes and markers). Cached.
  List<ModelMeta> metasNamed(String name) => _namedQueries.putIfAbsent(
      name,
      () => List.unmodifiable(scene.metas
          .where((m) => isQueryMeta(m) && m.name == name)));

  /// Continuous world → scene-local inverse of [localToLevelWorld].
  (double, double) _localFromWorld(double worldX, double worldZ) {
    final origin = cellWorld(originRow, originCol);
    final dx = worldX - origin.x;
    final dz = worldZ - origin.z;
    return switch (_turns) {
      1 => (dz, dx + _l - 1),
      2 => (dx + _w - 1, -dz + _l - 1),
      3 => (-dz + _w - 1, -dx),
      _ => (-dx, dz),
    };
  }

  /// The cell a continuous scene-local point belongs to (cells are centered
  /// on integers and span half-open `[c-0.5, c+0.5)`).
  static (int, int) _localCellOf(double x, double z) =>
      ((x + 0.5).floor(), (z + 0.5).floor());

  static (int, int) _markerCell(ModelMeta meta) =>
      _localCellOf(meta.x, meta.z);

  static bool _boxHitsCell(ModelMeta meta, int x, int z) {
    final hw = meta.dim('w', 1) / 2;
    final hd = meta.dim('d', 1) / 2;
    final minX = meta.x - hw, maxX = meta.x + hw;
    final minZ = meta.z - hd, maxZ = meta.z + hd;
    return maxX > x - 0.5 &&
        minX < x + 0.5 &&
        maxZ > z - 0.5 &&
        minZ < z + 0.5;
  }

  static bool _boxContainsPoint(ModelMeta meta, double x, double z) {
    final hw = meta.dim('w', 1) / 2;
    final hd = meta.dim('d', 1) / 2;
    return x > meta.x - hw &&
        x < meta.x + hw &&
        z > meta.z - hd &&
        z < meta.z + hd;
  }

  /// Border cells on the scene's entry sides (the port of
  /// `chunkPassableEntryCells`).
  Set<(int, int)> get entryBorderCells {
    final out = <(int, int)>{};
    void row(int z) {
      for (var x = 0; x < _w; x++) {
        out.add((x, z));
      }
    }

    void col(int x) {
      for (var z = 0; z < _l; z++) {
        out.add((x, z));
      }
    }

    if (scene.entries.contains(ModelSide.north)) row(0);
    if (scene.entries.contains(ModelSide.south)) row(_l - 1);
    if (scene.entries.contains(ModelSide.west)) col(0);
    if (scene.entries.contains(ModelSide.east)) col(_w - 1);
    return out;
  }

  bool _isBorder(int x, int z) =>
      x == 0 || x == _w - 1 || z == 0 || z == _l - 1;

  /// Scene-local passability (the port of `chunkMapCellValue` == 0).
  bool isCellPassable(int x, int z) {
    final cell = (x, z);
    if (doorCells.contains(cell)) return true;
    if (unpassableCells.contains(cell)) return false;
    final onBorder = _isBorder(x, z);
    if (hasDoors) return !onBorder;
    if (onBorder && !entryBorderCells.contains(cell)) return false;
    return true;
  }

  /// Passable footprint cells in level coordinates.
  Set<(int, int)> get openCells {
    final out = <(int, int)>{};
    for (var z = 0; z < _l; z++) {
      for (var x = 0; x < _w; x++) {
        if (isCellPassable(x, z)) out.add(cellToLevel(x, z));
      }
    }
    return out;
  }

  /// Blocked footprint cells in level coordinates (walls of the scene).
  Set<(int, int)> get blockedCells {
    final out = <(int, int)>{};
    for (var z = 0; z < _l; z++) {
      for (var x = 0; x < _w; x++) {
        if (!isCellPassable(x, z)) out.add(cellToLevel(x, z));
      }
    }
    return out;
  }

  // ── sides ────────────────────────────────────────────────────────────

  /// The scene-local side corresponding to a level [side] (rotation-aware).
  ModelSide localSideOf(ModelSide side) => switch (_turns) {
        1 => switch (side) {
            ModelSide.north => ModelSide.west,
            ModelSide.east => ModelSide.north,
            ModelSide.south => ModelSide.east,
            ModelSide.west => ModelSide.south,
          },
        2 => oppositeSide(side),
        3 => switch (side) {
            ModelSide.north => ModelSide.east,
            ModelSide.east => ModelSide.south,
            ModelSide.south => ModelSide.west,
            ModelSide.west => ModelSide.north,
          },
        _ => side,
      };

  /// Passable border cells of the placement on the level [side] — the cells
  /// the level can connect through.
  Set<(int, int)> openBorderCells(ModelSide side) {
    final local = localSideOf(side);
    final out = <(int, int)>{};
    for (var z = 0; z < _l; z++) {
      for (var x = 0; x < _w; x++) {
        if (!_isBorder(x, z)) continue;
        final matches = switch (local) {
          ModelSide.north => z == 0,
          ModelSide.south => z == _l - 1,
          ModelSide.west => x == 0,
          ModelSide.east => x == _w - 1,
        };
        if (matches && isCellPassable(x, z)) out.add(cellToLevel(x, z));
      }
    }
    return out;
  }

  /// Door cells of the placement on the level [side].
  Set<(int, int)> doorBorderCells(ModelSide side) {
    final local = localSideOf(side);
    final out = <(int, int)>{};
    for (final (x, z) in doorCells) {
      final matches = switch (local) {
        ModelSide.north => z == 0,
        ModelSide.south => z == _l - 1,
        ModelSide.west => x == 0,
        ModelSide.east => x == _w - 1,
      };
      if (matches) out.add(cellToLevel(x, z));
    }
    return out;
  }

  /// Whether the scene declares the level [side] as an entry (rotation-aware:
  /// the scene's local entry sides are mapped through the placement).
  bool hasEntry(ModelSide side) => scene.entries.contains(localSideOf(side));

  /// Footprint cells whose scene ceiling must be skipped: a scene object
  /// rising above the first cell overlaps the cell — the port of
  /// `chunkOpenCeilingCells`. Derived from element heights, never stored.
  Set<(int, int)> get openCeilingCells {
    final out = <(int, int)>{};
    for (var z = 0; z < _l; z++) {
      for (var x = 0; x < _w; x++) {
        final cellMinX = x - 0.5, cellMaxX = x + 0.5;
        final cellMinZ = z - 0.5, cellMaxZ = z + 0.5;
        final tall = scene.objects.any((o) {
          final (lo, hi) = objectBounds(o);
          return hi.y > 1.0 &&
              lo.x < cellMaxX &&
              hi.x > cellMinX &&
              lo.z < cellMaxZ &&
              hi.z > cellMinZ;
        });
        if (tall) out.add(cellToLevel(x, z));
      }
    }
    return out;
  }
}

/// A set of scene placements over one level grid: derived passability,
/// overlap detection and automatic docking checks (the primitives the level
/// validator builds on).
class SceneLayout {
  final List<ScenePlacement> placements;

  SceneLayout(this.placements);

  /// Footprint cells covered by more than one placement.
  Map<(int, int), List<ScenePlacement>> get overlaps {
    final owners = <(int, int), List<ScenePlacement>>{};
    for (final p in placements) {
      for (final cell in p.cells) {
        owners.putIfAbsent(cell, () => []).add(p);
      }
    }
    owners.removeWhere((_, list) => list.length < 2);
    return owners;
  }

  ScenePlacement? placementAt(int row, int col) {
    for (final p in placements) {
      if (p.containsLevelCell(row, col)) return p;
    }
    return null;
  }

  /// Passability of a level cell across the layout: null when no scene
  /// covers it; true when at least one covering scene makes it passable;
  /// false when every covering scene blocks it.
  bool? isPassableAt(int row, int col) {
    var covered = false;
    for (final p in placements) {
      if (!p.containsLevelCell(row, col)) continue;
      covered = true;
      final (x, z) = p.levelToCell(row, col);
      if (p.isCellPassable(x, z)) return true;
    }
    return covered ? false : null;
  }

  // ── meta queries (plan §3.25.2, подшаг 5.1) ──────────────────────────

  /// Metas at the level cell across every covering placement («сцена + мета»).
  List<PlacedMeta> metasAt(int row, int col) {
    final out = <PlacedMeta>[];
    for (final p in placements) {
      for (final meta in p.metasAtLevel(row, col)) {
        out.add((placement: p, meta: meta));
      }
    }
    return List.unmodifiable(out);
  }

  /// Metas at the world point across every placement whose footprint
  /// contains it.
  List<PlacedMeta> metasAtWorld(double worldX, double worldZ) {
    final out = <PlacedMeta>[];
    for (final p in placements) {
      for (final meta in p.metasAtWorld(worldX, worldZ)) {
        out.add((placement: p, meta: meta));
      }
    }
    return List.unmodifiable(out);
  }

  /// Every queryable meta of the level (boxes and markers, no comments).
  List<PlacedMeta> get allMetas {
    final out = <PlacedMeta>[];
    for (final p in placements) {
      for (final meta in p.queryMetas) {
        out.add((placement: p, meta: meta));
      }
    }
    return List.unmodifiable(out);
  }

  /// Level metas named [name] (boxes and markers).
  List<PlacedMeta> metasNamed(String name) {
    final out = <PlacedMeta>[];
    for (final p in placements) {
      for (final meta in p.metasNamed(name)) {
        out.add((placement: p, meta: meta));
      }
    }
    return List.unmodifiable(out);
  }

  /// Names of all queryable level metas.
  Set<String> get metaNames =>
      {for (final p in placements) ...p.queryMetas.map((m) => m.name)};

  /// Whether [a] and [b] are edge-adjacent on the level grid.
  static ModelSide? sharedSide(ScenePlacement a, ScenePlacement b) {
    final aRowEnd = a.originRow + a.footprintRows;
    final aColEnd = a.originCol + a.footprintCols;
    final bRowEnd = b.originRow + b.footprintRows;
    final bColEnd = b.originCol + b.footprintCols;
    final rowsOverlap =
        a.originRow < bRowEnd && b.originRow < aRowEnd;
    final colsOverlap =
        a.originCol < bColEnd && b.originCol < aColEnd;
    if (colsOverlap && a.originRow == bRowEnd) return ModelSide.north;
    if (colsOverlap && b.originRow == aRowEnd) return ModelSide.south;
    if (rowsOverlap && a.originCol == bColEnd) return ModelSide.west;
    if (rowsOverlap && b.originCol == aColEnd) return ModelSide.east;
    return null;
  }

  /// Automatic docking check: [a] and [b] are edge-adjacent and every
  /// opening of the shared border lines up — each door of one placement
  /// faces a cell the neighbor leaves passable. Returns false when the two
  /// are not adjacent.
  bool dockedWith(ScenePlacement a, ScenePlacement b) {
    final side = sharedSide(a, b);
    if (side == null) return false;
    final opposite = oppositeSide(side);
    for (final cell in a.doorBorderCells(side)) {
      if (!_facesPassable(b, cell, side)) return false;
    }
    for (final cell in b.doorBorderCells(opposite)) {
      if (!_facesPassable(a, cell, opposite)) return false;
    }
    return true;
  }

  /// Whether [p] leaves the level cell across [outward] from [cell]
  /// passable (the door opens into [p]).
  static bool _facesPassable(
      ScenePlacement p, (int, int) cell, ModelSide outward) {
    final (r, c) = switch (outward) {
      ModelSide.north => (cell.$1 - 1, cell.$2),
      ModelSide.east => (cell.$1, cell.$2 + 1),
      ModelSide.south => (cell.$1 + 1, cell.$2),
      ModelSide.west => (cell.$1, cell.$2 - 1),
    };
    if (!p.containsLevelCell(r, c)) return false;
    final (x, z) = p.levelToCell(r, c);
    return p.isCellPassable(x, z);
  }
}
