import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/model_renderer.dart' show ModelRenderer;
import 'package:pet_engine/src/services/texture_cache.dart' show TextureCache;
import 'package:vector_math/vector_math.dart' as vm;

ModelObject _poly({String id = 'p'}) => ModelObject(
      id: id,
      name: 'mesh',
      kind: polyhedronKind,
      x: 2,
      y: 1,
      z: 3,
      scaleX: 2,
      scaleY: 3,
      scaleZ: 4,
      mesh: PolyMesh.box(w: 1, h: 1, d: 1),
    );

ModelData _doc({List<ModelObject>? objects}) => ModelData(
      id: 'm',
      name: 'm',
      size: ModelSize(w: 6, l: 8, h: 4),
      objects: objects ?? [_poly()],
    );

void main() {
  group('objectWorldMatrix', () {
    test('anchor + поворот + per-axis масштаб', () {
      final model = _doc();
      final obj = model.objects.single;
      final matrix = objectWorldMatrix(model, obj);
      final anchor = matrix.getTranslation();
      final expected = chunkWorld(obj.x, obj.z, model.size.w, model.size.l);
      expect(anchor.x, closeTo(expected.x, 1e-9));
      expect(anchor.y, closeTo(1, 1e-9));
      expect(anchor.z, closeTo(expected.z, 1e-9));
      // Вершина (0.5, 1, 0.5) уходит в масштаб ×(2, 3, 4).
      final world = matrix.transform3(vm.Vector3(0.5, 1, 0.5));
      expect(world.y, closeTo(1 + 3, 1e-9));
    });
  });

  group('ModelNode: инвалидация пикинга и контуры', () {
    test('после правки сети pickParts пересобираются', () {
      final controller = SceneController();
      controller.loadModelData(_doc());
      final node = controller.objectNode('p')!;
      final before = node.pickParts.length;
      expect(before, 6);
      final mesh = node.object.mesh!;
      mesh.moveVertices([0, 1, 2, 3], vm.Vector3(0, 2, 0));
      node.invalidatePicking();
      final moved = node.pickParts.first.geometry.data.positions;
      var maxY = double.negativeInfinity;
      for (var i = 1; i < moved.length; i += 3) {
        if (moved[i] > maxY) maxY = moved[i];
      }
      expect(maxY, greaterThan(2.5));
      controller.dispose();
    });

    test('wireframeSegments многогранника — точные контуры граней', () {
      final controller = SceneController();
      controller.loadModelData(_doc());
      final node = controller.objectNode('p')!;
      // 12 уникальных рёбер куба × 2 точки (общие рёбра дедуплицируются).
      expect(node.wireframeSegments(), hasLength(12 * 2));
      // Без включённых граней и без общего wireframe — пусто.
      expect(node.wireframeSegments(all: false), isEmpty);
      node.setFaceWireframe('+y', true);
      expect(node.wireframeSegments(all: false), hasLength(4 * 2));
      controller.dispose();
    });
  });

  group('конверсия: applyTo и чистка материалов', () {
    test('applyTo кубоида: вид, сеть, dims, поворот сохранён', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        rotY: 30,
        dims: {'w': 2, 'h': 3, 'd': 4},
        faces: {'+y': ModelMaterial(color: [1, 2, 3])},
      );
      final bake = bakePolyhedron(_doc(objects: [obj]), obj)!;
      bake.applyTo(obj);
      expect(obj.kind, polyhedronKind);
      expect(obj.mesh!.faces, hasLength(6));
      expect(obj.dims, isEmpty);
      expect(obj.rotY, 30);
      expect(obj.faces['+y']!.color, [1, 2, 3]);
    });

    test('applyTo CSG: операнды очищены, поворот запечён', () {
      final model = ModelData(
        id: 'm',
        name: 'm',
        size: ModelSize(w: 6, l: 6, h: 6),
        objects: [
          ModelObject(
            id: 'a',
            name: 'a',
            kind: 'cuboid',
            dims: {'w': 2, 'h': 2, 'd': 2},
          ),
          ModelObject(
            id: 'b',
            name: 'b',
            kind: 'cuboid',
            dims: {'w': 1, 'h': 4, 'd': 1},
          ),
          ModelObject(
            id: 'r',
            name: 'r',
            kind: csgKind,
            op: csgOpDifference,
            operands: ['a', 'b'],
            rotY: 45,
          ),
        ],
      );
      final csg = model.objectById('r')!;
      final bake = bakePolyhedron(model, csg)!;
      expect(bake.rotationBaked, isTrue);
      bake.applyTo(csg);
      expect(csg.kind, polyhedronKind);
      expect(csg.operands, isNull);
      expect(csg.op, isNull);
      expect(csg.rotY, 0);
      expect(csg.mesh!.faces, isNotEmpty);
    });

    test('pruneFaceMaterials убирает устаревшие ключи', () {
      final obj = _poly();
      obj.faces['+y'] = ModelMaterial(color: [9, 9, 9]);
      obj.faces['stale'] = ModelMaterial(color: [1, 1, 1]);
      final removed = pruneFaceMaterials(obj);
      expect(removed, ['stale']);
      expect(obj.faces.keys, ['+y']);
    });
  });

  group('левый уровень: режим запекания', () {
    test('многогранник всегда node', () {
      final obj = _poly();
      expect(bakeModeOf(obj), BakeMode.node);
      obj.bake = 'merge';
      expect(bakeModeOf(obj), BakeMode.node);
    });
  });

  group('ModelRenderer.rebuildObject: отказы', () {
    test('model/gltf и mergeStatic требуют полной пересборки', () {
      final renderer = ModelRenderer(TextureCache());
      final model = _doc(
        objects: [
          ModelObject(
            id: 'ref',
            name: 'ref',
            kind: modelRefKind,
            refModelId: 'src',
            refSize: ModelSize(),
          ),
        ],
      );
      expect(renderer.rebuildObject(model, model.objects.single), isFalse);

      final merging = ModelRenderer(TextureCache(), mergeStatic: true);
      final poly = _poly();
      expect(merging.rebuildObject(_doc(objects: [poly]), poly), isFalse);
    });
  });
}
