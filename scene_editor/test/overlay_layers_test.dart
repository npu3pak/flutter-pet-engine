import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:scene_editor/src/scene/light_renderer.dart';
import 'package:scene_editor/src/scene/meta_renderer.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

/// Headless checks of the incremental overlay layers: a moved meta/light
/// keeps its nodes (only transforms change), added/removed items touch only
/// their own nodes.

ModelData _doc() => ModelData(
      id: 'm',
      name: 'm',
      size: ModelSize(w: 5, l: 5, h: 3),
      metas: [
        ModelMeta(id: 'a', kind: metaKindMarker, name: '', x: 1, y: 0, z: 1),
        ModelMeta(id: 'b', kind: metaKindMarker, name: '', x: 3, y: 0, z: 3),
      ],
    );

List<SceneNode> _metaNodes(MetaOverlayLayer layer, String id) => layer
    .root
    .children
    .where((n) => n.name == '$metaNodePrefix$id')
    .toList();

List<SceneNode> _lightNodes(LightGizmoLayer layer, String id) => layer
    .root
    .children
    .where((n) => n.name == '$lightNodePrefix$id')
    .toList();

bool _sameMatrix(Matrix4 a, Matrix4 b) {
  for (var i = 0; i < 16; i++) {
    if ((a.storage[i] - b.storage[i]).abs() > 1e-9) return false;
  }
  return true;
}

void main() {
  testWidgets('moving a meta shifts its cached nodes only', (tester) async {
    final controller = SceneController(mergeStatic: false);
    final model = _doc();
    controller.loadModelData(model);
    final layer = MetaOverlayLayer(controller: controller);
    layer.rebuild(model);

    final a0 = _metaNodes(layer, 'a');
    final b0 = _metaNodes(layer, 'b');
    expect(a0, isNotEmpty);
    expect(b0, isNotEmpty);
    final aTransform = a0.first.transform.clone();
    final bTransform = b0.first.transform.clone();

    model.metaById('a')!.x += 2;
    layer.sync(model);

    final a1 = _metaNodes(layer, 'a');
    final b1 = _metaNodes(layer, 'b');
    expect(a1, hasLength(a0.length), reason: 'число нод меты не меняется');
    for (var i = 0; i < a1.length; i++) {
      expect(a1[i], same(a0[i]), reason: 'ноды меты переиспользуются');
    }
    expect(_sameMatrix(a1.first.transform, aTransform), isFalse,
        reason: 'трансформ перемещённой меты обновился');
    expect(b1.first, same(b0.first), reason: 'другая мета не тронута');
    expect(_sameMatrix(b1.first.transform, bTransform), isTrue);

    // Смена формы пересобирает только эту мету.
    model.metaById('a')!.kind = metaKindBox;
    layer.sync(model);
    expect(_metaNodes(layer, 'a').first, isNot(same(a0.first)),
        reason: 'смена формы пересобирает ноды меты');
    expect(_metaNodes(layer, 'b').first, same(b0.first));

    // Удаление меты убирает только её ноды.
    model.metas.removeWhere((m) => m.id == 'a');
    layer.sync(model);
    expect(_metaNodes(layer, 'a'), isEmpty);
    expect(_metaNodes(layer, 'b'), isNotEmpty);

    layer.dispose();
    controller.dispose();
  });

  testWidgets('moving a meta in full rebuild keeps the texture cache',
      (tester) async {
    // Смоук: полная пересборка (смена режима) не падает на кэше и
    // сохраняет ноды при повторном sync.
    final controller = SceneController(mergeStatic: false);
    final model = _doc();
    controller.loadModelData(model);
    final layer = MetaOverlayLayer(controller: controller);
    layer.rebuild(model);
    layer.rebuild(model);
    layer.sync(model);
    expect(_metaNodes(layer, 'a'), isNotEmpty);
    layer.dispose();
    controller.dispose();
  });

  testWidgets('light gizmos sync only the dragged source', (tester) async {
    final layer = LightGizmoLayer();
    final cfg = ModelLighting();
    cfg.lights.add(ModelLight(
      id: 'p1',
      kind: lightKindPoint,
      x: 0,
      y: 1,
      z: 0,
    ));
    cfg.lights.add(ModelLight(
      id: 'd1',
      kind: lightKindDirectional,
      x: 1,
      y: 1,
      z: 1,
      dirX: 0,
      dirY: -1,
      dirZ: 0,
    ));
    layer.rebuild(cfg, modelW: 5, modelL: 5);

    final p0 = _lightNodes(layer, 'p1');
    final d0 = _lightNodes(layer, 'd1');
    expect(p0, hasLength(1));
    expect(d0, hasLength(3), reason: 'направленный свет: шар, шток, конус');
    final pTransform = p0.single.transform.clone();
    final dTransform = d0.first.transform.clone();

    // Драг точечного света: свои ноды обновляются, чужие не тронуты.
    cfg.lights.first.x = 2;
    layer.sync(cfg, modelW: 5, modelL: 5, only: 'p1');
    final p1 = _lightNodes(layer, 'p1');
    expect(p1.single, same(p0.single), reason: 'нода переиспользуется');
    expect(_sameMatrix(p1.single.transform, pTransform), isFalse);
    final d1 = _lightNodes(layer, 'd1');
    expect(d1.first, same(d0.first), reason: 'чужой источник не тронут');
    expect(_sameMatrix(d1.first.transform, dTransform), isTrue);

    // Смена типа источника пересобирает его части.
    cfg.lights[0].kind = lightKindDirectional;
    layer.sync(cfg, modelW: 5, modelL: 5);
    expect(_lightNodes(layer, 'p1'), hasLength(3),
        reason: 'точечный → направленный: шар и стрелка');

    // Удаление источника убирает только его ноды.
    cfg.lights.removeWhere((l) => l.id == 'p1');
    layer.sync(cfg, modelW: 5, modelL: 5);
    expect(_lightNodes(layer, 'p1'), isEmpty);
    expect(_lightNodes(layer, 'd1'), hasLength(3));

    layer.dispose();
  });
}
