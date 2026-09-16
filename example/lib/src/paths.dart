import 'dart:io';

import 'package:path/path.dart' as p;

/// Каталоги приложения example: где лежат файл проверок, журнал замеров и
/// история изменений движка.
///
/// Приложение запускают по-разному: `fvm flutter run` из `example` (рабочий
/// каталог — каталог приложения), из IDE с тем же `cwd` или как собранный
/// `example.app` (рабочий каталог произвольный). Поэтому каталог приложения
/// ищется обходом вверх от текущего каталога и от исполняемого файла до
/// `pubspec.yaml` с `name: example`.
class AppPaths {
  AppPaths(this.appDir);

  /// Каталог приложения (`example`).
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
  /// `pubspec.yaml`, в котором `name: example` (не дальше 12 уровней).
  static Directory? findAppDir(Directory start) {
    var dir = start.absolute;
    for (var depth = 0; depth < 12; depth++) {
      final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync() && _isExamplePubspec(pubspec)) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static bool _isExamplePubspec(File pubspec) {
    try {
      return RegExp(
        r'^name:\s*example\s*$',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync());
    } on FileSystemException {
      return false;
    }
  }

  /// Корень репозитория (`pet_engine`): `example` → корень.
  Directory get repoRoot => appDir.parent;

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

  /// История изменений движка (`CHANGELOG.md` в корне репозитория).
  File get changelogFile => File(p.join(repoRoot.path, 'CHANGELOG.md'));

  /// Каталог для временных файлов приложения (`example/temp/`).
  Directory get tempDir => Directory(p.join(appDir.path, 'temp'));

  /// Каталог снимков экрана для визуальной проверки: `temp/screenshots`
  /// на настольных платформах, `Documents/screenshots` на iOS.
  Directory get screenshotsDir =>
      Directory(p.join(storageDir.path, 'screenshots'));

  /// Журнал команд диплинков (`temp/deeplink.log` или `Documents/deeplink.log`).
  File get deeplinkLogFile => File(p.join(storageDir.path, 'deeplink.log'));
}
