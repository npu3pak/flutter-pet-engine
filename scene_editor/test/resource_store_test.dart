import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:scene_editor/src/services/resource_store.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// A tiny PNG (1×1 red pixel).
Uint8List _pngBytes() {
  final image = img.Image(width: 2, height: 2);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodePng(image));
}

/// A wide 400×200 PNG.
Uint8List _widePngBytes() {
  final image = img.Image(width: 400, height: 200);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late Directory dir;
  late ProjectStore project;
  late ResourceStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_res_test');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    final controller = SceneController();
    await controller.createProject(dir, name: 'test');
    project = controller.project;
    store = ResourceStore(project);
    await store.reload();
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  Future<String> importTestFile(String family, [String? name]) async {
    final src = File(p.join(dir.path, '${name ?? 'src_${family}_tmp'}.png'))
      ..writeAsBytesSync(_pngBytes());
    final imported = await store.importFile(src.path, family: family);
    expect(imported, isNotNull);
    return imported!;
  }

  test('import writes PNG into the family folder and indexes it', () async {
    final name = await importTestFile('texture');
    expect(File('${dir.path}/textures/$name.png').existsSync(), isTrue);
    expect(project.resources[name]!.family, 'texture');
    expect(store.items, hasLength(1));
    expect(store.items.single.family, 'texture');
    expect(store.items.single.width, 2);
  });

  test('import with family sprite goes to sprites/ and keeps family', () async {
    final name = await importTestFile('sprite');
    expect(File('${dir.path}/sprites/$name.png').existsSync(), isTrue);
    expect(File('${dir.path}/textures/$name.png').existsSync(), isFalse);
    expect(project.resources[name]!.family, 'sprite');
    expect(store.items.single.family, 'sprite');
    // Both families stay distinct in the store.
    await importTestFile('texture', 'tex');
    final families = store.items.map((i) => i.family).toSet();
    expect(families, {'texture', 'sprite'});
  });

  test('duplicate names get a numeric suffix', () async {
    final a = await importTestFile('texture', 'dup');
    final b = await importTestFile('texture', 'dup');
    expect(a, 'dup');
    expect(b, 'dup_2');
  });

  test('reload groups working file with _original backup', () async {
    await importTestFile('texture', 'g');
    final item = store.items.single;
    store.applyScale(item: item, width: 4, height: 4);
    await store.saveItem(item);
    // After save the original backup exists on disk.
    expect(File('${dir.path}/textures/g_original.png').existsSync(), isTrue);

    await store.reload();
    final reloaded = store.items.singleWhere((i) => i.name == 'g');
    expect(reloaded.hasDiskOriginal, isTrue);
    expect(reloaded.width, 4);
    expect(reloaded.history, hasLength(2));
  });

  test('rename moves the file and the _original backup', () async {
    await importTestFile('texture', 'r');
    final item = store.items.single;
    store.applyScale(item: item, width: 8, height: 8);
    await store.saveItem(item);
    expect(File('${dir.path}/textures/r_original.png').existsSync(), isTrue);

    final err = await store.rename(item, 'renamed');
    expect(err, isNull);
    expect(File('${dir.path}/textures/renamed.png').existsSync(), isTrue);
    expect(File('${dir.path}/textures/r.png').existsSync(), isFalse);
    expect(
      File('${dir.path}/textures/renamed_original.png').existsSync(),
      isTrue,
    );
    expect(File('${dir.path}/textures/r_original.png').existsSync(), isFalse);
    expect(project.resources['renamed'], isNotNull);

    await store.reload();
    final reloaded = store.items.singleWhere((i) => i.name == 'renamed');
    expect(reloaded.hasDiskOriginal, isTrue);
    expect(reloaded.width, 8);
  });

  test('setFamily moves the file between folders', () async {
    await importTestFile('texture', 'f');
    final item = store.items.single;
    await store.setFamily(item, 'sprite');
    expect(item.family, 'sprite');
    expect(File('${dir.path}/sprites/f.png').existsSync(), isTrue);
    expect(File('${dir.path}/textures/f.png').existsSync(), isFalse);
    expect(project.resources['f']!.family, 'sprite');
  });

  test('validateName rejects reserved _original suffix; rename rejects taken names', () async {
    expect(store.validateName('foo_original'), isNotNull);
    expect(store.validateName('a/b'), isNotNull);
    expect(store.validateName('ok_name'), isNull);
    await importTestFile('texture', 'taken');
    final other = await importTestFile('texture', 'mine');
    final err = await store.rename(
      store.items.singleWhere((i) => i.name == other),
      'taken',
    );
    expect(err, 'Ресурс с таким именем уже есть');
    expect(store.items.singleWhere((i) => i.name == other).name, 'mine');
  });

  test('tolerance persists via project index', () async {
    final name = await importTestFile('texture', 'tol');
    await store.applyRemoval(item: store.items.single, tolerance: 55);
    expect(project.resources[name]!.tolerance, 55);

    await store.reload();
    expect(store.items.single.tolerancePercent, 55);
  });

  test('delete removes file + original + index entry', () async {
    final name = await importTestFile('texture', 'del');
    final item = store.items.single;
    store.applyScale(item: item, width: 4, height: 4);
    await store.saveItem(item);
    await store.delete(item);
    expect(File('${dir.path}/textures/del.png').existsSync(), isFalse);
    expect(File('${dir.path}/textures/del_original.png').existsSync(), isFalse);
    expect(project.resources.containsKey(name), isFalse);
    expect(store.items, isEmpty);
  });

  test('rollback restores the original', () async {
    await importTestFile('texture', 'hist');
    final item = store.items.single;
    store.applyScale(item: item, width: 16, height: 16);
    expect(item.width, 16);
    store.rollback(item, 0);
    expect(item.width, 2);
  });

  test(
    'applyScale modes: contain fits, cover fills, stretch distorts',
    () async {
      final src = File(p.join(dir.path, 'wide.png'))
        ..writeAsBytesSync(_widePngBytes());
      await store.importFile(src.path, family: 'texture');
      final item = store.items.single;
      expect((item.width, item.height), (400, 200));

      // contain: 400×200 → fits a 256 box → 256×128, aspect kept.
      store.applyScale(
        item: item,
        width: 256,
        height: 256,
        mode: ResourceScaleMode.contain,
      );
      expect((item.width, item.height), (256, 128));

      // cover: fills the box exactly, cropping the excess.
      store.applyScale(
        item: item,
        width: 100,
        height: 100,
        mode: ResourceScaleMode.cover,
      );
      expect((item.width, item.height), (100, 100));

      // stretch: exact target, aspect distorted.
      store.applyScale(
        item: item,
        width: 100,
        height: 50,
        mode: ResourceScaleMode.stretch,
      );
      expect((item.width, item.height), (100, 50));
    },
  );

  test('exportSelected writes chosen items to the destination', () async {
    final a = await importTestFile('texture', 'ex1');
    final b = await importTestFile('sprite', 'ex2');
    store.selectAll();
    final dest = Directory('${dir.path}/out');
    final msg = await store.exportSelected(dest.path);
    expect(msg, contains('2'));
    expect(File('${dest.path}/$a.png').existsSync(), isTrue);
    expect(File('${dest.path}/$b.png').existsSync(), isTrue);
  });

  test('selectAll/clearSelection filter by family', () async {
    final tex = await importTestFile('texture', 'sel_tex');
    final spr = await importTestFile('sprite', 'sel_spr');
    await importTestFile('texture', 'sel_tex2');

    store.selectAll(family: 'sprite');
    expect(store.items.map((i) => (i.name, i.selectedForExport)).toSet(), {
      ('sel_tex', false),
      ('sel_tex2', false),
      ('sel_spr', true),
    });

    store.selectAll();
    expect(store.selectedCount, 3);

    store.clearSelection(family: 'texture');
    expect(
      store.items.singleWhere((i) => i.name == tex).selectedForExport,
      isFalse,
    );
    expect(
      store.items.singleWhere((i) => i.name == 'sel_tex2').selectedForExport,
      isFalse,
    );
    expect(
      store.items.singleWhere((i) => i.name == spr).selectedForExport,
      isTrue,
    );
  });

  test(
    'deleteSelected removes flagged items, keeps the rest, resets _selected',
    () async {
      final a = await importTestFile('texture', 'del1');
      final b = await importTestFile('sprite', 'del2');
      final keep = await importTestFile('texture', 'keep');
      final delItem = store.items.singleWhere((i) => i.name == a);
      store.applyScale(item: delItem, width: 4, height: 4);
      await store.saveItem(delItem);
      store.select(delItem);
      store.toggleExport(delItem);
      store.toggleExport(store.items.singleWhere((i) => i.name == b));

      final deleted = await store.deleteSelected();
      expect(deleted, 2);
      expect(File('${dir.path}/textures/del1.png').existsSync(), isFalse);
      expect(
        File('${dir.path}/textures/del1_original.png').existsSync(),
        isFalse,
      );
      expect(File('${dir.path}/sprites/del2.png').existsSync(), isFalse);
      expect(project.resources.containsKey(a), isFalse);
      expect(project.resources.containsKey(b), isFalse);
      expect(project.resources.containsKey(keep), isTrue);
      expect(store.items.map((i) => i.name), [keep]);
      expect(store.selected, isNull);
      expect(store.selectedCount, 0);
    },
  );
}
