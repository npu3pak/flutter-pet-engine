import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

ModelMeta box(String name, double x, double z, {double w = 1, double d = 1}) =>
    ModelMeta(
      id: 'box_${name}_${x}_$z',
      kind: metaKindBox,
      name: name,
      x: x,
      z: z,
      dims: {'w': w, 'h': 1, 'd': d},
    );

ModelMeta marker(String name, double x, double z) => ModelMeta(
      id: 'marker_${name}_${x}_$z',
      kind: metaKindMarker,
      name: name,
      x: x,
      z: z,
    );

ModelMeta comment(String text, double x, double z) => ModelMeta(
      id: 'comment_${x}_$z',
      kind: metaKindComment,
      name: 'заметка',
      comment: text,
      x: x,
      z: z,
    );

ModelData scene({
  int w = 5,
  int l = 5,
  List<ModelMeta> metas = const [],
  Set<ModelSide> entries = const {},
}) =>
    ModelData(
      id: 's',
      name: 's',
      size: ModelSize(w: w, l: l, h: 3),
      entries: Set.of(entries),
      metas: List.of(metas),
    );

List<String> ids(Iterable<ModelMeta> metas) =>
    metas.map((m) => m.id).toList()..sort();

void main() {
  group('ScenePlacement.metasAtCell', () {
    test('a 1×1 box belongs to its cell only', () {
      final meta = box(metaNameUnpassable, 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(1, 1), contains(meta));
      expect(p.metasAtCell(0, 1), isEmpty);
      expect(p.metasAtCell(2, 1), isEmpty);
      expect(p.metasAtCell(1, 0), isEmpty);
      expect(p.metasAtCell(1, 2), isEmpty);
    });

    test('a box overlapping a cell edge belongs to both cells', () {
      final meta = box(metaNameUnpassable, 2.5, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(2, 1), contains(meta), reason: 'заезжает краешком');
      expect(p.metasAtCell(3, 1), contains(meta), reason: 'заезжает краешком');
      expect(p.metasAtCell(1, 1), isEmpty);
      expect(p.metasAtCell(4, 1), isEmpty);
    });

    test('a pure edge touch does not count', () {
      final meta = box(metaNameUnpassable, 2, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(2, 1), contains(meta));
      expect(p.metasAtCell(1, 1), isEmpty, reason: 'касание краем не считается');
      expect(p.metasAtCell(3, 1), isEmpty, reason: 'касание краем не считается');
    });

    test('a wide box covers every overlapped cell', () {
      final meta = box(metaNameUnpassable, 2, 2, w: 3, d: 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(1, 2), contains(meta));
      expect(p.metasAtCell(2, 2), contains(meta));
      expect(p.metasAtCell(3, 2), contains(meta));
      expect(p.metasAtCell(0, 2), isEmpty);
      expect(p.metasAtCell(2, 1), isEmpty);
    });

    test('a marker belongs to the cell of its anchor', () {
      final onCenter = marker('spawn', 2, 1);
      final onEdge = marker('spawn', 2.5, 1);
      final p = ScenePlacement(
        scene: scene(metas: [onCenter, onEdge]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(2, 1), contains(onCenter));
      expect(p.metasAtCell(2, 1), isNot(contains(onEdge)));
      expect(p.metasAtCell(3, 1), contains(onEdge),
          reason: 'якорь ровно на границе — половина [c−0.5, c+0.5)');
    });

    test('comments never participate', () {
      final note = comment('тут вход', 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [note]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(1, 1), isEmpty);
      expect(p.metasNamed('заметка'), isEmpty);
      expect(p.queryMetas, isEmpty);
    });

    test('cells outside the footprint are empty', () {
      final meta = box(metaNameUnpassable, 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      expect(p.metasAtCell(-1, 0), isEmpty);
      expect(p.metasAtCell(5, 0), isEmpty);
      expect(p.metasAtCell(0, 5), isEmpty);
    });

    test('per-cell results are cached', () {
      final p = ScenePlacement(
        scene: scene(metas: [box(metaNameUnpassable, 1, 1)]),
        originRow: 0,
        originCol: 0,
      );
      expect(identical(p.metasAtCell(1, 1), p.metasAtCell(1, 1)), isTrue);
    });
  });

  group('ScenePlacement.metasAtLevel', () {
    test('rot 0 maps the scene-local cell to the level cell', () {
      final meta = box(metaNameDoor, 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 5,
        originCol: 7,
      );
      expect(p.metasAtLevel(6, 8), contains(meta));
      expect(p.metasAtLevel(5, 7), isEmpty);
    });

    test('rot 90 rotates the query with the placement', () {
      final meta = box(metaNameDoor, 0, 0);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 5,
        originCol: 7,
        rotY: 90,
      );
      // Local (0, 0) lands on level (originRow, originCol + l − 1).
      expect(p.metasAtLevel(5, 11), contains(meta));
      expect(p.metasAtLevel(5, 7), isEmpty);
    });

    test('cells outside the rotated footprint are empty', () {
      final meta = box(metaNameDoor, 0, 0);
      final p = ScenePlacement(
        scene: scene(w: 5, l: 3, metas: [meta]),
        originRow: 0,
        originCol: 0,
        rotY: 90,
      );
      expect(p.footprintRows, 5);
      expect(p.footprintCols, 3);
      expect(p.metasAtLevel(0, 2), isNotEmpty);
      expect(p.metasAtLevel(0, 3), isEmpty);
      expect(p.metasAtLevel(5, 0), isEmpty);
    });
  });

  group('ScenePlacement.metasAtWorld', () {
    test('a box matches a point inside its rectangle', () {
      final meta = box(metaNameUnpassable, 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 5,
        originCol: 7,
      );
      final (wx, wz) = p.localToLevelWorld(1.2, 0.9);
      expect(p.metasAtWorld(wx, wz), contains(meta));
    });

    test('a box does not match a point outside it but in the same cell', () {
      final meta = box(metaNameUnpassable, 1, 1, w: 0.5, d: 0.5);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      final (wx, wz) = p.localToLevelWorld(1.4, 1.4);
      expect(p.metasAtWorld(wx, wz), isEmpty,
          reason: 'мировые координаты не округляются до клетки');
    });

    test('a marker matches a point in the same cell', () {
      final meta = marker('spawn', 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      final (sameX, sameZ) = p.localToLevelWorld(1.4, 1.4);
      expect(p.metasAtWorld(sameX, sameZ), contains(meta));
      final (otherX, otherZ) = p.localToLevelWorld(1.6, 1.4);
      expect(p.metasAtWorld(otherX, otherZ), isEmpty);
    });

    test('world queries follow the placement rotation', () {
      final meta = box(metaNameUnpassable, 0, 0);
      for (final rot in const [0, 90, 180, 270]) {
        final p = ScenePlacement(
          scene: scene(metas: [meta]),
          originRow: 5,
          originCol: 7,
          rotY: rot,
        );
        final (wx, wz) = p.localToLevelWorld(0.0, 0.0);
        expect(p.metasAtWorld(wx, wz), contains(meta), reason: 'rot=$rot');
      }
    });

    test('points outside the footprint match nothing', () {
      final meta = box(metaNameUnpassable, 1, 1);
      final p = ScenePlacement(
        scene: scene(metas: [meta]),
        originRow: 0,
        originCol: 0,
      );
      final (wx, wz) = p.localToLevelWorld(8.0, 8.0);
      expect(p.metasAtWorld(wx, wz), isEmpty);
    });
  });

  group('ScenePlacement.metasNamed', () {
    test('filters by name across boxes and markers', () {
      final door = box(metaNameDoor, 0, 0);
      final markerDoor = marker(metaNameDoor, 2, 2);
      final blocked = box(metaNameUnpassable, 1, 1);
      final note = comment('текст', 3, 3);
      final p = ScenePlacement(
        scene: scene(metas: [door, markerDoor, blocked, note]),
        originRow: 0,
        originCol: 0,
      );
      expect(ids(p.metasNamed(metaNameDoor)), ids([door, markerDoor]));
      expect(ids(p.metasNamed(metaNameUnpassable)), ids([blocked]));
      expect(p.metasNamed('нет такого'), isEmpty);
    });
  });

  group('SceneLayout meta queries', () {
    test('metasAt merges every covering placement', () {
      final metaA = box(metaNameUnpassable, 2, 1);
      final metaB = marker('spawn', 0, 1);
      final a = ScenePlacement(
        scene: scene(w: 3, l: 3, metas: [metaA]),
        originRow: 0,
        originCol: 0,
      );
      final b = ScenePlacement(
        scene: scene(w: 3, l: 3, metas: [metaB]),
        originRow: 0,
        originCol: 2,
      );
      final layout = SceneLayout([a, b]);
      final at = layout.metasAt(1, 2);
      expect(at, hasLength(2));
      expect(at.map((e) => e.meta.id).toSet(), {metaA.id, metaB.id});
      expect(at.map((e) => e.placement).toSet(), {a, b});
      expect(layout.metasAt(0, 0), isEmpty);
    });

    test('metasAtWorld finds metas across placements', () {
      final metaA = box(metaNameUnpassable, 1, 1);
      final metaB = marker('spawn', 1, 1);
      final a = ScenePlacement(
        scene: scene(w: 3, l: 3, metas: [metaA]),
        originRow: 0,
        originCol: 0,
      );
      final b = ScenePlacement(
        scene: scene(w: 3, l: 3, metas: [metaB]),
        originRow: 0,
        originCol: 2,
      );
      final layout = SceneLayout([a, b]);
      final (wx, wz) = b.localToLevelWorld(1.0, 1.0);
      final at = layout.metasAtWorld(wx, wz);
      expect(at.map((e) => e.meta.id), [metaB.id]);
      expect(at.single.placement, b);
    });

    test('allMetas and metaNames list boxes and markers, not comments', () {
      final metaA = box(metaNameUnpassable, 1, 1);
      final metaB = marker('spawn', 1, 1);
      final note = comment('текст', 2, 2);
      final a = ScenePlacement(
        scene: scene(metas: [metaA, metaB, note]),
        originRow: 0,
        originCol: 0,
      );
      final layout = SceneLayout([a]);
      expect(ids(layout.allMetas.map((e) => e.meta)), ids([metaA, metaB]));
      expect(layout.metaNames, {metaNameUnpassable, 'spawn'});
    });

    test('metasNamed returns pairs with their placement', () {
      final metaA = box(metaNameDoor, 0, 0);
      final metaB = box(metaNameDoor, 0, 0);
      final a = ScenePlacement(
        scene: scene(metas: [metaA]),
        originRow: 0,
        originCol: 0,
      );
      final b = ScenePlacement(
        scene: scene(metas: [metaB]),
        originRow: 0,
        originCol: 5,
      );
      final layout = SceneLayout([a, b]);
      final doors = layout.metasNamed(metaNameDoor);
      expect(doors, hasLength(2));
      expect(doors.map((e) => e.placement).toSet(), {a, b});
    });

    test('an empty layout answers empty everywhere', () {
      final layout = SceneLayout([]);
      expect(layout.metasAt(0, 0), isEmpty);
      expect(layout.metasAtWorld(0, 0), isEmpty);
      expect(layout.allMetas, isEmpty);
      expect(layout.metaNames, isEmpty);
    });
  });

  group('биомные проекты: боксы совпадают с правилом центра', () {
    for (final project in const [
      'Streets',
      'Dungeon',
      'Forest',
      'AbandonedBuilding',
    ]) {
      test(project, () {
        final dir = Directory('../projects/$project/models');
        expect(dir.existsSync(), isTrue, reason: 'нет ${dir.path}');
        final files = dir.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.json'),
            );
        expect(files, isNotEmpty);
        for (final file in files) {
          final id = file.uri.pathSegments.last.replaceAll('.json', '');
          final model = ModelData.fromJson(file.readAsStringSync(), id: id);
          final p = ScenePlacement(scene: model, originRow: 0, originCol: 0);
          for (final meta in model.metas.where((m) => m.isBox)) {
            final hw = meta.dim('w', 1) / 2;
            final hd = meta.dim('d', 1) / 2;
            final byCenter = <(int, int)>{};
            for (var z = 0; z < model.size.l; z++) {
              for (var x = 0; x < model.size.w; x++) {
                final dx = x - meta.x;
                final dz = z - meta.z;
                if (dx > -hw && dx < hw && dz > -hd && dz < hd) {
                  byCenter.add((x, z));
                }
              }
            }
            final byQuery = <(int, int)>{};
            for (var z = 0; z < model.size.l; z++) {
              for (var x = 0; x < model.size.w; x++) {
                if (p.metasAtCell(x, z).contains(meta)) byQuery.add((x, z));
              }
            }
            expect(byQuery, byCenter,
                reason: '$id/${meta.id}: правила клеток разошлись');
          }
        }
      });
    }
  });
}
