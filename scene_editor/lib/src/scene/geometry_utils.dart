import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Custom geometry for the model editor (game-compatible PBR pipeline).

/// Packs consecutive point PAIRS into segment endpoints: points[2i] and
/// points[2i+1] become one segment (six distinct floats). A trailing odd
/// point is dropped. Pure, so it can be unit-tested without a GPU.
Float32List packSegmentPairs(List<(double, double, double)> points) {
  final count = points.length ~/ 2;
  final floats = Float32List(count * 6);
  for (var i = 0; i < count; i++) {
    final (ax, ay, az) = points[i * 2];
    final (bx, by, bz) = points[i * 2 + 1];
    final base = i * 6;
    floats[base] = ax;
    floats[base + 1] = ay;
    floats[base + 2] = az;
    floats[base + 3] = bx;
    floats[base + 4] = by;
    floats[base + 5] = bz;
  }
  return floats;
}

/// Thick line segments from a list of point pairs (xyz triples). Each pair
/// of consecutive points is ONE segment — a degenerate (zero-length) segment
/// would collapse to an invisible hairline in the line shader. A trailing odd
/// point is dropped.
LineGeometry lineSegments(
  List<(double, double, double)> points, {
  double width = 0.012,
}) {
  final count = points.length ~/ 2;
  final segments = <vm.Vector3>[];
  for (var i = 0; i < count; i++) {
    final (ax, ay, az) = points[i * 2];
    final (bx, by, bz) = points[i * 2 + 1];
    segments
      ..add(vm.Vector3(ax, ay, az))
      ..add(vm.Vector3(bx, by, bz));
  }
  return LineGeometry(segments, width: width);
}

/// The ring-tube (torus) vertex positions for [ringTubeGeometry] — the
/// cross-section circle (radius [tubeRadius]) swept around the main ring
/// (radius [radius]) in the XZ plane. Pure, unit-testable.
List<vm.Vector3> ringTubeVertices({
  double radius = 0.9,
  double tubeRadius = 0.09,
  int ringSegments = 48,
  int tubeSegments = 10,
}) {
  final verts = <vm.Vector3>[];
  // Cross-section basis at ring angle a: radial-out n = (cos a, 0, sin a),
  // the ring axis b = (0, 1, 0) — the cross-section circle spans
  // n·cos t + b·sin t around the ring point R·n.
  for (var i = 0; i < ringSegments; i++) {
    final a0 = 2 * math.pi * i / ringSegments;
    final a1 = 2 * math.pi * (i + 1) / ringSegments;
    final n0 = vm.Vector3(math.cos(a0), 0, math.sin(a0));
    final n1 = vm.Vector3(math.cos(a1), 0, math.sin(a1));
    final p0 = n0 * radius;
    final p1 = n1 * radius;
    final axis = vm.Vector3(0, 1, 0);
    for (var j = 0; j < tubeSegments; j++) {
      final t0 = 2 * math.pi * j / tubeSegments;
      final t1 = 2 * math.pi * (j + 1) / tubeSegments;
      final c0 = math.cos(t0), s0 = math.sin(t0);
      final c1 = math.cos(t1), s1 = math.sin(t1);
      final q00 = p0 + (n0 * c0 + axis * s0) * tubeRadius;
      final q10 = p1 + (n1 * c0 + axis * s0) * tubeRadius;
      final q11 = p1 + (n1 * c1 + axis * s1) * tubeRadius;
      final q01 = p0 + (n0 * c1 + axis * s1) * tubeRadius;
      verts.addAll([q00, q10, q11, q01]);
    }
  }
  return verts;
}

/// An OPEN tube shaped as a ring (torus) in the XZ plane: a circle of
/// [radius] centered on the origin, swept along +Y, with a circular
/// cross-section of [tubeRadius]. No caps — a raycast hits only the ring
/// itself, the disc inside stays clickable. Used for the rotate gizmo's
/// invisible hit zones. Pure geometry, no materials.
SceneGeometry ringTubeGeometry({
  double radius = 0.9,
  double tubeRadius = 0.09,
  int ringSegments = 48,
  int tubeSegments = 10,
}) {
  final verts = ringTubeVertices(
    radius: radius,
    tubeRadius: tubeRadius,
    ringSegments: ringSegments,
    tubeSegments: tubeSegments,
  );
  final b = GeometryBuilder();
  for (var i = 0; i < ringSegments; i++) {
    for (var j = 0; j < tubeSegments; j++) {
      final base = (i * tubeSegments + j) * 4;
      b.setNormal(verts[base].normalized());
      final i0 = b.addVertex(verts[base]);
      final i1 = b.addVertex(verts[base + 1]);
      final i2 = b.addVertex(verts[base + 2]);
      final i3 = b.addVertex(verts[base + 3]);
      b.addTriangle(i0, i1, i2);
      b.addTriangle(i0, i2, i3);
    }
  }
  return b.build();
}

/// Wireframe box centered at [center] with extents [size]: twelve line
/// segments (a [LineNode] with the double-sided unlit line material). The
/// [color] is the passed RGBA Vector4 (white by default); [alphaBlend]
/// switches the material to the blend alpha mode.
LineNode wireframeBox(
  vm.Vector3 center,
  vm.Vector3 size, {
  double width = 0.014,
  vm.Vector4? color,
  bool alphaBlend = false,
}) {
  final col = color ?? vm.Vector4(1, 1, 1, 1);
  final hx = size.x / 2, hy = size.y / 2, hz = size.z / 2;
  final (x0, x1) = (center.x - hx, center.x + hx);
  final (y0, y1) = (center.y - hy, center.y + hy);
  final (z0, z1) = (center.z - hz, center.z + hz);
  final pts = <(double, double, double)>[
    // bottom face
    (x0, y0, z0), (x1, y0, z0), (x1, y0, z0), (x1, y0, z1),
    (x1, y0, z1), (x0, y0, z1), (x0, y0, z1), (x0, y0, z0),
    // top face
    (x0, y1, z0), (x1, y1, z0), (x1, y1, z0), (x1, y1, z1),
    (x1, y1, z1), (x0, y1, z1), (x0, y1, z1), (x0, y1, z0),
    // verticals
    (x0, y0, z0), (x0, y1, z0), (x1, y0, z0), (x1, y1, z0),
    (x1, y0, z1), (x1, y1, z1), (x0, y0, z1), (x0, y1, z1),
  ];
  final node = LineNode(
    geometry: lineSegments(pts),
    color: Color.fromARGB(
      (col.w * 255).round(),
      (col.x * 255).round(),
      (col.y * 255).round(),
      (col.z * 255).round(),
    ),
    width: width,
  );
  if (alphaBlend) node.material.alphaMode = SceneAlphaMode.blend;
  return node;
}
