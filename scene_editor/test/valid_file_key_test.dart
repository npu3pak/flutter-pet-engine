import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/right_panel.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_vfk');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    File('${dir.path}/textures/wall.png').writeAsBytesSync([1]);
    File('${dir.path}/sprites/tree.png').writeAsBytesSync([1]);
    app = AppState();
    await app.createProject(dir.path, name: 'test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('valid keys pass for their own type', () {
    expect(validFileKey(MaterialType.texture, 'wall.png', app), 'wall.png');
    expect(validFileKey(MaterialType.sprite, 'tree.png', app), 'tree.png');
  });

  test('wrong-type and missing keys return null', () {
    expect(validFileKey(MaterialType.sprite, 'wall.png', app), isNull);
    expect(validFileKey(MaterialType.texture, 'tree.png', app), isNull);
    expect(validFileKey(MaterialType.texture, 'nope.png', app), isNull);
    expect(validFileKey(MaterialType.color, 'wall.png', app), isNull);
    expect(validFileKey(MaterialType.texture, '', app), isNull);
  });

  test('empty store returns null', () {
    expect(validFileKey(MaterialType.texture, 'wall.png', null), isNull);
  });
}
