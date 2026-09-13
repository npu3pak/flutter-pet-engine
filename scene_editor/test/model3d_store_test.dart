import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:scene_editor/src/services/model3d_store.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// Builds a Sketchfab-style glTF source folder: `scene.gltf` + siblings
/// (bin, textures/, license) referenced by relative paths.
Directory _makeGltfFolder(String root, String name) {
  final folder = Directory(p.join(root, name))..createSync(recursive: true);
  Directory(p.join(folder.path, 'textures')).createSync();
  File(p.join(folder.path, 'scene.gltf')).writeAsBytesSync([1, 2, 3]);
  File(p.join(folder.path, 'scene.bin')).writeAsBytesSync(List.filled(1000, 7));
  File(p.join(folder.path, 'textures', 'mat.png')).writeAsBytesSync([4, 5]);
  File(p.join(folder.path, 'license.txt')).writeAsStringSync('CC-BY');
  return folder;
}

void main() {
  late Directory dir; // project root
  late Directory src; // import sources (outside the project)
  late ProjectStore project;
  late Model3dStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_model3d_test');
    Directory(p.join(dir.path, 'textures')).createSync();
    Directory(p.join(dir.path, 'sprites')).createSync();
    final controller = SceneController();
    await controller.createProject(dir, name: 'test');
    project = controller.project;
    store = Model3dStore(project);
    await store.reload();
    src = Directory.systemTemp.createTempSync('scene_editor_model3d_src');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    src.deleteSync(recursive: true);
  });

  test('empty project has no catalog until import', () async {
    expect(store.items, isEmpty);
    expect(store.scanned, isTrue);
    expect(Directory(p.join(dir.path, '3d_models')).existsSync(), isFalse);
  });

  test(
    'importing a .gltf file copies its whole folder into 3d_models/',
    () async {
      final model = _makeGltfFolder(src.path, 'cat_src');
      final result = await store.importFile(p.join(model.path, 'scene.gltf'));
      expect(result.error, isNull);
      expect(result.name, 'cat_src');

      final catalog = p.join(dir.path, '3d_models', 'cat_src');
      expect(File(p.join(catalog, 'scene.gltf')).existsSync(), isTrue);
      expect(File(p.join(catalog, 'scene.bin')).existsSync(), isTrue);
      expect(File(p.join(catalog, 'textures', 'mat.png')).existsSync(), isTrue);
      expect(File(p.join(catalog, 'license.txt')).existsSync(), isTrue);

      expect(store.items, hasLength(1));
      final entry = store.items.single;
      expect(entry.name, 'cat_src');
      expect(entry.isFolder, isTrue);
      expect(entry.kindLabel, 'glTF');
      expect(entry.sourcePath, p.join(catalog, 'scene.gltf'));
      // bin (1000) + gltf (3) + texture (2) + license (5).
      expect(entry.sizeBytes, 1010);
      // Imports never touch the project.json index.
      expect(project.resources, isEmpty);
    },
  );

  test('importing a .glb file copies a single file', () async {
    final glb = File(p.join(src.path, 'rig.glb'))
      ..writeAsBytesSync(List.filled(500, 3));
    final result = await store.importFile(glb.path);
    expect(result.error, isNull);
    expect(result.name, 'rig');
    expect(File(p.join(dir.path, '3d_models', 'rig.glb')).lengthSync(), 500);
    final entry = store.items.single;
    expect(entry.isFolder, isFalse);
    expect(entry.kindLabel, 'GLB');
  });

  test('importing a folder picks up the .gltf inside', () async {
    final model = _makeGltfFolder(src.path, 'puppy_src');
    final result = await store.importDirectory(model.path);
    expect(result.error, isNull);
    expect(result.name, 'puppy_src');
    expect(
      File(p.join(dir.path, '3d_models', 'puppy_src', 'scene.gltf'))
          .existsSync(),
      isTrue,
    );
  });

  test('import rejects folders without .gltf and unknown extensions', () async {
    final empty = Directory(p.join(src.path, 'nope'))..createSync();
    final dirResult = await store.importDirectory(empty.path);
    expect(dirResult.error, isNotNull);
    expect(dirResult.name, isNull);

    final txt = File(p.join(src.path, 'readme.txt'))..writeAsStringSync('hi');
    final fileResult = await store.importFile(txt.path);
    expect(fileResult.error, isNotNull);
    expect(store.items, isEmpty);
  });

  test('duplicate import names get a numeric suffix', () async {
    final a = _makeGltfFolder(src.path, 'dup');
    final b = _makeGltfFolder(src.path, 'dup2');
    final r1 = await store.importDirectory(a.path);
    final r2 = await store.importDirectory(b.path);
    // Same target name 'dup' via a second import of the already-imported
    // folder named 'dup'.
    final imported = Directory(p.join(dir.path, '3d_models', 'dup'));
    final r3 = await store.importDirectory(imported.path);
    expect(r1.name, 'dup');
    expect(r2.name, 'dup2');
    expect(r3.name, 'dup_2');
    expect(
      store.items.map((e) => e.name),
      containsAll(['dup', 'dup2', 'dup_2']),
    );
  });

  test('scan sorts entries by name and skips unrelated content', () async {
    _makeGltfFolder(src.path, 'b_model');
    _makeGltfFolder(src.path, 'a_model');
    Directory(p.join(src.path, 'no_gltf')).createSync();
    final tmpNoise = File(p.join(src.path, 'noise.txt'))
      ..writeAsStringSync('x');
    await store.importDirectory(p.join(src.path, 'b_model'));
    await store.importDirectory(p.join(src.path, 'a_model'));
    expect(store.items.map((e) => e.name).toList(), ['a_model', 'b_model']);
    tmpNoise.deleteSync();
  });

  test('rename moves the folder and updates the catalog', () async {
    final model = _makeGltfFolder(src.path, 'old_name');
    await store.importDirectory(model.path);
    final err = store.rename('old_name', 'new_name');
    expect(err, isNull);
    await store.reload();
    expect(
      Directory(p.join(dir.path, '3d_models', 'new_name')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(dir.path, '3d_models', 'old_name')).existsSync(),
      isFalse,
    );
    expect(store.items.single.name, 'new_name');
  });

  test('rename validates names and rejects taken ones', () async {
    final model = _makeGltfFolder(src.path, 'one');
    final model2 = _makeGltfFolder(src.path, 'two');
    await store.importDirectory(model.path);
    await store.importDirectory(model2.path);

    expect(store.validateName(''), isNotNull);
    expect(store.validateName('bad/name'), isNotNull);
    expect(store.validateName('x_original'), isNotNull);
    expect(store.rename('one', 'two'), isNotNull); // taken
    expect(store.rename('one', 'one'), isNull); // no-op rename
    expect(store.rename('ghost', 'three'), isNotNull);
  });

  test('delete removes the whole model folder recursively', () async {
    final model = _makeGltfFolder(src.path, 'victim');
    await store.importDirectory(model.path);
    expect(store.items, hasLength(1));

    final err = store.delete('victim');
    expect(err, isNull);
    await store.reload();
    expect(store.items, isEmpty);
    expect(
      Directory(p.join(dir.path, '3d_models', 'victim')).existsSync(),
      isFalse,
    );
    expect(store.delete('victim'), isNotNull); // already gone
  });

  test('glb rename renames the single file', () async {
    final glb = File(p.join(src.path, 'old.glb'))
      ..writeAsBytesSync(List.filled(10, 1));
    await store.importFile(glb.path);
    final err = store.rename('old', 'rig');
    expect(err, isNull);
    await store.reload();
    expect(File(p.join(dir.path, '3d_models', 'rig.glb')).existsSync(), isTrue);
    expect(store.items.single.isFolder, isFalse);
  });
}
