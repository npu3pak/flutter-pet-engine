import 'package:vector_math/vector_math.dart' as vm;

/// Готовый маршрут движения: точки в мировых x/z, результат
/// [PathPlanner.plan]. Неизменяем; передаётся [PathFollower.setPath].
class NavPath {
  NavPath(List<vm.Vector2> waypoints)
    : assert(waypoints.isNotEmpty),
      waypoints = List.unmodifiable(waypoints);

  final List<vm.Vector2> waypoints;

  /// Последняя точка маршрута (цель; может отличаться от запрошенной — если
  /// та была в препятствии, берётся ближайшая проходимая).
  vm.Vector2 get target => waypoints.last;

  /// Суммарная длина ломаной.
  double get length {
    var total = 0.0;
    for (var i = 0; i + 1 < waypoints.length; i++) {
      total += (waypoints[i + 1] - waypoints[i]).length;
    }
    return total;
  }
}
