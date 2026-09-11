import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('LevelGrid.fromRows', () {
    test('maps characters to cell types', () {
      final grid = LevelGrid.fromRows([
        '.#.',
        '.~.',
        '.. ',
      ]);
      expect(grid.rows, 3);
      expect(grid.cols, 3);
      expect(grid.cellAt(0, 0).type, LevelCellType.open);
      expect(grid.cellAt(0, 0).passable, isTrue);
      expect(grid.cellAt(0, 1).type, LevelCellType.solid);
      expect(grid.cellAt(0, 1).passable, isFalse);
      expect(grid.cellAt(1, 1).type, LevelCellType.open);
      expect(grid.cellAt(1, 1).passable, isFalse, reason: 'water is open but not passable');
      expect(grid.cellAt(2, 2).type, LevelCellType.empty);
    });

    test('assigns region ids per character', () {
      final grid = LevelGrid.fromRows(
        ['.', '#'],
        regionFor: (ch, r, c) => ch == '.' ? 'floor' : 'wall',
      );
      expect(grid.cellAt(0, 0).regionId, 'floor');
      expect(grid.cellAt(1, 0).regionId, 'wall');
    });
  });

  group('cells and regions', () {
    test('cellAt throws outside, tryCellAt returns null', () {
      final grid = LevelGrid(2, 2, fill: LevelCell.open());
      expect(grid.contains(1, 1), isTrue);
      expect(grid.contains(2, 0), isFalse);
      expect(grid.tryCellAt(5, 5), isNull);
      expect(() => grid.cellAt(5, 5), throwsRangeError);
    });

    test('regionAt resolves the referenced region', () {
      final grid = LevelGrid(
        1,
        2,
        regions: [LevelRegion(id: 'room', name: 'Комната', wallHeight: 4)],
      );
      grid.setCell(0, 0, LevelCell.open(regionId: 'room'));
      expect(grid.regionAt(0, 0)?.name, 'Комната');
      expect(grid.regionAt(0, 0)?.wallHeight, 4);
      expect(grid.regionAt(0, 1), isNull);
      expect(grid.regionList.single.id, 'room');
    });

    test('region ceiling defaults to the wall height', () {
      final region = LevelRegion(id: 'r', wallHeight: 5);
      expect(region.ceilingY, 5);
      expect(LevelRegion(id: 'r', wallHeight: 5, ceilingY: 7).ceilingY, 7);
    });

    test('passableCells lists only passable cells', () {
      final grid = LevelGrid.fromRows([
        '.#',
        '~.',
      ]);
      expect(grid.passableCells.toSet(), {(0, 0), (1, 1)});
    });
  });

  group('derived edges', () {
    test('sideNeighbor uses the compass mapping', () {
      final grid = LevelGrid(3, 3, fill: LevelCell.open());
      expect(grid.sideNeighbor(1, 1, ModelSide.north), (0, 1));
      expect(grid.sideNeighbor(1, 1, ModelSide.east), (1, 2));
      expect(grid.sideNeighbor(1, 1, ModelSide.south), (2, 1));
      expect(grid.sideNeighbor(1, 1, ModelSide.west), (1, 0));
      expect(grid.sideNeighbor(0, 0, ModelSide.north), isNull);
      expect(grid.sideNeighbor(2, 2, ModelSide.east), isNull);
    });

    test('passableNeighbors skips blocked and diagonal cells', () {
      final grid = LevelGrid.fromRows([
        '.#.',
        '...',
        '.#.',
      ]);
      expect(grid.passableNeighbors(1, 1).toSet(), {(1, 2), (1, 0)});
      expect(grid.passableNeighbors(0, 0).toSet(), {(1, 0)});
    });

    test('edges are derived, not stored', () {
      final grid = LevelGrid.fromRows([
        '..',
        '..',
      ]);
      expect(grid.edges.length, 4);
      grid.setCell(0, 1, LevelCell.solid());
      expect(grid.edges.length, 2);
    });

    test('edges contain every passable pair once', () {
      final grid = LevelGrid.fromRows([
        '...',
      ]);
      final edges = grid.edges.toList();
      expect(edges, [((0, 0), (0, 1)), ((0, 1), (0, 2))]);
    });
  });

  group('world mapping', () {
    test('cellAtWorld round-trips every cell through cellWorld', () {
      final grid = LevelGrid(4, 5, fill: LevelCell.open());
      for (var r = 0; r < grid.rows; r++) {
        for (var c = 0; c < grid.cols; c++) {
          final world = grid.cellCenterWorld(r, c);
          expect(grid.cellAtWorld(world.x, world.z), (r, c));
        }
      }
    });

    test('cellAtWorld uses the mirrored X axis', () {
      final grid = LevelGrid(2, 2, fill: LevelCell.open());
      final world = vm.Vector3(-1, 0, 0); // col 1
      expect(grid.cellAtWorld(world.x, world.z), (0, 1));
      expect(grid.cellAtWorld(50, 50), isNull);
    });
  });

  group('openings', () {
    test('openings are kept as authored', () {
      final grid = LevelGrid(
        2,
        2,
        fill: LevelCell.open(),
        openings: [
          LevelOpening(row: 0, col: 1, side: ModelSide.east),
          LevelOpening(
            row: 1,
            col: 0,
            side: ModelSide.north,
            kind: LevelOpeningKind.window,
          ),
        ],
      );
      expect(grid.openings.length, 2);
      expect(grid.openings.first.kind, LevelOpeningKind.door);
      expect(grid.openings.last.side, ModelSide.north);
    });
  });
}
