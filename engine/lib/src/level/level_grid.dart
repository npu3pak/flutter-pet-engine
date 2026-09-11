import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model_scene.dart';

/// What occupies a level cell — the engine-generic half of the cell's
/// description (the game-specific half lives in [LevelCell.kind]).
enum LevelCellType {
  /// Walkable space: floors are derived under it, ceilings above it (unless
  /// the region disables them), walls around its open borders.
  open,

  /// Solid fabric (wall block): no floor/ceiling of its own; walls are the
  /// faces between it and open/empty cells.
  solid,

  /// Nothing (chasm, outside the level): no floor/ceiling; walls are the
  /// faces between it and open cells.
  empty,
}

/// One cell of a [LevelGrid]: the engine-generic space description plus the
/// game-owned `kind` tag (opaque to the engine) and an optional material
/// override.
class LevelCell {
  LevelCellType type;

  /// Whether the player can walk through the cell. Independent of [type]:
  /// water is [LevelCellType.open] but not passable.
  bool passable;

  /// Id of the region whose materials/height rules apply (null = grid
  /// defaults).
  String? regionId;

  /// Floor height of the cell (0 = the level's base plane).
  double elevation;

  /// Game-defined cell tag (e.g. `river`, `deck`, `rubble`). Opaque.
  String? kind;

  /// Optional per-cell material override (region materials apply when null).
  String? materialKey;

  LevelCell({
    this.type = LevelCellType.empty,
    this.passable = false,
    this.regionId,
    this.elevation = 0,
    this.kind,
    this.materialKey,
  });

  /// A walkable open cell (passable unless [passable] is false — water).
  LevelCell.open({
    this.passable = true,
    this.regionId,
    this.elevation = 0,
    this.kind,
    this.materialKey,
  }) : type = LevelCellType.open;

  /// A solid (wall) cell.
  LevelCell.solid({this.regionId, this.kind, this.materialKey})
      : type = LevelCellType.solid,
        passable = false,
        elevation = 0;

  /// An empty (void) cell.
  LevelCell.empty({this.regionId, this.kind})
      : type = LevelCellType.empty,
        passable = false,
        elevation = 0,
        materialKey = null;

  LevelCell.copy(LevelCell o)
      : this(
          type: o.type,
          passable: o.passable,
          regionId: o.regionId,
          elevation: o.elevation,
          kind: o.kind,
          materialKey: o.materialKey,
        );

  bool get isOpen => type == LevelCellType.open;

  bool get isSolid => type == LevelCellType.solid;

  bool get isEmpty => type == LevelCellType.empty;
}

/// A named group of cells with shared rules and materials (room, corridor,
/// water, street). The engine does not know the names; the game owns them.
class LevelRegion {
  final String id;
  String name;

  /// Material keys (texture file names or color descriptors) of the derived
  /// shell surfaces; null = the grid/builder default.
  String? floorMaterial;
  String? wallMaterial;
  String? ceilingMaterial;

  /// Height of the walls derived around the region's open cells.
  double wallHeight;

  /// Ceiling plane height; defaults to [wallHeight].
  double? ceilingYOverride;

  /// Whether the region gets a derived ceiling.
  bool hasCeiling;

  LevelRegion({
    required this.id,
    this.name = '',
    this.floorMaterial,
    this.wallMaterial,
    this.ceilingMaterial,
    this.wallHeight = 3.0,
    double? ceilingY,
    this.hasCeiling = true,
  }) : ceilingYOverride = ceilingY;

  /// The effective ceiling plane height.
  double get ceilingY => ceilingYOverride ?? wallHeight;

  LevelRegion.copy(LevelRegion o)
      : this(
          id: o.id,
          name: o.name,
          floorMaterial: o.floorMaterial,
          wallMaterial: o.wallMaterial,
          ceilingMaterial: o.ceilingMaterial,
          wallHeight: o.wallHeight,
          ceilingY: o.ceilingYOverride,
          hasCeiling: o.hasCeiling,
        );
}

/// Kind of a per-cell opening in a derived wall.
enum LevelOpeningKind { door, window }

/// An opening in the wall on the given [side] of the cell (row, col).
/// Doors become full-height passages with a lintel above; windows keep a
/// sill and a header.
class LevelOpening {
  int row;
  int col;
  ModelSide side;
  LevelOpeningKind kind;

  LevelOpening({
    required this.row,
    required this.col,
    required this.side,
    this.kind = LevelOpeningKind.door,
  });
}

/// A rectangular grid of level cells with derived neighbour links.
///
/// Cell (0, 0) maps to world (0, 0, 0) through [cellWorld]; cell centers sit
/// on the integers. The mirrored-X convention is sacred — always go through
/// [cellWorld]/[cellAtWorld], never raw x/z.
class LevelGrid {
  final int rows;
  final int cols;
  final List<LevelCell> _cells;
  final Map<String, LevelRegion> regions;
  final List<LevelOpening> openings;

  LevelGrid(
    this.rows,
    this.cols, {
    List<LevelRegion>? regions,
    List<LevelOpening>? openings,
    LevelCell? fill,
  })  : assert(rows >= 0 && cols >= 0),
        _cells = List.generate(
          rows * cols,
          (_) => LevelCell.copy(fill ?? LevelCell()),
        ),
        regions = {
          for (final r in regions ?? const <LevelRegion>[]) r.id: r,
        },
        openings = List.of(openings ?? const <LevelOpening>[]);

  /// Builds a grid from a character matrix:
  /// `.` = open passable, `~` = open not passable (water), `#` = solid,
  /// space = empty. [regionFor] assigns a region id per character.
  factory LevelGrid.fromRows(
    List<String> rows, {
    List<LevelRegion>? regions,
    List<LevelOpening>? openings,
    String? Function(String ch, int row, int col)? regionFor,
  }) {
    final height = rows.length;
    final width = height == 0 ? 0 : rows.first.length;
    final grid = LevelGrid(height, width, regions: regions, openings: openings);
    for (var r = 0; r < height; r++) {
      final line = rows[r];
      for (var c = 0; c < width; c++) {
        final ch = c < line.length ? line[c] : ' ';
        final region = regionFor?.call(ch, r, c);
        switch (ch) {
          case '.':
            grid.setCell(r, c, LevelCell.open(regionId: region));
          case '~':
            grid.setCell(r, c, LevelCell.open(passable: false, regionId: region));
          case '#':
            grid.setCell(r, c, LevelCell.solid(regionId: region));
          default:
            grid.setCell(r, c, LevelCell.empty(regionId: region));
        }
      }
    }
    return grid;
  }

  bool contains(int row, int col) =>
      row >= 0 && row < rows && col >= 0 && col < cols;

  int _index(int row, int col) {
    if (!contains(row, col)) {
      throw RangeError('cell ($row, $col) outside ${rows}x$cols');
    }
    return row * cols + col;
  }

  LevelCell cellAt(int row, int col) => _cells[_index(row, col)];

  LevelCell? tryCellAt(int row, int col) =>
      contains(row, col) ? _cells[_index(row, col)] : null;

  void setCell(int row, int col, LevelCell cell) =>
      _cells[_index(row, col)] = cell;

  bool isPassable(int row, int col) {
    final cell = tryCellAt(row, col);
    return cell != null && cell.passable;
  }

  /// All cells in row-major order (name distinct from [ModelData.entries]).
  Iterable<((int, int), LevelCell)> get cells sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        yield ((r, c), _cells[r * cols + c]);
      }
    }
  }

  Iterable<(int, int)> get passableCells sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (_cells[r * cols + c].passable) yield (r, c);
      }
    }
  }

  /// The existing 4-way neighbour of (row, col) on [side] (null outside).
  (int, int)? sideNeighbor(int row, int col, ModelSide side) {
    final (dr, dc) = switch (side) {
      ModelSide.north => (-1, 0),
      ModelSide.east => (0, 1),
      ModelSide.south => (1, 0),
      ModelSide.west => (0, -1),
    };
    final (r, c) = (row + dr, col + dc);
    return contains(r, c) ? (r, c) : null;
  }

  /// Passable neighbours of (row, col) (derived links — never stored).
  List<(int, int)> passableNeighbors(int row, int col) => [
        for (final side in ModelSide.values)
          if (sideNeighbor(row, col, side) case final n?)
            if (isPassable(n.$1, n.$2)) n,
      ];

  /// All derived passable links, each cell pair once (a→b with row-major a).
  Iterable<((int, int), (int, int))> get edges sync* {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!isPassable(r, c)) continue;
        final east = sideNeighbor(r, c, ModelSide.east);
        if (east != null && isPassable(east.$1, east.$2)) {
          yield ((r, c), east);
        }
        final south = sideNeighbor(r, c, ModelSide.south);
        if (south != null && isPassable(south.$1, south.$2)) {
          yield ((r, c), south);
        }
      }
    }
  }

  /// The grid cell containing the world point (x, z), or null outside.
  (int, int)? cellAtWorld(double worldX, double worldZ) {
    final row = worldZ.round();
    final col = (-worldX).round();
    return contains(row, col) ? (row, col) : null;
  }

  /// World-space center of the cell's base (the [cellWorld] convention).
  vm.Vector3 cellCenterWorld(int row, int col) => cellWorld(row, col);

  /// Regions of the grid in insertion order.
  List<LevelRegion> get regionList => regions.values.toList();

  /// The region of (row, col), if the cell references a known one.
  LevelRegion? regionAt(int row, int col) {
    final id = tryCellAt(row, col)?.regionId;
    return id == null ? null : regions[id];
  }
}
