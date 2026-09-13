import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

ModelObject cuboid(
  String id, {
  double x = 0,
  double y = 0,
  double z = 0,
  double w = 1,
  double h = 1,
  double d = 1,
  double rotY = 0,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      dims: {'w': w, 'h': h, 'd': d},
    );

void main() {
  group('add / byId / remove / clear', () {
    test('add writes bake and tag, defaults to merge', () {
      final model = ConstructionModel(id: 'level_1');
      final a = model.add(cuboid('a'), tag: 'floor');
      final b = model.add(cuboid('b'), bake: BakeMode.node, tag: 'door');
      expect(model.id, 'level_1');
      expect(model.elements.length, 2);
      expect(a.bake, isNull);
      expect(bakeModeOf(a), BakeMode.merge);
      expect(bakeModeOf(b), BakeMode.node);
      expect(a.tag, 'floor');
      expect(b.tag, 'door');
      expect(model.byId('b'), same(b));
      expect(model.byId('missing'), isNull);
    });

    test('remove and clear', () {
      final model = ConstructionModel();
      model.add(cuboid('a'));
      model.add(cuboid('b'));
      expect(model.remove('a'), isTrue);
      expect(model.remove('a'), isFalse);
      expect(model.elements.single.id, 'b');
      model.clear();
      expect(model.elements, isEmpty);
    });

    test('bakeModeOf reads the serialized hint', () {
      expect(bakeModeOf(cuboid('a')), BakeMode.merge);
      expect(bakeModeOf(cuboid('a')..bake = 'batch'), BakeMode.batch);
      expect(bakeModeOf(cuboid('a')..bake = 'node'), BakeMode.node);
      expect(bakeModeOf(cuboid('a')..bake = 'unknown'), BakeMode.merge);
    });
  });

  group('bounds', () {
    test('boundsOf is rotation-aware', () {
      final model = ConstructionModel();
      final a = model.add(cuboid('a', w: 2, h: 1, d: 2));
      final flat = model.boundsOf('a')!;
      expect(flat.$1.x, closeTo(-1, 1e-9));
      expect(flat.$2.x, closeTo(1, 1e-9));
      a.rotY = 45;
      final turned = model.boundsOf('a')!;
      expect(turned.$1.x, closeTo(-1.4142, 1e-3));
      expect(turned.$2.x, closeTo(1.4142, 1e-3));
      expect(model.boundsOf('missing'), isNull);
    });

    test('bounds unions all elements', () {
      final model = ConstructionModel();
      model.add(cuboid('a', x: -2, w: 2, h: 1, d: 2));
      model.add(cuboid('b', x: 3, w: 2, h: 1, d: 2));
      final bounds = model.bounds!;
      expect(bounds.$1.x, closeTo(-3, 1e-9));
      expect(bounds.$2.x, closeTo(4, 1e-9));
      expect(ConstructionModel().bounds, isNull);
    });
  });

  group('serialization', () {
    test('round-trips elements, bake and tag', () {
      final model = ConstructionModel(id: 'floor_1', name: 'Этаж');
      model.data.size = ModelSize(w: 7, l: 5, h: 3);
      model.add(cuboid('a', x: 1.5), tag: 'floor');
      model.add(
        cuboid('b', x: 2, y: 3),
        bake: BakeMode.node,
        tag: 'door',
      );
      model.add(cuboid('c'), bake: BakeMode.batch);
      model.data.metas.add(ModelMeta(
        id: 'm1',
        kind: metaKindBox,
        name: 'unpassable',
        x: 2,
        z: 1,
        dims: {'w': 1, 'h': 1, 'd': 1},
      ));

      final restored =
          ConstructionModel.fromJson(model.toJsonString(), id: 'floor_1');
      expect(restored.id, 'floor_1');
      expect(restored.name, 'Этаж');
      expect(restored.size.w, 7);
      expect(restored.elements.length, 3);
      expect(restored.byId('a')!.tag, 'floor');
      expect(restored.byId('a')!.bake, isNull);
      expect(bakeModeOf(restored.byId('b')!), BakeMode.node);
      expect(bakeModeOf(restored.byId('c')!), BakeMode.batch);
      expect(restored.data.metas.single.name, 'unpassable');
      expect(restored.data.metas.single.x, 2);
    });

    test('objects without bake/tag stay null (backward compatible)', () {
      final obj = ModelObject.fromJson({
        'id': 'a',
        'kind': 'cuboid',
        'pos': [0, 0, 0],
        'size': [1, 1, 1],
      });
      expect(obj.bake, isNull);
      expect(obj.tag, isNull);
      final json = obj.toJson();
      expect(json.containsKey('bake'), isFalse);
      expect(json.containsKey('tag'), isFalse);
    });
  });
}
