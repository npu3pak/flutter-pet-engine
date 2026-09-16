import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('project_store_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('createProject writes project_v1 and opens the session', () async {
    final controller = SceneController();
    final ok = await controller.createProject(dir, name: 'Мой проект');
    addTearDown(controller.dispose);

    expect(ok, isTrue);
    expect(controller.status.isReady, isTrue);
    expect(controller.project.name, 'Мой проект');
    expect(controller.project.created, isNotNull);
    expect(controller.project.directory?.path, dir.path);

    final json =
        jsonDecode(File('${dir.path}/project.json').readAsStringSync())
            as Map<String, Object?>;
    expect(json['format'], projectFormatV1);
    expect(json['name'], 'Мой проект');
  });

  test('models save and reload through the project store', () async {
    final controller = SceneController();
    await controller.createProject(dir, name: 'P');
    addTearDown(controller.dispose);

    final model = controller.project.createModel(id: 'model_1', name: 'One');
    model.objects.add(
      ModelObject(id: 'obj_1', name: 'box', kind: 'cuboid', x: 1, z: 1),
    );
    await controller.project.saveModel(model);
    expect(File('${dir.path}/models/model_1.json').existsSync(), isTrue);

    final reopened = SceneController();
    addTearDown(reopened.dispose);
    await reopened.open(DirectoryProjectSource(dir));
    expect(reopened.project.modelIds, ['model_1']);
    expect(reopened.resources!.model('model_1')!.objects, hasLength(1));
  });

  test('resource index and last model round-trip through saveMeta', () async {
    final controller = SceneController();
    await controller.createProject(dir, name: 'P');
    addTearDown(controller.dispose);

    controller.project.resources['wallpaper'] = ResourceMeta(
      id: 'wallpaper',
      family: 'texture',
      tolerance: 42,
    );
    await controller.project.saveMeta(lastModelId: 'model_2');
    expect(File('${dir.path}/project.json.tmp').existsSync(), isFalse);

    final reopened = SceneController();
    addTearDown(reopened.dispose);
    await reopened.open(DirectoryProjectSource(dir));
    expect(reopened.project.lastModelId, 'model_2');
    final meta = reopened.project.resources['wallpaper'];
    expect(meta, isNotNull);
    expect(meta!.family, 'texture');
    expect(meta.tolerance, closeTo(42, 1e-9));
    expect(reopened.project.name, 'P');
  });

  test('malformed project.json does not break opening', () async {
    File('${dir.path}/project.json').writeAsStringSync('{not json');
    final controller = SceneController();
    final ok = await controller.createProject(dir, name: 'X');
    addTearDown(controller.dispose);
    expect(ok, isTrue);
    expect(controller.project.resources, isEmpty);
  });
}
