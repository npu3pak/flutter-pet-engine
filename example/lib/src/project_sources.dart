import 'dart:io';
import 'dart:typed_data';

import 'package:pet_engine/pet_engine.dart';

/// Возвращает источник ресурсов для фичи.
///
/// [name] — имя проекта из каталога фич: `'Pet'`, `'House'`; `null` — сцена,
/// собранная кодом (ресурсы не нужны).
///
/// Исходники проектов лежат в `example/assets/<Имя>/` и читаются из ассетов
/// (`AssetProjectSource`) — одинаково в запущенном приложении, на мобильной
/// сборке и в тестах.
///
/// `--dart-define=pet.project=<путь>` подменяет источник на произвольную
/// папку (отладка отредактированного проекта).
ProjectSource sourceForProject(String? name) {
  const customPath = String.fromEnvironment('pet.project');
  if (customPath.isNotEmpty) {
    return DirectoryProjectSource(Directory(customPath));
  }
  if (name == 'Pet') return AssetProjectSource('assets/Pet/');
  if (name == 'House') return AssetProjectSource('assets/House/');
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
