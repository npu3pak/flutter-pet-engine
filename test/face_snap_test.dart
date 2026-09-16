import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/face_snap.dart' show roundBoxLocalNormal;

ModelObject cuboid({
  double x = 0,
  double y = 0,
  double z = 0,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
}) =>
    ModelObject(
      id: 'c',
      name: 'c',
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      rotX: rotX,
      rotY: rotY,
      rotZ: rotZ,
      dims: {'w': 1.0, 'h': 1.0, 'd': 1.0},
    );

void _expectClose(vm.Vector3? a, vm.Vector3 b) {
  expect(a, isNotNull);
  expect(a!.x, closeTo(b.x, 1e-6), reason: 'x: $a vs $b');
  expect(a.y, closeTo(b.y, 1e-6), reason: 'y: $a vs $b');
  expect(a.z, closeTo(b.z, 1e-6), reason: 'z: $a vs $b');
}

void main() {
  group('faceNormalAt', () {
    test('cuboid axis-aligned faces', () {
      final o = cuboid();
      for (final (key, n) in [
        ('+x', vm.Vector3(1, 0, 0)),
        ('-x', vm.Vector3(-1, 0, 0)),
        ('+y', vm.Vector3(0, 1, 0)),
        ('-y', vm.Vector3(0, -1, 0)),
        ('+z', vm.Vector3(0, 0, 1)),
        ('-z', vm.Vector3(0, 0, -1)),
      ]) {
        _expectClose(faceNormalAt(o, key, billboardYaw: 0), n);
      }
    });

    test('faces rotate with the object (rotY=90, rotX=90)', () {
      final y = cuboid(rotY: 90);
      // Ry(90)·(1,0,0) = (0,0,−1).
      _expectClose(faceNormalAt(y, '+x', billboardYaw: 0), vm.Vector3(0, 0, -1));
      // Ry(90)·(0,0,1) = (1,0,0).
      _expectClose(faceNormalAt(y, '+z', billboardYaw: 0), vm.Vector3(1, 0, 0));
      final x = cuboid(rotX: 90);
      // Rx(90)·(0,1,0) = (0,0,1).
      _expectClose(faceNormalAt(x, '+y', billboardYaw: 0), vm.Vector3(0, 0, 1));
    });

    test('trapezoid slopes face outward (up and away)', () {
      final o = ModelObject(
        id: 't',
        name: 't',
        kind: 'trapezoid',
        dims: {'bottomW': 4.0, 'bottomD': 4.0, 'topW': 2.0, 'topD': 2.0, 'h': 1.0},
      );
      // The −z side leans inward going up; outward = up and back.
      _expectClose(
        faceNormalAt(o, '-z', billboardYaw: 0),
        vm.Vector3(0, 1 / math.sqrt(2), -1 / math.sqrt(2)),
      );
      _expectClose(
        faceNormalAt(o, '+z', billboardYaw: 0),
        vm.Vector3(0, 1 / math.sqrt(2), 1 / math.sqrt(2)),
      );
      // The bottom face stays down; the top face up.
      _expectClose(faceNormalAt(o, '-y', billboardYaw: 0), vm.Vector3(0, -1, 0));
      _expectClose(faceNormalAt(o, '+y', billboardYaw: 0), vm.Vector3(0, 1, 0));
    });

    test('cylinder side: the normal follows the click angle (rendered frame)',
        () {
      final o = ModelObject(
        id: 'y',
        name: 'y',
        kind: 'cylinder',
        dims: {'bottomR': 0.5, 'topR': 0.5, 'h': 1.0},
      );
      // The click is in the RENDERED frame: the visual +x surface of the
      // cylinder sits at the MODEL's −x side (the cellWorld mirror), so a
      // click at model +0.5 is the visual −x side → outward (−1,0,0).
      _expectClose(
        faceNormalAt(o, 'side', clickLocal: vm.Vector3(0.5, 0.3, 0), billboardYaw: 0),
        vm.Vector3(-1, 0, 0),
      );
      // z is not mirrored: model +0.5 in z = the visual +z side.
      _expectClose(
        faceNormalAt(o, 'side', clickLocal: vm.Vector3(0, 0.3, 0.5), billboardYaw: 0),
        vm.Vector3(0, 0, 1),
      );
      // The visual −x/−z corner: the model normal flips its x (+x, −z).
      _expectClose(
        faceNormalAt(o, 'side', clickLocal: vm.Vector3(-0.35, 0.3, -0.35), billboardYaw: 0),
        vm.Vector3(1 / math.sqrt(2), 0, -1 / math.sqrt(2)),
      );
    });

    test('cone side tilts up-outward', () {
      final o = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cylinder',
        dims: {'bottomR': 0.5, 'topR': 0.0, 'h': 1.0},
      );
      // Click at model +0.5 = the visual −x side (mirrored frame): the
      // outward normal = (−1, 0.5) normalized — up and to the visual −x.
      final n = faceNormalAt(o, 'side', clickLocal: vm.Vector3(0.5, 0, 0), billboardYaw: 0)!;
      final expected = vm.Vector3(-1, 0.5, 0).normalized();
      _expectClose(n, expected);
    });

    test('cylinder geometry rotates with the object (rotX=90)', () {
      final o = ModelObject(
        id: 'y',
        name: 'y',
        kind: 'cylinder',
        rotX: 90,
        dims: {'bottomR': 0.25, 'topR': 0.25, 'h': 1.0},
      );
      // Rx(90) maps (0, ±1, 0) → (0, 0, ±1): the caps face along Z now.
      _expectClose(faceNormalAt(o, '+y', billboardYaw: 0), vm.Vector3(0, 0, 1));
      _expectClose(faceNormalAt(o, '-y', billboardYaw: 0), vm.Vector3(0, 0, -1));
      // Cap centers rotate with the object: anchor + Rx(90)·(0, h, 0).
      _expectClose(faceCenterAt(o, '+y', billboardYaw: 0), vm.Vector3(0, 0, 1));
      _expectClose(faceCenterAt(o, '-y', billboardYaw: 0), vm.Vector3(0, 0, 0));
      // Side: the click (0, −0.25, 0.4) is object-local (0, 0.4, 0.25) —
      // on the surface at θ = π/2. Normal (0,0,1) local → world (0,−1,0).
      _expectClose(
        faceNormalAt(o, 'side', clickLocal: vm.Vector3(0, -0.25, 0.4), billboardYaw: 0),
        vm.Vector3(0, -1, 0),
      );
      // Side center: local (0.25·cos π/2, 0.5, 0.25·sin π/2) → world (0,−0.25,0.5).
      _expectClose(
        faceCenterAt(o, 'side', clickLocal: vm.Vector3(0, -0.25, 0.4), billboardYaw: 0),
        vm.Vector3(0, -0.25, 0.5),
      );
    });

    test('cylinder caps and plane/sprite faces', () {
      final cyl = ModelObject(
        id: 'y',
        name: 'y',
        kind: 'cylinder',
        dims: {'bottomR': 0.5, 'topR': 0.5, 'h': 1.0},
      );
      _expectClose(faceNormalAt(cyl, '+y', billboardYaw: 0), vm.Vector3(0, 1, 0));
      _expectClose(faceNormalAt(cyl, '-y', billboardYaw: 0), vm.Vector3(0, -1, 0));

      final vertical = ModelObject(
        id: 'p',
        name: 'p',
        kind: 'plane',
        dims: {'w': 1.0, 'd': 1.0, 'vertical': 1},
      );
      _expectClose(faceNormalAt(vertical, '+z', billboardYaw: 0), vm.Vector3(0, 0, 1));
      final flat = ModelObject(id: 'p', name: 'p', kind: 'plane', dims: {'w': 1.0, 'd': 1.0});
      _expectClose(faceNormalAt(flat, '+y', billboardYaw: 0), vm.Vector3(0, 1, 0));

      final sprite = ModelObject(
        id: 's',
        name: 's',
        kind: 'sprite',
        dims: {'w': 1.0, 'h': 1.0},
      );
      _expectClose(faceNormalAt(sprite, '*', billboardYaw: 0), vm.Vector3(0, 0, 1));
      // Billboards mirror through −X: yaw 90° → (−1, 0, 0).
      _expectClose(faceNormalAt(sprite, '*', billboardYaw: math.pi / 2), vm.Vector3(-1, 0, 0));
    });
  });

  group('faceCenterAt', () {
    test('flat faces: the quad center (rendered frame)', () {
      final o = cuboid(x: 1, y: 2, z: 3);
      _expectClose(faceCenterAt(o, '+z', billboardYaw: 0), vm.Vector3(1, 2.5, 3.5));
      _expectClose(faceCenterAt(o, '+y', billboardYaw: 0), vm.Vector3(1, 3, 3));
      // rotY=90 rotates the center: local (0, 0.5, 0.5) → model (1.5, 2.5, 3)
      // — the RENDERED (visual) center mirrors X through the anchor:
      // x' = 2·1 − 1.5 = 0.5 (the cellWorld quirk: chunkWorld(anchor)+local).
      final r = cuboid(x: 1, y: 2, z: 3, rotY: 90);
      _expectClose(faceCenterAt(r, '+z', billboardYaw: 0), vm.Vector3(0.5, 2.5, 3));
      // The model-frame center would land on the OPPOSITE face.
      expect(faceCenterAt(r, '+z', billboardYaw: 0)!.x, isNot(closeTo(1.5, 1e-9)));
    });

    test('cylinder caps: disc centers; side: the mid-height ring point', () {
      final o = ModelObject(
        id: 'y',
        name: 'y',
        kind: 'cylinder',
        x: 1,
        y: 2,
        z: 3,
        dims: {'bottomR': 0.5, 'topR': 0.5, 'h': 1.0},
      );
      _expectClose(faceCenterAt(o, '+y', billboardYaw: 0), vm.Vector3(1, 3, 3));
      _expectClose(faceCenterAt(o, '-y', billboardYaw: 0), vm.Vector3(1, 2, 3));
      // The side center is the surface point at the click angle and
      // MID-HEIGHT (the face spans the whole side, like the painting
      // outline) — not the click point itself.
      _expectClose(
        faceCenterAt(o, 'side', clickLocal: vm.Vector3(1.5, 2.1, 3), billboardYaw: 0),
        vm.Vector3(1.5, 2.5, 3),
      );
      _expectClose(
        faceCenterAt(o, 'side', clickLocal: vm.Vector3(1, 2.9, 3.5), billboardYaw: 0),
        vm.Vector3(1, 2.5, 3.5),
      );
    });

    test('cone side center uses the mid radius', () {
      final o = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cylinder',
        dims: {'bottomR': 0.5, 'topR': 0.0, 'h': 1.0},
      );
      // θ = 0: mid radius (0.5+0)/2 = 0.25, mid height 0.5.
      _expectClose(
        faceCenterAt(o, 'side', clickLocal: vm.Vector3(0.5, 0.1, 0), billboardYaw: 0),
        vm.Vector3(0.25, 0.5, 0),
      );
    });

    test('regression: a cone picked instead of the cube face misses the cube',
        () {
      // The user's failing model (model_2 «Тестирование прикрепления к
      // граням»): cube 1×1×1 at (1,0,0), the cone rotated parallel to the
      // cube's −x face (rotY 90, rotZ 90) with its base ON the face at
      // (0.5, 0.5, 0) — the intended target of «Перенести к грани» is the
      // cube's −x face center. The centers are in the RENDERED frame (the
      // visual mirror): the VISUAL −x face sits at the model's +x side.
      final cube = ModelObject(
        id: 'obj_2',
        name: 'cuboid',
        kind: 'cuboid',
        x: 1,
        y: 0,
        z: 0,
        dims: {'w': 1.0, 'h': 1.0, 'd': 1.0},
      );
      final cone = ModelObject(
        id: 'obj_8',
        name: 'cone',
        kind: 'cylinder',
        x: 0.5,
        y: 0.5,
        z: 0,
        rotY: 90,
        rotZ: 90,
        dims: {'bottomR': 0.25, 'topR': 0.0, 'h': 1.0},
      );
      // The correct face center (what the user intended): the cube spans
      // [0.5, 1.5], its VISUAL −x face at the model's +x side → (1.5, 0.5, 0).
      _expectClose(faceCenterAt(cube, '-x', billboardYaw: 0), vm.Vector3(1.5, 0.5, 0));
      // But a click swallowed by the CONE (it lies on the face and blocks
      // the raycast) computes the cone's OWN mid point: x = 1.0 — inside
      // the cube, off the face — the «провалился внутрь куба» symptom. The
      // x deviation is θ-independent, so the test is robust.
      final mid = faceCenterAt(
        cone,
        'side',
        clickLocal: vm.Vector3(0.5, 0.5, 0.1),
        billboardYaw: 0,
      )!;
      expect(mid.x, closeTo(1.0, 1e-9));
      expect((mid.x - 1.5).abs(), greaterThan(0.4));
      expect(mid.y, closeTo(0.5, 0.13));
    });
  });

  group('parallelToFaceAngles', () {
    test('window (plane) on a cylinder side: rotY only', () {
      final window = ModelObject(
        id: 'w',
        name: 'w',
        kind: 'plane',
        dims: {'w': 1.0, 'd': 1.0, 'vertical': 1},
      );
      // Cylinder side at θ=0: normal (1,0,0) → +Z must point along +X.
      final (rx, ry, rz) = parallelToFaceAngles(window, vm.Vector3(1, 0, 0));
      expect(rx, closeTo(0, 1e-6));
      expect(ry, closeTo(90, 1e-6));
      expect(rz, closeTo(0, 1e-6));
    });

    test('roof slab (cuboid) on a trapezoid slope: tilted about X', () {
      final slab = cuboid();
      final n = vm.Vector3(0, 1 / math.sqrt(2), -1 / math.sqrt(2));
      final (rx, ry, rz) = parallelToFaceAngles(slab, n);
      expect(rx, closeTo(-45, 1e-6));
      expect(ry, closeTo(0, 1e-6));
      expect(rz, closeTo(0, 1e-6));
      // The slab's +Y lands on the slope normal.
      final m = vm.Matrix4.rotationZ(rz * math.pi / 180) *
          vm.Matrix4.rotationX(rx * math.pi / 180) *
          vm.Matrix4.rotationY(ry * math.pi / 180);
      _expectClose(m.transform3(vm.Vector3(0, 1, 0)), n);
    });

    test('horizontal face keeps the yaw (solids and sheets)', () {
      final slab = cuboid(rotY: 45);
      final (rx, ry, rz) = parallelToFaceAngles(slab, vm.Vector3(0, 1, 0));
      expect(rx, closeTo(0, 1e-6));
      expect(ry, closeTo(45, 1e-6)); // the yaw is preserved
      expect(rz, closeTo(0, 1e-6));

      final window = ModelObject(
        id: 'w',
        name: 'w',
        kind: 'plane',
        rotY: 30,
        dims: {'w': 1.0, 'd': 1.0, 'vertical': 1},
      );
      final (rx2, ry2, rz2) = parallelToFaceAngles(window, vm.Vector3(0, 1, 0));
      expect(rx2, closeTo(-90, 1e-6)); // +Z → +Y
      expect(ry2, closeTo(30, 1e-6));
      expect(rz2, closeTo(0, 1e-6));
    });

    test('solid on a vertical +x face tilts about Z', () {
      final (rx, ry, rz) = parallelToFaceAngles(cuboid(), vm.Vector3(1, 0, 0));
      expect(rx, closeTo(0, 1e-6));
      expect(ry, closeTo(-90, 1e-6));
      expect(rz, closeTo(-90, 1e-6));
      final m = vm.Matrix4.rotationZ(rz * math.pi / 180) *
          vm.Matrix4.rotationX(rx * math.pi / 180) *
          vm.Matrix4.rotationY(ry * math.pi / 180);
      _expectClose(m.transform3(vm.Vector3(0, 1, 0)), vm.Vector3(1, 0, 0));
    });

    test('gimbal: solid on a +z face tilts about X and keeps the yaw', () {
      final (rx, ry, rz) = parallelToFaceAngles(cuboid(rotY: 20), vm.Vector3(0, 0, 1));
      expect(rx, closeTo(90, 1e-6));
      expect(ry, closeTo(20, 1e-6));
      expect(rz, closeTo(0, 1e-6));
      final m = vm.Matrix4.rotationZ(rz * math.pi / 180) *
          vm.Matrix4.rotationX(rx * math.pi / 180) *
          vm.Matrix4.rotationY(ry * math.pi / 180);
      _expectClose(m.transform3(vm.Vector3(0, 1, 0)), vm.Vector3(0, 0, 1));
    });

    test('the primary axis always lands on the normal (roundtrip)', () {
      // A sweep of normals: the solid's +Y and the sheet's +Z must map to n.
      for (final n in [
        vm.Vector3(0, 1, 0),
        vm.Vector3(0, -1, 0),
        vm.Vector3(1, 0, 0),
        vm.Vector3(-1, 0, 0),
        vm.Vector3(0, 0, 1),
        vm.Vector3(0, 0, -1),
        vm.Vector3(0, 1 / math.sqrt(2), 1 / math.sqrt(2)),
        vm.Vector3(1 / math.sqrt(3), 1 / math.sqrt(3), 1 / math.sqrt(3)),
        vm.Vector3(-1 / math.sqrt(2), 1 / math.sqrt(2), 0),
      ]) {
        final (rx, ry, rz) = parallelToFaceAngles(cuboid(), n);
        final m = vm.Matrix4.rotationZ(rz * math.pi / 180) *
            vm.Matrix4.rotationX(rx * math.pi / 180) *
            vm.Matrix4.rotationY(ry * math.pi / 180);
        _expectClose(m.transform3(vm.Vector3(0, 1, 0)), n);

        final sheet = ModelObject(
          id: 's',
          name: 's',
          kind: 'plane',
          dims: {'w': 1.0, 'd': 1.0, 'vertical': 1},
        );
        final (sx, sy, sz) = parallelToFaceAngles(sheet, n);
        final ms = vm.Matrix4.rotationZ(sz * math.pi / 180) *
            vm.Matrix4.rotationX(sx * math.pi / 180) *
            vm.Matrix4.rotationY(sy * math.pi / 180);
        _expectClose(ms.transform3(vm.Vector3(0, 0, 1)), n);
      }
    });
  });

  group('скруглённый кубоид (round)', () {
    ModelObject round() => ModelObject(
          id: 'r',
          name: 'r',
          kind: 'cuboid',
          x: 5,
          y: 0,
          z: 5,
          dims: {'w': 2.0, 'h': 2.0, 'd': 2.0, 'roundR': 0.2},
        );

    test('аналитическая нормаль в точке поверхности (без поворота)', () {
      final o = round();
      // Точка на плоской верхней грани.
      _expectClose(
          roundBoxLocalNormal(o, vm.Vector3(5.4, 2.0, 5.2)),
          vm.Vector3(0, 1, 0));
      // Точка на верхне-передней дуге (полосе): радиус наружу (y,z)-дуги.
      _expectClose(
          roundBoxLocalNormal(o, vm.Vector3(5.5, 1.8 + 0.2 * math.sqrt(0.5),
              5 + 0.8 + 0.2 * math.sqrt(0.5))),
          vm.Vector3(0, math.sqrt(0.5), math.sqrt(0.5)));
      // Точка на октанте верхнего переднего угла: диагональ (1,1,1).
      final apex = 0.2 / math.sqrt(3);
      _expectClose(
          roundBoxLocalNormal(
              o,
              vm.Vector3(5 + 0.8 + apex, 1.8 + apex, 5 + 0.8 + apex)),
          vm.Vector3(1 / math.sqrt(3), 1 / math.sqrt(3), 1 / math.sqrt(3)));
      // Низ.
      _expectClose(roundBoxLocalNormal(o, vm.Vector3(5.3, 0, 5.1)),
          vm.Vector3(0, -1, 0));
    });

    test('faceNormalAt(''round'') возвращает нормаль по клику', () {
      final o = round();
      final apex = 0.2 / math.sqrt(3);
      final n = faceNormalAt(o, roundFaceKey,
          clickLocal: vm.Vector3(5 + 0.8 + apex, 1.8 + apex, 5 + 0.8 + apex),
          billboardYaw: 0);
      _expectClose(
          n, vm.Vector3(1 / math.sqrt(3), 1 / math.sqrt(3), 1 / math.sqrt(3)));
      // Центр «грани» — сама точка клика (с зеркалом X).
      final c = faceCenterAt(o, roundFaceKey,
          clickLocal: vm.Vector3(5.5, 1.5, 5.5), billboardYaw: 0);
      _expectClose(c, vm.Vector3(2 * 5 - 5.5, 1.5, 5.5));
    });

    test('нормаль «round» следует за поворотом объекта', () {
      final o = ModelObject(
        id: 'r',
        name: 'r',
        kind: 'cuboid',
        x: 5,
        y: 0,
        z: 5,
        rotY: 90,
        dims: {'w': 2.0, 'h': 2.0, 'd': 2.0, 'roundR': 0.2},
      );
      // Локальная точка на верхне-передней дуге (внутреннее ребро + r·n0).
      final n0 = vm.Vector3(0, math.sqrt(0.5), math.sqrt(0.5));
      final p0 = vm.Vector3(0, 1.8, 0.8) + n0 * 0.2;
      final m = vm.Matrix4.rotationY(90 * math.pi / 180);
      final click = vm.Vector3(5, 0, 5) + m.transform3(p0);
      // Объект-локальная нормаль от точки не зависит от поворота...
      final localN = roundBoxLocalNormal(o, click);
      _expectClose(localN, n0);
      // ...а faceNormalAt возвращает её в модельных координатах.
      final modelN = faceNormalAt(o, roundFaceKey,
          clickLocal: click, billboardYaw: 0);
      _expectClose(modelN, m.transform3(n0));
    });
  });
}
