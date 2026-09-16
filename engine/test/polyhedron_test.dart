import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/src/scene/polyhedron.dart';
import 'package:vector_math/vector_math.dart' as vm;

double _triangleArea(vm.Vector2 a, vm.Vector2 b, vm.Vector2 c) =>
    ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2;

double _totalArea(
  List<(int, int, int)> triangles,
  List<vm.Vector2> points,
) =>
    triangles.fold<double>(
      0,
      (sum, t) =>
          sum +
          _triangleArea(points[t.$1], points[t.$2], points[t.$3]),
    );

void main() {
  group('triangulateLoops', () {
    test('выпуклый квадрат даёт два CCW треугольника', () {
      final points = [
        vm.Vector2(0, 0),
        vm.Vector2(1, 0),
        vm.Vector2(1, 1),
        vm.Vector2(0, 1),
      ];
      final tris = triangulateLoops(
        outer: [0, 1, 2, 3],
        holes: const [],
        project: (i) => points[i],
      );
      expect(tris, hasLength(2));
      expect(_totalArea(tris, points), closeTo(1, 1e-9));
      for (final t in tris) {
        expect(
          _triangleArea(points[t.$1], points[t.$2], points[t.$3]),
          greaterThan(0),
        );
      }
    });

    test('вогнутый L-контур триангулируется без дырок в площади', () {
      final points = [
        vm.Vector2(0, 0),
        vm.Vector2(3, 0),
        vm.Vector2(3, 1),
        vm.Vector2(1, 1),
        vm.Vector2(1, 3),
        vm.Vector2(0, 3),
      ];
      final tris = triangulateLoops(
        outer: [0, 1, 2, 3, 4, 5],
        holes: const [],
        project: (i) => points[i],
      );
      expect(tris, hasLength(4));
      final area = _totalArea(tris, points);
      expect(area, closeTo(5, 1e-9));
    });

    test('дырка вычитается из площади, треугольники не заходят внутрь', () {
      final points = [
        // outer 4×4 CCW
        vm.Vector2(0, 0),
        vm.Vector2(4, 0),
        vm.Vector2(4, 4),
        vm.Vector2(0, 4),
        // hole 2×2 (CW, как принято)
        vm.Vector2(1, 1),
        vm.Vector2(1, 3),
        vm.Vector2(3, 3),
        vm.Vector2(3, 1),
      ];
      final tris = triangulateLoops(
        outer: [0, 1, 2, 3],
        holes: [
          [4, 5, 6, 7],
        ],
        project: (i) => points[i],
      );
      expect(tris, isNotEmpty);
      expect(_totalArea(tris, points), closeTo(12, 1e-9));
      // Центроид ни одного треугольника не должен лежать строго внутри
      // дырки (0..1..3 в квадрате 1..3).
      for (final t in tris) {
        final a = points[t.$1], b = points[t.$2], c = points[t.$3];
        final cx = (a.x + b.x + c.x) / 3;
        final cy = (a.y + b.y + c.y) / 3;
        final insideHole = cx > 1.001 &&
            cx < 2.999 &&
            cy > 1.001 &&
            cy < 2.999;
        expect(insideHole, isFalse, reason: 'треугольник $t внутри дырки');
      }
    });

    test('ориентация внешнего и внутреннего контуров не важна', () {
      final points = [
        vm.Vector2(0, 0),
        vm.Vector2(4, 0),
        vm.Vector2(4, 4),
        vm.Vector2(0, 4),
        vm.Vector2(1, 1),
        vm.Vector2(3, 1),
        vm.Vector2(3, 3),
        vm.Vector2(1, 3),
      ];
      final tris = triangulateLoops(
        // outer CW, hole CCW — обе ориентации «наоборот».
        outer: [3, 2, 1, 0],
        holes: [
          [4, 5, 6, 7],
        ],
        project: (i) => points[i],
      );
      expect(_totalArea(tris, points).abs(), closeTo(12, 1e-9));
    });

    test('вырожденный контур даёт пустой результат, без зависаний', () {
      final points = [
        vm.Vector2(0, 0),
        vm.Vector2(1, 0),
        vm.Vector2(2, 0),
      ];
      final tris = triangulateLoops(
        outer: [0, 1, 2],
        holes: const [],
        project: (i) => points[i],
      );
      expect(tris, isEmpty);
    });

    test('дубликаты и замыкание контура очищаются', () {
      final points = [
        vm.Vector2(0, 0),
        vm.Vector2(1, 0),
        vm.Vector2(1, 1),
        vm.Vector2(0, 1),
      ];
      final tris = triangulateLoops(
        outer: [0, 1, 1, 2, 3, 0],
        holes: const [],
        project: (i) => points[i],
      );
      expect(tris, hasLength(2));
      expect(_totalArea(tris, points), closeTo(1, 1e-9));
    });
  });

  group('PolyMesh: нормали, базис, площадь', () {
    PolyMesh square() => PolyMesh(
          vertices: [
            vm.Vector3(0, 0, 0),
            vm.Vector3(1, 0, 0),
            vm.Vector3(1, 1, 0),
            vm.Vector3(0, 1, 0),
          ],
          faces: [
            PolyFace(key: '+z', outer: PolyLoop(vertices: [0, 1, 2, 3])),
          ],
        );

    test('Newell-нормаль CCW-контура смотрит наружу', () {
      final mesh = square();
      final n = polyFaceNormal(mesh, mesh.faces.first);
      expect(n.x, closeTo(0, 1e-9));
      expect(n.y, closeTo(0, 1e-9));
      // Newell не нормирован: длина = 2 × площадь (квадрат 1×1 → 2).
      expect(n.z, closeTo(2, 1e-9));
    });

    test('базис правый: cross(u, v) = нормаль', () {
      final (u, v) = polyFaceBasis(vm.Vector3(0, 0, 1));
      final cross = u.cross(v);
      expect(cross.x, closeTo(0, 1e-9));
      expect(cross.y, closeTo(0, 1e-9));
      expect(cross.z, closeTo(1, 1e-9));
    });

    test('площадь грани с дыркой', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(4, 0, 0),
          vm.Vector3(4, 4, 0),
          vm.Vector3(0, 4, 0),
          vm.Vector3(1, 1, 0),
          vm.Vector3(1, 3, 0),
          vm.Vector3(3, 3, 0),
          vm.Vector3(3, 1, 0),
        ],
        faces: [
          PolyFace(
            key: 'top',
            outer: PolyLoop(vertices: [0, 1, 2, 3]),
            holes: [PolyLoop(vertices: [4, 5, 6, 7])],
          ),
        ],
      );
      expect(polyFaceArea(mesh, mesh.faces.first), closeTo(12, 1e-9));
      final tris = triangulatePolyFace(mesh, mesh.faces.first);
      var area = 0.0;
      for (final t in tris) {
        final a = mesh.vertices[t.$1];
        final b = mesh.vertices[t.$2];
        final c = mesh.vertices[t.$3];
        area += (b - a).cross(c - a).length / 2;
      }
      expect(area, closeTo(12, 1e-9));
    });

    test('vertexBounds считает AABB', () {
      final mesh = square();
      final (min, max) = mesh.vertexBounds!;
      expect(min, vm.Vector3(0, 0, 0));
      expect(max, vm.Vector3(1, 1, 0));
    });
  });

  group('PolyMesh: удобные конструкторы', () {
    test('PolyFace.triangle/quad создают контуры и UV', () {
      final triangle = PolyFace.triangle(
        key: 't',
        a: 0,
        b: 1,
        c: 2,
        uvs: [vm.Vector2(0, 0), vm.Vector2(1, 0), vm.Vector2(0, 1)],
      );
      expect(triangle.outer.vertices, [0, 1, 2]);
      expect(triangle.outer.hasUvs, isTrue);
      final quad = PolyFace.quad(key: 'q', a: 3, b: 2, c: 1, d: 0);
      expect(quad.outer.vertices, [3, 2, 1, 0]);
      expect(quad.outer.hasUvs, isFalse);
    });

    test('PolyMesh.box: 8 вершин, 6 граней, нормали наружу', () {
      final box = PolyMesh.box(w: 2, h: 3, d: 4);
      expect(box.vertices, hasLength(8));
      expect(box.faces.map((f) => f.key).toSet(),
          {'+x', '-x', '+y', '-y', '+z', '-z'});
      final expected = {
        '+x': vm.Vector3(1, 0, 0),
        '-x': vm.Vector3(-1, 0, 0),
        '+y': vm.Vector3(0, 1, 0),
        '-y': vm.Vector3(0, -1, 0),
        '+z': vm.Vector3(0, 0, 1),
        '-z': vm.Vector3(0, 0, -1),
      };
      for (final face in box.faces) {
        final n = polyFaceNormal(box, face).normalized();
        expect(n.dot(expected[face.key]!), closeTo(1, 1e-9),
            reason: face.key);
      }
      final back = PolyMesh.fromJson(box.toJson());
      expect(back.toJson(), box.toJson());
    });
  });

  group('PolyMesh: JSON и sanitize', () {
    test('полный круг с UV и дырками сохраняется без потерь', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(4, 0, 0),
          vm.Vector3(4, 0, 4),
          vm.Vector3(0, 0, 4),
          vm.Vector3(1, 0, 1),
          vm.Vector3(1, 0, 3),
          vm.Vector3(3, 0, 3),
          vm.Vector3(3, 0, 1),
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
                  vm.Vector2(0.25, 0.75),
                  vm.Vector2(0.75, 0.75),
                  vm.Vector2(0.75, 0.25),
                ],
              ),
            ],
          ),
        ],
      );
      final json = jsonDecode(jsonEncode(mesh.toJson()));
      final back = PolyMesh.fromJson(json);
      expect(back.toJson(), mesh.toJson());
      expect(back.faces.first.outer.hasUvs, isTrue);
      expect(back.faces.first.holes.first.uvs[2], vm.Vector2(0.75, 0.75));
      expect(round6(0.12345678), 0.123457);
    });

    test('sanitize убирает битые грани и индексы', () {
      final mesh = PolyMesh.fromJson({
        'verts': [
          [0, 0, 0],
          [1, 0, 0],
          [1, 1, 0],
          [0, 1, 0],
        ],
        'faces': [
          {'k': 'ok', 'v': [0, 1, 2, 3]},
          {'k': 'bad_ref', 'v': [0, 1, 99]},
          {'k': 'short', 'v': [0, 1]},
          {
            'k': 'hole_ok',
            'v': [0, 1, 2, 3],
            'h': [
              {'v': [0, 99, 2]},
            ],
          },
        ],
      });
      expect(mesh.faces.map((f) => f.key), ['ok', 'hole_ok']);
      expect(mesh.faces.last.holes, isEmpty);
    });

    test('несовпадающие UV отключаются, а не ломают загрузку', () {
      final mesh = PolyMesh.fromJson({
        'verts': [
          [0, 0, 0],
          [1, 0, 0],
          [1, 1, 0],
        ],
        'faces': [
          {
            'k': 'f',
            'v': [0, 1, 2],
            'uv': [
              [0, 0],
              [1, 0],
            ],
          },
        ],
      });
      expect(mesh.faces.single.outer.hasUvs, isFalse);
    });
  });
}
