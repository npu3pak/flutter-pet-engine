import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

BoxMarkupNavigation _room([List<vm.Aabb2> obstacles = const []]) =>
    BoxMarkupNavigation(
      obstacles: obstacles,
      bounds: vm.Aabb2.minMax(vm.Vector2(-2.5, -2.5), vm.Vector2(2.5, 2.5)),
    );

vm.Aabb2 _rect(double minX, double minZ, double maxX, double maxZ) =>
    vm.Aabb2.minMax(vm.Vector2(minX, minZ), vm.Vector2(maxX, maxZ));

void main() {
  test('arcs forward to a target behind', () {
    final source = _room();
    final planner = PathPlanner(source, step: 0.1);
    final follower = PathFollower(
      source: source,
      position: vm.Vector2(0, 1.5),
      heading: vm.Vector2(0, 1),
    );
    final path = planner.plan(follower.position, vm.Vector2(0, -1.5));
    expect(path, isNotNull);
    expect(follower.setPath(path!), isTrue);
    expect(follower.pivotFirst, isFalse);

    final start = follower.position.clone();
    follower.update(1 / 60);
    expect(
      (follower.position - start).dot(vm.Vector2(0, 1)),
      greaterThan(0),
      reason: 'первый шаг — вперёд по курсу, а не назад',
    );
    _simulate(follower, source);
    expect(follower.active, isFalse);
    expect((follower.position - vm.Vector2(0, -1.5)).length, lessThan(0.2));
  });

  test('pivots in place when the front is blocked', () {
    final source = _room([_rect(-1.5, 0.8, 1.5, 1.4)]);
    final planner = PathPlanner(source, step: 0.1);
    final follower = PathFollower(
      source: source,
      position: vm.Vector2(0, 0.6),
      heading: vm.Vector2(0, 1),
    );
    final path = planner.plan(follower.position, vm.Vector2(0, -1.5));
    expect(path, isNotNull);
    expect(follower.setPath(path!), isTrue);
    expect(follower.pivotFirst, isTrue);

    final start = follower.position.clone();
    for (var i = 0; i < 5; i++) {
      follower.update(1 / 60);
    }
    expect(
      (follower.position - start).length,
      lessThan(1e-9),
      reason: 'во время разворота агент не смещается',
    );
    _simulate(follower, source);
    expect(follower.active, isFalse);
    expect((follower.position - vm.Vector2(0, -1.5)).length, lessThan(0.2));
  });

  test('turn rate never exceeds the limit and the body stays clear', () {
    final source = _room([_rect(-0.6, -0.6, 0.6, 0.6)]);
    final planner = PathPlanner(source, step: 0.1);
    final follower = PathFollower(
      source: source,
      position: vm.Vector2(-2, 2),
      heading: vm.Vector2(0, 1),
    );
    final path = planner.plan(follower.position, vm.Vector2(2, -2));
    expect(path, isNotNull);
    expect(follower.setPath(path!), isTrue);

    final dt = 1 / 60;
    var previous = follower.heading.clone();
    var elapsed = 0.0;
    while (follower.active && elapsed < 30) {
      follower.update(dt);
      elapsed += dt;
      final delta = _signedAngle(previous, follower.heading).abs();
      expect(delta, lessThanOrEqualTo(follower.maxTurnRate * dt + 1e-6));
      expect(
        source.isPassable(follower.position),
        isTrue,
        reason: 'агент вошёл в препятствие',
      );
      previous = follower.heading.clone();
    }
    expect(follower.active, isFalse);
    expect((follower.position - vm.Vector2(2, -2)).length, lessThan(0.2));
  });

  test('a single-point path stops the follower', () {
    final source = _room();
    final follower = PathFollower(
      source: source,
      position: vm.Vector2(0, 0),
      heading: vm.Vector2(0, 1),
    );
    expect(follower.setPath(NavPath([vm.Vector2(0, 0)])), isFalse);
    expect(follower.active, isFalse);
  });

  test('stop clears the current path', () {
    final source = _room();
    final follower = PathFollower(
      source: source,
      position: vm.Vector2(0, 1.5),
      heading: vm.Vector2(0, 1),
    );
    expect(
      follower.setPath(NavPath([vm.Vector2(0, 1.5), vm.Vector2(0, -1.5)])),
      isTrue,
    );
    follower.stop();
    expect(follower.active, isFalse);
    follower.update(1 / 60);
    expect(follower.position, vm.Vector2(0, 1.5));
  });
}

/// Прогоняет движение до прибытия (или 30 секунд) с проверкой проходимости.
void _simulate(
  PathFollower follower,
  NavigationSource source, {
  double dt = 1 / 60,
}) {
  var elapsed = 0.0;
  while (follower.active && elapsed < 30) {
    follower.update(dt);
    elapsed += dt;
    expect(
      source.isPassable(follower.position),
      isTrue,
      reason: 'агент вошёл в препятствие',
    );
  }
}

double _signedAngle(vm.Vector2 from, vm.Vector2 to) {
  final a = math.atan2(from.y, from.x);
  final b = math.atan2(to.y, to.x);
  var delta = b - a;
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  while (delta < -math.pi) {
    delta += 2 * math.pi;
  }
  return delta;
}
