import 'dart:convert';

import 'package:demo/src/features/biome_scenes.dart';
import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/legacy_chunks.dart';
import 'package:demo/src/features/level.dart';
import 'package:demo/src/features/level_baking.dart';
import 'package:demo/src/features/level_common.dart';
import 'package:demo/src/features/level_docking.dart';
import 'package:demo/src/features/level_loading.dart';
import 'package:demo/src/features/level_meta_cells.dart';
import 'package:demo/src/features/level_meta_query.dart';
import 'package:demo/src/features/level_validation.dart';
import 'package:demo/src/project_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FeatureBuildContext buildContext({
    SceneResources? project,
    Map<String, Object?> params = const {},
  }) =>
      FeatureBuildContext(project: project, paths: testPaths(), params: params);

  Future<SceneResources> openProject(String name) async {
    final controller = SceneController();
    await controller.open(sourceForProject(name));
    return controller.resources!;
  }

  test('каталог группы 6.6 содержит двенадцать фич и проходит проверку', () {
    expect(levelFeatures, hasLength(12));
    expect(validateFeatureCatalog(levelFeatures), isEmpty);
    expect(
      levelFeatures.map((f) => f.id),
      containsAll(const [
        'level_shell',
        'level_meta_cells',
        'level_meta_query',
        'level_docking',
        'level_validation',
        'level_baking',
        'level_loading',
        'legacy_chunks',
        'biome_dungeon',
        'biome_forest',
        'biome_abandoned_building',
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

  test('стыковка домов Streets проверяется автоматически', () async {
    final manager = await openProject('Streets');
    final houses = streetHouses(manager.models.toList());
    expect(houses, isNotEmpty);
    final row = buildStreetsRow(houses);
    expect(row, isNotNull);
    final summary = summarizeDocking(manager);
    expect(summary.houses, houses.length);
    expect(summary.overlaps, 0);
    expect(summary.dockedPairs, greaterThan(0));
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

  test('ряд сцен каждого биома собирается без ошибок структуры', () async {
    for (final name in const ['Dungeon', 'Forest', 'AbandonedBuilding']) {
      final manager = await openProject(name);
      final scenes = biomeScenes(manager);
      expect(scenes, isNotEmpty, reason: name);
      final row = buildSceneRow(scenes, id: '${name}_row', name: name);
      expect(row, isNotNull, reason: name);
      expect(row!.elements, hasLength(scenes.length), reason: name);
      expect(
        row.data.size.w,
        scenes.fold(0, (w, s) => w + s.size.w),
        reason: name,
      );
      // kind `model` ставит центр сетки источника в `pos`: привязка сцены —
      // её центр, тогда сцена занимает клетки из ScenePlacement.
      var col = 0;
      for (final scene in scenes) {
        final ref = row.elements.firstWhere((o) => o.refModelId == scene.id);
        expect(ref.x, col + (scene.size.w - 1) / 2, reason: name);
        expect(ref.z, (scene.size.l - 1) / 2, reason: name);
        col += scene.size.w;
      }
      final summary = summarizeBiome(manager);
      expect(summary.scenes, scenes.length, reason: name);
      expect(summary.objects, greaterThan(0), reason: name);
      expect(summary.errors, 0, reason: name);
    }
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

  test('старый чанк Streets преобразуется в сцену model_v1', () async {
    final manager = await openProject('Streets');
    final bytes = await manager.readBytes('chunks/chunk_1.json');
    expect(bytes, isNotNull);
    final converted = convertLegacyChunk(
      utf8.decode(bytes!),
      id: 'legacy_chunk_1',
    );
    expect(converted.objects, isNotEmpty);
    expect(
      converted.metas.any((m) => m.name == doc.metaNameUnpassable),
      isTrue,
    );
    final summary = await summarizeLegacyChunk(manager, 1);
    expect(summary, isNotNull);
    expect(summary!.objects, converted.objects.length);
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
