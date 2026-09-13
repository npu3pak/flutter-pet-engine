import 'package:demo/src/features/fmat_effects.dart';
import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/particle_params.dart';
import 'package:demo/src/features/particles.dart';
import 'package:demo/src/features/weather_cave_draft.dart';
import 'package:demo/src/features/weather_common.dart';
import 'package:demo/src/features/weather_rain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeatureBuildContext buildContext({Map<String, Object?> params = const {}}) =>
      FeatureBuildContext(project: null, paths: testPaths(), params: params);

  test('каталог группы 6.5 содержит шесть фич и проходит проверку', () {
    expect(particleFeatures, hasLength(6));
    expect(validateFeatureCatalog(particleFeatures), isEmpty);
    expect(
      particleFeatures.map((f) => f.id),
      containsAll(const [
        'weather_rain',
        'weather_snow',
        'weather_wind',
        'weather_cave_draft',
        'particle_params',
        'fmat_effects',
      ]),
    );
  });

  test('погодная сцена содержит площадку, строения и фонарь', () {
    final model = buildWeatherScene(buildContext(), 'weather_rain');
    expect(model.objectById('ground'), isNotNull);
    expect(model.objectById('building_1'), isNotNull);
    expect(model.objectById('lamp'), isNotNull);
    expect(model.size.w, 12);
  });

  test('сцена параметров частиц содержит стены', () {
    final model = buildParticleParamsScene(buildContext());
    expect(model.objects.where((o) => o.id.startsWith('wall_')), hasLength(4));
  });

  test('сцена эффектов содержит постамент и стенку', () {
    final model = buildFmatScene(buildContext());
    expect(model.objectById('pedestal'), isNotNull);
    expect(model.objectById('back'), isNotNull);
  });

  test('копия конфигурации частиц меняет только заданные поля', () {
    final base = ParticlePresets.streetRain;
    final copy = copyParticleConfig(
      base,
      maxPerCell: 20,
      fullDensityRings: 5,
      viewRadius: 8,
      windSpeed: 3,
    );
    expect(copy.maxPerCell, 20);
    expect(copy.fullDensityRings, 5);
    expect(copy.viewRadius, 8);
    expect(copy.windSpeed, 3);
    expect(copy.kind, base.kind);
    expect(copy.sprites, base.sprites);
    expect(copy.opacity, base.opacity);
  });

  test('пресеты частиц различаются по характеру движения', () {
    expect(ParticlePresets.streetRain.fallSpeedMax, greaterThan(0));
    expect(ParticlePresets.passSnow.rotationSpin, greaterThan(0));
    expect(ParticlePresets.passWind.fallSpeedMax, 0);
    expect(ParticlePresets.caveWindStreak.kind, ParticleKind.wind);
  });

  testWidgets('управление погодой открывается без проекта', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, weatherRainFeature);
    expect(find.text('Погода'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление сквозняком показывает два слоя', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, weatherCaveDraftFeature);
    expect(find.textContaining('двух слоёв'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('направление ветра учитывает зеркальный мир', () {
    // Мир зеркалит X модели: восток — world −X, запад — +X.
    expect(windDirectionFor('east').x, lessThan(0));
    expect(windDirectionFor('west').x, greaterThan(0));
    expect(windDirectionFor('north').z, lessThan(0));
    expect(windDirectionFor('south').z, greaterThan(0));
  });

  testWidgets('управление параметрами частиц открывается без проекта', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, particleParamsFeature);
    expect(find.text('Параметры слоя'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление эффектами открывается без проекта', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, fmatEffectsFeature);
    expect(find.text('Эффект на спрайте'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in particleFeatures) {
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
