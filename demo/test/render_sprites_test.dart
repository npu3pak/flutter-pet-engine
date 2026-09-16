import 'package:demo/src/features/billboard_batch.dart';
import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/render_sprites.dart';
import 'package:demo/src/features/sprite_atlas.dart';
import 'package:demo/src/features/static_merge.dart';
import 'package:demo/src/features/transparency_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart' as doc;

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  doc.ModelObject objectOf(String id, String kind) =>
      doc.ModelObject(id: id, name: id, kind: kind);

  FeatureBuildContext buildContext({Map<String, Object?> params = const {}}) =>
      FeatureBuildContext(project: null, paths: testPaths(), params: params);

  test('каталог группы 6.3 содержит четыре фичи и проходит проверку', () {
    expect(renderSpriteFeatures, hasLength(4));
    expect(validateFeatureCatalog(renderSpriteFeatures), isEmpty);
    expect(
      renderSpriteFeatures.map((f) => f.id),
      containsAll(const [
        'billboard_batch',
        'sprite_atlas',
        'transparency_order',
        'static_merge',
      ]),
    );
  });

  test('сцена пакетной отрисовки содержит площадку и ориентиры', () {
    final model = buildBillboardScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objects.where((o) => o.id.startsWith('post_')), hasLength(4));
  });

  test('сцена атласа содержит площадку и стенку', () {
    final model = buildSpriteAtlasScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objectById('back'), isNotNull);
  });

  test('сцена прозрачности содержит площадку и стенку', () {
    final model = buildTransparencyScene(buildContext());
    expect(model.objectById('ground'), isNotNull);
    expect(model.objectById('back'), isNotNull);
  });

  test('план объединения статики считает объекты и группы', () {
    final model = buildStaticMergeScene(buildContext());
    final plan = mergePlanOf(model);
    expect(plan.objects, 43);
    expect(plan.groups, 8);

    final transparent = mergePlanOf(buildTransparencyScene(buildContext()));
    expect(transparent.objects, 2);
    expect(transparent.groups, 2);
  });

  test('слияние не учитывает спрайты и вставки сцен', () {
    final model = buildStaticMergeScene(buildContext());
    model.objects.add(objectOf('sprite', 'sprite'));
    model.objects.add(objectOf('ref', doc.modelRefKind));
    final plan = mergePlanOf(model);
    expect(plan.objects, 43);
  });

  testWidgets('управление пакетной отрисовки открывается без проекта', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, billboardBatchFeature);
    expect(find.text('Поток спрайтов'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление атласом открывается без проекта', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, spriteAtlasFeature);
    expect(find.text('Атлас из спрайтов проекта'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление прозрачностью открывается без проекта', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, transparencyOrderFeature);
    expect(find.text('Пересекающиеся спрайты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('управление слиянием статики показывает счётчики', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, staticMergeFeature);
    expect(find.text('Объектов до объединения: 43'), findsOneWidget);
    expect(find.text('Объединённых мешей после: 8'), findsOneWidget);
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in renderSpriteFeatures) {
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
