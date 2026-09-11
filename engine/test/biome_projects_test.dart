import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';

/// Биомные проекты фазы 4: чанки игры, сконвертированные в сцены `model_v1`.
const _biomeProjects = ['Streets', 'Dungeon', 'Forest', 'AbandonedBuilding'];

List<File> _jsonFiles(Directory dir) => (dir.existsSync() ? dir.listSync() : [])
    .whereType<File>()
    .where((f) => f.path.toLowerCase().endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

String _chunkText(String project, String id) =>
    File('../projects/$project/chunks/$id.json').readAsStringSync();

Map<String, Object?> _chunkJson(String project, String id) =>
    jsonDecode(_chunkText(project, id)) as Map<String, Object?>;

ModelData _model(String project, String id) =>
    loadModelData(File('../projects/$project/models/$id.json').readAsStringSync(),
        id: id);

/// Правила игры для легаси-чанка (`chunkMapCellValue`): современные чанки
/// (с маркерами проходов) игнорируют `blocked`, у легаси кромка проходима
/// только на входных сторонах, внутри — по `blocked`.
bool _gamePassable(
  Map<String, Object?> chunk,
  ModelData model,
  int x,
  int z,
) {
  final size = ModelSize.fromJson(chunk['size']);
  final w = size.w, l = size.l;
  final onBorder = x == 0 || x == w - 1 || z == 0 || z == l - 1;
  final objects = chunk['objects'];
  final hasPassage = objects is List &&
      objects.any((o) => o is Map && o['kind'] == legacyMetaPassKind);
  final doors = legacyPassageCells(objects, size);
  if (hasPassage) {
    if (onBorder && !doors.contains((x, z))) return false;
    return true;
  }
  final entryCells = <(int, int)>{};
  if (model.entries.contains(ModelSide.north)) {
    for (var i = 0; i < w; i++) {
      entryCells.add((i, 0));
    }
  }
  if (model.entries.contains(ModelSide.south)) {
    for (var i = 0; i < w; i++) {
      entryCells.add((i, l - 1));
    }
  }
  if (model.entries.contains(ModelSide.west)) {
    for (var i = 0; i < l; i++) {
      entryCells.add((0, i));
    }
  }
  if (model.entries.contains(ModelSide.east)) {
    for (var i = 0; i < l; i++) {
      entryCells.add((w - 1, i));
    }
  }
  if (onBorder && !entryCells.contains((x, z))) return false;
  if (chunk['blocked'] is List) {
    for (final v in chunk['blocked'] as List) {
      final cell = parseLegacyCell(v);
      if (cell == null || cell != (x, z)) continue;
      if (doors.contains(cell)) return true;
      return false;
    }
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('биомные проекты', () {
    test('каждый проект — project_v1, чанков и моделей поровну, без монстров',
        () {
      for (final name in _biomeProjects) {
        final meta = jsonDecode(
            File('../projects/$name/project.json').readAsStringSync())
            as Map<String, Object?>;
        expect(meta['format'], 'project_v1', reason: name);
        expect(meta['name'], isNotEmpty, reason: name);

        final chunks = _jsonFiles(Directory('../projects/$name/chunks'));
        final models = _jsonFiles(Directory('../projects/$name/models'));
        expect(chunks, isNotEmpty, reason: '$name: исходные чанки на месте');
        expect(models.map((f) => f.path.split('/').last).toList(),
            chunks.map((f) => f.path.split('/').last).toList(),
            reason: '$name: по сцене на чанк');
        expect(Directory('../projects/$name/monsters').existsSync(), isFalse,
            reason: '$name: механика вне проекта (решение 3.18)');

        for (final f in models) {
          final id = f.path.split('/').last.replaceAll('.json', '');
          final model = _model(name, id);
          expect(model.objects.any((o) => o.kind == legacyMetaPassKind), isFalse,
              reason: '$name/$id: маркер не стал геометрией');
        }
      }
    });

    test('сцены проходят структурные проверки без ошибок', () {
      final validator = LevelValidator();
      for (final name in _biomeProjects) {
        for (final f in _jsonFiles(Directory('../projects/$name/models'))) {
          final id = f.path.split('/').last.replaceAll('.json', '');
          final issues = validator.checkConstruction(
            ConstructionModel.wrap(_model(name, id)),
          );
          final errors = issues
              .where((i) => i.severity == LevelIssueSeverity.error)
              .toList();
          expect(errors, isEmpty, reason: '$name/$id: $errors');
        }
      }
    });
  });

  group('паритет конвертации', () {
    test('закоммиченные модели совпадают с перегенерацией из чанков', () {
      for (final name in _biomeProjects) {
        for (final f in _jsonFiles(Directory('../projects/$name/models'))) {
          final id = f.path.split('/').last.replaceAll('.json', '');
          final fromFile = _model(name, id);
          final fromChunk = convertLegacyChunk(_chunkText(name, id), id: id);
          expect(fromFile.toJson(), equals(fromChunk.toJson()),
              reason: '$name/$id');
        }
      }
    });
  });

  group('проходимость', () {
    test('ScenePlacement повторяет правила легаси-чанка по всем клеткам', () {
      for (final name in _biomeProjects) {
        for (final f in _jsonFiles(Directory('../projects/$name/models'))) {
          final id = f.path.split('/').last.replaceAll('.json', '');
          final chunk = _chunkJson(name, id);
          final model = _model(name, id);
          final placement =
              ScenePlacement(scene: model, originRow: 0, originCol: 0);
          final size = ModelSize.fromJson(chunk['size']);
          final objects = chunk['objects'];
          final hasPassage = objects is List &&
              objects.any((o) => o is Map && o['kind'] == legacyMetaPassKind);
          final hasBlocked =
              chunk['blocked'] is List && (chunk['blocked'] as List).isNotEmpty;
          for (var z = 0; z < size.l; z++) {
            for (var x = 0; x < size.w; x++) {
              final actual = placement.isCellPassable(x, z);
              final expected = _gamePassable(chunk, model, x, z);
              if (hasPassage && hasBlocked && !expected) {
                // Решение 3.22 (замечание 5): явный `unpassable` в движке
                // всегда сильнее. Конвертированные сцены дверей и blocked
                // одновременно не имеют — ветка страхует будущие данные.
                expect(actual, isFalse, reason: '$name/$id ($x,$z)');
                continue;
              }
              expect(actual, expected, reason: '$name/$id ($x,$z)');
            }
          }
          for (final (x, z) in placement.doorCells) {
            expect(placement.isCellPassable(x, z), isTrue,
                reason: '$name/$id: дверь ($x,$z) проходима');
          }
        }
      }
    });

    test('открытый потолок выводится из высоких объектов', () {
      for (final name in _biomeProjects) {
        for (final f in _jsonFiles(Directory('../projects/$name/models'))) {
          final id = f.path.split('/').last.replaceAll('.json', '');
          final model = _model(name, id);
          final placement =
              ScenePlacement(scene: model, originRow: 0, originCol: 0);
          final expected = <(int, int)>{};
          for (var z = 0; z < model.size.l; z++) {
            for (var x = 0; x < model.size.w; x++) {
              final tall = model.objects.any((o) {
                final (lo, hi) = objectBounds(o);
                return hi.y > 1.0 &&
                    lo.x < x + 0.5 &&
                    hi.x > x - 0.5 &&
                    lo.z < z + 0.5 &&
                    hi.z > z - 0.5;
              });
              if (tall) expected.add(placement.cellToLevel(x, z));
            }
          }
          expect(placement.openCeilingCells, expected, reason: '$name/$id');
        }
      }
    });
  });

  group('расстановка сцен', () {
    test('сцены всех биомов ставятся в ряд без наложений', () {
      for (final name in _biomeProjects) {
        final models = [
          for (final f in _jsonFiles(Directory('../projects/$name/models')))
            _model(name, f.path.split('/').last.replaceAll('.json', '')),
        ];
        final placements = <ScenePlacement>[];
        var col = 0;
        for (final model in models) {
          final p = ScenePlacement(scene: model, originRow: 0, originCol: col);
          expect(p.footprintRows, model.size.l, reason: '$name/${model.id}');
          expect(p.footprintCols, model.size.w, reason: '$name/${model.id}');
          placements.add(p);
          col += p.footprintCols;
        }
        expect(SceneLayout(placements).overlaps, isEmpty, reason: name);
      }
    });

    test('сцены ставятся в ряд с поворотом на 90° без наложений', () {
      for (final name in _biomeProjects) {
        final models = [
          for (final f in _jsonFiles(Directory('../projects/$name/models')))
            _model(name, f.path.split('/').last.replaceAll('.json', '')),
        ];
        final placements = <ScenePlacement>[];
        var col = 0;
        for (final model in models) {
          final p = ScenePlacement(
              scene: model, originRow: 0, originCol: col, rotY: 90);
          expect(p.footprintRows, model.size.w, reason: '$name/${model.id}');
          expect(p.footprintCols, model.size.l, reason: '$name/${model.id}');
          placements.add(p);
          col += p.footprintCols;
        }
        expect(SceneLayout(placements).overlaps, isEmpty, reason: name);
      }
    });
  });
}
