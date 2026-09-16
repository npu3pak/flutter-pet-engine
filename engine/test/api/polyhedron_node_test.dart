import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

SceneController _controller() {
  final controller = SceneController();
  controller.setViewport(const Size(200, 100), 1);
  return controller;
}

void main() {
  group('PolyhedronNode', () {
    test('строит парты по граням и отдаёт ключи при пикинге', () {
      final node = PolyhedronNode(
        id: 'p',
        mesh: PolyMesh.box(w: 2, h: 2, d: 2),
      );
      expect(node.pickGeometries, hasLength(6));
      expect(
        node.pickParts.map((p) => p.faceKey).toSet(),
        {'+x', '-x', '+y', '-y', '+z', '-z'},
      );
      final bounds = node.worldBounds!;
      expect(bounds.min.x, closeTo(-1, 1e-9));
      expect(bounds.max.y, closeTo(2, 1e-9));
      node.dispose();
    });

    test('луч возвращает FaceRef с ключом грани', () {
      final controller = _controller();
      final node = PolyhedronNode(
        id: 'p',
        name: 'p',
        mesh: PolyMesh.box(w: 2, h: 2, d: 2),
      );
      controller.add(node);
      final hit = controller.raycastRay(
        vm.Ray.originDirection(
          vm.Vector3(0, 5, 0),
          vm.Vector3(0, -1, 0),
        ),
      );
      expect(hit, isNotNull);
      expect(hit!.node, same(node));
      expect(hit.face, isNotNull);
      expect(hit.face!.key, '+y');
      controller.dispose();
    });

    test('материалы по граням: override и возврат к общему', () {
      final global = SceneMaterial.pbr();
      final top = SceneMaterial.pbr(doubleSided: true);
      final node = PolyhedronNode(
        mesh: PolyMesh.box(),
        material: global,
        faceMaterials: {'+y': top},
      );
      expect(node.material, same(global));
      expect(node.faceMaterial('+y'), same(top));
      expect(node.faceMaterial('+x'), same(global));
      final byKey = {
        for (final part in node.pickParts) part.faceKey: part.side,
      };
      expect(byKey['+y'], 'double');
      expect(byKey['+x'], 'outer');
      node.setFaceMaterial('+y', null);
      expect(node.faceMaterial('+y'), same(global));
      node.dispose();
    });

    test('замена меша обновляет парты и грани', () {
      final node = PolyhedronNode(
        mesh: PolyMesh.box(),
      );
      expect(node.pickParts, hasLength(6));
      node.mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(1, 0, 0),
          vm.Vector3(0, 0, 1),
        ],
        faces: [PolyFace.triangle(key: 'top', a: 0, b: 1, c: 2)],
      );
      expect(node.pickParts, hasLength(1));
      expect(node.pickParts.single.faceKey, 'top');
      node.dispose();
    });

    test('контуры граней без диагоналей триангуляции', () {
      final node = PolyhedronNode(mesh: PolyMesh.box());
      // 6 граней × 4 ребра × 2 точки.
      expect(node.wireframeSegments(), hasLength(6 * 4 * 2));
      final withHole = PolyhedronNode(
        mesh: PolyMesh(
          vertices: [
            vm.Vector3(0, 0, 0),
            vm.Vector3(4, 0, 0),
            vm.Vector3(4, 0, 4),
            vm.Vector3(0, 0, 4),
            vm.Vector3(1, 0, 1),
            vm.Vector3(3, 0, 1),
            vm.Vector3(3, 0, 3),
            vm.Vector3(1, 0, 3),
          ],
          faces: [
            PolyFace(
              key: '+y',
              outer: PolyLoop(vertices: [0, 1, 2, 3]),
              holes: [PolyLoop(vertices: [4, 5, 6, 7])],
            ),
          ],
        ),
      );
      expect(withHole.wireframeSegments(), hasLength((4 + 4) * 2));
      node.dispose();
      withHole.dispose();
    });

    test('per-axis масштаб наследуется от SceneNode', () {
      final node = PolyhedronNode(mesh: PolyMesh.box());
      node.scale = vm.Vector3(2, 3, 4);
      expect(node.scale.x, closeTo(2, 1e-9));
      expect(node.scale.y, closeTo(3, 1e-9));
      expect(node.scale.z, closeTo(4, 1e-9));
      node.dispose();
    });

    test('явные UV доходят до геометрии', () {
      final node = PolyhedronNode(
        mesh: PolyMesh(
          vertices: [
            vm.Vector3(0, 0, 0),
            vm.Vector3(2, 0, 0),
            vm.Vector3(0, 0, 2),
          ],
          faces: [
            PolyFace.triangle(
              key: 't',
              a: 0,
              b: 1,
              c: 2,
              uvs: [
                vm.Vector2(0.1, 0.2),
                vm.Vector2(0.9, 0.2),
                vm.Vector2(0.1, 0.8),
              ],
            ),
          ],
        ),
      );
      final geometry = node.pickGeometries.single;
      final coords = geometry.data.texCoords!;
      expect(coords[0], closeTo(0.1, 1e-6));
      expect(coords[1], closeTo(0.2, 1e-6));
      node.dispose();
    });
  });
}
