import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  late PerspectiveCamera camera;
  late ScreenPicking picking;
  const size = Size(200, 100);

  setUp(() {
    camera = PerspectiveCamera(
      position: vm.Vector3(0, 0, -5),
      target: vm.Vector3.zero(),
      fovRadiansY: 45 * 0.0174533,
      fovNear: 0.1,
      fovFar: 100,
    );
    picking = ScreenPicking(camera);
  });

  group('worldToScreen', () {
    test('maps a point in front to the view center', () {
      final center = picking.worldToScreen(vm.Vector3.zero(), size);
      expect(center, isNotNull);
      expect(center!.dx, closeTo(size.width / 2, 1e-6));
      expect(center.dy, closeTo(size.height / 2, 1e-6));
    });

    test('maps side points off center', () {
      final right = picking.worldToScreen(vm.Vector3(1, 0, 0), size);
      expect(right, isNotNull);
      expect((right!.dx - size.width / 2).abs(), greaterThan(1));
      expect(right.dy, closeTo(size.height / 2, 1e-6));
    });

    test('returns null behind the camera', () {
      expect(picking.worldToScreen(vm.Vector3(0, 0, -10), size), isNull);
    });
  });

  group('screenRect', () {
    test('covers the projected AABB', () {
      final rect = picking.screenRect(
        vm.Aabb3.minMax(vm.Vector3(-1, -1, -1), vm.Vector3(1, 1, 1)),
        size,
      );
      expect(rect, isNotNull);
      expect(rect!.contains(const Offset(100, 50)), isTrue);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });

    test('returns null when a corner is behind the camera', () {
      final rect = picking.screenRect(
        vm.Aabb3.minMax(vm.Vector3(-1, -1, -30), vm.Vector3(1, 1, -10)),
        size,
      );
      expect(rect, isNull);
    });
  });

  group('nearest', () {
    test('picks the closest projected candidate within the threshold', () {
      final candidates = [vm.Vector3(-1, 0, 0), vm.Vector3(1, 0, 0)];
      final target = picking.worldToScreen(candidates[1], size)!;
      final hit = picking.nearest(
        target,
        size,
        candidates,
        project: (candidate, viewSize) =>
            picking.worldToScreen(candidate, viewSize),
        maxDistance: 20,
      );
      expect(hit, same(candidates[1]));
    });

    test('respects the max distance', () {
      final candidates = [vm.Vector3(5, 0, 0)];
      final hit = picking.nearest(
        const Offset(0, 0),
        size,
        candidates,
        project: (candidate, viewSize) =>
            picking.worldToScreen(candidate, viewSize),
        maxDistance: 10,
      );
      expect(hit, isNull);
    });
  });

  group('raycast', () {
    test('hits a sphere under the tap and picks the nearest one', () {
      final near = vm.Vector3.zero();
      final far = vm.Vector3(0, 0, 2);
      final hit = picking.raycast(
        const Offset(100, 50),
        size,
        [far, near],
        center: (candidate) => candidate,
        radius: (_) => 0.5,
      );
      expect(hit, same(near));
    });

    test('misses off-axis spheres', () {
      final hit = picking.raycast(
        const Offset(100, 50),
        size,
        [vm.Vector3(5, 0, 0)],
        center: (candidate) => candidate,
        radius: (_) => 0.5,
      );
      expect(hit, isNull);
    });

    test('accepts a tap inside the sphere', () {
      final hit = picking.raycast(
        const Offset(100, 50),
        size,
        [vm.Vector3(0, 0, -4)],
        center: (candidate) => candidate,
        radius: (_) => 2,
      );
      expect(hit, isNotNull);
    });
  });
}
