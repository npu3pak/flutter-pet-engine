import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelMaterial color(int r, int g, int b) =>
    ModelMaterial(type: MaterialType.color, color: [r, g, b]);

ModelObject cuboid(
  String id, {
  double x = 0,
  double y = 0,
  double z = 0,
  double w = 1,
  double h = 1,
  double d = 1,
  ModelMaterial? material,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      dims: {'w': w, 'h': h, 'd': d},
      material: material,
    );

void main() {
  final baker = LevelBaker.planning();

  test('plan merges by material and batches by shape+material', () {
    final model = ConstructionModel(id: 'level');
    final floorMat = color(100, 100, 100);
    final pillarMat = color(200, 150, 100);
    final uniqueMat = color(10, 20, 30);
    for (var i = 0; i < 3; i++) {
      model.add(cuboid('floor_$i', x: i.toDouble(), h: 0.1, material: floorMat),
          tag: 'floor');
    }
    model.add(cuboid('pillar_1', w: 0.3, h: 2, d: 0.3, material: pillarMat),
        bake: BakeMode.batch, tag: 'pillar');
    model.add(
        cuboid('pillar_2', x: 2, w: 0.3, h: 2, d: 0.3, material: pillarMat),
        bake: BakeMode.batch,
        tag: 'pillar');
    model.add(cuboid('door', x: 1, h: 2, d: 0.1, material: pillarMat),
        bake: BakeMode.node, tag: 'door');
    model.add(cuboid('unique', x: 5, material: uniqueMat), tag: 'wall');

    final plan = baker.plan(model);
    expect(plan.modes['floor_0'], BakeMode.merge);
    expect(plan.modes['pillar_1'], BakeMode.batch);
    expect(plan.modes['door'], BakeMode.node);
    expect(plan.mergedMeshes, 1, reason: 'три пола слиты по материалу');
    expect(plan.batchMeshes, 1, reason: 'две одинаковые стойки');
    expect(plan.separateNodes, 2, reason: 'дверь и одиночная стена');
    expect(plan.groupKeys['floor_0'], plan.groupKeys['floor_1']);
    expect(plan.groupKeys['floor_0'], isNot(plan.groupKeys['unique']));
    expect(plan.groupKeys['pillar_1'], plan.groupKeys['pillar_2']);
    expect(plan.groupKeys.containsKey('door'), isFalse);
  });

  test('plan does not batch different shapes', () {
    final model = ConstructionModel();
    final mat = color(120, 120, 120);
    model.add(cuboid('a', w: 0.3, h: 1, d: 0.3, material: mat),
        bake: BakeMode.batch);
    model.add(cuboid('b', w: 0.5, h: 1, d: 0.5, material: mat),
        bake: BakeMode.batch);
    final plan = baker.plan(model);
    expect(plan.batchMeshes, 0);
    expect(plan.separateNodes, 2);
  });

  test('plan merges different shapes of the same material', () {
    final model = ConstructionModel();
    final mat = color(80, 90, 100);
    model.add(cuboid('a', w: 1, h: 0.1, d: 1, material: mat));
    model.add(cuboid('b', x: 2, w: 2, h: 0.2, d: 1, material: mat));
    final plan = baker.plan(model);
    expect(plan.mergedMeshes, 1);
    expect(plan.separateNodes, 0);
  });

  test('plan keeps default (merge) elements of different materials apart', () {
    final model = ConstructionModel();
    model.add(cuboid('a', material: color(1, 2, 3)));
    model.add(cuboid('b', material: color(4, 5, 6)));
    final plan = baker.plan(model);
    expect(plan.mergedMeshes, 0);
    expect(plan.separateNodes, 2);
  });

  test('plan handles a stress-sized construction without a GPU', () {
    final model = ConstructionModel(id: 'stress');
    final mat = color(100, 100, 100);
    for (var r = 0; r < 20; r++) {
      for (var c = 0; c < 20; c++) {
        model.add(cuboid('cell_${r}_$c',
            x: c.toDouble(), z: r.toDouble(), h: 0.04, material: mat));
      }
    }
    final plan = baker.plan(model);
    expect(plan.modes, hasLength(400));
    expect(plan.mergedMeshes, 1);
    expect(plan.separateNodes, 0);
  });

  test('sprites, model and gltf instances always stay separate nodes', () {
    final model = ConstructionModel();
    model.add(ModelObject(
      id: 'sprite',
      name: 'sprite',
      kind: 'sprite',
      dims: {'w': 1, 'h': 1},
      material: color(1, 2, 3),
    ));
    model.add(ModelObject(
      id: 'house',
      name: 'house',
      kind: modelRefKind,
      refModelId: 'house_src',
    ));
    model.add(ModelObject(
      id: 'cat',
      name: 'cat',
      kind: gltfRefKind,
      gltfName: 'cat',
    ));
    final plan = baker.plan(model);
    expect(plan.modes['sprite'], BakeMode.node);
    expect(plan.modes['house'], BakeMode.node);
    expect(plan.modes['cat'], BakeMode.node);
    expect(plan.mergedMeshes, 0);
    expect(plan.separateNodes, 3);
  });

  test('a csg without a whole-result material stays a separate node', () {
    final model = ConstructionModel();
    model.add(cuboid('leaf', material: color(9, 9, 9)));
    model.add(ModelObject(
      id: 'cut',
      name: 'cut',
      kind: 'csg',
      op: 'subtract',
      operands: const ['leaf'],
    ));
    final plan = baker.plan(model);
    expect(plan.modes['cut'], BakeMode.node);
  });

  test('per-face materials keep elements apart in the plan', () {
    final model = ConstructionModel();
    final base = color(50, 50, 50);
    final a = cuboid('a', material: base);
    a.faces['+y'] = color(200, 200, 200);
    final b = cuboid('b', x: 2, material: base);
    b.faces['+y'] = color(10, 10, 10);
    model.add(a);
    model.add(b);
    final plan = baker.plan(model);
    expect(plan.groupKeys['a'], isNot(plan.groupKeys['b']));
    expect(plan.mergedMeshes, 0);
  });

  test('reorientBillboards keeps the top-level anchor and the nested chain',
      () {
    final anchor = vm.Vector3(3, 1, 4);
    final top = Node(
      name: 'top',
      localTransform: vm.Matrix4.translation(anchor) *
          vm.Matrix4.diagonal3Values(-1, 1, 1) *
          vm.Matrix4.rotationY(0.7),
    );
    final nested = Node(name: 'nested');
    final chain = vm.Matrix4.translation(vm.Vector3(10, 0, 0));
    final result = LevelBakeResult(
      root: Node(name: 'level'),
      nodes: const {},
      stats: const LevelBakeStats(
        elements: 0,
        mergedMeshes: 0,
        batchMeshes: 0,
        separateNodes: 0,
        vertices: 0,
        triangles: 0,
      ),
      buildTime: Duration.zero,
      billboards: [(top, null), (nested, chain)],
    );
    result.reorientBillboards(0, 1);
    final yaw = screenParallelYaw(0, 1);
    final mirrorYaw =
        vm.Matrix4.diagonal3Values(-1, 1, 1) * vm.Matrix4.rotationY(yaw);
    expect(top.localTransform.getTranslation(), anchor);
    expect(top.localTransform, vm.Matrix4.translation(anchor) * mirrorYaw);
    expect(nested.localTransform, chain * mirrorYaw);
  });
}
