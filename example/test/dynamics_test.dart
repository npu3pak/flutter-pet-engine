import 'package:example/src/features/camera_modes.dart';
import 'package:example/src/features/dynamics.dart';
import 'package:example/src/features/dynamics_objects.dart';
import 'package:example/src/features/feature_registry.dart';
import 'package:example/src/features/picking_hit.dart';
import 'package:example/src/features/screen_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeatureBuildContext buildContext({Map<String, Object?> params = const {}}) =>
      FeatureBuildContext(project: null, paths: testPaths(), params: params);

  test('каталог группы 6.4 содержит пять фич и проходит проверку', () {
    expect(dynamicsFeatures, hasLength(5));
    expect(validateFeatureCatalog(dynamicsFeatures), isEmpty);
    expect(
      dynamicsFeatures.map((f) => f.id),
      containsAll(const [
        'dynamic_objects',
        'camera_modes',
        'picking_hit',
        'screen_projection',
        'gizmos',
      ]),
    );
  });

  test('сцена динамики содержит площадку и ориентиры', () {
    final model = buildDynamicScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objects.where((o) => o.id.startsWith('post_')), hasLength(4));
  });

  test('сцена камер содержит стены и ящик', () {
    final model = buildCameraScene(buildContext());
    expect(model.objectById('wall_n'), isNotNull);
    expect(model.objectById('divider'), isNotNull);
    expect(model.objectById('crate'), isNotNull);
  });

  test('сцена выбора содержит площадку, цели добавляет управление', () {
    final model = buildPickingScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objects, hasLength(1));
  });

  test('сцена проецирования содержит четыре разных объекта', () {
    final model = buildProjectionScene(buildContext());
    expect(model.objectById('cube'), isNotNull);
    expect(model.objectById('tall_box'), isNotNull);
    expect(model.objectById('cylinder'), isNotNull);
    expect(model.objectById('cone'), isNotNull);
  });

  testWidgets('управление камерой переключает режим по клеткам', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, cameraModesFeature);
    expect(host.cellNavigation, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(host.cellNavigation, isFalse);
  });

  testWidgets('фича выбора регистрирует обработчик нажатия', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, pickingHitFeature);
    expect(host.onTap, isNotNull);

    host.onTap!(Offset.zero, const Size(100, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('фича проецирования регистрирует слой меток', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, screenProjectionFeature);
    expect(host.overlayBuilder, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление динамикой показывает счётчики', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, dynamicObjectsFeature);
    expect(find.textContaining('живых:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in dynamicsFeatures) {
      await tester.pumpWidget(const SizedBox());
      final host = FakeSceneHost(paths: testPaths());
      await pumpShell(tester, features: [spec], host: host);
      await tester.tap(find.byKey(Key('feature-${spec.id}')));
      await tester.pumpAndSettle();
      expect(host.error, isNull, reason: spec.id);
      expect(host.ready, isTrue, reason: spec.id);
    }
  });
}
