import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

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
  List<ModelObject> objects = const [],
}) =>
    ModelData(
      id: 's',
      name: 's',
      size: ModelSize(w: w, l: l, h: 3),
      entries: Set.of(entries),
      front: front,
      metas: List.of(metas),
      objects: List.of(objects),
    );

ModelData streets(String id) => ModelData.fromJson(
      File('../projects/Streets/models/$id.json').readAsStringSync(),
      id: id,
    );

void main() {
  group('footprint and cell mapping', () {
    test('rotation swaps the footprint', () {
      final s = scene(w: 5, l: 4);
      expect(ScenePlacement(scene: s, originRow: 0, originCol: 0).footprintRows,
          4);
      expect(ScenePlacement(scene: s, originRow: 0, originCol: 0).footprintCols,
          5);
      final r90 = ScenePlacement(
          scene: s, originRow: 0, originCol: 0, rotY: 90);
      expect((r90.footprintRows, r90.footprintCols), (5, 4));
      final r270 = ScenePlacement(
          scene: s, originRow: 0, originCol: 0, rotY: 270);
      expect((r270.footprintRows, r270.footprintCols), (5, 4));
    });

    test('rotY is normalized', () {
      final p = ScenePlacement(scene: scene(), originRow: 0, originCol: 0, rotY: 450);
      expect(p.rotY, 90);
      expect(ScenePlacement(scene: scene(), originRow: 0, originCol: 0, rotY: -90).rotY,
          270);
    });

    test('cellToLevel matches the game probes', () {
      final p = ScenePlacement(scene: scene(), originRow: 5, originCol: 7);
      expect(p.cellToLevel(0, 0), (5, 7));
      expect(p.cellToLevel(2, 1), (6, 9));
      final r90 = ScenePlacement(
          scene: scene(), originRow: 5, originCol: 7, rotY: 90);
      expect(r90.cellToLevel(0, 0), (5, 9));
      expect(r90.cellToLevel(2, 0), (7, 9));
      final r180 = ScenePlacement(
          scene: scene(), originRow: 5, originCol: 7, rotY: 180);
      expect(r180.cellToLevel(0, 0), (7, 9));
      final r270 = ScenePlacement(
          scene: scene(), originRow: 5, originCol: 7, rotY: 270);
      expect(r270.cellToLevel(0, 0), (7, 7));
    });

    test('levelToCell inverts cellToLevel for every rotation', () {
      for (final rot in const [0, 90, 180, 270]) {
        final p = ScenePlacement(
            scene: scene(), originRow: 5, originCol: 7, rotY: rot);
        for (var z = 0; z < 3; z++) {
          for (var x = 0; x < 3; x++) {
            final level = p.cellToLevel(x, z);
            expect(p.levelToCell(level.$1, level.$2), (x, z),
                reason: 'rot=$rot ($x,$z)');
          }
        }
      }
    });

    test('all rotations keep geometry on the walkability lattice', () {
      for (final rot in const [0, 90, 180, 270]) {
        final p = ScenePlacement(
            scene: scene(), originRow: 5, originCol: 7, rotY: rot);
        for (var z = 0; z < 3; z++) {
          for (var x = 0; x < 3; x++) {
            final (wx, wz) = p.localToLevelWorld(x.toDouble(), z.toDouble());
            final (r, c) = p.cellToLevel(x, z);
            final world = cellWorld(r, c);
            expect((wx, wz), (world.x, world.z),
                reason: 'rot=$rot cell ($x,$z)');
          }
        }
      }
    });

    test('fractional coordinates are continuous', () {
      final p = ScenePlacement(scene: scene(), originRow: 5, originCol: 7);
      final (wx, wz) = p.localToLevelWorld(1.0, 1.0);
      expect((wx, wz), (-8.0, 6.0));
      final (wx2, wz2) = p.localToLevelWorld(1.5, 1.0);
      expect((wx2, wz2), (-8.5, 6.0));
    });

    test('fractional offsets stay linear along rotated local axes', () {
      for (final rot in const [0, 90, 180, 270]) {
        final p = ScenePlacement(
            scene: scene(), originRow: 5, originCol: 7, rotY: rot);
        for (var z = 0; z < 3; z++) {
          for (var x = 0; x < 3; x++) {
            final base = p.localToLevelWorld(x.toDouble(), z.toDouble());
            if (x + 1 < 3) {
              final next =
                  p.localToLevelWorld((x + 1).toDouble(), z.toDouble());
              final quarter = p.localToLevelWorld(x + 0.25, z.toDouble());
              expect(quarter.$1,
                  closeTo(base.$1 + (next.$1 - base.$1) * 0.25, 1e-9),
                  reason: 'rot=$rot local +x ($x,$z)');
              expect(quarter.$2,
                  closeTo(base.$2 + (next.$2 - base.$2) * 0.25, 1e-9),
                  reason: 'rot=$rot local +x ($x,$z)');
            }
            if (z + 1 < 3) {
              final next =
                  p.localToLevelWorld(x.toDouble(), (z + 1).toDouble());
              final quarter = p.localToLevelWorld(x.toDouble(), z + 0.25);
              expect(quarter.$1,
                  closeTo(base.$1 + (next.$1 - base.$1) * 0.25, 1e-9),
                  reason: 'rot=$rot local +z ($x,$z)');
              expect(quarter.$2,
                  closeTo(base.$2 + (next.$2 - base.$2) * 0.25, 1e-9),
                  reason: 'rot=$rot local +z ($x,$z)');
            }
          }
        }
      }
    });

    test('containsLevelCell uses the rotated footprint', () {
      final p = ScenePlacement(
          scene: scene(w: 5, l: 4), originRow: 10, originCol: 20, rotY: 90);
      expect(p.containsLevelCell(10, 20), isTrue);
      expect(p.containsLevelCell(14, 23), isTrue);
      expect(p.containsLevelCell(15, 20), isFalse);
      expect(p.containsLevelCell(10, 24), isFalse);
    });
  });

  group('meta boxes to cells', () {
    test('legacy border rule: entries open, the rest of the border is wall',
        () {
      final p = ScenePlacement(
        scene: scene(entries: {ModelSide.south}),
        originRow: 0,
        originCol: 0,
      );
      expect(p.isCellPassable(1, 2), isTrue, reason: 'южная кромка — вход');
      expect(p.isCellPassable(0, 2), isTrue);
      expect(p.isCellPassable(2, 2), isTrue);
      expect(p.isCellPassable(1, 0), isFalse, reason: 'север без входа');
      expect(p.isCellPassable(0, 1), isFalse, reason: 'запад без входа');
      expect(p.isCellPassable(2, 1), isFalse, reason: 'восток без входа');
      expect(p.isCellPassable(1, 1), isTrue, reason: 'интерьер свободен');
    });

    test('unpassable boxes block interior cells', () {
      final p = ScenePlacement(
        scene: scene(
          entries: {ModelSide.south},
          metas: [box(metaNameUnpassable, 1, 1)],
        ),
        originRow: 0,
        originCol: 0,
      );
      expect(p.isCellPassable(1, 1), isFalse);
      expect(p.unpassableCells, {(1, 1)});
    });

    test('modern frame rule: only doors stay open on the border', () {
      final p = ScenePlacement(
        scene: scene(metas: [box(metaNameDoor, 1, 0)]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.hasDoors, isTrue);
      expect(p.isCellPassable(1, 0), isTrue, reason: 'дверь');
      expect(p.isCellPassable(0, 1), isFalse, reason: 'кромка без двери');
      expect(p.isCellPassable(1, 1), isTrue, reason: 'интерьер');
    });

    test('a door wins over an unpassable box', () {
      final p = ScenePlacement(
        scene: scene(metas: [
          box(metaNameUnpassable, 1, 0),
          box(metaNameDoor, 1, 0),
        ]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.isCellPassable(1, 0), isTrue);
      expect(p.doorCells, {(1, 0)});
    });

    test('window boxes never map to passability', () {
      final p = ScenePlacement(
        scene: scene(metas: [
          box(metaNameWindow, 1, 0),
          box(metaNameUnpassable, 1, 1),
        ]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.windowCells, {(1, 0)});
      expect(p.isCellPassable(1, 0), isFalse,
          reason: 'окно — только геометрия, кромка без двери');
      expect(p.isCellPassable(1, 1), isFalse);
    });

    test('boxes outside the footprint cover nothing', () {
      final p = ScenePlacement(
        scene: scene(metas: [box(metaNameUnpassable, 7, 7)]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.unpassableCells, isEmpty);
    });
  });

  group('sides and openings', () {
    test('localSideOf rotates with the placement', () {
      final s = scene();
      expect(
          ScenePlacement(scene: s, originRow: 0, originCol: 0)
              .localSideOf(ModelSide.north),
          ModelSide.north);
      expect(
          ScenePlacement(scene: s, originRow: 0, originCol: 0, rotY: 90)
              .localSideOf(ModelSide.north),
          ModelSide.west);
      expect(
          ScenePlacement(scene: s, originRow: 0, originCol: 0, rotY: 180)
              .localSideOf(ModelSide.north),
          ModelSide.south);
      expect(
          ScenePlacement(scene: s, originRow: 0, originCol: 0, rotY: 270)
              .localSideOf(ModelSide.north),
          ModelSide.east);
    });

    test('openBorderCells follows the rotation', () {
      final p = ScenePlacement(
        scene: scene(entries: {ModelSide.west}),
        originRow: 0,
        originCol: 0,
        rotY: 90,
      );
      // Local west border (x=0) maps to the level north border.
      expect(p.openBorderCells(ModelSide.north),
          {(0, 0), (0, 1), (0, 2)});
      expect(p.openBorderCells(ModelSide.south), isEmpty);
    });

    test('openCeilingCells is derived from element heights', () {
      final tall = ModelObject(
        id: 't',
        name: 't',
        kind: 'cuboid',
        x: 1,
        y: 0,
        z: 1,
        dims: {'w': 1, 'h': 3, 'd': 1},
      );
      final low = ModelObject(
        id: 'l',
        name: 'l',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        dims: {'w': 1, 'h': 0.5, 'd': 1},
      );
      final p = ScenePlacement(
        scene: scene(objects: [tall, low]),
        originRow: 2,
        originCol: 3,
      );
      expect(p.openCeilingCells, {(3, 4)});
    });
  });

  group('SceneLayout', () {
    test('detects footprint overlaps', () {
      final a = ScenePlacement(scene: scene(), originRow: 0, originCol: 0);
      final b = ScenePlacement(scene: scene(), originRow: 0, originCol: 2);
      final layout = SceneLayout([a, b]);
      expect(layout.overlaps, hasLength(3));
      expect(layout.overlaps.keys, {(0, 2), (1, 2), (2, 2)});
    });

    test('isPassableAt merges covering placements', () {
      final wall = ScenePlacement(
        scene: scene(entries: {ModelSide.south}),
        originRow: 0,
        originCol: 0,
      );
      final layout = SceneLayout([wall]);
      expect(layout.isPassableAt(1, 1), isTrue);
      expect(layout.isPassableAt(0, 1), isFalse);
      expect(layout.isPassableAt(9, 9), isNull);
    });

    test('dockedWith requires adjacency', () {
      final a = ScenePlacement(scene: scene(), originRow: 0, originCol: 0);
      final b = ScenePlacement(scene: scene(), originRow: 0, originCol: 5);
      expect(SceneLayout([a, b]).dockedWith(a, b), isFalse);
    });

    test('dockedWith checks door alignment on the shared border', () {
      final a = ScenePlacement(
        scene: scene(entries: {ModelSide.south}, metas: [box(metaNameDoor, 1, 2)]),
        originRow: 0,
        originCol: 0,
      );
      // B is below A and its north wall (no door) faces A's south door.
      final b = ScenePlacement(scene: scene(), originRow: 3, originCol: 0);
      expect(SceneLayout([a, b]).dockedWith(a, b), isFalse);
      // B rotated 180° has its door on the level north border → docked.
      final bOk = ScenePlacement(
        scene: scene(entries: {ModelSide.south}, metas: [box(metaNameDoor, 1, 2)]),
        originRow: 3,
        originCol: 0,
        rotY: 180,
      );
      expect(SceneLayout([a, bOk]).dockedWith(a, bOk), isTrue);
    });
  });

  group('ряд домов streets', () {
    test('houses stand in a row with matching passages', () {
      const ids = [
        'chunk_2',
        'chunk_3',
        'chunk_4',
        'chunk_5',
        'chunk_6',
        'chunk_7',
        'chunk_8',
      ];
      final placements = <ScenePlacement>[];
      var col = 0;
      for (final id in ids) {
        final house = streets(id);
        final p = ScenePlacement(scene: house, originRow: 0, originCol: col);
        placements.add(p);
        col += p.footprintCols;
      }
      final layout = SceneLayout(placements);
      expect(layout.overlaps, isEmpty, reason: 'дома стоят вплотную без наложений');

      // У каждого дома есть проход на юг (на улицу), и все они на одной строке.
      for (final p in placements) {
        final openings = p.openBorderCells(ModelSide.south);
        expect(openings, isNotEmpty, reason: 'у ${p.scene.id} есть вход на юг');
        expect(openings.every((cell) => cell.$1 == 3), isTrue,
            reason: 'проходы на одной линии улицы');
      }

      // Соседние дома стыкуются: явных дверей между ними нет, стык проходит.
      for (var i = 0; i < placements.length - 1; i++) {
        expect(layout.dockedWith(placements[i], placements[i + 1]), isTrue,
            reason: 'стыковка ${placements[i].scene.id} и '
                '${placements[i + 1].scene.id}');
        expect(placements[i].doorBorderCells(ModelSide.east), isEmpty);
        expect(placements[i + 1].doorBorderCells(ModelSide.west), isEmpty);
      }
    });

    test('a rotated house faces its entry the other way', () {
      final p = ScenePlacement(
          scene: streets('chunk_2'), originRow: 4, originCol: 0, rotY: 180);
      final north = p.openBorderCells(ModelSide.north);
      expect(north, hasLength(3));
      expect(north.every((cell) => cell.$1 == 4), isTrue);
      expect(p.openBorderCells(ModelSide.south), isEmpty);
    });
  });
}
