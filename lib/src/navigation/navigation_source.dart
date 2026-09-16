import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model_scene.dart';

/// Источник данных навигации (решение 3.4): «проходима ли точка», «свободен
/// ли отрезок», «ближайшая проходимая точка», «сколько места впереди».
///
/// Источник выбирает игра: разметка боксами (`unpassable`), сетка клеток,
/// границы уровня, позже — навигационная сетка по поверхности. Механизмы
/// движка (`PathPlanner`, `PathFollower`) работают через этот интерфейс и не
/// знают, откуда пришли данные.
///
/// Координаты — **мировые** x/z (зеркальный кадр рендера); источник сам
/// переводит документ модели в мир через [chunkWorld]. Источник предполагается
/// неизменным во время движения; при правке сцены игра создаёт его заново
/// (или сбрасывает кэш планировщика через `PathPlanner.invalidate`).
abstract class NavigationSource {
  /// Прямоугольник, в котором источник определён (мировые x/z), или null.
  vm.Aabb2? get bounds;

  /// Проходима ли точка.
  bool isPassable(vm.Vector2 point);

  /// Свободен ли отрезок [a]–[b] целиком. Базовая реализация — сэмплирование
  /// [isPassable]; источники с точной геометрией переопределяют.
  bool isSegmentPassable(
    vm.Vector2 a,
    vm.Vector2 b, {
    double sampleStep = 0.05,
  }) {
    if (!isPassable(a) || !isPassable(b)) return false;
    final length = (b - a).length;
    final steps = (length / sampleStep).ceil();
    for (var i = 1; i < steps; i++) {
      if (!isPassable(a + (b - a) * (i / steps))) return false;
    }
    return true;
  }

  /// Ближайшая проходимая точка к [point] в радиусе [maxRadius], либо null.
  /// Базовая реализация — скан квадрата с шагом [sampleStep].
  vm.Vector2? nearestPassable(
    vm.Vector2 point, {
    double maxRadius = 1.0,
    double sampleStep = 0.05,
  }) {
    if (isPassable(point)) return point.clone();
    final steps = (maxRadius / sampleStep).ceil();
    vm.Vector2? best;
    var bestDistance2 = maxRadius * maxRadius + 1e-9;
    for (var iz = -steps; iz <= steps; iz++) {
      for (var ix = -steps; ix <= steps; ix++) {
        final candidate = vm.Vector2(
          point.x + ix * sampleStep,
          point.y + iz * sampleStep,
        );
        final d2 = candidate.distanceToSquared(point);
        if (d2 >= bestDistance2 || !isPassable(candidate)) continue;
        bestDistance2 = d2;
        best = candidate;
      }
    }
    return best;
  }

  /// Запас свободного места вдоль [direction] от [from] (не дальше
  /// [maxDistance]) — «есть ли впереди место для маневра».
  double clearance(
    vm.Vector2 from,
    vm.Vector2 direction, {
    double maxDistance = 1.0,
    double sampleStep = 0.05,
  }) {
    final d = direction.normalized();
    var distance = 0.0;
    while (distance + sampleStep <= maxDistance + 1e-9) {
      final next = distance + sampleStep;
      if (!isPassable(from + d * next)) break;
      distance = next;
    }
    return distance;
  }
}

/// Источник по разметке боксами документа `model_v1`: прямоугольники в
/// плоскости x/z (по умолчанию — мета-боксы `unpassable`), раздутые на радиус
/// тела. Точная геометрия: отрезок проверяется пересечением с прямоугольником
/// (Liang–Barsky), без сэмплирования.
class BoxMarkupNavigation extends NavigationSource {
  /// Создаёт источник из прямоугольников в мировых координатах.
  BoxMarkupNavigation({
    required List<vm.Aabb2> obstacles,
    required this.bounds,
    double radius = 0,
  }) : obstacles = [
         for (final o in obstacles)
           radius <= 0
               ? vm.Aabb2.minMax(o.min.clone(), o.max.clone())
               : vm.Aabb2.minMax(
                   vm.Vector2(o.min.x - radius, o.min.y - radius),
                   vm.Vector2(o.max.x + radius, o.max.y + radius),
                 ),
       ];

  /// Источник по мета-боксам [name] модели [model] (мир — через
  /// [chunkWorld]; границы комнаты — `[−w/2, w/2] × [−l/2, l/2]`).
  factory BoxMarkupNavigation.fromModel(
    ModelData model, {
    double radius = 0,
    String name = metaNameUnpassable,
  }) {
    final w = model.size.w;
    final l = model.size.l;
    final obstacles = <vm.Aabb2>[
      for (final meta in model.metas)
        if (meta.kind == metaKindBox && meta.name == name)
          _metaRectToWorld(meta, w, l),
    ];
    return BoxMarkupNavigation(
      obstacles: obstacles,
      bounds: vm.Aabb2.minMax(
        vm.Vector2(-w / 2, -l / 2),
        vm.Vector2(w / 2, l / 2),
      ),
      radius: radius,
    );
  }

  /// Препятствия, уже раздутые на радиус (мировые x/z).
  final List<vm.Aabb2> obstacles;

  @override
  final vm.Aabb2 bounds;

  static vm.Aabb2 _metaRectToWorld(ModelMeta meta, int w, int l) {
    final hw = meta.dim('w', 1) / 2;
    final hd = meta.dim('d', 1) / 2;
    final a = chunkWorld(meta.x - hw, meta.z - hd, w, l);
    final b = chunkWorld(meta.x + hw, meta.z + hd, w, l);
    return vm.Aabb2.minMax(
      vm.Vector2(math.min(a.x, b.x), math.min(a.z, b.z)),
      vm.Vector2(math.max(a.x, b.x), math.max(a.z, b.z)),
    );
  }

  @override
  bool isPassable(vm.Vector2 point) {
    if (point.x < bounds.min.x ||
        point.x > bounds.max.x ||
        point.y < bounds.min.y ||
        point.y > bounds.max.y) {
      return false;
    }
    for (final o in obstacles) {
      if (_rectContains(o, point)) return false;
    }
    return true;
  }

  @override
  bool isSegmentPassable(
    vm.Vector2 a,
    vm.Vector2 b, {
    double sampleStep = 0.05,
  }) {
    if (!isPassable(a) || !isPassable(b)) return false;
    for (final o in obstacles) {
      if (_segmentHitsRect(a, b, o)) return false;
    }
    return true;
  }

  static bool _rectContains(vm.Aabb2 rect, vm.Vector2 p) =>
      p.x > rect.min.x &&
      p.x < rect.max.x &&
      p.y > rect.min.y &&
      p.y < rect.max.y;

  /// Отрезок [a]–[b] пересекает внутренность прямоугольника (Liang–Barsky).
  /// Касание границы не считается препятствием — это согласовано со строгой
  /// проверкой [isPassable], где точка на границе проходима.
  static bool _segmentHitsRect(vm.Vector2 a, vm.Vector2 b, vm.Aabb2 rect) {
    const epsilon = 1e-9;
    final dx = b.x - a.x;
    final dz = b.y - a.y;
    var t0 = 0.0;
    var t1 = 1.0;

    bool clip(double p, double q) {
      if (p == 0) return q >= 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clip(-dx, a.x - (rect.min.x + epsilon))) return false;
    if (!clip(dx, (rect.max.x - epsilon) - a.x)) return false;
    if (!clip(-dz, a.y - (rect.min.y + epsilon))) return false;
    if (!clip(dz, (rect.max.y - epsilon) - a.y)) return false;
    return true;
  }
}
