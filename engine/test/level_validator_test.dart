import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

ModelMeta box(String name, double x, double z) => ModelMeta(
      id: 'm_${name}_${x}_$z',
      kind: metaKindBox,
      name: name,
      x: x,
      z: z,
      dims: const {'w': 1, 'h': 1, 'd': 1},
    );

ModelData scene({
  int w = 3,
  int l = 3,
  Set<ModelSide> entries = const {},
  ModelSide? front,
  List<ModelMeta> metas = const [],
}) =>
    ModelData(
      id: 's',
      name: 's',
      size: ModelSize(w: w, l: l, h: 3),
      entries: Set.of(entries),
      front: front,
      metas: List.of(metas),
    );

ModelData streets(String id) => ModelData.fromJson(
      File('../projects/Streets/models/$id.json').readAsStringSync(),
      id: id,
    );

void main() {
  const validator = LevelValidator();

  group('grid', () {
    test('unknown region ids are reported', () {
      final grid = LevelGrid(
        1,
        2,
        regions: [LevelRegion(id: 'room')],
      );
      grid.setCell(0, 0, LevelCell.open(regionId: 'room'));
      grid.setCell(0, 1, LevelCell.open(regionId: 'missing'));
      final issues = validator.checkGrid(grid);
      expect(issues, hasLength(1));
      expect(issues.single.kind, LevelIssueKind.unknownRegion);
      expect(issues.single.cell, (0, 1));
    });

    test('connectivity reports unreachable passable cells', () {
      final grid = LevelGrid.fromRows(const [
        '#####',
        '#.#.#',
        '#.#.#',
        '#####',
      ]);
      final issues = validator.checkGridConnectivity(
        grid,
        starts: const {(1, 1), (2, 1)},
      );
      expect(issues, hasLength(2));
      expect(issues.map((i) => i.cell).toSet(), {(1, 3), (2, 3)});
      expect(issues.every((i) => i.kind == LevelIssueKind.disconnectedCell),
          isTrue);
    });

    test('a connected grid has no connectivity issues', () {
      final grid = LevelGrid.fromRows(const [
        '#####',
        '#...#',
        '#...#',
        '#####',
      ]);
      expect(validator.checkGridConnectivity(grid), isEmpty);
    });

    test('a fully passable grid is clean', () {
      final grid = LevelGrid.fromRows(const ['...', '...']);
      expect(validator.checkGridConnectivity(grid), isEmpty);
    });

    test('openings outside the grid and blocked doors are reported', () {
      final grid = LevelGrid.fromRows(const [
        '###',
        '#.#',
        '###',
      ]);
      grid.openings.add(
          LevelOpening(row: 1, col: 1, side: ModelSide.east));
      grid.openings.add(
          LevelOpening(row: 9, col: 9, side: ModelSide.north));
      final issues = validator.checkGrid(grid);
      expect(issues.any((i) => i.kind == LevelIssueKind.openingBlocked), isTrue);
      expect(issues.any((i) => i.kind == LevelIssueKind.openingOutsideGrid),
          isTrue);
    });

    test('a door between passable cells is clean; windows are not checked',
        () {
      final grid = LevelGrid.fromRows(const ['...', '...']);
      grid.openings.add(
          LevelOpening(row: 0, col: 0, side: ModelSide.east));
      grid.openings.add(LevelOpening(
        row: 1,
        col: 0,
        side: ModelSide.north,
        kind: LevelOpeningKind.window,
      ));
      expect(validator.checkGrid(grid), isEmpty);
    });
  });

  group('placements', () {
    test('overlapping footprints are errors', () {
      final a = ScenePlacement(scene: scene(), originRow: 0, originCol: 0);
      final b = ScenePlacement(scene: scene(), originRow: 0, originCol: 2);
      final issues = validator.checkPlacements([a, b]);
      final overlaps = issues
          .where((i) => i.kind == LevelIssueKind.placementOverlap)
          .toList();
      expect(overlaps, hasLength(3));
      expect(overlaps.every((i) => i.severity == LevelIssueSeverity.error),
          isTrue);
    });

    test('a door on a side missing from entries is a warning', () {
      final p = ScenePlacement(
        scene: scene(metas: [box(metaNameDoor, 1, 2)]),
        originRow: 0,
        originCol: 0,
      );
      final issues = validator.checkPlacements([p]);
      expect(
          issues.any((i) => i.kind == LevelIssueKind.doorWithoutEntry), isTrue);
    });

    test('a modern entry without a door is a warning', () {
      final p = ScenePlacement(
        scene: scene(
          entries: {ModelSide.north, ModelSide.south},
          metas: [box(metaNameDoor, 1, 2)],
        ),
        originRow: 0,
        originCol: 0,
      );
      final issues = validator.checkPlacements([p]);
      final noDoor = issues
          .where((i) => i.kind == LevelIssueKind.entryWithoutDoor)
          .toList();
      expect(noDoor, hasLength(1));
      expect(noDoor.single.message, contains('north'));
    });

    test('a legacy entry without a door is accepted as an open passage', () {
      final p = ScenePlacement(
        scene: scene(entries: {ModelSide.south}),
        originRow: 0,
        originCol: 0,
      );
      final issues = validator.checkPlacements([p]);
      expect(
          issues.any((i) => i.kind == LevelIssueKind.entryWithoutDoor), isFalse);
    });

    test('mismatched adjacent doors are reported', () {
      final a = ScenePlacement(
        scene: scene(metas: [box(metaNameDoor, 1, 2)]),
        originRow: 0,
        originCol: 0,
      );
      final b = ScenePlacement(scene: scene(), originRow: 3, originCol: 0);
      final issues = validator.checkPlacements([a, b]);
      expect(issues.any((i) => i.kind == LevelIssueKind.dockingMismatch), isTrue);
    });

    test('the streets row is connected and docked', () {
      const ids = ['chunk_2', 'chunk_3', 'chunk_4', 'chunk_5'];
      final placements = <ScenePlacement>[];
      var col = 0;
      for (final id in ids) {
        final p = ScenePlacement(scene: streets(id), originRow: 0, originCol: col);
        placements.add(p);
        col += p.footprintCols;
      }
      final issues = validator.checkPlacements(placements);
      expect(issues.where((i) => i.kind == LevelIssueKind.placementOverlap),
          isEmpty);
      expect(issues.where((i) => i.kind == LevelIssueKind.disconnectedCell),
          isEmpty);
      expect(issues.where((i) => i.kind == LevelIssueKind.dockingMismatch),
          isEmpty);
      expect(issues.where((i) => i.kind == LevelIssueKind.entryFacesWall),
          isEmpty);
    });

    test('an entry facing a neighbor wall is reported (legacy scenes)', () {
      final a =
          ScenePlacement(scene: streets('chunk_2'), originRow: 0, originCol: 0);
      final b =
          ScenePlacement(scene: streets('chunk_2'), originRow: 4, originCol: 0);
      final issues = validator.checkPlacements([a, b]);
      expect(
          issues.any((i) => i.kind == LevelIssueKind.entryFacesWall), isTrue);
    });

    test('an entry facing a neighbor entry is clean', () {
      final a =
          ScenePlacement(scene: streets('chunk_2'), originRow: 0, originCol: 0);
      final b = ScenePlacement(
          scene: streets('chunk_2'), originRow: 4, originCol: 0, rotY: 180);
      final issues = validator.checkPlacements([a, b]);
      expect(
          issues.any((i) => i.kind == LevelIssueKind.entryFacesWall), isFalse);
    });

    test('a facade outside the entry sides is reported', () {
      final p = ScenePlacement(
        scene: scene(front: ModelSide.south),
        originRow: 0,
        originCol: 0,
      );
      final issues = validator.checkPlacements([p]);
      expect(issues.any((i) => i.kind == LevelIssueKind.frontNotEntry), isTrue);
    });

    test('starts override the default entry points', () {
      // Две комнаты, разделённые стеной: старт только в левой.
      final a = ScenePlacement(
        scene: scene(w: 3, l: 3, entries: {ModelSide.south}),
        originRow: 0,
        originCol: 0,
      );
      final issues = validator.checkPlacements([a], starts: const {(0, 0)});
      expect(issues, isEmpty);
    });
  });

  group('construction', () {
    test('duplicate ids are errors', () {
      final model = ConstructionModel();
      model.add(ModelObject(id: 'a', name: 'a', kind: 'cuboid'));
      model.add(ModelObject(id: 'a', name: 'a', kind: 'cuboid'));
      final issues = validator.checkConstruction(model);
      expect(issues, hasLength(1));
      expect(issues.single.kind, LevelIssueKind.duplicateElementId);
      expect(issues.single.severity, LevelIssueSeverity.error);
    });

    test('elements outside the grid are reported', () {
      final model = ConstructionModel();
      model.add(ModelObject(id: 'a', name: 'a', kind: 'cuboid', x: 10));
      final grid = LevelGrid(3, 3, fill: LevelCell.open());
      final issues = validator.checkConstruction(model, grid: grid);
      expect(issues, hasLength(1));
      expect(issues.single.kind, LevelIssueKind.elementOutsideGrid);
    });

    test('overlap checking is opt-in and finds intersecting bounds', () {
      final model = ConstructionModel();
      model.add(ModelObject(
          id: 'a', name: 'a', kind: 'cuboid', dims: {'w': 2, 'h': 1, 'd': 2}));
      model.add(ModelObject(
          id: 'b', name: 'b', kind: 'cuboid', x: 1, dims: {'w': 2, 'h': 1, 'd': 2}));
      expect(
          validator.checkConstruction(model).any(
              (i) => i.kind == LevelIssueKind.elementOverlap),
          isFalse);
      final issues = validator.checkConstruction(model, checkOverlaps: true);
      expect(issues, hasLength(1));
      expect(issues.single.kind, LevelIssueKind.elementOverlap);
    });

    test('a clean construction model has no issues', () {
      final model = ConstructionModel();
      model.add(ModelObject(id: 'a', name: 'a', kind: 'cuboid'));
      model.add(ModelObject(id: 'b', name: 'b', kind: 'cuboid', x: 2));
      expect(validator.checkConstruction(model), isEmpty);
    });
  });

  group('validate (combined)', () {
    test('runs every check the inputs allow', () {
      final grid = LevelGrid.fromRows(const ['##', '#.']);
      grid.setCell(0, 0, LevelCell.solid(regionId: 'missing'));
      final model = ConstructionModel();
      model.add(ModelObject(id: 'a', name: 'a', kind: 'cuboid'));
      final issues = validator.validate(grid: grid, model: model);
      expect(issues.any((i) => i.kind == LevelIssueKind.unknownRegion), isTrue);
      expect(issues.where((i) => i.severity == LevelIssueSeverity.error),
          isEmpty);
    });
  });
}
