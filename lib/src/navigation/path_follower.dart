import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'nav_path.dart';
import 'navigation_source.dart';

/// Механизм следования маршруту: pure pursuit с ограничением скорости
/// поворота. Работает в мировых x/z, ничего не знает о сцене и объектах —
/// вызывающая сторона забирает [position]/[heading] и применяет их к своему
/// объекту.
///
/// Поведение:
/// - кот рулит к точке маршрута на расстоянии [lookahead] впереди, поэтому
///   цель за спиной превращается в дугу вперёд, а не в разворот на месте;
/// - если начальный прицел сзади, а впереди по курсу нет места (меньше
///   [minDeparture] на расстоянии [forwardProbe]), включается [pivotFirst]:
///   разворот на месте до совпадения с маршрутом, затем движение;
/// - шаг проверяется источником: упершись в препятствие, агент доворачивает
///   без смещения;
/// - в [arriveDistance] от цели движение заканчивается ([active] = false).
///
/// Параметры задаёт игра (скорость, поворот, прицел, пороги).
class PathFollower {
  PathFollower({
    required this.source,
    required vm.Vector2 position,
    required vm.Vector2 heading,
    this.speed = 1.0,
    this.maxTurnRate = 240 * math.pi / 180,
    this.lookahead = 0.35,
    this.arriveDistance = 0.08,
    this.pivotAlign = 10 * math.pi / 180,
    this.arcThreshold = 75 * math.pi / 180,
    this.forwardProbe = 0.6,
    this.minDeparture = 0.3,
    this.arcDotThreshold = 0.0,
    this.slowdownFactor = 0.7,
  }) : position = position.clone(),
       heading = heading.normalized();

  final NavigationSource source;

  /// Скорость движения (мировые единицы в секунду).
  final double speed;

  /// Максимальная скорость поворота (радианы в секунду).
  final double maxTurnRate;

  /// Дистанция прицела pure pursuit.
  final double lookahead;

  /// Дистанция прибытия.
  final double arriveDistance;

  /// Порог совпадения курса при развороте на месте (радианы).
  final double pivotAlign;

  /// Порог «цель за спиной» (радианы): дальше него проверяется место впереди.
  final double arcThreshold;

  /// Насколько далеко вперёд проверяется запас места (мировые единицы).
  final double forwardProbe;

  /// Минимальный свободный запас впереди для выезда по дуге.
  final double minDeparture;

  /// Если прицел позади (скалярное произведение меньше порога), агент едет
  /// вперёд и одновременно доворачивает.
  final double arcDotThreshold;

  /// Доля замедления на крутых поворотах (0 — не замедляться).
  final double slowdownFactor;

  /// Позиция (мировые x/z).
  vm.Vector2 position;

  /// Курс — единичный вектор в мировых x/z.
  vm.Vector2 heading;

  List<vm.Vector2> _waypoints = const [];
  int _segment = 0;
  bool _pivotFirst = false;
  bool _active = false;

  bool get active => _active;

  /// Идёт ли разворот на месте перед движением.
  bool get pivotFirst => _pivotFirst;

  /// Последняя точка текущего маршрута.
  vm.Vector2 get target =>
      _waypoints.isEmpty ? position.clone() : _waypoints.last.clone();

  /// Принимает маршрут; false — маршрут пуст/из одной точки (агент стоит).
  bool setPath(NavPath path) {
    if (path.waypoints.length < 2) {
      stop();
      return false;
    }
    _waypoints = path.waypoints;
    _segment = 0;
    _pivotFirst = _needsPivot();
    _active = true;
    return true;
  }

  /// Останавливает движение (текущий маршрут забывается).
  void stop() {
    _active = false;
    _waypoints = const [];
    _pivotFirst = false;
  }

  /// Один кадр движения.
  void update(double dt) {
    if (!_active) return;
    final closest = _closestOnPath();
    _segment = closest.segment;
    if ((_waypoints.last - position).length <= arriveDistance) {
      position = _waypoints.last;
      _active = false;
      return;
    }
    final aim = _lookaheadFrom(closest.point, lookahead);
    final toAim = aim - position;
    if (toAim.length2 < 1e-12) return;
    final desired = toAim.normalized();

    if (_pivotFirst) {
      heading = _rotateTowards(heading, desired, maxTurnRate * dt);
      if (_signedAngle(heading, desired).abs() <= pivotAlign) {
        _pivotFirst = false;
      }
      return;
    }

    // Дуга: прицел позади — едем вперёд и плавно доворачиваем (разворот на
    // 180° в один приём невозможен).
    if (desired.dot(heading) < arcDotThreshold) {
      final turned = _rotateTowards(heading, desired, maxTurnRate * dt);
      final candidate = position + turned * (speed * dt);
      if (source.isPassable(candidate)) {
        position = candidate;
      }
      heading = turned;
      return;
    }

    // Крутые повороты проходим медленнее — дуга выглядит естественнее.
    final error = _signedAngle(heading, desired).abs();
    final scale = 1.0 - slowdownFactor * (error / math.pi).clamp(0.0, 1.0);
    final maxDelta = maxTurnRate * dt;
    final step = speed * scale * dt;
    final nextHeading = _rotateTowards(heading, desired, maxDelta);
    if (_tryStep(nextHeading, nextHeading, step, maxDelta)) return;

    // Прицел за препятствием (срезание угла): пробуем обойти выступ веером
    // направлений, поворачивая курс к выбранному не быстрее [maxDelta].
    for (final offset in _avoidanceOffsets) {
      final direction = _rotateVector(desired, offset);
      if (_tryStep(direction, direction, step, maxDelta)) return;
    }
    // Совсем зажаты — доворачиваем без смещения.
    heading = nextHeading;
  }

  /// Пробует шаг: [moveDirection] задаёт смещение, [faceDirection] — куда
  /// доворачивается курс (не быстрее [maxDelta]).
  bool _tryStep(
    vm.Vector2 moveDirection,
    vm.Vector2 faceDirection,
    double step,
    double maxDelta,
  ) {
    final candidate = position + moveDirection * step;
    if (!source.isPassable(candidate)) return false;
    position = candidate;
    heading = _rotateTowards(heading, faceDirection, maxDelta);
    return true;
  }

  /// Нужен ли разворот на месте: начальный прицел сзади и впереди мало места.
  bool _needsPivot() {
    final aim = _lookaheadFrom(_closestOnPath().point, lookahead);
    final toAim = aim - position;
    if (toAim.length2 < 1e-12) return false;
    final desired = toAim.normalized();
    final behind =
        math.acos(desired.dot(heading).clamp(-1.0, 1.0)) > arcThreshold;
    if (!behind) return false;
    return source.clearance(position, heading, maxDistance: forwardProbe) <
        minDeparture;
  }

  /// Ближайшая точка маршрута к текущей позиции (проекция на отрезок,
  /// ограниченная его концами) и номер этого отрезка.
  ({int segment, vm.Vector2 point}) _closestOnPath() {
    var bestSegment = _segment;
    var bestDistance2 = double.infinity;
    var bestPoint = position.clone();
    for (var i = _segment; i < _waypoints.length - 1; i++) {
      final a = _waypoints[i];
      final b = _waypoints[i + 1];
      final seg = b - a;
      final len2 = seg.length2;
      final t = len2 < 1e-12
          ? 0.0
          : ((position - a).dot(seg) / len2).clamp(0.0, 1.0);
      final point = a + seg * t;
      final d2 = (point - position).length2;
      if (d2 < bestDistance2) {
        bestDistance2 = d2;
        bestSegment = i;
        bestPoint = point;
      }
    }
    return (segment: bestSegment, point: bestPoint);
  }

  /// Точка маршрута на расстоянии [distance] впереди [from] (от ближайшей
  /// точки текущего отрезка).
  vm.Vector2 _lookaheadFrom(vm.Vector2 from, double distance) {
    var remaining = distance;
    var current = from;
    for (var i = _segment + 1; i < _waypoints.length; i++) {
      final to = _waypoints[i];
      final seg = to - current;
      final len = seg.length;
      if (len >= remaining) {
        return current + seg.normalized() * remaining;
      }
      remaining -= len;
      current = to;
    }
    return _waypoints.last;
  }

  static vm.Vector2 _rotateTowards(
    vm.Vector2 current,
    vm.Vector2 desired,
    double maxDelta,
  ) {
    final delta = _signedAngle(current, desired);
    if (delta.abs() <= maxDelta) return desired;
    final angle = math.atan2(current.y, current.x) + delta.sign * maxDelta;
    return vm.Vector2(math.cos(angle), math.sin(angle));
  }

  /// Углы веера локального обхода (радианы, в обе стороны).
  static const List<double> _avoidanceOffsets = [
    0.4,
    -0.4,
    0.8,
    -0.8,
    1.2,
    -1.2,
  ];

  static vm.Vector2 _rotateVector(vm.Vector2 v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return vm.Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  static double _signedAngle(vm.Vector2 from, vm.Vector2 to) {
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
}
