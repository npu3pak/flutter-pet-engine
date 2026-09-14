import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/features/polyhedra.dart';
import 'package:demo/src/features/polyhedra_all.dart';
import 'package:demo/src/features/polyhedra_common.dart';
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
    expect(polyhedraFeatures, hasLength(1));
    expect(validateFeatureCatalog(polyhedraFeatures), isEmpty);
    expect(polyhedraFeatures.single.id, 'polyhedra_all');
    expect(polyhedraFeatures.single.group, 'Многогранники');
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
}
