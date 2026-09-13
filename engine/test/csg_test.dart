import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:pet_engine_v2/src/scene/csg.dart';
import 'package:pet_engine_v2/src/scene/rounded_box.dart';


/// Cuboid leaf: anchor = center of the BASE at (x, y, z); the body spans
/// y .. y+h.
ModelObject cuboid(
  String id,
  double x,
  double y,
  double z,
  double w,
  double h,
  double d, {
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

ModelObject cyl(
  String id,
  double x,
  double z,
  double r,
  double h, {
  int segments = 16,
  double topR = -1,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cylinder',
      x: x,
      y: 0,
      z: z,
      dims: {
        'bottomR': r,
        'topR': topR < 0 ? r : topR,
        'h': h,
        'segments': segments.toDouble(),
      },
    );

/// Watertightness: the vector sum of the oriented face areas of a closed
/// surface is (near) zero, regardless of edge T-junctions.
void expectWatertight(List<CsgPoly> polys, {double atol = 1e-6}) {
  expect(polys, isNotEmpty, reason: 'пустая поверхность');
  var sum = vm.Vector3.zero();
  var total = 0.0;
  for (final p in polys) {
    final a = p.area();
    total += a;
    sum += p.normal * a;
  }
  expect(sum.length / total, lessThan(atol),
      reason: 'незамкнутая поверхность: ΣA·n/ΣA = ${sum.length / total}');
}

/// Signed volume of the closed soup via origin tetrahedra (positive when
/// the outward orientation is consistent).
double signedVolume(List<CsgPoly> polys) {
  var vol = 0.0;
  for (final p in polys) {
    final v = p.vertices;
    for (var i = 1; i < v.length - 1; i++) {
      vol += v[0].dot(v[i].cross(v[i + 1])) / 6;
    }
  }
  return vol;
}

/// All polygons must come from the listed source objects.
void expectSources(List<CsgPoly> polys, Set<String> ids) {
  for (final p in polys) {
    expect(ids, contains(p.surface.objId),
        reason: 'неожиданный провенанс ${p.surface.objId}:${p.surface.faceKey}');
  }
}

/// Every polygon must be planar convex (piece of one convex input face).
void expectConvexPlanar(List<CsgPoly> polys) {
  for (final p in polys) {
    final v = p.vertices;
    expect(v.length, greaterThanOrEqualTo(3));
    final ref = (v[1] - v[0]).cross(v[2] - v[0]);
    for (var i = 2; i + 1 < v.length; i++) {
      final n = (v[i] - v[0]).cross(v[i + 1] - v[0]);
      expect(ref.dot(n), greaterThan(0), reason: 'невыпуклый/неплоский полигон');
    }
  }
}

void main() {
  group('csg листья', () {
    test('кубоид: 6 полигонов, объём = w·h·d', () {
      final polys = csgLeafPolys(cuboid('a', 0, 0, 0, 2, 1, 1.5));
      expect(polys.length, 6);
      expectWatertight(polys);
      expect(signedVolume(polys), closeTo(3.0, 1e-9));
    });

    test('повёрнутый кубоид сохраняет объём', () {
      final polys = csgLeafPolys(cuboid('a', 0, 0, 0, 2, 1, 1, rotY: 45));
      expectWatertight(polys);
      expect(signedVolume(polys), closeTo(2.0, 1e-6));
    });

    test('цилиндр: side + 2 крышки, объём N-угольника', () {
      final polys = csgLeafPolys(cyl('c', 0, 0, 0.5, 1, segments: 16));
      expect(polys.length, 18);
      expectWatertight(polys);
      final apothemVol = 16 / 2 * 0.5 * 0.5 * math.sin(2 * math.pi / 16) * 1;
      expect(signedVolume(polys), closeTo(apothemVol, 1e-6));
    });

    test('трапеция замкнута и имеет провенанс граней', () {
      final obj = ModelObject(
        id: 't',
        name: 't',
        kind: 'trapezoid',
        dims: {'bottomW': 2.0, 'bottomD': 2.0, 'topW': 1.0, 'topD': 1.0, 'h': 1.0},
      );
      final polys = csgLeafPolys(obj);
      expectWatertight(polys);
      expect(polys.length, 6);
      expectSources(polys, {'t'});
    });
  });

  group('булевы операции', () {
    test('объединение непересекающихся кубоидов = сумма объёмов', () {
      final a = csgLeafPolys(cuboid('a', 0.5, 0, 0.5, 1, 1, 1));
      final b = csgLeafPolys(cuboid('b', 2.5, 0, 0.5, 1, 1, 1));
      final u = csgApply(csgOpUnion, a, b);
      expectWatertight(u);
      expect(signedVolume(u), closeTo(2.0, 1e-9));
      expectSources(u, {'a', 'b'});
    });

    test('объединение двух впритык кубоидов без внутренней грани', () {
      // A: x ∈ [0,1], B: x ∈ [1,2] — общая плоскость x = 1.
      final a = csgLeafPolys(cuboid('a', 0.5, 0, 0.5, 1, 1, 1));
      final b = csgLeafPolys(cuboid('b', 1.5, 0, 0.5, 1, 1, 1));
      final u = csgApply(csgOpUnion, a, b);
      expectWatertight(u);
      expect(signedVolume(u), closeTo(2.0, 1e-9));
      // Внутренняя грань (плоскость x = 1) должна исчезнуть целиком.
      for (final p in u) {
        final onPlane = p.vertices.every((v) => (v.x - 1.0).abs() < 1e-4);
        final n = p.normal;
        expect(onPlane && n.x.abs() > 0.99, isFalse,
            reason: 'внутренняя грань не удалена (${p.surface.faceKey})');
      }
    });

    test('пересечение двух кубоидов = их общий объём', () {
      // A: x∈[0,1], B: x∈[0.5,1.5] → overlap 0.5.
      final a = csgLeafPolys(cuboid('a', 0.5, 0, 0.5, 1, 1, 1));
      final b = csgLeafPolys(cuboid('b', 1.0, 0, 0.5, 1, 1, 1));
      final i = csgApply(csgOpIntersect, a, b);
      expectWatertight(i);
      expect(signedVolume(i), closeTo(0.5, 1e-9));
      expectSources(i, {'a', 'b'});
    });

    test('вычитание сквозного кубоида делает отверстие', () {
      // Стена 3×1×1 на полу, окно 0.5×0.6 навылет (глубже стены).
      final wall = csgLeafPolys(cuboid('wall', 1, 0, 0.5, 3, 1, 1));
      final win = csgLeafPolys(cuboid('win', 1.5, 0.4, 0.5, 0.5, 0.6, 2));
      final d = csgApply(csgOpDifference, wall, win);
      expectWatertight(d);
      final vol = 3.0 - 0.5 * 0.6 * 1.0;
      expect(signedVolume(d), closeTo(vol, 1e-7));
      // Стенки отверстия несут провенанс вычитаемого.
      expect(d.any((p) => p.surface.objId == 'win'), isTrue);
      expectConvexPlanar(d);
    });

    test('вычитание строго внутреннего тела = объём с полостью', () {
      final big = csgLeafPolys(cuboid('big', 1, 0, 1, 3, 2, 3));
      final inner = csgLeafPolys(cuboid('inner', 1, 0.5, 1, 1, 1, 1));
      final d = csgApply(csgOpDifference, big, inner);
      expectWatertight(d);
      expect(signedVolume(d), closeTo(18 - 1.0, 1e-7));
      expect(d.any((p) => p.surface.objId == 'inner'), isTrue);
    });

    test('вычитание без пересечения = исходное тело', () {
      final a = csgLeafPolys(cuboid('a', 0.5, 0, 0, 1, 1, 1));
      final b = csgLeafPolys(cuboid('b', 3, 0, 0, 1, 1, 1));
      final d = csgApply(csgOpDifference, a, b);
      expectWatertight(d);
      expect(signedVolume(d), closeTo(1.0, 1e-9));
      expectSources(d, {'a'});
    });

    test('пересечение: кубоид в цилиндре = частичное тело', () {
      final c = csgLeafPolys(cyl('c', 1, 1, 0.4, 1, segments: 32));
      // Куб 0.4×0.5×0.4 стоит на y=0.5 внутри цилиндра-«колонны».
      final box = csgLeafPolys(cuboid('box', 1, 0.5, 1, 0.4, 1, 0.4));
      final i = csgApply(csgOpIntersect, c, box);
      expectWatertight(i);
      expect(signedVolume(i), closeTo(0.4 * 0.5 * 0.4, 1e-7));
      expectSources(i, {'c', 'box'});
    });

    test('вычитание полностью охватывающего тела = пусто', () {
      final c = csgLeafPolys(cyl('c', 1, 1, 0.4, 1, segments: 32));
      final big = csgLeafPolys(cuboid('big', 1, 0, 1, 2, 2, 2));
      final d = csgApply(csgOpDifference, c, big);
      expect(d, isEmpty);
    });
  });

  group('дерево операций (csgEvaluate)', () {
    test('(A ∪ B) ∖ C: вложенность и prune валиден', () {
      final a = cuboid('a', 0.5, 0, 0.5, 1, 1, 1);
      final b = cuboid('b', 1.5, 0, 0.5, 1, 1, 1);
      final c = cuboid('c', 1.0, 0, 0.5, 0.4, 1, 2);
      final node1 = ModelObject(
        id: 'n1',
        name: 'Объединение',
        kind: csgKind,
        op: csgOpUnion,
        operands: ['a', 'b'],
      );
      final node2 = ModelObject(
        id: 'n2',
        name: 'Вычитание',
        kind: csgKind,
        op: csgOpDifference,
        operands: ['n1', 'c'],
      );
      final model = ModelData(
        id: 'm',
        name: 'm',
        objects: [a, b, c, node1, node2],
      );
      model.pruneCsgNodes();
      expect(model.objects.map((o) => o.id),
          containsAll(['a', 'b', 'c', 'n1', 'n2']));

      final polys = csgEvaluate(node2, model);
      expectWatertight(polys);
      // (A ∪ B) = 2.0; C пробивает всё насквозь (сечение 0.4×1×1).
      expect(signedVolume(polys), closeTo(2.0 - 0.4, 1e-7));
    });

  group('скруглённые кубоиды', () {
    ModelObject roundBox(
      String id,
      double x,
      double y,
      double z,
      double w,
      double h,
      double d,
      double r, {
      int segments = 16,
    }) =>
        ModelObject(
          id: id,
          name: id,
          kind: 'cuboid',
          x: x,
          y: y,
          z: z,
          dims: {
            'w': w,
            'h': h,
            'd': d,
            'roundR': r,
            'roundSegments': segments.toDouble(),
          },
        );

    // Стейнер: объём скруглённого бокса = внутренний бокс ⊕ шар.
    double steiner(double w, double h, double d, double r) {
      final v0 = (w - 2 * r) * (h - 2 * r) * (d - 2 * r);
      final s0 = 2 *
          ((w - 2 * r) * (h - 2 * r) +
              (w - 2 * r) * (d - 2 * r) +
              (h - 2 * r) * (d - 2 * r));
      final sumL = 4 * (w + h + d - 6 * r);
      return v0 + s0 * r + (math.pi / 4 * sumL) * r * r +
          4 * math.pi / 3 * r * r * r;
    }

    // БСП-операции над фасеточными листьями оставляют микроскопические
    // осколки (~eps 1e-2 у касательных рядов): водонепроницаемость
    // проверяется с запасом.
    const roundAtol = 6e-3;

    test('лист: замкнут, наружу, провенанс граней и «round»', () {
      final polys = csgLeafPolys(roundBox('rb', 1, 0, 1, 2, 2, 2, 0.2));
      expectWatertight(polys);
      expectConvexPlanar(polys);
      expect(polys.length, 6 + 180 * 16);
      expectSources(polys, {'rb'});
      // Плоские грани + единая поверхность скруглений.
      final keys = {for (final p in polys) p.surface.faceKey};
      expect(keys, {'+x', '-x', '+y', '-y', '+z', '-z', roundFaceKey});
      // Лист сдвинут (x=1, z=1) — вершины в модельных координатах.
      final inside = vm.Vector3(1, 1, 1);
      for (final p in polys) {
        final n = p.normal;
        expect(n.dot(p.vertices[0] - inside), greaterThan(0),
            reason: 'намотка внутрь');
      }
      // Объём фасеточного тела ≈ формуле Стейнера (хорды чуть меньше).
      final vol = signedVolume(polys);
      final want = steiner(2, 2, 2, 0.2);
      expect((vol - want).abs(), lessThan(4e-3),
          reason: 'объём скруглённого листа: $vol vs $want');
    });

    test('объединение непересекающихся скруглённых кубоидов', () {
      final a = csgLeafPolys(roundBox('a', 0.5, 0, 0.5, 1, 1, 1, 0.1));
      final b = csgLeafPolys(roundBox('b', 3.0, 0, 0.5, 1, 1, 1, 0.1));
      final u = csgApply(csgOpUnion, a, b);
      expectWatertight(u, atol: roundAtol);
      expect(signedVolume(u),
          closeTo(2 * steiner(1, 1, 1, 0.1), 2e-3));
      expectSources(u, {'a', 'b'});
    });

    test('пересечение со скруглённым боксом внутри кубоида', () {
      // Скруглённый бокс целиком лежит в кубе 3×3×3.
      final big = csgLeafPolys(cuboid('big', 1.5, 0, 1.5, 3, 2, 3));
      final rb = csgLeafPolys(roundBox('rb', 1.5, 0, 1.5, 1.2, 1.2, 1.2, 0.15));
      final i = csgApply(csgOpIntersect, big, rb);
      expectWatertight(i, atol: roundAtol);
      expect(signedVolume(i),
          closeTo(steiner(1.2, 1.2, 1.2, 0.15), 8e-3));
      expectSources(i, {'big', 'rb'});
    });

    test('вычитание окна из скруглённой стены', () {
      final wall =
          csgLeafPolys(roundBox('wall', 1.5, 0, 0.5, 3, 1.2, 1, 0.15));
      final win = csgLeafPolys(cuboid('win', 2.0, 0.4, 0.5, 0.5, 0.5, 2));
      final d = csgApply(csgOpDifference, wall, win);
      expectWatertight(d, atol: roundAtol);
      expect(signedVolume(d),
          closeTo(steiner(3, 1.2, 1, 0.15) - 0.5 * 0.5, 3e-3));
      expect(d.any((p) => p.surface.objId == 'win'), isTrue,
          reason: 'стенки отверстия несут провенанс вычитаемого');
      // Внутренние куски окна несут материал скруглений стены.
      expect(
          d.any((p) =>
              p.surface.objId == 'wall' && p.surface.faceKey == roundFaceKey),
          isTrue);
    });

    test('вычитание одинакового скруглённого бокса почти пусто', () {
      final a = csgLeafPolys(roundBox('a', 1, 0, 1, 2, 2, 2, 0.2));
      final b = csgLeafPolys(roundBox('b', 1, 0, 1, 2, 2, 2, 0.2));
      final d = csgApply(csgOpDifference, a, b);
      // Тело полностью вычитается; остаются только осколки ~eps (объём
      // много меньше объёма исходного бокса 7.8).
      expect(signedVolume(d).abs(), lessThan(0.25));
    });
  });

    test('prune удаляет битые и циклические узлы', () {
      final a = cuboid('a', 0.5, 0, 0.5, 1, 1, 1);
      final broken = ModelObject(
        id: 'n1',
        name: 'x',
        kind: csgKind,
        op: csgOpUnion,
        operands: ['a', 'missing'],
      );
      final self = ModelObject(
        id: 'n2',
        name: 'self',
        kind: csgKind,
        op: csgOpUnion,
        operands: ['n2', 'a'],
      );
      final cycA = ModelObject(
        id: 'cA',
        name: 'cA',
        kind: csgKind,
        op: csgOpDifference,
        operands: ['a', 'cB'],
      );
      final cycB = ModelObject(
        id: 'cB',
        name: 'cB',
        kind: csgKind,
        op: csgOpDifference,
        operands: ['cA', 'a'],
      );
      final model = ModelData(
        id: 'm',
        name: 'm',
        objects: [a, broken, self, cycA, cycB],
      );
      model.pruneCsgNodes();
      expect(model.objects.map((o) => o.id), ['a']);
    });
  });

  group('текстурные фреймы скруглений (raw)', () {
    test('CsgBandFrame: u непрерывен между соседними фасетками полосы', () {
      final patches = roundedBoxPatches(w: 2, h: 2, d: 2, r: 0.2, segments: 8);
      CsgBandFrame frameOf(List<vm.Vector3> c, int s0) {
        final c0 = c[0], c1 = c[1];
        final row = (c[2] + c[3]) / 2 - (c0 + c1) / 2;
        final uLen = (c1 - c0).length;
        final vLen = row.length;
        return CsgBandFrame(
            c0, (c1 - c0) / uLen, uLen, row / vLen, vLen, s0, 8);
      }

      // Соседние фасетки: вершины на общем кольце θ совпадают, u на стыке
      // не «прыгает» (похордовая аппроксимация даёт близкие значения).
      var checked = 0;
      for (var i = 6; i + 1 < patches.length && checked < 3; i++) {
        final a = patches[i];
        final b = patches[i + 1];
        if (a is! RoundBandPatch || b is! RoundBandPatch) continue;
        if (b.arcIndex != a.arcIndex + 1) continue;
        // Общая вершина на кольце (θk+1, e0) = c1(a) == c0(b).
        if ((a.loop[1] - b.loop[0]).length > 1e-6) continue;
        final fa = frameOf(a.loop, a.arcIndex);
        final fb = frameOf(b.loop, b.arcIndex);
        final ua = fa.raw(a.loop[1]).$1;
        final ub = fb.raw(b.loop[0]).$1;
        expect((ua - ub).abs(), lessThan(0.03),
            reason: 'разрыв u на стыке фасеток: $ua vs $ub');
        // u на обоих концах фасетки в возрастающем порядке.
        expect(fa.raw(a.loop[0]).$1, lessThan(fa.raw(a.loop[1]).$1));
        checked++;
      }
      expect(checked, greaterThan(0));
    });

    test('CsgOctantFrame: raw в пределах [0..1] на октанте', () {
      const r = 0.2;
      const w = 2.0, h = 2.0, d = 2.0;
      final patches = roundedBoxPatches(w: w, h: h, d: d, r: r, segments: 8);
      for (final p in patches.whereType<RoundOctantPatch>()) {
        final f = CsgOctantFrame(p.center, r, p.sx, p.sy, p.sz);
        for (final v in p.loop) {
          final (u, vv) = f.raw(v);
          expect(u, inInclusiveRange(0.0, 1.0));
          expect(vv, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
