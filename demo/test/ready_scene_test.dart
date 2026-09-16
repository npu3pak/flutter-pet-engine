import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/ready_scene.dart';
import 'package:demo/src/features/ready_scenes.dart';
import 'package:demo/src/project_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SceneResources> openPet() async {
    final controller = SceneController();
    await controller.open(sourceForProject('Pet'));
    return controller.resources!;
  }

  test('каталог группы 6.7 содержит готовую сцену', () {
    expect(readySceneFeatures, hasLength(1));
    expect(validateFeatureCatalog(readySceneFeatures), isEmpty);
    expect(readySceneFeatures.first.id, 'ready_scene');
  });

  test('готовая сцена берёт эталонную модель Pet', () async {
    final manager = await openPet();
    final model = buildReadyScene(
      FeatureBuildContext(project: manager, paths: testPaths()),
    );
    expect(model.id, 'model_2');
    expect(
      model.objects.any((o) => o.kind == doc.gltfRefKind),
      isTrue,
      reason: 'в эталонной сцене есть кот (glTF)',
    );
    expect(model.objects, isNotEmpty);
  });

  test('без проекта готовая сцена даёт запасную оболочку', () {
    final model = buildReadyScene(
      FeatureBuildContext(project: null, paths: testPaths()),
    );
    expect(model.id, 'level_shell');
  });

  test('пол эталонной сцены находится адресно', () async {
    final manager = await openPet();
    final model = buildReadyScene(
      FeatureBuildContext(project: manager, paths: testPaths()),
    );
    final floor = model.objectById('obj_11');
    expect(floor, isNotNull, reason: 'пол — объект obj_11');
    expect(floor!.name, 'Пол');
    // Материал пола называется furniture_texture_3, поэтому смена текстуры
    // по префиксу floor_ его не находила.
    expect(floor.material?.key ?? '', isNot(startsWith('floor_')));
  });

  testWidgets('управление готовой сцены открывается без проекта', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, readySceneFeature);
    expect(find.text('Виды камеры'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('готовая сцена открывается в каркасе', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: readySceneFeatures, host: host);
    await tester.tap(find.byKey(const Key('feature-ready_scene')));
    await tester.pumpAndSettle();
    expect(host.error, isNull);
    expect(host.ready, isTrue);
  });
}
