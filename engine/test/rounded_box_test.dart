import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/csg.dart'
    show CsgPoly, CsgTexOctant, csgLeafPolys;
import 'package:pet_engine/src/scene/rounded_box.dart'
    show
        RoundBandPatch,
        RoundFacePatch,
        RoundOctantPatch,
        RoundPatch,
        roundedBoxPatches;
import 'package:vector_math/vector_math.dart';

String exactKey(Vector3 v) => '${v.x}|${v.y}|${v.z}';
String roundKey(Vector3 v, double eps) =>
    '${(v.x / eps).round()}|${(v.y / eps).round()}|${(v.z / eps).round()}';

Map<String, int> edgeCounts(
  List<RoundPatch> patches,
  String Function(Vector3) key,
) {
  final edges = <String, int>{};
  for (final p in patches) {
    final loop = p.loop;
    for (var i = 0; i < loop.length; i++) {
      final a = key(loop[i]);
      final b = key(loop[(i + 1) % loop.length]);
      final k = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      edges[k] = (edges[k] ?? 0) + 1;
    }
  }
  return edges;
}

/// Суммарный ориентированный объём полигонального «супа» (веер по каждому
/// полигону от его первой вершины).
double soupVolume(List<CsgPoly> polys) {
  var volume = 0.0;
  for (final p in polys) {
    final v0 = p.vertices[0];
    for (var i = 1; i + 1 < p.vertices.length; i++) {
      final v1 = p.vertices[i];
      final v2 = p.vertices[i + 1];
      volume += v0.dot(v1.cross(v2)) / 6.0;
    }
  }
  return volume;
}

ModelObject roundedObject(double r, int segments) => ModelObject(
  id: 'rounded',
  name: 'rounded',
  kind: 'cuboid',
  dims: {
    'w': 1.6,
    'h': 1.6,
    'd': 1.6,
    'roundR': r,
    'roundSegments': segments,
  },
);

void main() {
  test('патчи скруглённого куба замкнуты по рёбрам', () {
    for (final r in [0.25, 0.6]) {
      for (final n in [12, 32]) {
        final patches = roundedBoxPatches(
          w: 1.6,
          h: 1.6,
          d: 1.6,
          r: r,
          segments: n,
        );
        for (final entry in {
          'точно': exactKey,
          '1e-9': (Vector3 v) => roundKey(v, 1e-9),
          '1e-6': (Vector3 v) => roundKey(v, 1e-6),
        }.entries) {
          final edges = edgeCounts(patches, entry.value);
          final bad = edges.entries.where((e) => e.value != 2).toList();
          expect(
            bad,
            isEmpty,
            reason:
                'r=$r n=$n ключ ${entry.key}: ${bad.take(6).map((e) => '${e.value}x ${e.key}').join(', ')}',
          );
        }
      }
    }
  });

  test('полигоны скруглённого куба ориентированы наружу и дают объём', () {
    for (final r in [0.25, 0.6]) {
      for (final n in [12, 32]) {
        final polys = csgLeafPolys(roundedObject(r, n));
        final center = Vector3(0, 0.8, 0);
        final a = 1.6 - 2 * r;
        final expected =
            a * a * a +
            2 * r * (a * a * 3) +
            math.pi * r * r * (a * 3) +
            4 / 3 * math.pi * r * r * r;
        final volume = soupVolume(polys);
        expect(
          volume,
          closeTo(expected, 0.08),
          reason: 'r=$r n=$n: объём $volume, ожидается ~$expected',
        );

        var inward = 0;
        var degenerate = 0;
        for (final p in polys) {
          if (p.area() < 1e-12) degenerate++;
          final centroid = Vector3.zero();
          for (final v in p.vertices) {
            centroid.add(v);
          }
          centroid.scale(1 / p.vertices.length);
          final radial = centroid - center;
          if (radial.length2 < 1e-12) continue;
          if (p.normal.dot(radial) <= 0) inward++;
        }
        expect(inward, 0, reason: 'r=$r n=$n: внутрь смотрят $inward');
        expect(degenerate, 0, reason: 'r=$r n=$n: вырожденных $degenerate');
      }
    }
  });

  test('нормали фасеток смотрят из центра октанта', () {
    for (final r in [0.25, 0.6]) {
      for (final n in [12, 32]) {
        final patches = roundedBoxPatches(
          w: 1.6,
          h: 1.6,
          d: 1.6,
          r: r,
          segments: n,
        );
        var badFaces = 0;
        var badOctants = 0;
        var worstOctant = 0.0;
        for (final p in patches) {
          final loop = p.loop;
          final normal = (loop[1] - loop[0])
              .cross(loop[2] - loop[0])
              .normalized();
          final centroid = Vector3.zero();
          for (final v in loop) {
            centroid.add(v);
          }
          centroid.scale(1 / loop.length);
          final cos = switch (p) {
            RoundFacePatch() => _faceCos(p.faceKey, normal),
            RoundOctantPatch(:final center) =>
              normal.dot((centroid - center).normalized()),
            RoundBandPatch() => 1.0,
          };
          if (cos < math.cos(math.pi / 4)) {
            if (p is RoundFacePatch) badFaces++;
            if (p is RoundOctantPatch) {
              badOctants++;
              if (cos < worstOctant) worstOctant = cos;
            }
          }
        }
        expect(badFaces, 0, reason: 'r=$r n=$n плоские грани');
        expect(
          badOctants,
          0,
          reason: 'r=$r n=$n угловые октанты (худший cos=$worstOctant)',
        );
      }
    }
  });

  test('UV октантов скруглённого куба не вырождаются', () {
    final obj = ModelObject(
      id: 'rounded',
      name: 'rounded',
      kind: 'cuboid',
      x: 3.5,
      z: 2,
      dims: const {
        'w': 1.2,
        'h': 1.2,
        'd': 1.2,
        'roundR': 0.25,
        'roundSegments': 12,
      },
    );
    final polys = csgLeafPolys(obj);
    final octants = [
      for (final p in polys)
        if (p.tex is CsgTexOctant) p,
    ];
    expect(octants, isNotEmpty);

    var degenerate = 0;
    var outOfBounds = 0;
    for (final p in octants) {
      final frame = (p.tex as CsgTexOctant).frame;
      // Центр октанта должен лежать внутри объекта, а не уехать от
      // повторных мутаций общего вектора.
      if (frame.center.x < 2.8 ||
          frame.center.x > 4.2 ||
          frame.center.y < -0.2 ||
          frame.center.y > 1.4 ||
          frame.center.z < 1.3 ||
          frame.center.z > 2.7) {
        outOfBounds++;
      }
      var minU = double.infinity;
      var maxU = -double.infinity;
      var minV = double.infinity;
      var maxV = -double.infinity;
      for (final v in p.vertices) {
        final (u, vv) = frame.raw(v);
        minU = math.min(minU, u);
        maxU = math.max(maxU, u);
        minV = math.min(minV, vv);
        maxV = math.max(maxV, vv);
      }
      if ((maxU - minU).abs() + (maxV - minV).abs() < 1e-4) degenerate++;
    }
    expect(outOfBounds, 0, reason: 'центры октантов вне объекта');
    expect(degenerate, 0, reason: 'вырожденные UV октантов');
  });
}

/// cos между нормалью и осью плоской грани.
double _faceCos(String key, Vector3 normal) {
  final axis = switch (key) {
    '+x' => Vector3(1, 0, 0),
    '-x' => Vector3(-1, 0, 0),
    '+y' => Vector3(0, 1, 0),
    '-y' => Vector3(0, -1, 0),
    '+z' => Vector3(0, 0, 1),
    _ => Vector3(0, 0, -1),
  };
  return normal.dot(axis);
}
