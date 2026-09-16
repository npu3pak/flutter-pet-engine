// Staging-скрипт бандла приложения demo: собирает из каталога проекта Pet
// только те файлы, которые реально нужны приложению, в
// demo/assets/pet_project/ (каталог в .gitignore — генерируется
// заново при изменении сцен/ресурсов).
//
// Запуск (из корня репозитория):
//   fvm dart run scripts/stage_app_assets.dart
//   fvm dart run scripts/stage_app_assets.dart --project projects/Pet --out demo/assets/pet_project
//   fvm dart run scripts/stage_app_assets.dart --full --out ../pet_engine_scene_editor/assets/pet_project
//
// Бандл сохраняет структуру проекта: project.json, models/*.json,
// textures/<key>, sprites/<key>, 3d_models/<имя>/… (целиком для glTF-папок).
// В конце пишется manifest.json со списком файлов (для BundleProjectSource).
// С `--full` копируется весь проект целиком (редактору нужны все ресурсы,
// включая бэкапы `_original`).
import 'dart:convert';
import 'dart:io';

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

const _textureExtrasPrefixes = ['wallpaper_', 'floor_'];
const _spriteExtrasPrefixes = ['window_'];
const _skipSuffix = '_original';

void main(List<String> args) {
  final project = _arg(args, '--project', 'projects/Pet');
  final out = _arg(args, '--out', 'demo/assets/pet_project');
  final full = args.contains('--full');
  final root = Directory(project);
  if (!root.existsSync() || !File('$project/project.json').existsSync()) {
    stderr.writeln('Проект не найден: $project');
    exit(1);
  }
  final outDir = Directory(out);
  if (outDir.existsSync()) {
    outDir.deleteSync(recursive: true);
  }
  outDir.createSync(recursive: true);

  final copied = <String>{};
  void copy(String rel) {
    final src = File('$project/$rel');
    if (!src.existsSync()) return;
    // Flutter asset directory entries are not recursive → flatten the
    // layout: slashes become '__' in the staged file name (see
    // BundleProjectSource.assetKeyOf).
    final dst = File('$out/${rel.replaceAll('/', '__')}');
    dst.parent.createSync(recursive: true);
    src.copySync(dst.path);
    copied.add(rel);
  }

  void copyDir(String rel) {
    final dir = Directory('$project/$rel');
    if (!dir.existsSync()) return;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        copy('$rel/${e.path.substring(dir.path.length + 1)}');
      }
    }
  }

  if (full) {
    // Полный бандл: весь проект как есть (редактор).
    for (final e in root.listSync(recursive: true)) {
      if (e is File) {
        copy(e.path.substring(root.path.length + 1));
      }
    }
  } else {
    _stageDemoProject(project, copy, copyDir);
  }

  final manifest = copied.toList()..sort();
  File('$out/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  var bytes = 0;
  for (final rel in copied) {
    bytes += File('$out/${rel.replaceAll('/', '__')}').lengthSync();
  }
  stdout.writeln('Бандл собран: ${outDir.uri}');
  stdout.writeln('  файлов: ${copied.length}');
  stdout.writeln('  размер: ${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ');
  stdout.writeln('  модели: ${copied.where((f) => f.startsWith('models/')).length} · '
      '3d_models: ${copied.where((f) => f.startsWith('3d_models/')).length}');
}

/// Сжатый бандл demo: модели, нужные сценам ресурсы и 3D-модели.
void _stageDemoProject(
  String project,
  void Function(String rel) copy,
  void Function(String rel) copyDir,
) {
  // project.json + модели.
  copy('project.json');
  for (final f in Directory('$project/models')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.json'))) {
    copy('models/${f.uri.pathSegments.last}');
  }

  // Ресурсы: замыкание по всем моделям + семейства-экстры для UI демо.
  final needed = <String>{};
  final modelFiles = Directory('$project/models')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.json'));
  for (final f in modelFiles) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    for (final o in (json['objects'] as List? ?? const [])) {
      void spec(Map<String, Object?>? m) {
        if (m == null) return;
        final key = m['key'];
        if (key is String) needed.add(key);
      }

      final obj = o as Map<String, Object?>;
      spec(obj['material'] as Map<String, Object?>?);
      for (final m in ((obj['faces'] as Map?) ?? const {}).values) {
        spec(m as Map<String, Object?>?);
      }
    }
  }

  bool wantedResource(String name) =>
      !name.contains(_skipSuffix) &&
      (needed.contains(name) ||
          _textureExtrasPrefixes.any((p) => name.startsWith(p)) ||
          _spriteExtrasPrefixes.any((p) => name.startsWith(p)));

  for (final f in Directory('$project/textures')
      .listSync()
      .whereType<File>()
      .where((f) => wantedResource(f.uri.pathSegments.last))) {
    copy('textures/${f.uri.pathSegments.last}');
  }
  for (final f in Directory('$project/sprites')
      .listSync()
      .whereType<File>()
      .where((f) => wantedResource(f.uri.pathSegments.last))) {
    copy('sprites/${f.uri.pathSegments.last}');
  }

  // 3D-модели: целиком те, что используются сценами (gltfName).
  final usedModels = <String>{};
  for (final f in modelFiles) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    for (final o in (json['objects'] as List? ?? const [])) {
      final gltf = (o as Map<String, Object?>)['gltf'];
      if (gltf is String) usedModels.add(gltf);
    }
  }
  final catalogDir = Directory('$project/3d_models');
  if (catalogDir.existsSync()) {
    for (final e in catalogDir.listSync()) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (!usedModels.contains(name)) continue;
      copyDir('3d_models/$name');
    }
  }
}
