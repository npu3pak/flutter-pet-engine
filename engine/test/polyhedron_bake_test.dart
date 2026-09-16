import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart';
import 'package:pet_engine/src/api/pick_geometry.dart';
import 'package:pet_engine/src/api/picking.dart' show intersectGeometry;
import 'package:pet_engine/src/scene/csg.dart';
import 'package:pet_engine/src/scene/polyhedron.dart';
import 'package:pet_engine/src/scene/polyhedron_bake.dart';
import 'package:pet_engine/src/scene/polyhedron_geometry.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelData _model({int w = 10, int l = 10, int h = 10}) => ModelData.fromJson(
      jsonEncode({
        'format': 'model_v1',
        'id': 'm',
        'name': 'm',
        'size': {'w': w, 'l': l, 'h': h},
        'objects': <Object>[],
      }),
      id: 'm',
    );

ModelObject _cuboid() => ModelObject(
      id: 'c',
      name: 'c',
      kind: 'cuboid',
      x: 1,
      y: 2,
      z: 3,
      rotY: 25,
      dims: {'w': 2, 'h': 3, 'd': 4},
    );

void main() {
  group('bakePolyhedron: примитивы', () {
    test('кубоид: 8 вершин, 6 граней, нормали наружу', () {
      final bake = bakePolyhedron(_model(), _cuboid())!;
      expect(bake.rotationBaked, isFalse);
      expect(bake.mesh.vertices, hasLength(8));
      expect(bake.mesh.faces.map((f) => f.key).toSet(),
          {'+x', '-x', '+y', '-y', '+z', '-z'});
      // Конверсия кубоида — это в точности удобный PolyMesh.box.
      expect(
        bake.mesh.toJson(),
        PolyMesh.box(w: 2, h: 3, d: 4).toJson(),
      );
      final expected = {
        '+x': vm.Vector3(1, 0, 0),
        '-x': vm.Vector3(-1, 0, 0),
        '+y': vm.Vector3(0, 1, 0),
        '-y': vm.Vector3(0, -1, 0),
        '+z': vm.Vector3(0, 0, 1),
        '-z': vm.Vector3(0, 0, -1),
      };
      for (final face in bake.mesh.faces) {
        final n = polyFaceNormal(bake.mesh, face).normalized();
        expect(n.dot(expected[face.key]!), closeTo(1, 1e-9),
            reason: face.key);
      }
    });

    test('трапеция: 8 вершин, все нормали наружу', () {
      final obj = ModelObject(
        id: 't',
        name: 't',
        kind: 'trapezoid',
        dims: {'bottomW': 2, 'bottomD': 4, 'topW': 1, 'topD': 2, 'h': 3},
      );
      final bake = bakePolyhedron(_model(), obj)!;
      expect(bake.mesh.vertices, hasLength(8));
      expect(bake.mesh.faces, hasLength(6));
      var centroid = vm.Vector3.zero();
      for (final v in bake.mesh.vertices) {
        centroid += v;
      }
      centroid /= bake.mesh.vertices.length.toDouble();
      for (final face in bake.mesh.faces) {
        final n = polyFaceNormal(bake.mesh, face).normalized();
        // Внешняя нормаль смотрит от внутренней точки наружу.
        expect(n.dot(_faceCenter(bake.mesh, face) - centroid),
            greaterThan(0),
            reason: face.key);
      }
    });

    test('цилиндр: сегментные грани и две крышки', () {
      final obj = ModelObject(
        id: 'cy',
        name: 'cy',
        kind: 'cylinder',
        dims: {'bottomR': 1, 'topR': 1, 'h': 2, 'segments': 8},
      );
      final bake = bakePolyhedron(_model(), obj)!;
      expect(bake.mesh.vertices, hasLength(16));
      final keys = bake.mesh.faces.map((f) => f.key).toList();
      expect(keys.where((k) => k.startsWith('side_')), hasLength(8));
      expect(keys, containsAll(['+y', '-y']));
      final side = bake.mesh.faces.firstWhere((f) => f.key == 'side_0');
      final n = polyFaceNormal(bake.mesh, side).normalized();
      final c = _faceCenter(bake.mesh, side);
      expect(n.dot(vm.Vector3(c.x, 0, c.z).normalized()), greaterThan(0.9));
      final top = bake.mesh.faces.firstWhere((f) => f.key == '+y');
      expect(polyFaceNormal(bake.mesh, top).normalized().y, closeTo(1, 1e-9));
      final bottom = bake.mesh.faces.firstWhere((f) => f.key == '-y');
      expect(polyFaceNormal(bake.mesh, bottom).normalized().y,
          closeTo(-1, 1e-9));
    });

    test('конус: вершина одна, верхней крышки нет', () {
      final obj = ModelObject(
        id: 'co',
        name: 'co',
        kind: 'cylinder',
        dims: {'bottomR': 1, 'topR': 0, 'h': 2, 'segments': 6},
      );
      final bake = bakePolyhedron(_model(), obj)!;
      expect(bake.mesh.vertices, hasLength(7));
      expect(bake.mesh.faces.where((f) => f.key == '+y'), isEmpty);
      final side = bake.mesh.faces.first;
      expect(side.outer.vertices, hasLength(3));
    });

    test('плоскость и спрайт: одна грань', () {
      final plane = ModelObject(
        id: 'p',
        name: 'p',
        kind: 'plane',
        dims: {'w': 2, 'd': 3, 'vertical': 0},
      );
      final bake = bakePolyhedron(_model(), plane)!;
      expect(bake.mesh.faces.single.key, '+y');
      expect(polyFaceNormal(bake.mesh, bake.mesh.faces.single).normalized().y,
          closeTo(1, 1e-9));

      final sprite = ModelObject(
        id: 's',
        name: 's',
        kind: 'sprite',
        dims: {'w': 2, 'h': 3},
      );
      final spriteBake = bakePolyhedron(_model(), sprite)!;
      expect(spriteBake.mesh.faces.single.key, '*');
      expect(
          polyFaceNormal(spriteBake.mesh, spriteBake.mesh.faces.single)
              .normalized()
              .z,
          closeTo(1, 1e-9));
    });

    test('material переносится на новые ключи сегментов', () {
      final mat = ModelMaterial(color: [1, 2, 3]);
      final obj = ModelObject(
        id: 'cy',
        name: 'cy',
        kind: 'cylinder',
        dims: {'bottomR': 1, 'topR': 0, 'h': 2, 'segments': 4},
        faces: {'side': mat, '+y': mat},
      );
      final bake = bakePolyhedron(_model(), obj)!;
      expect(bake.faces['side_0'], isNotNull);
      expect(bake.faces['side_3'], isNotNull);
      expect(bake.faces.containsKey('+y'), isFalse);
    });
  });

  group('bakePolyhedron: csg и скруглённый кубоид', () {
    test('csg difference: вершины совпадают с зеркальной выдачей рендера', () {
      final model = ModelData.fromJson(
        jsonEncode({
          'format': 'model_v1',
          'id': 'm',
          'name': 'm',
          'size': {'w': 10, 'l': 10, 'h': 10},
          'objects': [
            {
              'id': 'a',
              'name': 'a',
              'kind': 'cuboid',
              'pos': [0, 0, 0],
              'size': [4, 4, 4],
            },
            {
              'id': 'b',
              'name': 'b',
              'kind': 'cuboid',
              'pos': [0, 0, 0],
              'size': [2, 6, 2],
            },
            {
              'id': 'r',
              'name': 'r',
              'kind': 'csg',
              'op': 'difference',
              'operands': ['a', 'b'],
            },
          ],
        }),
        id: 'm',
      );
      final csg = model.objectById('r')!;
      final bake = bakePolyhedron(model, csg)!;
      expect(bake.rotationBaked, isTrue);
      expect(bake.mesh.faces, isNotEmpty);

      // Мир старого пути: (originX − x, y, z − originZ).
      const ox = 4.5, oz = 4.5;
      final expected = <String>{};
      for (final p in csgEvaluate(csg, model)) {
        for (final v in p.vertices) {
          expected.add('${round6(ox - v.x)},${round6(v.y)},${round6(v.z - oz)}');
        }
      }
      final actual = <String>{};
      final parts = buildObjectPickParts(model, csg);
      for (final part in parts) {
        final data = part.geometry.data;
        for (var i = 0; i + 2 < data.positions.length; i += 3) {
          actual.add(
            '${round6(data.positions[i])},'
            '${round6(data.positions[i + 1])},'
            '${round6(data.positions[i + 2])}',
          );
        }
      }
      expect(actual.difference(expected), isEmpty,
          reason: 'новые вершины не должны выходить за пределы CSG');
      expect(expected.difference(actual), isEmpty,
          reason: 'все вершины CSG должны присутствовать');
    });

    test('скруглённый кубоид: rotationBaked и материалы round', () {
      final mat = ModelMaterial(color: [9, 9, 9]);
      final obj = ModelObject(
        id: 'rb',
        name: 'rb',
        kind: 'cuboid',
        dims: {'w': 2, 'h': 2, 'd': 2, 'roundR': 0.3, 'roundSegments': 4},
        faces: {'round': mat},
      );
      final bake = bakePolyhedron(_model(), obj)!;
      expect(bake.rotationBaked, isTrue);
      expect(bake.mesh.faces, isNotEmpty);
      final roundKeys =
          bake.faces.keys.where((k) => k == 'round' || k.startsWith('round_'));
      expect(roundKeys, isNotEmpty);
    });
  });

  group('buildPolyFaceGeometry', () {
    test('явные UV используются как есть', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(4, 0, 0),
          vm.Vector3(0, 0, 4),
        ],
        faces: [
          PolyFace(
            key: '+y',
            outer: PolyLoop(
              vertices: [0, 1, 2],
              uvs: [
                vm.Vector2(0.1, 0.2),
                vm.Vector2(0.5, 0.2),
                vm.Vector2(0.1, 0.9),
              ],
            ),
          ),
        ],
      );
      final obj = ModelObject(
        id: 'p',
        name: 'p',
        kind: polyhedronKind,
        mesh: mesh,
      );
      final geometry = buildPolyFaceGeometry(obj, mesh, mesh.faces.single)!;
      final data = geometry.data;
      expect(data.texCoords, isNotNull);
      final coords = <(double, double)>{
        for (var i = 0; i + 1 < data.texCoords!.length; i += 2)
          (round6(data.texCoords![i]), round6(data.texCoords![i + 1])),
      };
      expect(coords, contains((0.1, 0.2)));
      expect(coords, contains((0.5, 0.2)));
      expect(coords, contains((0.1, 0.9)));
    });

    test('плоские UV нормируются и учитывают tile', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(0, 0, 0),
          vm.Vector3(4, 0, 0),
          vm.Vector3(4, 0, 4),
          vm.Vector3(0, 0, 4),
        ],
        faces: [
          PolyFace(key: '+y', outer: PolyLoop(vertices: [0, 1, 2, 3])),
        ],
      );
      final stretch = ModelObject(
        id: 'p',
        name: 'p',
        kind: polyhedronKind,
        mesh: mesh,
        material: ModelMaterial(stretch: 'stretch'),
      );
      final stretched =
          buildPolyFaceGeometry(stretch, mesh, mesh.faces.single)!;
      final coords = stretched.data.texCoords!;
      double maxCoord = 0;
      for (final c in coords) {
        if (c > maxCoord) maxCoord = c;
      }
      expect(maxCoord, closeTo(1, 1e-9));

      final tiled = ModelObject(
        id: 'p2',
        name: 'p2',
        kind: polyhedronKind,
        mesh: mesh,
        material: ModelMaterial(stretch: 'tile', tileScale: 1),
      );
      final tiledGeometry =
          buildPolyFaceGeometry(tiled, mesh, mesh.faces.single)!;
      double maxTiled = 0;
      for (final c in tiledGeometry.data.texCoords!) {
        if (c > maxTiled) maxTiled = c;
      }
      expect(maxTiled, closeTo(4, 1e-9));
    });

    test('дырка не перекрывается лучами пикинга', () {
      final mesh = PolyMesh(
        vertices: [
          vm.Vector3(-2, 0, -2),
          vm.Vector3(2, 0, -2),
          vm.Vector3(2, 0, 2),
          vm.Vector3(-2, 0, 2),
          vm.Vector3(-1, 0, -1),
          vm.Vector3(-1, 0, 1),
          vm.Vector3(1, 0, 1),
          vm.Vector3(1, 0, -1),
        ],
        faces: [
          PolyFace(
            key: 'top',
            outer: PolyLoop(vertices: [0, 1, 2, 3]),
            holes: [PolyLoop(vertices: [4, 5, 6, 7])],
          ),
        ],
      );
      final obj = ModelObject(
        id: 'h',
        name: 'h',
        kind: polyhedronKind,
        mesh: mesh,
      );
      final parts = buildObjectPickParts(_model(), obj);
      expect(parts, hasLength(1));
      final geometry = parts.single.geometry;
      // Мировая рамка модели 10×10: anchor = (4.5, 0, −4.5).
      // Луч вниз через центр дырки — промах.
      final throughHole = intersectGeometry(
        geometry,
        vm.Vector3(4.5, 5, -4.5),
        vm.Vector3(0, -1, 0),
      );
      expect(throughHole, isNull);
      // Луч вниз через материал — попадание.
      final throughSolid = intersectGeometry(
        geometry,
        vm.Vector3(6.1, 5, -4.5),
        vm.Vector3(0, -1, 0),
      );
      expect(throughSolid, isNotNull);
    });
  });

  group('faceLoops', () {
    test('возвращает внешний контур и дырки', () {
      final obj = ModelObject(
        id: 'f',
        name: 'f',
        kind: polyhedronKind,
        mesh: PolyMesh(
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
              key: 'top',
              outer: PolyLoop(vertices: [0, 1, 2, 3]),
              holes: [PolyLoop(vertices: [4, 5, 6, 7])],
            ),
          ],
        ),
      );
      final loops = _faceLoops(obj, 'top');
      expect(loops, hasLength(2));
      expect(loops[0], hasLength(4));
      expect(loops[1], hasLength(4));
    });
  });
}

List<List<vm.Vector3>> _faceLoops(ModelObject obj, String key) {
  final mesh = obj.mesh;
  final face = mesh?.faceByKey(key);
  if (mesh == null || face == null) return const [];
  List<vm.Vector3> loop(PolyLoop l) =>
      [for (final i in l.vertices) mesh.vertices[i]];
  return [loop(face.outer), for (final h in face.holes) loop(h)];
}

vm.Vector3 _faceCenter(PolyMesh mesh, PolyFace face) {
  var sum = vm.Vector3.zero();
  for (final i in face.outer.vertices) {
    sum += mesh.vertices[i];
  }
  return sum / face.outer.vertices.length.toDouble();
}
