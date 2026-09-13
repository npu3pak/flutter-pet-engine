import 'dart:io';

import 'package:path/path.dart' as p;

/// Каталоги приложения demo: где лежат файл проверок, журнал замеров и
/// история изменений движка.
///
/// Приложение запускают по-разному: `fvm flutter run` из `demo` (рабочий
/// каталог — каталог приложения), из IDE с тем же `cwd` или как собранный
/// `demo.app` (рабочий каталог произвольный). Поэтому каталог приложения
/// ищется обходом вверх от текущего каталога и от исполняемого файла до
/// `pubspec.yaml` с `name: demo`.
class AppPaths {
  AppPaths(this.appDir);

  /// Каталог приложения (`demo`).
  final Directory appDir;

  /// Ищет каталог приложения от текущего каталога и от исполняемого файла;
  /// при неудаче возвращает текущий каталог (запись файлов может не работать,
  /// приложение сообщит об этом).
  static AppPaths resolve() {
    final starts = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final start in starts) {
      final dir = findAppDir(start);
      if (dir != null) return AppPaths(dir);
    }
    return AppPaths(Directory.current);
  }

  /// Поднимается от [start] вверх и возвращает первый каталог с
  /// `pubspec.yaml`, в котором `name: demo` (не дальше 12 уровней).
  static Directory? findAppDir(Directory start) {
    var dir = start.absolute;
    for (var depth = 0; depth < 12; depth++) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync() && _isDemoPubspec(pubspec)) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static bool _isDemoPubspec(File pubspec) {
    try {
      return RegExp(
        r'^name:\s*demo\s*$',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync());
    } on FileSystemException {
      return false;
    }
  }

  /// Корень репозитория (`pet_engine_v2`): `demo` → корень.
  Directory get repoRoot => appDir.parent;

  /// Каталог пакета движка (`engine/`).
  Directory get engineDir => Directory(p.join(repoRoot.path, 'engine'));

  /// Каталог для изменяемых файлов приложения: общий `pet_games/temp`
  /// рабочей области (журналы и снимки не смешиваются с исходниками).
  ///
  /// На iOS запись в каталог репозитория невозможна: файлы живут в
  /// `Documents` песочницы приложения, откуда их забирает `devicectl`.
  Directory get storageDir {
    if (Platform.isIOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, 'Documents'));
      }
      return Directory.systemTemp;
    }
    return Directory(p.join(repoRoot.parent.path, 'temp'));
  }

  /// Файл проверок и журнала замечаний.
  File get visualTestsFile => Platform.isIOS
      ? File(p.join(storageDir.path, 'visual_tests.json'))
      : File(p.join(appDir.path, 'visual_tests.json'));

  /// Журнал замеров производительности (`docs/perf_journal.md`).
  File get perfJournalFile => Platform.isIOS
      ? File(p.join(storageDir.path, 'perf_journal.md'))
      : File(p.join(repoRoot.path, 'docs', 'perf_journal.md'));

  /// История изменений движка (`engine/CHANGELOG.md`).
  File get changelogFile => File(p.join(engineDir.path, 'CHANGELOG.md'));

  /// Каталог для временных файлов приложения (`demo/temp/`).
  Directory get tempDir => Directory(p.join(appDir.path, 'temp'));

  /// Каталог снимков экрана для визуальной проверки: `temp/screenshots`
  /// на настольных платформах, `Documents/screenshots` на iOS.
  Directory get screenshotsDir =>
      Directory(p.join(storageDir.path, 'screenshots'));

  /// Журнал команд диплинков (`temp/deeplink.log` или `Documents/deeplink.log`).
  File get deeplinkLogFile => File(p.join(storageDir.path, 'deeplink.log'));
}
