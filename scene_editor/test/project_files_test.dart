import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:scene_editor/src/services/project_files.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scene_editor_files_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('scanProjects lists only folders with project.json', () async {
    Directory('${dir.path}/a').createSync();
    Directory('${dir.path}/b').createSync();
    Directory('${dir.path}/c/deep').createSync(recursive: true);
    File('${dir.path}/b/project.json').writeAsStringSync('{}');
    File('${dir.path}/c/deep/project.json').writeAsStringSync('{}');

    final found = await scanProjects(dir.path);
    final names = found.map((f) => p.basename(f)).toList();
    expect(names, ['b']);
  });

  test('scanProjects ignores missing roots', () async {
    expect(await scanProjects('${dir.path}/nope'), isEmpty);
  });

  test('copyDirectory copies files and subfolders recursively', () async {
    Directory('${dir.path}/src/textures').createSync(recursive: true);
    Directory('${dir.path}/src/models').createSync(recursive: true);
    File('${dir.path}/src/project.json').writeAsStringSync('{"format":"project_v1"}');
    File('${dir.path}/src/textures/wall.png').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/src/models/a.json').writeAsStringSync('{}');

    final err = await copyDirectory(
        '${dir.path}/src', '${dir.path}/dst');
    expect(err, isNull);
    expect(File('${dir.path}/dst/project.json').existsSync(), isTrue);
    expect(File('${dir.path}/dst/textures/wall.png').readAsBytesSync(), [1, 2, 3]);
    expect(File('${dir.path}/dst/models/a.json').existsSync(), isTrue);
  });

  test('copyDirectory reports a missing source', () async {
    final err = await copyDirectory('${dir.path}/missing', '${dir.path}/dst');
    expect(err, isNotNull);
    expect(Directory('${dir.path}/dst').existsSync(), isFalse);
  });
}
