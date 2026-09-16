import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/level.dart';
import 'package:demo/src/features/level_baking.dart';
import 'package:demo/src/features/level_common.dart';
import 'package:demo/src/features/level_loading.dart';
import 'package:demo/src/features/level_meta_cells.dart';
import 'package:demo/src/features/level_meta_query.dart';
import 'package:demo/src/features/level_validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeatureBuildContext buildContext({
    SceneResources? project,
    Map<String, Object?> params = const {},
  }) =>
      FeatureBuildContext(project: project, paths: testPaths(), params: params);

  test('каталог группы 6.6 содержит семь фич и проходит проверку', () {
    expect(levelFeatures, hasLength(7));
    expect(validateFeatureCatalog(levelFeatures), isEmpty);
    expect(
      levelFeatures.map((f) => f.id),
      containsAll(const [
        'level_shell',
        'level_meta_cells',
        'level_meta_query',
        'level_validation',
        'level_baking',
        'level_loading',
        'level_stress',
      ]),
    );
  });

  test('оболочка уровня собрана без совпадающих граней', () {
    final model = buildLevelShell();
    expect(countCoincidentFaces(model.data), 0);
  });

  test('оболочка: твёрдые клетки блоками, полы только под открытыми', () {
    final model = buildLevelShell();
    final floors = model.elements.where((o) => o.tag == 'floor').length;
    final ceilings = model.elements.where((o) => o.tag == 'ceiling').length;
    final solids = model.elements.where((o) => o.tag == 'solid').length;
    final grid = LevelGrid.fromRows(levelShellRows);
    final open = grid.cells.where((e) => e.$2.isOpen).length;
    final solid = grid.cells.where((e) => e.$2.isSolid).length;
    expect(floors, open);
    expect(ceilings, open);
    // Клетка за окном заменена рамкой из четырёх блоков плюс ниша.
    expect(solids, solid + 3);
    expect(model.elements.where((o) => o.tag == 'window_recess'), hasLength(1));
    expect(model.elements.any((o) => o.tag == 'door'), isTrue);
    expect(model.elements.any((o) => o.tag == 'window'), isTrue);
    expect(model.elements.any((o) => o.tag == 'decor'), isTrue);
  });

  test('оконный проём свободен, за ним тёмная ниша', () {
    final model = buildLevelShell();
    const openingMinX = 4 - 0.4;
    const openingMaxX = 4 + 0.4;
    const openingMinY = 0.6;
    const openingMaxY = 1.4;
    for (final o in model.elements) {
      if (o.kind != 'cuboid') continue;
      final (lo, hi) = objectBounds(o);
      final overlapsX = hi.x > openingMinX + 1e-9 && lo.x < openingMaxX - 1e-9;
      final overlapsY = hi.y > openingMinY + 1e-9 && lo.y < openingMaxY - 1e-9;
      final overlapsZ = hi.z > 0.45 && lo.z < 0.68;
      expect(
        overlapsX && overlapsY && overlapsZ,
        isFalse,
        reason: 'тело ${o.id} перекрывает оконный проём',
      );
    }
  });

  test('декор можно выключить, окно — отдельным переключателем', () {
    final model = buildLevelShell(withDecor: false, withWindow: false);
    expect(model.elements.any((o) => o.tag == 'decor'), isFalse);
    expect(model.elements.any((o) => o.tag == 'window'), isFalse);
  });

  test('правило клеток под боксами разметки', () {
    final summary = summarizeLevelMeta();
    expect(summary.blocked, 5);
    expect(summary.doors, 1);
    expect(summary.windows, 1);
    expect(summary.doorPassable, isTrue);
    expect(summary.blockedPassable, isFalse);
  });

  test('запросы к метам: клетки, фильтр и список уровня', () {
    final s = summarizeMetaQueries();
    expect(s.cellMetas, [metaNameUnpassable]);
    expect(s.edgeCellMetas, [
      metaNameUnpassable,
    ], reason: 'широкий бокс заезжает краешком в соседнюю клетку');
    expect(s.rotatedCellMetas, [
      metaNameDoor,
    ], reason: 'повёрнутая сцена находит дверь в клетке уровня');
    expect(
      s.total,
      4,
      reason:
          'бокс, дверь и маркер первой сцены плюс дверь второй; '
          'заметка не участвует',
    );
    expect(s.names, [metaNameDoor, 'spawn', metaNameUnpassable]);
    expect(s.unpassable, 1);
    expect(s.comments, 1);
  });

  test('уровень загрузчика содержит пол, стену, ящик, спрайт и заготовку', () {
    final model = buildLoadingLevel();
    expect(model.elements, hasLength(5));
    expect(model.byId('floor')!.material!.key, loadingTextureKey);
    expect(model.byId('crate')!.bake, 'node');
    expect(model.byId('sprite')!.kind, 'sprite');
    expect(model.byId('prefab')!.kind, modelRefKind);
    expect(model.byId('prefab')!.refModelId, 'model_1');
    final withLost = buildLoadingLevel(withMissingTexture: true);
    expect(withLost.elements, hasLength(6));
    expect(withLost.byId('lost')!.material!.key, loadingMissingTextureKey);
  });

  testWidgets('управление загрузкой показывает переключатель и кнопку', (
    tester,
  ) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpFeatureControls(tester, host, levelLoadingFeature);
    expect(find.text('Потерянный ресурс'), findsOneWidget);
    expect(find.text('Загрузить заново'), findsOneWidget);
  });

  test('проверки уровня находят заготовленные ошибки', () {
    final issues = levelValidationIssues();
    final kinds = issues.map((i) => i.kind).toSet();
    expect(kinds, contains(LevelIssueKind.disconnectedCell));
    expect(kinds, contains(LevelIssueKind.duplicateElementId));
    expect(kinds, contains(LevelIssueKind.elementOutsideGrid));
    final scene = buildValidationScene(buildContext());
    expect(scene.objects.any((o) => o.id.startsWith('issue_')), isTrue);
  });

  test('план запекания: объединение, пакет и отдельные узлы', () {
    final elements = buildLevelShell().elements.length;
    final merge = bakingPlan(BakeMode.merge);
    final batch = bakingPlan(BakeMode.batch);
    final node = bakingPlan(BakeMode.node);
    expect(merge.modes.length, elements);
    expect(node.separateNodes, elements);
    expect(merge.mergedMeshes, greaterThan(0));
    expect(batch.batchMeshes, greaterThanOrEqualTo(merge.mergedMeshes));
    expect(merge.separateNodes, lessThan(elements));
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in levelFeatures) {
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
