import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart' show roundFaceKey;

/// Fully-rounded cuboid («rounded box») geometry.
///
/// A cuboid with a rounding radius `r > 0` keeps its 6 outer face planes
/// (trimmed to the inner rectangle) while every edge becomes a
/// quarter-cylinder of radius r and every corner becomes a sphere octant —
/// all tangent to the face planes. The solid is the Minkowski sum of an
/// inner box (inset by r on every side, centered the same way) and a ball
/// of radius r, so it stays CONVEX and every rounded zone blends
/// tangentially into its neighbors.
///
/// The tessellation lives HERE in pure model-local coordinates (no engine,
/// no textures): the CSG leaf builder (`csg.dart`) and the renderer consume
/// exactly the same patch list, so the shape shown on screen is the shape
/// boolean operations cut. Face patches keep the six planar face keys
/// ('+x'…'-y'); every curved patch carries [roundFaceKey] ('round').

/// The effective rounding radius: never more than half of the smallest
/// side, never negative.
double clampRoundRadius(double w, double h, double d, double r) {
  if (r <= 0) return 0;
  return math.min(r, math.min(math.min(w, h), d) / 2);
}

/// Arc angle k of n at a quarter turn: k = 0 → 0, k = n → exactly π/2,
/// otherwise the uniform step. Every surface sampling a shared boundary arc
/// uses the same helper with the same k, so their vertices coincide bitwise.
double _arcAngle(int k, int n) => math.pi / 2 * k / n;

/// (cos, sin) of the arc angle [k], with the boundary values exact:
/// k = 0 → (1, 0), k = n → (0, 1) (math.cos(math.pi / 2) is not exactly 0).
(double, double) _arcPair(int k, int n) => k == 0
    ? (1, 0)
    : k == n
        ? (0, 1)
        : (math.cos(_arcAngle(k, n)), math.sin(_arcAngle(k, n)));

// ── patches ─────────────────────────────────────────────────────────────

/// One planar-convex piece of the rounded surface: the vertex loop plus the
/// piece's texture role. Loops are wound OUTWARD.
sealed class RoundPatch {
  final String faceKey;
  final List<vm.Vector3> loop;
  RoundPatch(this.faceKey, this.loop);
}

/// A planar face of the rounded box: the outer face plane trimmed to the
/// inner rectangle. Corners keep the renderer's quad order (bottom-left →
/// bottom-right → top-right → top-left), like `cuboidFaceCorners`.
class RoundFacePatch extends RoundPatch {
  RoundFacePatch(super.faceKey, super.loop);
}

/// One quad facet of an edge fillet: a planar parallelogram strip between
/// two arc generators. Corners are ordered
/// (θ_k at edge start) → (θ_{k+1} at edge start) → (θ_{k+1} at edge end) →
/// (θ_k at edge end), so the facet's u row runs along the arc and its v row
/// along the rounded edge.
class RoundBandPatch extends RoundPatch {
  /// k — the facet's arc step (0..segments−1).
  final int arcIndex;

  /// Total arc segments.
  final int segments;
  RoundBandPatch(List<vm.Vector3> loop, this.arcIndex, this.segments)
      : super(roundFaceKey, loop);
}

/// One triangle facet of a corner sphere octant.
class RoundOctantPatch extends RoundPatch {
  /// The octant's sphere center (the inner-box corner).
  final vm.Vector3 center;

  /// Radius of the sphere.
  final double radius;

  /// Outward sign octant of the corner (±1 each).
  final int sx, sy, sz;
  RoundOctantPatch(
    this.center,
    this.radius,
    this.sx,
    this.sy,
    this.sz,
    List<vm.Vector3> loop,
  ) : super(roundFaceKey, loop);
}

/// The rounded box's boundary patches for outer dims w×h×d, rounding
/// radius [r] and [segments] arc steps (clamped to 3..64), in object-local
/// coordinates (base at y = 0, X/Z centered like the cuboid's faces).
/// Closed (every shared edge appears twice) and wound outward; the patch
/// count is 6 + 12n fillet quads + 168n corner triangles (8 octants × 21n,
/// four rings each).
List<RoundPatch> roundedBoxPatches({
  required double w,
  required double h,
  required double d,
  required double r,
  required int segments,
}) {
  final rr = clampRoundRadius(w, h, d, r);
  if (rr <= 0) return const [];
  final n = segments < 3 ? 3 : (segments > 64 ? 64 : segments);
  final cy = h / 2;
  final out = <RoundPatch>[];

  // Inner half-extents (outer box inset by r) and axis centers. The inner
  // box is centered at (0, h/2, 0) — like the outer box.
  final half = [w / 2 - rr, h / 2 - rr, d / 2 - rr];
  final center = [0.0, cy, 0.0];

  /// Coordinate along axis [e] at the side [s] with a radial offset [off]:
  /// s = ±1, off = 0 → the inner bound, off = rr → the outer face plane.
  /// One shared formula keeps vertices that sit on the same tangent line
  /// bitwise equal across patches.
  double coord(int e, int s, double off) => center[e] + s * (half[e] + off);

  // A point of the box well inside the solid (the center of the inner box).
  final inside = vm.Vector3(0, cy, 0);

  List<vm.Vector3> outward(List<vm.Vector3> loop) {
    final c = (loop[1] - loop[0]).cross(loop[2] - loop[0]);
    return c.dot(loop[0] - inside) < 0
        ? loop.reversed.toList()
        : List.of(loop);
  }

  vm.Vector3 v(double x, double y, double z) => vm.Vector3(x, y, z);

  // ── the six planar faces (renderer quad order) ─────────────────────
  final xlo = -half[0], xhi = half[0];
  final ylo = center[1] - half[1], yhi = center[1] + half[1];
  final zlo = -half[2], zhi = half[2];
  final xpos = coord(0, 1, rr), xneg = -xpos;
  final ytop = coord(1, 1, rr), ybot = coord(1, -1, rr);
  final zpos = coord(2, 1, rr), zneg = -zpos;
  final faces = <String, List<vm.Vector3>>{
    '+z': [
      v(xlo, ylo, zpos),
      v(xhi, ylo, zpos),
      v(xhi, yhi, zpos),
      v(xlo, yhi, zpos),
    ],
    '-z': [
      v(xhi, ylo, zneg),
      v(xlo, ylo, zneg),
      v(xlo, yhi, zneg),
      v(xhi, yhi, zneg),
    ],
    '+x': [
      v(xpos, ylo, zhi),
      v(xpos, ylo, zlo),
      v(xpos, yhi, zlo),
      v(xpos, yhi, zhi),
    ],
    '-x': [
      v(xneg, ylo, zlo),
      v(xneg, ylo, zhi),
      v(xneg, yhi, zhi),
      v(xneg, yhi, zlo),
    ],
    '+y': [
      v(xlo, ytop, zhi),
      v(xhi, ytop, zhi),
      v(xhi, ytop, zlo),
      v(xlo, ytop, zlo),
    ],
    '-y': [
      v(xlo, ybot, zlo),
      v(xhi, ybot, zlo),
      v(xhi, ybot, zhi),
      v(xlo, ybot, zhi),
    ],
  };
  // (varying span 1, varying span 2) of each face — degenerate faces (a
  // rounding of half the smallest side) are dropped.
  (double, double) spanOf(String key) => switch (key) {
        '+z' || '-z' => (xhi - xlo, yhi - ylo),
        '+x' || '-x' => (zhi - zlo, yhi - ylo),
        _ => (xhi - xlo, zhi - zlo),
      };
  for (final f in faces.entries) {
    final (sa, sb) = spanOf(f.key);
    if (sa < 1e-9 || sb < 1e-9) continue;
    out.add(RoundFacePatch(f.key, outward(f.value)));
  }

  // ── the 12 edge fillets: quarter-cylinder strips ────────────────────
  for (var e = 0; e < 3; e++) {
    if (half[e] < 1e-9) continue;
    final p = (e + 1) % 3, q = (e + 2) % 3;
    for (final sp in const [-1, 1]) {
      for (final sq in const [-1, 1]) {
        // The inner edge runs along axis e between two inner corners; the
        // cross-section circle lives in the (p, q) plane, tangent to the
        // outer p/q face planes at θ = 0 and θ = π/2.
        vm.Vector3 bandPoint(int ts, double c, double s) {
          final comps = <double>[0, 0, 0];
          comps[e] = center[e] + ts * half[e];
          comps[p] = coord(p, sp, rr * c);
          comps[q] = coord(q, sq, rr * s);
          return v(comps[0], comps[1], comps[2]);
        }

        for (var k = 0; k < n; k++) {
          final (c0, s0) = _arcPair(k, n);
          final (c1, s1) = _arcPair(k + 1, n);
          final quad = [
            bandPoint(-1, c0, s0),
            bandPoint(-1, c1, s1),
            bandPoint(1, c1, s1),
            bandPoint(1, c0, s0),
          ];
          out.add(RoundBandPatch(outward(quad), k, n));
        }
      }
    }
  }

  // ── the 8 corner octants ────────────────────────────────────────────
  // Each sphere octant is a stack of rings from the interior apex to the
  // boundary loop (the three quarter arcs shared with the adjacent
  // fillets). A single apex fan would leave a fixed chord sagitta that
  // never shrinks with n; each additional ring divides that arc and cuts
  // the sagitta by its square, keeping the surface convex.
  const rings = 4;
  final invSqrt3 = 1 / math.sqrt(3); // octant's body-diagonal direction
  for (final sx in const [-1, 1]) {
    for (final sy in const [-1, 1]) {
      for (final sz in const [-1, 1]) {
        final octCenter = v(coord(0, sx, 0), coord(1, sy, 0), coord(2, sz, 0));
        // Points of the octant's surface with canonical direction (dx, dy,
        // dz) (the sign octant's own frame): components are radial offsets
        // from the inner-box corner.
        vm.Vector3 pt(double dx, double dy, double dz) => v(
              coord(0, sx, rr * dx),
              coord(1, sy, rr * dy),
              coord(2, sz, rr * dz),
            );
        // The boundary loop: x-arc (x→y), then y-arc (y→z), then z-arc
        // (z→x), each quarter arc sampled with the shared arc helper so the
        // ring vertices coincide with the fillet end rings bitwise.
        final bLoop = <vm.Vector3>[];
        for (var k = 1; k <= n; k++) {
          final (c, s) = _arcPair(k, n);
          bLoop.add(pt(c, s, 0)); // x→y arc
        }
        for (var k = 1; k <= n; k++) {
          final (c, s) = _arcPair(k, n);
          bLoop.add(pt(0, c, s)); // y→z arc
        }
        for (var k = 1; k <= n; k++) {
          final (c, s) = _arcPair(k, n);
          bLoop.add(pt(s, 0, c)); // z→x arc (toward the x corner)
        }
        final apex = pt(invSqrt3, invSqrt3, invSqrt3);
        // Ring [level] (1..rings−1): canonical directions interpolated
        // between the apex and each boundary point, snapped onto the sphere.
        final ringLoops = <List<vm.Vector3>>[];
        for (var level = 1; level < rings; level++) {
          final t = level / rings;
          final ring = <vm.Vector3>[];
          for (final b in bLoop) {
            final d = (b - octCenter) / rr; // canonical-ish spatial dir
            final dx = sx * d.x, dy = sy * d.y, dz = sz * d.z;
            final nx = invSqrt3 + t * (dx - invSqrt3);
            final ny = invSqrt3 + t * (dy - invSqrt3);
            final nz = invSqrt3 + t * (dz - invSqrt3);
            final l = math.sqrt(nx * nx + ny * ny + nz * nz);
            ring.add(pt(nx / l, ny / l, nz / l));
          }
          ringLoops.add(ring);
        }
        final ring = 3 * n;
        // Cap: the apex fan to the first ring.
        final first = ringLoops.first;
        for (var i = 0; i < ring; i++) {
          final j = (i + 1) % ring;
          out.add(RoundOctantPatch(octCenter, rr, sx, sy, sz,
              outward([apex, first[i], first[j]])));
        }
        // Annular bands between rings, then the last ring to the boundary.
        for (var level = 0; level < ringLoops.length; level++) {
          final inner = ringLoops[level];
          final outer = level + 1 < ringLoops.length
              ? ringLoops[level + 1]
              : bLoop;
          for (var i = 0; i < ring; i++) {
            final j = (i + 1) % ring;
            out.add(RoundOctantPatch(octCenter, rr, sx, sy, sz,
                outward([inner[i], inner[j], outer[j]])));
            out.add(RoundOctantPatch(octCenter, rr, sx, sy, sz,
                outward([inner[i], outer[j], outer[i]])));
          }
        }
      }
    }
  }
  return out;
}
