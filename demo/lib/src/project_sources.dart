import 'dart:io';
import 'dart:typed_data';

import 'package:pet_engine_v2/pet_engine_v2.dart';

/// Возвращает источник ресурсов для фичи.
///
/// [name] — имя проекта из каталога фич: `'Pet'`, `'Streets'`, `'Dungeon'`,
/// `'Forest'`, `'AbandonedBuilding'`; `null` — сцена, собранная кодом
/// (ресурсы не нужны).
///
/// Правила выбора:
/// - `--dart-define=pet.source=bundle` — бандл `assets/pet_project/`
///   (мобильные сборки; проект Pet);
/// - `--dart-define=pet.project=<путь>` — произвольная папка;
/// - по умолчанию (macOS, запуск из `demo`) — папки `../projects/<Имя>`;
///   если папки нет (мобильная сборка) — пустой источник, фича покажет
///   запасную сцену из кода.
ProjectSource sourceForProject(String? name) {
  const mode = String.fromEnvironment('pet.source');
  const customPath = String.fromEnvironment('pet.project');
  if (name == 'Pet' && mode == 'bundle') {
    return BundleProjectSource('assets/pet_project/');
  }
  if (customPath.isNotEmpty) {
    return DirectoryProjectSource(Directory(customPath));
  }
  if (name == 'Pet') {
    final repoProject = Directory('../projects/Pet');
    if (repoProject.existsSync()) {
      return DirectoryProjectSource(repoProject);
    }
    return BundleProjectSource('assets/pet_project/');
  }
  if (name != null) {
    final repoProject = Directory('../projects/$name');
    if (repoProject.existsSync()) {
      return DirectoryProjectSource(repoProject);
    }
  }
  return EmptyProjectSource();
}

/// Пустой источник: проект не нужен — сцена собрана кодом из примитивов и
/// цветовых материалов.
class EmptyProjectSource extends ProjectSource {
  @override
  String get label => 'сцена из кода';

  @override
  bool get writable => false;

  @override
  Future<Uint8List?> readBytes(String relPath) async => null;

  @override
  Future<List<String>> listFiles(String relDir) async => const [];

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) =>
      throw UnsupportedError('EmptyProjectSource is read-only');
}
