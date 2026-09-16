import 'package:example/src/features/csg_ops.dart';
import 'package:example/src/features/document_scene.dart';
import 'package:example/src/features/feature_registry.dart';
import 'package:example/src/features/gltf_models.dart';
import 'package:example/src/features/meta_objects.dart';
import 'package:example/src/features/model_refs.dart';
import 'package:example/src/features/primitives_all.dart';
import 'package:example/src/features/primitives_textured.dart';
import 'package:example/src/features/rounded_box.dart';
import 'package:example/src/project_sources.dart';
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

  Future<SceneResources> openPet() async {
    final controller = SceneController();
    await controller.open(sourceForProject('Pet'));
    return controller.resources!;
  }

  test('каталог группы 6.1 содержит семь фич и проходит проверку', () {
    expect(documentSceneFeatures, hasLength(7));
    expect(validateFeatureCatalog(documentSceneFeatures), isEmpty);
    expect(
      documentSceneFeatures.map((f) => f.id),
      containsAll(const [
        'primitives_all',
        'primitives_textured',
        'rounded_box',
        'csg_ops',
        'model_refs',
        'gltf_models',
        'meta_objects',
      ]),
    );
  });

  test('сцена примитивов содержит все виды геометрии', () {
    final model = buildPrimitivesScene(buildContext());
    expect(model.objects, hasLength(8));
    expect(model.objects.map((o) => o.kind).toSet(), {
      'cuboid',
      'trapezoid',
      'cylinder',
      'plane',
      'sprite',
    });
    expect(model.objectById('rounded')!.dim('roundR', 0), greaterThan(0));
    expect(model.objectById('cone')!.dim('topR', 1), 0);
    expect(model.objectById('sprite')!.kind, 'sprite');
  });

  test('текстурирование отражает параметры управления', () {
    final model = buildTexturedPrimitivesScene(
      buildContext(
        params: const {
          'stretch': 'tile',
          'tileScale': 2.5,
          'uvDir': 90,
          'flipX': true,
          'flipY': true,
          'side': 'both',
          'faceMode': 'face',
          'materialKind': 'texture',
        },
      ),
    );
    final cube = model.objectById('cube')!;
    expect(cube.material!.type, doc.MaterialType.color);
    final face = cube.faces['+y']!;
    expect(face.type, doc.MaterialType.texture);
    expect(face.stretch, 'tile');
    expect(face.tileScale, 2.5);
    expect(face.uvDir, 90);
    expect(face.flipX, isTrue);
    expect(face.flipY, isTrue);
    expect(face.side, 'both');
  });

  test('текстуры берутся из проекта Pet', () async {
    final manager = await openPet();
    final model = buildTexturedPrimitivesScene(buildContext(project: manager));
    final cube = model.objectById('cube')!;
    expect(cube.material!.type, doc.MaterialType.texture);
    expect(cube.material!.key, startsWith('wallpaper_'));
    expect(cube.material!.key, endsWith('.png'));
  });

  test('скругления зависят от радиуса и числа сегментов', () {
    final model = buildRoundedBoxScene(
      buildContext(params: const {'radius': 0.5, 'segments': 32}),
    );
    final rounded = model.objectById('rounded')!;
    expect(rounded.dim('roundR', 0), 0.5);
    expect(rounded.dim('roundSegments', 0), 32);
    expect(
      model.objectById('plain'),
      isNull,
      reason: 'в сцене не должно быть нескруглённых кубов',
    );

    final cutBase = model.objectById('cut_base')!;
    expect(cutBase.dim('roundR', 0), 0.5);
    expect(cutBase.dim('roundSegments', 0), 32);

    final cut = model.objectById('cut_result')!;
    expect(cut.kind, doc.csgKind);
    expect(cut.op, doc.csgOpDifference);
    expect(cut.operands, const ['cut_base', 'cut_tool']);

    // Скруглённое основание участвует в CSG-вычитании: листья операции
    // содержат основание с заданным радиусом.
    final leaves = model.csgLeavesOf('cut_result');
    expect(leaves.map((o) => o.id), contains('cut_base'));
    final baseLeaf = leaves.firstWhere((o) => o.id == 'cut_base');
    expect(baseLeaf.dim('roundR', 0), 0.5);
  });

  test('логические операции строят три результата и вложенную операцию', () {
    final model = buildCsgScene(
      buildContext(
        params: const {'showSources': true, 'resultColor': 'yellow'},
      ),
    );
    final csg = model.objects.where((o) => o.kind == doc.csgKind).toList();
    expect(csg, hasLength(5));
    expect(
      csg.map((o) => o.op),
      containsAll([doc.csgOpUnion, doc.csgOpDifference, doc.csgOpIntersect]),
    );
    expect(csg.first.material!.color, const [222, 196, 88]);
    expect(model.objectById('src_a'), isNotNull);

    final withoutSources = buildCsgScene(
      buildContext(params: const {'showSources': false}),
    );
    expect(withoutSources.objectById('src_a'), isNull);
    expect(withoutSources.objectById('src_b'), isNull);
  });

  test('ссылки на модели используют каталог проекта Pet', () async {
    final manager = await openPet();
    final model = buildModelRefsScene(buildContext(project: manager));
    final first = model.objectById('ref_first')!;
    expect(first.kind, doc.modelRefKind);
    expect(first.refModelId, manager.modelIds.first);
    final missing = model.objectById('ref_missing')!;
    expect(missing.refSize, isNotNull);
  });

  test('ссылки на модели без проекта дают запасные идентификаторы', () {
    final model = buildModelRefsScene(buildContext());
    expect(model.objectById('ref_first')!.refModelId, 'model_1');
    expect(model.objectById('ref_second')!.refModelId, 'model_2');
  });

  test('gltf-сцена содержит кота и отсутствующий ресурс', () async {
    final manager = await openPet();
    final model = buildGltfScene(buildContext(project: manager));
    expect(model.objectById('cat')!.gltfName, 'cat');
    expect(model.objectById('missing')!.gltfName, 'missing_resource');
    if (manager.gltfEntry('puppy') != null) {
      expect(model.objectById('puppy'), isNotNull);
    }
  });

  test('разметка: имена боксов и клетки под ними', () {
    final model = buildMetaModel();
    expect(metaBoxNames(model), containsAll(['зона_спавна', 'непроходимо']));
    final spawn = metaBoxCells(model, 'зона_спавна');
    expect(spawn, containsAll(const [(6, 3), (6, 5)]));
    expect(spawn, hasLength(2));
    expect(metaBoxCells(model, 'непроходимо'), hasLength(1));
    expect(model.metas.where((m) => m.kind == doc.metaKindComment), isNotEmpty);
    expect(model.metas.where((m) => m.kind == doc.metaKindMarker), isNotEmpty);
  });

  testWidgets('каждая фича группы открывается в каркасе без ошибок', (
    tester,
  ) async {
    for (final spec in documentSceneFeatures) {
      await tester.pumpWidget(const SizedBox());
      final host = FakeSceneHost(paths: testPaths());
      await pumpShell(tester, features: [spec], host: host);
      await tester.tap(find.byKey(Key('feature-${spec.id}')));
      await tester.pumpAndSettle();
      expect(host.error, isNull, reason: spec.id);
      expect(host.ready, isTrue, reason: spec.id);
      expect(
        find.byKey(const Key('viewport')),
        findsOneWidget,
        reason: spec.id,
      );
    }
  });
}
