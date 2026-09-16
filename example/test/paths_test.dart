import 'dart:io';

import 'package:example/src/paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каталог приложения ищется вверх по pubspec.yaml с name: example', () {
    final base = Directory('temp/paths_test/example');
    base.createSync(recursive: true);
    File('${base.path}/pubspec.yaml')
        .writeAsStringSync('name: example\nversion: 1.0.0\n');

    final found = AppPaths.findAppDir(Directory('${base.path}/lib/src'));
    expect(found, isNotNull);
    expect(found!.path, base.absolute.path);
  });

  test('pubspec с другим именем пакета пропускается', () {
    final base = Directory('temp/paths_other/lib');
    base.createSync(recursive: true);
    File('temp/paths_other/pubspec.yaml')
        .writeAsStringSync('name: other_package\n');

    final found = AppPaths.findAppDir(base);
    expect(found?.path, isNot(endsWith('paths_other')));
  });

  test('пути файлов проверок, журнала и истории собираются от каталога', () {
    final paths = AppPaths(Directory('temp/paths_test/example'));
    expect(paths.visualTestsFile.path, endsWith('visual_tests.json'));
    expect(paths.perfJournalFile.path, endsWith('docs/perf_journal.md'));
    expect(paths.changelogFile.path, endsWith('CHANGELOG.md'));
    expect(paths.repoRoot.path, endsWith('paths_test'));
  });
}
