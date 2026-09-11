// Импорт биома игры в проект редактора (фаза 4):
//
//   fvm dart run tool/import_biome.dart \
//       ../math_quest/assets/dungeons/dungeon ../projects/Dungeon
//
// Копирует из источника `textures/`, `sprites/` и `chunks/` (папку
// `monsters/` и служебные файлы не переносит — решение 3.18), конвертирует
// каждый чанк в сцену `model_v1` (`models/<id>.json`, таблица 3.14) и пишет
// `project.json` формата `project_v1`. Повторный запуск перезаписывает
// textures/sprites/chunks/models и project.json, остальные файлы проекта не
// трогает. Исходные `chunks/` остаются как источник для конвертера.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pet_engine_v2/models.dart';

const _skipNames = {'monsters', '3d_models'};

// Дублирует projectFormatV1 из services/project_store.dart: тот файл тянет
// flutter/foundation, а CLI запускается обычным `dart run`.
const _projectFormatV1 = 'project_v1';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    stderr.writeln(
      'Использование: import_biome.dart <источник> <проект> [--name Имя]',
    );
    exit(64);
  }
  final source = Directory(positional[0]);
  final target = Directory(positional[1]);
  final nameArg = _arg(args, '--name');
  final name = nameArg ?? _pascalCase(p.basename(source.path));

  if (!source.existsSync()) {
    stderr.writeln('Источник не найден: ${source.path}');
    exit(1);
  }
  final chunksDir = Directory(p.join(source.path, 'chunks'));
  if (!chunksDir.existsSync()) {
    stderr.writeln('В источнике нет каталога chunks/: ${source.path}');
    exit(1);
  }

  final copied = <String, int>{'textures': 0, 'sprites': 0, 'chunks': 0};
  for (final sub in copied.keys) {
    final dir = Directory(p.join(target.path, sub));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    _copyDir(Directory(p.join(source.path, sub)), dir, copied, sub);
  }
  final modelsDir = Directory(p.join(target.path, 'models'))
    ..createSync(recursive: true);
  for (final f in modelsDir.listSync().whereType<File>()) {
    if (f.path.toLowerCase().endsWith('.json')) f.deleteSync();
  }

  final chunkFiles = chunksDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final modelIds = <String>[];
  var objects = 0;
  var metas = 0;
  for (final f in chunkFiles) {
    final id = p.basenameWithoutExtension(f.path);
    final model = convertLegacyChunk(f.readAsStringSync(), id: id);
    File(p.join(modelsDir.path, '$id.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(model.toJson()),
    );
    final entries = model.entries.map((s) => s.name).join(',');
    stdout.writeln(
      '$id: objects=${model.objects.length} metas=${model.metas.length} '
      'entries=[$entries] front=${model.front?.name ?? '-'}',
    );
    modelIds.add(id);
    objects += model.objects.length;
    metas += model.metas.length;
  }

  final projectJson = {
    'format': _projectFormatV1,
    'name': name,
    'created': DateTime.now().toUtc().toIso8601String(),
    'settings': {
      if (modelIds.isNotEmpty) 'lastModelId': modelIds.first,
    },
  };
  File(p.join(target.path, 'project.json')).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(projectJson),
  );

  stdout.writeln('Проект: ${target.path} («$name»)');
  stdout.writeln('  textures: ${copied['textures']}, '
      'sprites: ${copied['sprites']}, chunks: ${copied['chunks']}');
  stdout.writeln('  модели: ${modelIds.length}, '
      'объектов: $objects, разметки: $metas');
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

String _pascalCase(String value) => value
    .split(RegExp('[_\\- ]+'))
    .where((s) => s.isNotEmpty)
    .map((s) => s[0].toUpperCase() + s.substring(1))
    .join();

/// Копирует содержимое каталога, пропуская служебные имена и папки механики.
void _copyDir(
  Directory source,
  Directory target,
  Map<String, int> copied,
  String sub,
) {
  if (!source.existsSync()) return;
  for (final e in source.listSync(recursive: true)) {
    final name = p.basename(e.path);
    if (name.startsWith('.') || name.endsWith('_original')) continue;
    final rel = p.relative(e.path, from: source.path);
    if (rel.split(p.separator).any(_skipNames.contains)) continue;
    if (e is! File) continue;
    final dst = File(p.join(target.path, rel));
    dst.parent.createSync(recursive: true);
    e.copySync(dst.path);
    copied[sub] = (copied[sub] ?? 0) + 1;
  }
}
