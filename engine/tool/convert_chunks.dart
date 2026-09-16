// Конвертер легаси-чанков проекта в сцены `model_v1` (фаза 3.2/4):
//
//   fvm dart run tool/convert_chunks.dart projects/Streets
//
// Читает <project>/chunks/*.json, пишет <project>/models/<id>.json по
// таблице миграции 3.14: blocked → боксы unpassable, meta_pass → боксы door,
// entries/front → поля сцены. Исходные chunks/ остаются как источник.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pet_engine/models.dart';

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : 'projects/Streets';
  final chunksDir = Directory(p.join(root, 'chunks'));
  if (!chunksDir.existsSync()) {
    stderr.writeln('Каталог chunks не найден: ${chunksDir.path}');
    exit(1);
  }
  final modelsDir = Directory(p.join(root, 'models'))
    ..createSync(recursive: true);
  var converted = 0;
  for (final f in chunksDir.listSync().whereType<File>()) {
    if (!f.path.toLowerCase().endsWith('.json')) continue;
    final id = p.basenameWithoutExtension(f.path);
    try {
      final model = convertLegacyChunk(f.readAsStringSync(), id: id);
      final out = File(p.join(modelsDir.path, '$id.json'));
      out.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(model.toJson()),
      );
      final entries = model.entries.map((s) => s.name).join(',');
      stdout.writeln(
        '$id: objects=${model.objects.length} metas=${model.metas.length} '
        'entries=[$entries] front=${model.front?.name ?? '-'}',
      );
      converted++;
    } catch (e) {
      stderr.writeln('$id: ошибка конвертации: $e');
    }
  }
  stdout.writeln('Готово: $converted → ${modelsDir.path}');
}
