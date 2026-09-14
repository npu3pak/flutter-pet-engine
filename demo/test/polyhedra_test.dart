import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/polyhedra.dart';
import 'package:demo/src/features/polyhedra_all.dart';
import 'package:demo/src/features/polyhedra_bake.dart';
import 'package:demo/src/features/polyhedra_common.dart';
import 'package:demo/src/features/polyhedra_map.dart';
import 'package:demo/src/features/polyhedra_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'test_helpers/test_app.dart';

FeatureBuildContext _buildContext() =>
    FeatureBuildContext(project: null, paths: testPaths());

/// Знаковый объём замкнутой сети: положительный, когда внешние контуры
/// граней обходятся наружу (нормали Ньюэлла смотрят из тела).
double _signedVolume(PolyMesh mesh) {
  var volume = 0.0;
  for (final face in mesh.faces) {
    for (final (a, b, c) in triangulatePolyFace(mesh, face)) {
      volume += mesh.vertices[a].dot(
            mesh.vertices[b].cross(mesh.vertices[c]),
          ) /
          6;
    }
  }
  return volume;
}

void main() {
  test('группа «Многогранники» собрана и проходит проверку', () {
    expect(polyhedraFeatures, hasLength(4));
    expect(validateFeatureCatalog(polyhedraFeatures), isEmpty);
    expect(
      polyhedraFeatures.map((f) => f.id),
      containsAll(const [
        'polyhedra_all',
        'polyhedra_bake',
        'polyhedra_map',
        'polyhedra_runtime',
      ]),
    );
    expect(polyhedraFeatures.first.group, 'Многогранники');
  });

  test('сцена сборки: четыре многогранника и подставка', () {
    final model = buildPolyhedraAllScene(_buildContext());
    expect(model.objectById('cube')!.kind, doc.polyhedronKind);
    expect(model.objectById('pyramid')!.kind, doc.polyhedronKind);
    expect(model.objectById('prism')!.kind, doc.polyhedronKind);
    expect(model.objectById('slab')!.kind, doc.polyhedronKind);
    expect(model.objectById('pedestal')!.kind, 'cuboid');

    expect(model.objectById('cube')!.mesh!.vertices, hasLength(8));
    expect(model.objectById('cube')!.mesh!.faces, hasLength(6));
    expect(model.objectById('pyramid')!.mesh!.vertices, hasLength(5));
    expect(model.objectById('pyramid')!.mesh!.faces, hasLength(5));
    expect(model.objectById('prism')!.mesh!.faces, hasLength(8));
  });

  test('плита: у верхней и нижней граней по одному отверстию', () {
    final model = buildPolyhedraAllScene(_buildContext());
    final mesh = model.objectById('slab')!.mesh!;
    final top = mesh.faceByKey('+y')!;
    final bottom = mesh.faceByKey('-y')!;
    expect(top.holes, hasLength(1));
    expect(bottom.holes, hasLength(1));
    expect(top.holes.single.vertices, hasLength(4));
    // Площадь верхней грани: 3×3 минус отверстие 1.4×1.4.
    expect(polyFaceArea(mesh, top), closeTo(9 - 1.96, 1e-4));
  });

  test('все замкнутые многогранники ориентированы наружу', () {
    final model = buildPolyhedraAllScene(_buildContext());
    for (final id in ['cube', 'pyramid', 'prism', 'slab']) {
      final mesh = model.objectById(id)!.mesh!;
      expect(_signedVolume(mesh), greaterThan(0),
          reason: '$id: грани должны смотреть наружу');
    }
  });

  test('материалы по граням переносятся в документ', () {
    final model = buildPolyhedraAllScene(_buildContext());
    final slab = model.objectById('slab')!;
    expect(slab.faces['+y']!.color, [96, 186, 112]); // зелёный верх
    expect(slab.faces['hole_0']!.color, [214, 76, 76]); // красные стенки
  });

  test('помощники сборки дают валидные замкнутые сети', () {
    final plate = plateWithHole(
      width: 2,
      depth: 2,
      thickness: 0.5,
      holeWidth: 0.5,
      holeDepth: 0.5,
    );
    expect(_signedVolume(plate), closeTo(2 * 2 * 0.5 - 0.5 * 0.5 * 0.5, 1e-9));
    final prism = extrudeProfile(
      profile: [vm.Vector2(0, 0), vm.Vector2(2, 0), vm.Vector2(2, 2)],
      height: 1.5,
    );
    expect(_signedVolume(prism), closeTo(2 * 2 / 2 * 1.5, 1e-9));
  });

  test('конверсия: у каждого оригинала есть многогранник', () {
    final model = buildPolyhedraBakeScene(_buildContext());
    for (final id in ['box', 'trap', 'cyl', 'cut']) {
      final poly = model.objectById('${id}_poly');
      expect(poly, isNotNull, reason: id);
      expect(poly!.kind, doc.polyhedronKind, reason: id);
      expect(poly.mesh, isNotNull, reason: id);
      expect(poly.mesh!.faces, isNotEmpty, reason: id);
    }
    expect(model.objectById('box_poly')!.mesh!.faces, hasLength(6));
    expect(
      model.objectById('cyl_poly')!
          .mesh!
          .faces
          .where((f) => f.key.startsWith('side_')),
      hasLength(16),
    );
  });

  test('конверсия сохраняет материалы граней и поворот', () {
    final model = buildPolyhedraBakeScene(_buildContext());
    expect(model.objectById('box_poly')!.faces['+y']!.color, [96, 186, 112]);
    expect(model.objectById('cyl_poly')!.faces['+y']!.color, [96, 186, 112]);
    expect(model.objectById('trap_poly')!.rotY, 15);
  });

  test('переключатель скрывает оригиналы, многогранники остаются', () {
    final model = buildPolyhedraBakeScene(
      FeatureBuildContext(
        project: null,
        paths: testPaths(),
        params: const {'showOriginals': false},
      ),
    );
    expect(model.objectById('box'), isNull);
    expect(model.objectById('cut'), isNull);
    expect(model.objectById('box_poly'), isNotNull);
    expect(model.objectById('cut_poly'), isNotNull);
  });

  test('карта: явные UV пола и стен на месте', () {
    final model = buildPolyhedraMapScene(_buildContext());
    final floor = model.objectById('floor')!.mesh!;
    final top = floor.faceByKey('+y')!;
    expect(top.outer.hasUvs, isTrue);
    for (var i = 0; i < top.outer.vertices.length; i++) {
      final vertex = floor.vertices[top.outer.vertices[i]];
      expect(top.outer.uvs[i].x, closeTo(vertex.x / 2, 1e-6));
      expect(top.outer.uvs[i].y, closeTo(vertex.z / 2, 1e-6));
    }
    final walls = model.objectById('walls')!.mesh!;
    expect(walls.faces, hasLength(6));
    for (final face in walls.faces) {
      expect(face.outer.hasUvs, isTrue, reason: face.key);
      expect(face.outer.uvs, hasLength(face.outer.vertices.length));
    }
  });

  test('стены карты смотрят внутрь комнаты', () {
    final walls = buildMapWalls(profile: mapRoomProfile, height: 2.2);
    final shell = extrudeProfile(profile: mapRoomProfile, height: 2.2);
    for (var i = 0; i < mapRoomProfile.length; i++) {
      final inward =
          polyFaceNormal(walls, walls.faceByKey('wall_$i')!).normalized();
      final outward =
          polyFaceNormal(shell, shell.faceByKey('side_$i')!).normalized();
      expect(inward.dot(outward), closeTo(-1, 1e-6), reason: 'wall_$i');
    }
  });

  test('колонна карты — замкнутый куб с цветным верхом', () {
    final model = buildPolyhedraMapScene(_buildContext());
    final pillar = model.objectById('pillar')!;
    expect(pillar.kind, doc.polyhedronKind);
    expect(pillar.mesh!.faces, hasLength(6));
    expect(pillar.faces['+y']!.color, [230, 150, 70]);
  });

  test('группа выросла до четырёх фич', () {
    expect(polyhedraFeatures, hasLength(4));
    expect(
      polyhedraFeatures.map((f) => f.id),
      contains('polyhedra_runtime'),
    );
  });

  test('runtime-куб: парты, переопределение грани и масштаб', () {
    final box = buildRuntimeBoxNode();
    expect(box.mesh.faces, hasLength(6));
    expect(box.pickParts, hasLength(6));
    final top = box.faceMaterial('+y');
    expect(identical(box.faceMaterial('+x'), box.material), isTrue);
    expect(identical(top, box.material), isFalse);
    box.setFaceMaterial('+y', null);
    expect(identical(box.faceMaterial('+y'), box.material), isTrue);
    box.scale = vm.Vector3(1, 2.5, 1);
    expect(box.scale.y, closeTo(2.5, 1e-9));
    box.dispose();
  });

  test('runtime-плита: отверстие и красные стенки', () {
    final slab = buildRuntimeSlabNode();
    final top = slab.mesh.faceByKey('+y')!;
    expect(top.holes, hasLength(1));
    for (final key in const ['hole_0', 'hole_1', 'hole_2', 'hole_3']) {
      expect(identical(slab.faceMaterial(key), slab.material), isFalse,
          reason: key);
    }
    slab.dispose();
  });

  test('сцена runtime: только площадка, узлы добавляет управление', () {
    final model = buildPolyhedraRuntimeScene(_buildContext());
    expect(model.objects, hasLength(1));
    expect(model.objects.single.kind, 'plane');
  });
}
