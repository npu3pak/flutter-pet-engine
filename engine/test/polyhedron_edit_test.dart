import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

PolyMesh _quad() => PolyMesh(
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
          outer: PolyLoop(
            vertices: [0, 1, 2, 3],
            uvs: [
              vm.Vector2(0, 0),
              vm.Vector2(1, 0),
              vm.Vector2(1, 1),
              vm.Vector2(0, 1),
            ],
          ),
          holes: [
            PolyLoop(
              vertices: [4, 5, 6, 7],
              uvs: [
                vm.Vector2(0.25, 0.25),
                vm.Vector2(0.75, 0.25),
                vm.Vector2(0.75, 0.75),
                vm.Vector2(0.25, 0.75),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  group('PolyMesh: правка вершин', () {
    test('moveVertices двигает только указанные и пропускает битые', () {
      final mesh = _quad();
      mesh.moveVertices([0, 2, 99, -1], vm.Vector3(1, 2, 3));
      expect(mesh.vertices[0], vm.Vector3(1, 2, 3));
      expect(mesh.vertices[2], vm.Vector3(5, 2, 7));
      expect(mesh.vertices[1], vm.Vector3(4, 0, 0));
      expect(mesh.vertices, hasLength(8));
    });

    test('rotateVertices поворачивает вокруг оси и пивота', () {
      final mesh = _quad();
      mesh.rotateVertices(
        [0],
        vm.Vector3(0, 1, 0),
        3.141592653589793 / 2,
        pivot: vm.Vector3(0, 0, 0),
      );
      expect(mesh.vertices[0].x, closeTo(0, 1e-9));
      expect(mesh.vertices[0].z, closeTo(-0, 1e-9));
      expect(mesh.vertices[0].y, closeTo(0, 1e-9));
    });
  });

  group('PolyMesh: добавление вершины', () {
    test('вставка в ближайшее ребро внешнего контура с UV', () {
      final mesh = _quad();
      final index = mesh.addVertexToFace('+y', vm.Vector3(2, 0, 0));
      expect(index, 8);
      expect(mesh.vertices[8], vm.Vector3(2, 0, 0));
      final loop = mesh.faces.single.outer;
      expect(loop.vertices, [0, 8, 1, 2, 3]);
      // UV интерполирован посередине первого ребра.
      expect(loop.uvs[1].x, closeTo(0.5, 1e-9));
      expect(loop.uvs[1].y, closeTo(0, 1e-9));
      expect(loop.uvs, hasLength(5));
      // Дырка не тронута.
      expect(mesh.faces.single.holes.single.vertices, hasLength(4));
    });

    test('вставка может попасть в контур дырки', () {
      final mesh = _quad();
      // Ближайшее ребро — 7→4 контура дырки (x = 1, z = 1..3).
      final index = mesh.addVertexToFace('+y', vm.Vector3(1, 0, 2));
      expect(index, 8);
      expect(mesh.faces.single.outer.vertices, [0, 1, 2, 3]);
      final hole = mesh.faces.single.holes.single;
      expect(hole.vertices, [4, 5, 6, 7, 8]);
      expect(hole.uvs, hasLength(5));
      // UV интерполирован посередине последнего ребра (7→4).
      expect(hole.uvs[4].x, closeTo(0.25, 1e-9));
      expect(hole.uvs[4].y, closeTo(0.5, 1e-9));
    });

    test('неизвестная грань возвращает null', () {
      expect(_quad().addVertexToFace('nope', vm.Vector3.zero()), isNull);
    });
  });

  group('PolyMesh: удаление вершин', () {
    test('общая вершина убирается из всех граней, индексы перенумерованы', () {
      final mesh = PolyMesh.box(w: 2, h: 2, d: 2);
      mesh.deleteVertices([0]);
      expect(mesh.vertices, hasLength(7));
      expect(mesh.faces, hasLength(6));
      for (final face in mesh.faces) {
        for (final index in face.outer.vertices) {
          expect(index, lessThan(mesh.vertices.length));
        }
      }
      // Грани, где была вершина 0, стали треугольниками.
      final affected = ['-x', '-y', '-z'];
      for (final key in affected) {
        expect(mesh.faceByKey(key)!.outer.vertices, hasLength(3), reason: key);
      }
      expect(mesh.faceByKey('+x')!.outer.vertices, hasLength(4));
    });

    test('удаление вершины треугольника убирает грань и чистит сеть', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(1, 0, 0),
          vm.Vector3(0, 1, 0),
        ],
        faces: [PolyFace.triangle(key: 't', a: 0, b: 1, c: 2)],
      );
      mesh.deleteVertices([1]);
      expect(mesh.faces, isEmpty);
      expect(mesh.vertices, isEmpty);
    });
  });

  group('PolyMesh: удаление граней и компакт', () {
    test('deleteFaces удаляет грань и неиспользуемые вершины', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(1, 0, 0),
          vm.Vector3(0, 1, 0),
          vm.Vector3(5, 5, 5), // используется только второй гранью
          vm.Vector3(6, 5, 5),
          vm.Vector3(5, 6, 5),
        ],
        faces: [
          PolyFace.triangle(key: 'a', a: 0, b: 1, c: 2),
          PolyFace.triangle(key: 'b', a: 3, b: 4, c: 5),
        ],
      );
      mesh.deleteFaces(['b']);
      expect(mesh.faces.map((f) => f.key), ['a']);
      expect(mesh.vertices, hasLength(3));
      expect(mesh.faceByKey('a')!.outer.vertices, [0, 1, 2]);
    });

    test('verticesOfFaces собирает внешние контуры и дырки', () {
      final mesh = _quad();
      expect(mesh.verticesOfFaces(['+y']), {0, 1, 2, 3, 4, 5, 6, 7});
      expect(mesh.verticesOfFaces(['+y', 'nope']), {0, 1, 2, 3, 4, 5, 6, 7});
    });
  });
}
