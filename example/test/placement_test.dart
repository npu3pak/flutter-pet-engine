import 'dart:math' as math;

import 'package:example/src/features/feature_registry.dart';
import 'package:example/src/features/placement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('каталог операций размещения: восемь фич в новой группе', () {
    expect(placementFeatures, hasLength(8));
    expect(validateFeatureCatalog(placementFeatures), isEmpty);
    expect(kFeatureGroups, contains('Операции размещения'));
    expect(placementFeatures.map((f) => f.group).toSet(), {
      'Операции размещения',
    });
  });

  test('прильнуть к грани: таблички стоят у всех шести граней', () {
    final data = buildPlacementSnapFaces();
    for (var i = 0; i < placementFaces.length; i++) {
      final target = data.objectById('target_$i')!;
      final plate = data.objectById('plate_$i')!;
      final normal = faceNormalAt(target, placementFaces[i], billboardYaw: 0)!;
      final along = (objectCenter(plate) - objectCenter(target)).dot(normal);
      expect(along, greaterThan(0.5), reason: placementFaces[i]);
      // Табличка развёрнута по нормали грани.
      final axis = objectRotation(plate).transform3(vm.Vector3(0, 1, 0));
      expect(axis.dot(normal), closeTo(1, 1e-6), reason: placementFaces[i]);
    }
  });

  test('прильнуть к цилиндру: бок на радиусе, торцы на дисках', () {
    final data = buildPlacementSnapCylinder();
    final cylinder = data.objectById('cylinder')!;
    for (var i = 0; i < 4; i++) {
      final center = objectCenter(data.objectById('side_$i')!);
      final radial = math.sqrt(
        math.pow(center.x - cylinder.x, 2) + math.pow(center.z - cylinder.z, 2),
      );
      expect(radial, closeTo(0.8, 0.15), reason: 'бок $i');
    }
    final top = objectBounds(data.objectById('top')!);
    expect(top.$1.y, greaterThanOrEqualTo(cylinder.y + 1.6 - 1e-6));
    final bottom = objectBounds(data.objectById('bottom')!);
    expect(bottom.$2.y, lessThanOrEqualTo(cylinder.y + 1e-6));
  });

  test('параллельно грани: ось таблички совпадает с нормалью', () {
    final data = buildPlacementParallel();
    for (var i = 0; i < placementFaces.length; i++) {
      final face = placementFaces[i];
      final target = data.objectById('target_$i')!;
      final normal = faceNormalAt(target, face, billboardYaw: 0)!;
      final plate = data.objectById('plate_$i')!;
      final axis = objectRotation(plate).transform3(vm.Vector3(0, 1, 0));
      expect(axis.dot(normal), closeTo(1, 1e-6), reason: face);
      final beam = data.objectById('beam_$i')!;
      // Брусок стоит вертикально: длинная ось (локальная Z) — по мировой Y.
      final longAxis = objectRotation(beam).transform3(vm.Vector3(0, 0, 1));
      expect(longAxis.y.abs(), closeTo(1, 1e-6), reason: 'брусок $face');
      // На горизонтальных опорах брусок стоит на табличке, а не сквозь неё.
      if (face == '+y' || face == '-y') {
        final plateTop = objectBounds(plate).$2.y;
        final beamBottom = objectBounds(beam).$1.y;
        expect(
          beamBottom,
          greaterThanOrEqualTo(plateTop - 1e-6),
          reason: 'зазор $face',
        );
      }
    }
  });

  test('выровнять по осям: центры совпадают по выбранной оси', () {
    final data = buildPlacementAlign();
    final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
    for (var i = 0; i < axes.length; i++) {
      final base = objectCenter(data.objectById('base_$i')!);
      final after = objectCenter(data.objectById('after_$i')!);
      final value = switch (axes[i]) {
        LevelAxis.x => (base.x, after.x),
        LevelAxis.y => (base.y, after.y),
        LevelAxis.z => (base.z, after.z),
      };
      expect(value.$1, closeTo(value.$2, 1e-6), reason: 'ось $i');
    }
  });

  test('заполнить промежуток: заполнитель упирается в стойки', () {
    final data = buildPlacementFillGap();
    final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
    for (var i = 0; i < axes.length; i++) {
      final a = objectBounds(data.objectById('post_a_$i')!);
      final b = objectBounds(data.objectById('post_b_$i')!);
      final f = objectBounds(data.objectById('filler_$i')!);
      switch (axes[i]) {
        case LevelAxis.x:
          expect(f.$1.x, closeTo(math.min(a.$2.x, b.$2.x), 1e-6));
          expect(f.$2.x, closeTo(math.max(a.$1.x, b.$1.x), 1e-6));
        case LevelAxis.y:
          expect(f.$1.y, closeTo(math.min(a.$2.y, b.$2.y), 1e-6));
          expect(f.$2.y, closeTo(math.max(a.$1.y, b.$1.y), 1e-6));
        case LevelAxis.z:
          expect(f.$1.z, closeTo(math.min(a.$2.z, b.$2.z), 1e-6));
          expect(f.$2.z, closeTo(math.max(a.$1.z, b.$1.z), 1e-6));
      }
    }
  });

  test('накрыть: крышка по размеру площадки и на её верхней грани', () {
    final data = buildPlacementCover();
    for (var i = 0; i < 3; i++) {
      final pad = data.objectById('pad_$i')!;
      final coverBox = data.objectById('cover_$i')!;
      expect(coverBox.dim('w', 0), closeTo(pad.dim('w', 0), 1e-6));
      expect(coverBox.dim('d', 0), closeTo(pad.dim('d', 0), 1e-6));
      expect(coverBox.x, closeTo(pad.x, 1e-6));
      expect(coverBox.z, closeTo(pad.z, 1e-6));
      expect(coverBox.y, closeTo(pad.y + pad.dim('h', 0), 1e-6));
    }
  });

  test('отступить внутрь и наружу: размеры меняются симметрично', () {
    final data = buildPlacementInsetOutset();
    const amounts = [0.2, 0.5, 0.9];
    for (var i = 0; i < amounts.length; i++) {
      final inner = data.objectById('inner_$i')!;
      final base = data.objectById('base_$i')!;
      final outer = data.objectById('outer_$i')!;
      expect(inner.dim('w', 0), closeTo(2.0 - 2 * amounts[i], 1e-6));
      expect(outer.dim('w', 0), closeTo(2.0 + 2 * amounts[i], 1e-6));
      expect(inner.dim('d', 0), closeTo(2.0 - 2 * amounts[i], 1e-6));
      expect(outer.dim('d', 0), closeTo(2.0 + 2 * amounts[i], 1e-6));
      expect(inner.dim('w', 0), greaterThanOrEqualTo(0));
      // Концентрическая стопка: наружу снизу, основа, внутрь сверху — все
      // три копии видны в кадре.
      expect(outer.y, lessThan(base.y));
      expect(base.y, lessThan(inner.y));
      expect(outer.x, closeTo(inner.x, 1e-9));
      expect(outer.z, closeTo(inner.z, 1e-9));
    }
  });

  test('растянуть до: элемент дотягивается до ближней грани опоры', () {
    final data = buildPlacementStretch();
    final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
    for (var i = 0; i < axes.length; i++) {
      final post = objectBounds(data.objectById('post_$i')!);
      final element = objectBounds(data.objectById('element_$i')!);
      switch (axes[i]) {
        case LevelAxis.x:
          expect(element.$2.x, closeTo(post.$1.x, 1e-6));
        case LevelAxis.y:
          expect(element.$2.y, closeTo(post.$1.y, 1e-6));
        case LevelAxis.z:
          expect(element.$2.z, closeTo(post.$1.z, 1e-6));
      }
    }
  });
}
