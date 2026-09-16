import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

import 'package:scene_editor/src/state/app_state.dart';

void main() {
  late Directory dir;
  late SceneController controller;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scene_editor_project_test');
    controller = SceneController();
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('create writes project.json with name/format/created', () async {
    await controller.createProject(dir, name: 'Мой проект');
    final store = controller.project;
    expect(store.name, 'Мой проект');
    expect(store.created, isNotNull);
    expect(File('${dir.path}/project.json').existsSync(), isTrue);
    final m = jsonDecode(
        File('${dir.path}/project.json').readAsStringSync()) as Map;
    expect(m['format'], 'project_v1');
    expect(m['name'], 'Мой проект');
    expect(m['created'], isNotNull);
  });

  test('create uses "project" when name is blank', () async {
    await controller.createProject(dir, name: '   ');
    expect(controller.project.name, 'project');
  });

  test('open on a folder without project.json keeps the folder label',
      () async {
    await controller.open(DirectoryProjectSource(dir));
    expect(controller.status.hasError, isFalse);
    expect(controller.project.name, dir.path);
  });

  test('open survives a malformed project.json', () async {
    File('${dir.path}/project.json').writeAsStringSync('{"format":"nope"}');
    await controller.open(DirectoryProjectSource(dir));
    expect(controller.status.hasError, isFalse);
    expect(controller.project.name, dir.path);
  });

  test('open restores name, lastModelId and resources index', () async {
    await controller.createProject(dir, name: 'P');
    final store = controller.project;
    store.lastModelId = 'model_1';
    store.resources['wall'] =
        ResourceMeta(id: 'wall', family: 'texture', tolerance: 45);
    await store.saveMeta();

    final reopened = SceneController();
    await reopened.open(DirectoryProjectSource(dir));
    expect(reopened.project.name, 'P');
    expect(reopened.project.lastModelId, 'model_1');
    expect(reopened.project.resources['wall']!.family, 'texture');
    expect(reopened.project.resources['wall']!.tolerance, 45);
  });

  test('open picks up textures/sprites/models from disk', () async {
    await controller.createProject(dir, name: 'P');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    Directory('${dir.path}/models').createSync();
    File('${dir.path}/textures/wall.png').writeAsBytesSync([1]);
    File('${dir.path}/sprites/tree.png').writeAsBytesSync([1]);
    File('${dir.path}/models/a.json').writeAsStringSync(
        const JsonEncoder().convert(ModelData(id: 'a', name: 'A').toJson()));

    await controller.open(DirectoryProjectSource(dir));
    expect(controller.resources!.textureKeys, ['wall']);
    expect(controller.resources!.spriteKeys, ['tree']);
    expect(controller.project.modelIds, ['a']);
  });

  test('openProject re-scans textures/sprites from disk', () async {
    await controller.createProject(dir, name: 'P');
    Directory('${dir.path}/textures').createSync();
    await controller.openProject();
    expect(controller.resources!.textureKeys, isEmpty);
    // A file added after the project was opened shows up on the next scan.
    File('${dir.path}/textures/new.png').writeAsBytesSync([1]);
    await controller.openProject();
    expect(controller.resources!.textureKeys, ['new']);
    // Same for sprites.
    Directory('${dir.path}/sprites').createSync();
    await controller.openProject();
    expect(controller.resources!.spriteKeys, isEmpty);
    File('${dir.path}/sprites/fresh.png').writeAsBytesSync([1]);
    await controller.openProject();
    expect(controller.resources!.spriteKeys, ['fresh']);
  });

  test('create migrates chunks/ into models/ as model_v1', () async {
    final biome = Directory('${dir.path}/src');
    Directory('${biome.path}/chunks').createSync(recursive: true);
    File('${biome.path}/chunks/house.json').writeAsStringSync('''
      {
        "format": "chunk_v3",
        "id": "house",
        "name": "Дом",
        "entries": ["south"],
        "front": "south",
        "blocked": ["1,1"],
        "objects": [
          {"id": "o", "name": "o", "kind": "cuboid", "pos": [0, 0, 0], "size": [1, 1, 1]}
        ]
      }''');

    final app = AppState();
    await app.createProject(biome.path, name: 'Migrated');
    expect(File('${biome.path}/models/house.json').existsSync(), isTrue);
    final model = app.project!.models['house']!;
    expect(model.format, 'model_v1');
    expect(model.objects, hasLength(1));
    // The chunk_v3 file itself is untouched.
    expect(File('${biome.path}/chunks/house.json').existsSync(), isTrue);
    app.closeProject();
  });

  test('atomic saveModel leaves no .tmp and dirty=false', () async {
    await controller.createProject(dir, name: 'P');
    final store = controller.project;
    final model = store.createModel(id: 'm1');
    model.dirty = true;
    await store.saveModel(model);
    expect(File('${dir.path}/models/m1.json').existsSync(), isTrue);
    expect(File('${dir.path}/models/m1.json.tmp').existsSync(), isFalse);
    expect(model.dirty, isFalse);
  });

  test('model CRUD: rename moves file, delete removes it', () async {
    await controller.createProject(dir, name: 'P');
    final store = controller.project;
    final model = store.createModel(id: 'a');
    await store.saveModel(model);
    await store.renameModel('a', 'b');
    expect(store.models.containsKey('b'), isTrue);
    expect(File('${dir.path}/models/b.json').existsSync(), isTrue);
    expect(File('${dir.path}/models/a.json').existsSync(), isFalse);
    await store.deleteModel('b');
    expect(store.models.containsKey('b'), isFalse);
    expect(File('${dir.path}/models/b.json').existsSync(), isFalse);
  });
}
