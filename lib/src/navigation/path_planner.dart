import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'nav_path.dart';
import 'navigation_source.dart';

/// Механизм построения пути: сэмплирует [NavigationSource] в сетку с шагом
/// [step], ищет путь A* (8 направлений, без срезания углов) и сглаживает его
/// «натягиванием нити» через запросы источника. Параметры (шаг, радиус
/// снапа) задаёт игра.
///
/// Источник предполагается неизменным: сетка строится один раз и кэшируется.
/// После правки сцены игра вызывает [invalidate] (или создаёт планировщик
/// заново). Источник без границ (`bounds == null`) не поддерживается — `plan`
/// возвращает null.
class PathPlanner {
  PathPlanner(this.source, {this.step = 0.1, this.maxSnap = 1.0});

  final NavigationSource source;

  /// Шаг сэмплированной сетки (мировые единицы).
  final double step;

  /// Насколько далеко от запрошенной точки ищется ближайшая проходимая.
  final double maxSnap;

  _PlannerGrid? _grid;

  /// Сбрасывает кэш сетки (после изменения источника).
  void invalidate() => _grid = null;

  /// Маршрут от [from] до [to]; null — пути нет или цель недостижима.
  ///
  /// Если [to] в препятствии, берётся ближайшая проходимая точка в радиусе
  /// [maxSnap]; если и её нет — null.
  NavPath? plan(vm.Vector2 from, vm.Vector2 to) {
    final target = source.nearestPassable(to, maxRadius: maxSnap);
    if (target == null) return null;
    final start = source.isPassable(from)
        ? from.clone()
        : source.nearestPassable(from, maxRadius: maxSnap);
    if (start == null) return null;
    final grid = _grid ??= _PlannerGrid(source, step);
    final points = grid.findPath(start, target);
    if (points == null) return null;
    return NavPath(points);
  }
}

/// Сэмплированная сетка проходимости источника: узлы, A*, сглаживание.
class _PlannerGrid {
  _PlannerGrid(this.source, this.step) {
    final b = source.bounds;
    if (b == null) {
      minX = minZ = maxX = maxZ = 0;
      nx = nz = 0;
      _blocked = const [];
      return;
    }
    minX = b.min.x;
    minZ = b.min.y;
    maxX = b.max.x;
    maxZ = b.max.y;
    nx = ((maxX - minX) / step).round() + 1;
    nz = ((maxZ - minZ) / step).round() + 1;
    _blocked = List<bool>.filled(nx * nz, false);
    for (var iz = 0; iz < nz; iz++) {
      for (var ix = 0; ix < nx; ix++) {
        _blocked[_index(ix, iz)] = !source.isPassable(_nodePoint(ix, iz));
      }
    }
  }

  final NavigationSource source;
  final double step;

  late final double minX;
  late final double minZ;
  late final double maxX;
  late final double maxZ;
  late final int nx;
  late final int nz;
  late final List<bool> _blocked;

  static const List<(int, int)> _neighbors = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
  ];

  int _index(int ix, int iz) => ix + iz * nx;

  vm.Vector2 _nodePoint(int ix, int iz) =>
      vm.Vector2(minX + ix * step, minZ + iz * step);

  /// Сглаженный путь от [from] до [to]; null — пути нет.
  List<vm.Vector2>? findPath(vm.Vector2 from, vm.Vector2 to) {
    if (nx == 0 || nz == 0) return null;
    final startNode = _nearestFreeNode(from);
    final goalNode = _nearestFreeNode(to);
    if (startNode == null || goalNode == null) return null;
    final nodes = _aStar(startNode, goalNode);
    if (nodes == null) return null;
    final points = <vm.Vector2>[from, ...nodes];
    if (source.isSegmentPassable(points.last, to)) points.add(to);
    return _smooth(points);
  }

  (int, int)? _nearestFreeNode(vm.Vector2 point) {
    (int, int)? best;
    var bestDistance2 = double.infinity;
    for (var iz = 0; iz < nz; iz++) {
      for (var ix = 0; ix < nx; ix++) {
        if (_blocked[_index(ix, iz)]) continue;
        final d2 = (point - _nodePoint(ix, iz)).length2;
        if (d2 < bestDistance2) {
          bestDistance2 = d2;
          best = (ix, iz);
        }
      }
    }
    return best;
  }

  List<vm.Vector2>? _aStar((int, int) start, (int, int) goal) {
    final startIndex = _index(start.$1, start.$2);
    final goalIndex = _index(goal.$1, goal.$2);
    if (startIndex == goalIndex) {
      return [_nodePoint(start.$1, start.$2)];
    }
    final total = nx * nz;
    final g = List<double>.filled(total, double.infinity);
    final cameFrom = List<int>.filled(total, -1);
    final closed = List<bool>.filled(total, false);
    final open = _MinHeap();

    g[startIndex] = 0;
    open.push(startIndex, _heuristic(start.$1, start.$2, goal.$1, goal.$2));

    while (!open.isEmpty) {
      final current = open.pop();
      if (closed[current]) continue;
      closed[current] = true;
      if (current == goalIndex) return _reconstruct(cameFrom, current);

      final cx = current % nx;
      final cz = current ~/ nx;
      for (final (dx, dz) in _neighbors) {
        final nx2 = cx + dx;
        final nz2 = cz + dz;
        if (nx2 < 0 || nx2 >= nx || nz2 < 0 || nz2 >= nz) continue;
        final next = _index(nx2, nz2);
        if (_blocked[next] || closed[next]) continue;
        if (dx != 0 && dz != 0) {
          // Диагональ без срезания угла: оба ортогональных соседа свободны.
          if (_blocked[_index(cx + dx, cz)] || _blocked[_index(cx, cz + dz)]) {
            continue;
          }
        }
        final cost = (dx == 0 || dz == 0) ? 1.0 : math.sqrt2;
        final tentative = g[current] + cost;
        if (tentative >= g[next]) continue;
        cameFrom[next] = current;
        g[next] = tentative;
        open.push(next, tentative + _heuristic(nx2, nz2, goal.$1, goal.$2));
      }
    }
    return null;
  }

  List<vm.Vector2> _reconstruct(List<int> cameFrom, int current) {
    final out = <vm.Vector2>[];
    var node = current;
    while (node != -1) {
      out.add(_nodePoint(node % nx, node ~/ nx));
      node = cameFrom[node];
    }
    return out.reversed.toList();
  }

  /// Октильная эвристика (шаг 8 направлений).
  static double _heuristic(int ax, int az, int bx, int bz) {
    final dx = (ax - bx).abs().toDouble();
    final dz = (az - bz).abs().toDouble();
    return dx + dz + (math.sqrt2 - 2) * math.min(dx, dz);
  }

  /// Жадное «натягивание нити»: из каждой точки берём самую дальнюю, до
  /// которой отрезок свободен по запросу источника.
  List<vm.Vector2> _smooth(List<vm.Vector2> points) {
    if (points.length <= 2) return List.of(points);
    final out = <vm.Vector2>[points.first];
    var i = 0;
    while (i < points.length - 1) {
      var j = points.length - 1;
      while (j > i + 1 && !source.isSegmentPassable(points[i], points[j])) {
        j--;
      }
      out.add(points[j]);
      i = j;
    }
    return out;
  }
}

/// Двоичная куча для A* (приоритет — f-оценка).
class _MinHeap {
  final List<int> _nodes = [];
  final List<double> _scores = [];

  bool get isEmpty => _nodes.isEmpty;

  void push(int node, double score) {
    _nodes.add(node);
    _scores.add(score);
    var child = _nodes.length - 1;
    while (child > 0) {
      final parent = (child - 1) >> 1;
      if (_scores[parent] <= _scores[child]) break;
      _swap(parent, child);
      child = parent;
    }
  }

  int pop() {
    final top = _nodes.first;
    final last = _nodes.length - 1;
    _nodes[0] = _nodes[last];
    _scores[0] = _scores[last];
    _nodes.removeLast();
    _scores.removeLast();
    var parent = 0;
    while (true) {
      final left = parent * 2 + 1;
      final right = left + 1;
      var smallest = parent;
      if (left < _nodes.length && _scores[left] < _scores[smallest]) {
        smallest = left;
      }
      if (right < _nodes.length && _scores[right] < _scores[smallest]) {
        smallest = right;
      }
      if (smallest == parent) break;
      _swap(parent, smallest);
      parent = smallest;
    }
    return top;
  }

  void _swap(int a, int b) {
    final n = _nodes[a];
    _nodes[a] = _nodes[b];
    _nodes[b] = n;
    final s = _scores[a];
    _scores[a] = _scores[b];
    _scores[b] = s;
  }
}
