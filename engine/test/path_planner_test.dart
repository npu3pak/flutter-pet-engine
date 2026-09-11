import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

BoxMarkupNavigation _source(List<vm.Aabb2> obstacles) => BoxMarkupNavigation(
  obstacles: obstacles,
  bounds: vm.Aabb2.minMax(vm.Vector2(-2.5, -2.5), vm.Vector2(2.5, 2.5)),
);

vm.Aabb2 _rect(double minX, double minZ, double maxX, double maxZ) =>
    vm.Aabb2.minMax(vm.Vector2(minX, minZ), vm.Vector2(maxX, maxZ));

void main() {
  test('path goes around a box and stays clear', () {
    final source = _source([_rect(-0.5, -0.5, 0.5, 0.5)]);
    final planner = PathPlanner(source, step: 0.1);
    final path = planner.plan(vm.Vector2(-2, 0), vm.Vector2(2, 0));
    expect(path, isNotNull);
    expect(
      path!.waypoints.length,
      greaterThan(2),
      reason: 'прямой путь занят — маршрут обязан обогнуть бокс',
    );
    _expectClear(source, path.waypoints);
    expect((path.target - vm.Vector2(2, 0)).length, lessThan(1e-9));
  });

  test('target inside an obstacle snaps to the nearest passable point', () {
    final source = _source([_rect(-0.5, -0.5, 0.5, 0.5)]);
    final planner = PathPlanner(source, step: 0.1);
    final path = planner.plan(vm.Vector2(-2, 0), vm.Vector2(0, 0));
    expect(path, isNotNull);
    expect(source.isPassable(path!.target), isTrue);
    expect((path.target - vm.Vector2(0, 0)).length, greaterThan(0.1));
    _expectClear(source, path.waypoints);
  });

  test('target far outside the source returns null', () {
    final source = _source(const []);
    final planner = PathPlanner(source, step: 0.1);
    expect(planner.plan(vm.Vector2(-2, 0), vm.Vector2(20, 20)), isNull);
  });

  test('a sealed room has no path inside', () {
    final source = _source([
      _rect(-1.3, 0.7, 1.3, 1.0), // север
      _rect(-1.3, -1.0, 1.3, -0.7), // юг
      _rect(-1.3, -1.0, -1.0, 1.0), // запад
      _rect(1.0, -1.0, 1.3, 1.0), // восток
    ]);
    final planner = PathPlanner(source, step: 0.1);
    expect(planner.plan(vm.Vector2(-2, 0), vm.Vector2(0, 0)), isNull);
    // Снаружи путь строится.
    expect(planner.plan(vm.Vector2(-2, 0), vm.Vector2(2, 0)), isNotNull);
  });

  test('invalidate resets the cached grid', () {
    final source = _source([_rect(-0.5, -0.5, 0.5, 0.5)]);
    final planner = PathPlanner(source, step: 0.1);
    expect(planner.plan(vm.Vector2(-2, 0), vm.Vector2(2, 0)), isNotNull);
    planner.invalidate();
    final again = planner.plan(vm.Vector2(-2, 0), vm.Vector2(2, 0));
    expect(again, isNotNull);
    _expectClear(source, again!.waypoints);
  });
}

/// Проверяет, что все точки и отрезки ломаной проходимы.
void _expectClear(NavigationSource source, List<vm.Vector2> points) {
  for (var i = 0; i < points.length; i++) {
    expect(
      source.isPassable(points[i]),
      isTrue,
      reason: 'waypoint $i в препятствии',
    );
    if (i + 1 >= points.length) continue;
    expect(
      source.isSegmentPassable(points[i], points[i + 1]),
      isTrue,
      reason: 'отрезок $i пересекает препятствие',
    );
  }
}
