import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/fog_distance.dart';
import 'package:demo/src/features/light_picture.dart';
import 'package:demo/src/features/lights_sources.dart';
import 'package:demo/src/features/picture_quality.dart';
import 'package:demo/src/features/shadow_cascades.dart';
import 'package:demo/src/features/skybox_static.dart';
import 'package:demo/src/features/ssao_ambient.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeatureBuildContext buildContext({Map<String, Object?> params = const {}}) =>
      FeatureBuildContext(project: null, paths: testPaths(), params: params);

  test('каталог группы 6.2 содержит шесть фич и проходит проверку', () {
    expect(lightPictureFeatures, hasLength(6));
    expect(validateFeatureCatalog(lightPictureFeatures), isEmpty);
    expect(
      lightPictureFeatures.map((f) => f.id),
      containsAll(const [
        'light_sources',
        'shadow_cascades',
        'fog_distance',
        'picture_quality',
        'ssao_ambient',
      ]),
    );
  });

  test('источники света отражают цвет, яркость, дальность и направление', () {
    final model = buildLightSourcesScene(
      buildContext(
        params: const {
          'color': 'warm',
          'intensity': 5.0,
          'range': 12.0,
          'direction': 'front',
        },
      ),
    );
    final lights = model.lighting.lights;
    expect(lights, hasLength(2));
    final sun = model.lighting.lightById('sun')!;
    expect(sun.kind, doc.lightKindDirectional);
    expect(sun.intensity, 5.0);
    expect(sun.r, closeTo(1.0, 1e-9));
    expect(sun.dirY, closeTo(-0.55, 1e-9));
    final lamp = model.lighting.lightById('lamp')!;
    expect(lamp.kind, doc.lightKindPoint);
    expect(lamp.range, 12.0);
    expect(model.lighting.shadows, isTrue);
    expect(model.lighting.ambient, lessThan(1));
  });

  test('сцена теней содержит направленный источник и ящики', () {
    final model = buildShadowScene(buildContext());
    expect(model.lighting.shadows, isTrue);
    expect(model.lighting.lights.first.kind, doc.lightKindDirectional);
    expect(model.objectById('near_box'), isNotNull);
    expect(model.objectById('middle_box'), isNotNull);
    expect(model.objectById('far_box'), isNotNull);
  });

  test('сцена тумана содержит метки на разных расстояниях', () {
    final model = buildFogScene(buildContext());
    expect(model.objectById('marker_0'), isNotNull);
    expect(model.objectById('marker_4'), isNotNull);
    expect(model.objectById('far_wall'), isNotNull);
    expect(model.size.l, 48);
  });

  test('сравнительная сцена картинки содержит тонкие столбики', () {
    final model = buildPictureScene(buildContext());
    expect(model.objects.where((o) => o.id.startsWith('pole_')), hasLength(10));
    expect(
      model.objects.where((o) => o.id.startsWith('slanted_')),
      hasLength(6),
    );
  });

  test('сцена SSAO содержит углы и ступени', () {
    final model = buildSsaoScene(buildContext());
    expect(model.objectById('back_wall'), isNotNull);
    expect(model.objectById('side_wall'), isNotNull);
    expect(model.objectById('corner_box'), isNotNull);
    expect(model.objects.where((o) => o.id.startsWith('step_')), hasLength(3));
  });

  test('сцена скайбокса содержит землю и ориентиры', () {
    final model = buildSkyboxScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objectById('near'), isNotNull);
    expect(model.objectById('far'), isNotNull);
    expect(model.objectById('wall'), isNotNull);
  });

  testWidgets('фича скайбокса сообщает об отсутствии картинки в заглушке', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, skyboxStaticFeature);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('не найдена'),
      findsOneWidget,
      reason: 'в тестовой заглушке проект не открыт',
    );
  });

  testWidgets('управление тенями меняет настройки сцены', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, shadowCascadesFeature);
    expect(host.settings!.shadows, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(host.settings!.shadows, isFalse);

    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(host.settings!.shadowCascades, 4);
  });

  testWidgets('управление туманом включает туман', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, fogDistanceFeature);
    expect(host.settings!.fogEnabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(host.settings!.fogEnabled, isTrue);
    expect(host.settings!.fogOpacity, greaterThan(0));
  });

  testWidgets('управление картинкой меняет сглаживание', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, pictureQualityFeature);

    await tester.tap(find.text('MSAA'));
    await tester.pumpAndSettle();
    expect(host.settings!.antiAliasing, SceneAntiAliasing.msaa);

    await tester.tap(find.text('мягкий'));
    await tester.pumpAndSettle();
    expect(host.settings!.filterQuality, FilterQuality.low);
  });

  testWidgets('управление SSAO включает затенение', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, ssaoAmbientFeature);
    expect(host.settings!.ssao, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(host.settings!.ssao, isTrue);
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in lightPictureFeatures) {
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
