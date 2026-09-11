import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Screen-space projection and picking over a scene [Camera] (the engine's
/// [GameScene.camera] or any fork camera).
///
/// Two picking styles, matching the game and the stand:
/// - [nearest]: screen-distance hit test — project the candidates and take the
///   closest within a pixel threshold (the game's tap-the-enemy rule);
/// - [raycast]: a tap ray against candidates' world bounding spheres — for
///   billboards, which the mesh raycast cannot test.
class ScreenPicking {
  ScreenPicking(this.camera);

  final Camera camera;

  /// World → logical-pixel screen position; null at/behind the camera plane.
  Offset? worldToScreen(vm.Vector3 world, Size viewSize) =>
      camera.worldToScreen(world, viewSize);

  /// The screen-space rect of a world-space AABB (all 8 corners projected);
  /// null when any corner is at/behind the camera plane.
  Rect? screenRect(vm.Aabb3 bounds, Size viewSize) {
    Offset? min;
    Offset? max;
    for (var i = 0; i < 8; i++) {
      final corner = vm.Vector3(
        (i & 1) == 0 ? bounds.min.x : bounds.max.x,
        (i & 2) == 0 ? bounds.min.y : bounds.max.y,
        (i & 4) == 0 ? bounds.min.z : bounds.max.z,
      );
      final p = camera.worldToScreen(corner, viewSize);
      if (p == null) return null;
      min = min == null
          ? p
          : Offset(math.min(min.dx, p.dx), math.min(min.dy, p.dy));
      max = max == null
          ? p
          : Offset(math.max(max.dx, p.dx), math.max(max.dy, p.dy));
    }
    if (min == null || max == null) return null;
    return Rect.fromLTRB(min.dx, min.dy, max.dx, max.dy);
  }

  /// The nearest candidate whose projected position is within [maxDistance]
  /// logical pixels of [tap]; [project] maps a candidate to its screen
  /// position (null when it is not on screen).
  T? nearest<T>(
    Offset tap,
    Size viewSize,
    Iterable<T> candidates, {
    required Offset? Function(T candidate, Size viewSize) project,
    double maxDistance = 140,
  }) {
    T? best;
    var bestDistance = maxDistance;
    for (final candidate in candidates) {
      final screen = project(candidate, viewSize);
      if (screen == null) continue;
      final distance = (screen - tap).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  /// The nearest candidate whose world bounding sphere is hit by the tap ray
  /// (nearest to the camera wins).
  T? raycast<T>(
    Offset tap,
    Size viewSize,
    Iterable<T> candidates, {
    required vm.Vector3 Function(T candidate) center,
    required double Function(T candidate) radius,
  }) {
    final ray = camera.screenPointToRay(tap, viewSize);
    final direction = ray.direction.normalized();
    T? best;
    var bestDistance = double.infinity;
    for (final candidate in candidates) {
      final hit = _raySphere(ray.origin, direction, center(candidate), radius(candidate));
      if (hit == null || hit >= bestDistance) continue;
      bestDistance = hit;
      best = candidate;
    }
    return best;
  }

  static double? _raySphere(
    vm.Vector3 origin,
    vm.Vector3 direction,
    vm.Vector3 center,
    double radius,
  ) {
    if (radius <= 0) return null;
    final oc = origin - center;
    final b = oc.dot(direction);
    final c = oc.length2 - radius * radius;
    final discriminant = b * b - c;
    if (discriminant < 0) return null;
    final root = math.sqrt(discriminant);
    final near = -b - root;
    if (near >= 0) return near;
    final far = -b + root;
    return far >= 0 ? 0.0 : null;
  }
}
