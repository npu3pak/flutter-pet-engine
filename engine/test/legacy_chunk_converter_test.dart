import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart';

const _chunkJson = '''
{
  "format": "chunk_v3",
  "id": "x",
  "name": "Чанк",
  "size": {"w": 3, "l": 3, "h": 3},
  "entries": ["north", "south"],
  "front": "south",
  "blocked": ["1,1", "0,1", "9,9", "-1,0"],
  "objects": [
    {"id": "o", "name": "o", "kind": "cuboid", "pos": [0, 0, 0], "size": [1, 1, 1]},
    {"id": "d", "name": "проход", "kind": "meta_pass", "pos": [1.5, 0, -0.5],
     "size": {"w": 2, "h": 0.2, "d": 0.2}}
  ]
}''';

void main() {
  group('loadModelData (единая точка загрузки)', () {
    test('dispatches legacy formats to the converter', () {
      final model = loadModelData(_chunkJson, id: 'x');
      expect(model.entries, {ModelSide.north, ModelSide.south});
      expect(model.metas.where((m) => m.name == metaNameDoor), hasLength(2));
      expect(model.objects.any((o) => o.kind == legacyMetaPassKind), isFalse);
    });

    test('parses model_v1 directly', () {
      const v1 = '{"format":"model_v1","id":"x","name":"x",'
          '"size":{"w":2,"l":2,"h":3},"objects":[],"entries":["east"]}';
      final model = loadModelData(v1, id: 'x');
      expect(model.entries, {ModelSide.east});
      expect(model.metas, isEmpty);
    });
  });

  group('convertLegacyChunk', () {
    test('blocked cells become unpassable boxes, clipped to the footprint',
        () {
      final model = convertLegacyChunk(_chunkJson, id: 'x');
      final boxes =
          model.metas.where((m) => m.name == metaNameUnpassable).toList();
      // "1,1" and "0,1" survive; "9,9" and "-1,0" are clipped away.
      expect(boxes, hasLength(2));
      expect(boxes.map((m) => (m.x, m.z)).toSet(), {(1.0, 1.0), (0.0, 1.0)});
      expect(boxes.every((m) => m.kind == metaKindBox), isTrue);
    });

    test('meta_pass markers become door boxes on the passage ring cells', () {
      final model = convertLegacyChunk(_chunkJson, id: 'x');
      final doors =
          model.metas.where((m) => m.name == metaNameDoor).toList();
      expect(doors, hasLength(2));
      expect(doors.map((m) => (m.x, m.z)).toSet(), {(1.0, 0.0), (2.0, 0.0)});
      expect(model.objects.any((o) => o.kind == legacyMetaPassKind), isFalse,
          reason: 'маркер не становится геометрией');
      expect(model.objects, hasLength(1));
    });

    test('a door cell never becomes unpassable', () {
      const json = '''
      {
        "format": "chunk_v3", "id": "x", "name": "x",
        "size": {"w": 3, "l": 3, "h": 3},
        "blocked": ["1,0"],
        "objects": [
          {"id": "d", "kind": "meta_pass", "pos": [1, 0, -0.5],
           "size": {"w": 1, "h": 0.2, "d": 0.2}}
        ]
      }''';
      final model = convertLegacyChunk(json, id: 'x');
      expect(model.metas.where((m) => m.name == metaNameDoor), hasLength(1));
      expect(model.metas.where((m) => m.name == metaNameUnpassable), isEmpty);
    });

    test('entries and front become scene fields', () {
      final model = convertLegacyChunk(_chunkJson, id: 'x');
      expect(model.entries, {ModelSide.north, ModelSide.south});
      expect(model.front, ModelSide.south);
      final json = model.toJson();
      expect(json['entries'], ['north', 'south']);
      expect(json['front'], 'south');
    });

    test('east/west door markers map to the correct ring cells', () {
      const json = '''
      {
        "format": "chunk_v3", "id": "x", "name": "x",
        "size": {"w": 3, "l": 3, "h": 3},
        "objects": [
          {"id": "d", "kind": "meta_pass", "pos": [2.5, 0, 1],
           "size": {"w": 0.2, "h": 0.2, "d": 1}}
        ]
      }''';
      final model = convertLegacyChunk(json, id: 'x');
      final doors = model.metas.where((m) => m.name == metaNameDoor).toList();
      expect(doors.map((m) => (m.x, m.z)).toSet(), {(2.0, 1.0)});
    });

    test('malformed blocked keys are ignored', () {
      const json = '''
      {
        "format": "chunk_v2", "id": "x", "name": "x",
        "size": {"w": 2, "l": 2, "h": 3},
        "blocked": ["nope", "1", "1,", ",2", "0,1"]
      }''';
      final model = convertLegacyChunk(json, id: 'x');
      expect(model.metas, hasLength(1));
      expect((model.metas.single.x, model.metas.single.z), (0.0, 1.0));
    });
  });

  group('реальные чанки streets', () {
    File chunk(String id) =>
        File('../projects/Streets/chunks/$id.json');

    test('chunk_2: out-of-footprint blocked cells are clipped', () {
      final text = chunk('chunk_2').readAsStringSync();
      final model = convertLegacyChunk(text, id: 'chunk_2');
      final raw = text;
      expect(raw.contains('"blocked"'), isTrue);
      final boxes =
          model.metas.where((m) => m.name == metaNameUnpassable).toList();
      expect(boxes, hasLength(17),
          reason: '26 записей, 9 за пределами 5×4 — отброшены');
      expect(boxes.every((m) => m.x >= 0 && m.x < 5), isTrue);
      expect(boxes.every((m) => m.z >= 0 && m.z < 4), isTrue);
      expect(model.entries, {ModelSide.south});
      expect(model.front, ModelSide.south);
    });

    test('every streets chunk converts without doors and keeps its fields',
        () {
      final dir = Directory('../projects/Streets/chunks');
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(10));
      for (final f in files) {
        final id = f.uri.pathSegments.last.replaceAll('.json', '');
        final model = convertLegacyChunk(f.readAsStringSync(), id: id);
        expect(model.objects.any((o) => o.kind == legacyMetaPassKind), isFalse);
        expect(model.entries, isNotEmpty, reason: '$id должен иметь входы');
        expect(model.front, isNotNull);
      }
    });

    // Паритет «чанк → закоммиченная сцена» по всем биомным проектам —
    // в biome_projects_test.dart (полное сравнение toJson).
  });
}
