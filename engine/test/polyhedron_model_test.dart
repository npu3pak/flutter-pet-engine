import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart';
import 'package:vector_math/vector_math.dart' as vm;

PolyMesh _tetra() => PolyMesh(
      vertices: [
        vm.Vector3(0, 0, 0),
        vm.Vector3(1, 0, 0),
        vm.Vector3(0.5, 0, 1),
        vm.Vector3(0.5, 1, 0.5),
      ],
      faces: [
        PolyFace(
          key: 'bottom',
          outer: PolyLoop(vertices: [0, 1, 2], uvs: [
            vm.Vector2(0, 0),
            vm.Vector2(1, 0),
            vm.Vector2(0.5, 1),
          ]),
        ),
        PolyFace(key: 'a', outer: PolyLoop(vertices: [0, 1, 3])),
        PolyFace(key: 'b', outer: PolyLoop(vertices: [1, 2, 3])),
        PolyFace(
          key: 'c',
          outer: PolyLoop(vertices: [2, 0, 3]),
          holes: [
            PolyLoop(vertices: [0, 2, 3]),
          ],
        ),
      ],
    );

void main() {
  group('ModelObject: вид polyhedron', () {
    test('сериализация/разбор без потерь (сеть, UV, дырки, масштаб)', () {
      final obj = ModelObject(
        id: 'o1',
        name: 'mesh',
        kind: polyhedronKind,
        x: 1.25,
        y: 2,
        z: -3.5,
        rotY: 30,
        scaleX: 1.5,
        scaleY: 2,
        scaleZ: 0.75,
        mesh: _tetra(),
        material: ModelMaterial(type: MaterialType.texture, key: 'a.png'),
        faces: {
          'bottom': ModelMaterial(color: [10, 20, 30]),
        },
      );
      final json = jsonDecode(jsonEncode(obj.toJson()));
      final back = ModelObject.fromJson(json);
      expect(back.kind, polyhedronKind);
      expect(back.isPolyhedron, isTrue);
      expect(back.scaleX, 1.5);
      expect(back.scaleY, 2);
      expect(back.scaleZ, 0.75);
      expect(back.mesh!.faces.map((f) => f.key), ['bottom', 'a', 'b', 'c']);
      expect(back.mesh!.faces.last.holes, hasLength(1));
      expect(back.mesh!.faces.first.outer.uvs, hasLength(3));
      expect(back.toJson(), obj.toJson());
    });

    test('равномерный масштаб пишется скаляром', () {
      final obj = ModelObject(
        id: 'o2',
        name: 'm',
        kind: polyhedronKind,
        scaleX: 2,
        scaleY: 2,
        scaleZ: 2,
        mesh: _tetra(),
      );
      expect(obj.toJson()['scale'], 2);
      final back = ModelObject.fromJson(obj.toJson());
      expect(back.scaleX, 2);
      expect(back.scaleY, 2);
      expect(back.scaleZ, 2);
    });

    test('facesOf отдаёт ключи граней', () {
      final obj = ModelObject(
        id: 'o3',
        name: 'm',
        kind: polyhedronKind,
        mesh: _tetra(),
      );
      expect(facesOf(obj), ['bottom', 'a', 'b', 'c']);
    });

    test('minCorner/maxCorner учитывают вершины и масштаб', () {
      final obj = ModelObject(
        id: 'o4',
        name: 'm',
        kind: polyhedronKind,
        x: 10,
        y: 5,
        z: -2,
        scaleX: 2,
        scaleY: 1,
        scaleZ: 1,
        mesh: _tetra(),
      );
      expect(obj.minCorner().$1, closeTo(10, 1e-9));
      expect(obj.minCorner().$2, closeTo(5, 1e-9));
      expect(obj.maxCorner().$1, closeTo(12, 1e-9));
      expect(obj.maxCorner().$2, closeTo(6, 1e-9));
    });

    test('copy глубоко копирует сеть и масштаб', () {
      final obj = ModelObject(
        id: 'o5',
        name: 'm',
        kind: polyhedronKind,
        scaleX: 3,
        mesh: _tetra(),
      );
      final copy = ModelObject.copy(obj);
      copy.mesh!.vertices[0].x = 99;
      copy.scaleX = 7;
      expect(obj.mesh!.vertices[0].x, 0);
      expect(obj.mesh!.faces.first.key, 'bottom');
      expect(identical(copy.mesh!.faces.first, obj.mesh!.faces.first), isFalse);
      expect(obj.scaleX, 3);
    });

    test('битая ссылка на вершину отбрасывается при загрузке', () {
      final obj = ModelObject.fromJson({
        'id': 'o6',
        'name': 'm',
        'kind': polyhedronKind,
        'mesh': {
          'verts': [
            [0, 0, 0],
            [1, 0, 0],
            [0, 1, 0],
          ],
          'faces': [
            {'k': 'ok', 'v': [0, 1, 2]},
            {'k': 'bad', 'v': [0, 1, 9]},
          ],
        },
      });
      expect(obj.mesh!.faces.map((f) => f.key), ['ok']);
    });

    test('старые виды не затронуты новыми полями', () {
      final old = ModelObject(
        id: 'o7',
        name: 'c',
        kind: 'cuboid',
        dims: {'w': 1, 'h': 2, 'd': 3},
      );
      expect(old.toJson().containsKey('mesh'), isFalse);
      expect(old.toJson().containsKey('scale'), isFalse);
      expect(ModelObject.copy(old).scaleX, 1);
    });
  });

  group('ModelSize: расширенные лимиты', () {
    test('старые границы читаются как раньше', () {
      final s = ModelSize.fromJson({'w': 64, 'l': 64, 'h': 32});
      expect([s.w, s.l, s.h], [64, 64, 32]);
      final zero = ModelSize.fromJson({'w': 0, 'l': -5, 'h': 0});
      expect([zero.w, zero.l, zero.h], [1, 1, 1]);
      final big = ModelSize.fromJson({'w': 4096, 'l': 2816, 'h': 400});
      expect([big.w, big.l, big.h], [4096, 2816, 400]);
    });
  });

  group('ModelData: polyhedron в документе', () {
    test('круг model_v1 с многогранником', () {
      final data = ModelData.fromJson(
        jsonEncode({
          'format': 'model_v1',
          'id': 'm',
          'name': 'm',
          'size': {'w': 10, 'l': 10, 'h': 5},
          'objects': [
            {
              'id': 'p',
              'name': 'p',
              'kind': polyhedronKind,
              'pos': [1, 0, 2],
              'scale': [1, 1, 0.5],
              'mesh': {
                'verts': [
                  [0, 0, 0],
                  [1, 0, 0],
                  [0, 1, 0],
                ],
                'faces': [
                  {
                    'k': 'top',
                    'v': [0, 1, 2],
                    'uv': [
                      [0, 0],
                      [1, 0],
                      [0, 1],
                    ],
                  },
                ],
              },
            },
          ],
        }),
        id: 'm',
      );
      final obj = data.objects.single;
      expect(obj.isPolyhedron, isTrue);
      expect(obj.scaleZ, 0.5);
      final json = jsonDecode(jsonEncode(data.toJson()));
      final back = ModelData.fromJson(jsonEncode(json), id: 'm');
      expect(back.toJson(), data.toJson());
    });
  });
}
