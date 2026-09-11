import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelObject cuboid(
  String id, {
  double x = 0,
  double y = 0,
  double z = 0,
  double w = 1,
  double h = 1,
  double d = 1,
  double rotY = 0,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      dims: {'w': w, 'h': h, 'd': d},
    );

void main() {
  group('exact operations', () {
    test('objectBounds/center/size of a cuboid', () {
      final o = cuboid('a', x: 1, y: 0, z: 2, w: 2, h: 3, d: 4);
      final (lo, hi) = objectBounds(o);
      expect(lo.x, closeTo(0, 1e-9));
      expect(lo.y, closeTo(0, 1e-9));
      expect(lo.z, closeTo(0, 1e-9));
      expect(hi.x, closeTo(2, 1e-9));
      expect(hi.y, closeTo(3, 1e-9));
      expect(hi.z, closeTo(4, 1e-9));
      final c = objectCenter(o);
      expect(c.x, closeTo(1, 1e-9));
      expect(c.y, closeTo(1.5, 1e-9));
      expect(c.z, closeTo(2, 1e-9));
      final s = objectSize(o);
      expect(s.x, closeTo(2, 1e-9));
      expect(s.y, closeTo(3, 1e-9));
      expect(s.z, closeTo(4, 1e-9));
    });

    test('objectBounds accounts for rotation', () {
      final o = cuboid('a', w: 2, h: 1, d: 2, rotY: 45);
      final (lo, hi) = objectBounds(o);
      expect(lo.x, closeTo(-1.4142, 1e-3));
      expect(hi.x, closeTo(1.4142, 1e-3));
      expect(lo.z, closeTo(-1.4142, 1e-3));
      expect(hi.z, closeTo(1.4142, 1e-3));
    });

    test('translateObject shifts the anchor', () {
      final o = cuboid('a');
      translateObject(o, vm.Vector3(1, 2, 3));
      expect((o.x, o.y, o.z), (1.0, 2.0, 3.0));
    });

    test('setSizeAlong writes the matching dims', () {
      final o = cuboid('a');
      setSizeAlong(o, LevelAxis.x, 4);
      setSizeAlong(o, LevelAxis.y, 5);
      setSizeAlong(o, LevelAxis.z, 6);
      expect((o.dim('w', 0), o.dim('h', 0), o.dim('d', 0)), (4.0, 5.0, 6.0));
      final plane = ModelObject(id: 'p', name: 'p', kind: 'plane', dims: {'w': 1, 'd': 1});
      setSizeAlong(plane, LevelAxis.x, 3);
      expect(plane.dim('w', 0), 3);
    });
  });

  group('face snap', () {
    test('snapToFace moves the anchor to the face center', () {
      final target = cuboid('t', w: 2, h: 3, d: 2);
      final element = cuboid('e');
      snapToFace(element, target, '+y');
      expect(element.x, closeTo(0, 1e-9));
      expect(element.y, closeTo(3, 1e-9));
      expect(element.z, closeTo(0, 1e-9));
      // +x face: the rendered center mirrors x (faceCenterAt), the gap
      // follows the rendered outward normal (−x for the model +x face).
      snapToFace(element, target, '+x', gap: 0.5);
      expect(element.x, closeTo(-1.5, 1e-9));
      expect(element.y, closeTo(1.5, 1e-9));
    });

    test('snapToFace lands on the face in the rendered frame', () {
      final target = cuboid('t', x: 3, w: 2, h: 3, d: 2);
      final element = cuboid('e');
      for (final face in ['+x', '-x', '+z', '-z']) {
        final center = faceCenterAt(target, face, billboardYaw: 0)!;
        final normal = faceNormalAt(target, face, billboardYaw: 0)!;
        snapToFace(element, target, face, gap: 0.25);
        expect(element.x, closeTo(center.x - normal.x * 0.25, 1e-9),
            reason: face);
        expect(element.y, closeTo(center.y + normal.y * 0.25, 1e-9),
            reason: face);
        expect(element.z, closeTo(center.z + normal.z * 0.25, 1e-9),
            reason: face);
      }
    });

    test('snapToFace по боку цилиндра использует точку нажатия', () {
      final target = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cylinder',
        dims: const {'bottomR': 1, 'topR': 1, 'h': 2, 'segments': 24},
      );
      final element = cuboid('e');
      snapToFace(element, target, 'side', clickLocal: vm.Vector3(1, 1, 0));
      final radial = vm.Vector3(element.x, 0, element.z).length;
      expect(radial, closeTo(1, 1e-6));
      expect(element.y, closeTo(1, 1e-6));
    });

    test('snapToFace без точки нажатия бок цилиндра не разрешается', () {
      final target = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cylinder',
        dims: const {'bottomR': 1, 'topR': 1, 'h': 2, 'segments': 24},
      );
      final element = cuboid('e', x: 5);
      snapToFace(element, target, 'side');
      expect(element.x, 5);
    });

    test('parallelToFace наклоняет элемент по боку конуса', () {
      final cone = ModelObject(
        id: 'cone',
        name: 'cone',
        kind: 'cylinder',
        dims: const {'bottomR': 1, 'topR': 0.2, 'h': 2, 'segments': 24},
      );
      final element = cuboid('e');
      parallelToFace(element, cone, 'side', clickLocal: vm.Vector3(1, 1, 0));
      final normal =
          objectRotation(element).transform3(vm.Vector3(0, 1, 0));
      // Бок конуса наклонён: нормаль не строго вертикальна.
      expect(normal.y.abs(), lessThan(0.999));
      expect(normal.y.abs(), greaterThan(0.1));
    });

    test('parallelToFace aligns the primary axis with the normal', () {
      final target = cuboid('t', w: 2, h: 3, d: 2);
      final sheet = ModelObject(id: 's', name: 's', kind: 'plane', dims: {'w': 1, 'd': 1});
      parallelToFace(sheet, target, '+y');
      // plane +Z → face normal (0, 1, 0): rotX = −90.
      final normal = objectRotation(sheet).transform3(vm.Vector3(0, 0, 1));
      expect(normal.x, closeTo(0, 1e-6));
      expect(normal.y, closeTo(1, 1e-6));
      expect(normal.z, closeTo(0, 1e-6));
    });

    test('faceCenterLocal is the pure frame, faceCenterAt the editor mirror', () {
      final o = cuboid('a', w: 2, h: 2, d: 2);
      final local = faceCenterLocal(o, '+x', billboardYaw: 0)!;
      expect(local.x, closeTo(1, 1e-9));
      expect(local.y, closeTo(1, 1e-9));
      expect(local.z, closeTo(0, 1e-9));
      final visual = faceCenterAt(o, '+x', billboardYaw: 0)!;
      expect(visual.x, closeTo(-1, 1e-9));
      expect(visual.y, closeTo(1, 1e-9));
      expect(visual.z, closeTo(0, 1e-9));
    });
  });

  group('convenient operations', () {
    test('alignTo matches the AABB centers on the axis', () {
      final target = cuboid('t', x: 3, y: 1, z: -2);
      final element = cuboid('e');
      alignTo(element, target, LevelAxis.x);
      expect(objectCenter(element).x, closeTo(objectCenter(target).x, 1e-9));
      expect(objectCenter(element).z, isNot(closeTo(objectCenter(target).z, 1e-9)));
    });

    test('fillGap spans the gap between two objects', () {
      final a = cuboid('a', x: -2);
      final b = cuboid('b', x: 2);
      final element = cuboid('e');
      fillGap(element, a, b, LevelAxis.x);
      expect(element.dim('w', 0), closeTo(3, 1e-9));
      expect(element.x, closeTo(0, 1e-9));
      // Overlapping objects: unchanged.
      final c = cuboid('c', x: -0.5);
      final d = cuboid('d', x: 0.5);
      fillGap(element, c, d, LevelAxis.x);
      expect(element.dim('w', 0), closeTo(3, 1e-9));
    });

    test('cover resizes the footprint and sits on the target top', () {
      final target = cuboid('t', x: 1, y: 0, z: 2, w: 4, h: 1, d: 2);
      final element = cuboid('e', y: 5);
      cover(element, target);
      expect(element.dim('w', 0), closeTo(4, 1e-9));
      expect(element.dim('d', 0), closeTo(2, 1e-9));
      expect(element.x, closeTo(1, 1e-9));
      expect(element.z, closeTo(2, 1e-9));
      expect(element.y, closeTo(1, 1e-9));
    });

    test('inset/outset change the footprint symmetrically', () {
      final o = cuboid('a', w: 4, d: 2);
      inset(o, 0.5);
      expect(o.dim('w', 0), closeTo(3, 1e-9));
      expect(o.dim('d', 0), closeTo(1, 1e-9));
      outset(o, 1);
      expect(o.dim('w', 0), closeTo(5, 1e-9));
      expect(o.dim('d', 0), closeTo(3, 1e-9));
      inset(o, 10);
      expect(o.dim('w', 0), 0);
    });

    test('stretchTo reaches the target near face', () {
      final element = cuboid('e', x: -2);
      final target = cuboid('t', x: 2);
      stretchTo(element, target, LevelAxis.x);
      expect(element.dim('w', 0), closeTo(4, 1e-9));
      expect(element.x, closeTo(-0.5, 1e-9));
      expect(objectBounds(element).$2.x, closeTo(objectBounds(target).$1.x, 1e-9));
    });

    test('stretchTo works from the other side', () {
      final element = cuboid('e', x: 4);
      final target = cuboid('t', x: 2);
      stretchTo(element, target, LevelAxis.x);
      expect(objectBounds(element).$1.x, closeTo(objectBounds(target).$2.x, 1e-9));
    });
  });
}
