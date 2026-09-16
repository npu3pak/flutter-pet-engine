import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import 'rounded_box.dart';

/// A live boolean operation (CSG) engine over the editor's convex
/// primitives.
///
/// All math runs in MODEL space (pure Cartesian coordinates, no engine
/// mirrors or winding quirks — those belong to the renderer). Each leaf
/// primitive is turned into a closed convex polygon soup where every input
/// polygon carries its provenance (leaf object id + face key) and a texture
/// frame that describes how the ORIGINAL face was parameterized by the
/// renderer. Boolean ops are performed with the classic BSP-node
/// clip/invert algorithm; every output polygon is a planar convex sub-piece
/// of exactly one input polygon, so provenance and texture frames survive
/// clipping and texture continuity across a result surface is preserved.
///
/// Faces are oriented outward (winding CCW when viewed from the outside),
/// including the polygon pieces produced by a subtraction (cutter surfaces
/// that border the void).

/// Plane-classification tolerance (in model units — one unit is one cell).
/// Coordinates live in float32 (vector_math), so the plane distance of a
/// point that GEOMETRICALLY lies on a plane carries up to ~1e-4..1e-3 noise
/// on scene-sized coordinates — and the tangency rows of faceted solids
/// (rounded boxes) place many near-parallel planes close to that noise.
/// Below the noise the split/clip breeds slivers without bound (a storm
/// that can eat gigabytes); a generous tolerance makes such clusters
/// classify as coplanar and keeps every operation bounded (the split
/// budget in [csgApply] is the final guard). Editor features are ≥ 0.01
/// cells, so merging planes closer than 1e-2 is never visible.
const csgEpsilon = 1e-2;

/// Drops output polygons whose area is below this threshold.
const csgAreaEpsilon = 1e-9;

// ── split budget ────────────────────────────────────────────────────────
//
// Near-coplanar facet clusters (a rounded cuboid's leaf has hundreds of
// planes within float32 noise of each other) can make the classic BSP
// split/clip non-terminating: a chain of partitions that each consume one
// polygon while its neighbors keep straddling the next near-parallel plane
// breeds fragments without bound. Every partition spends from a budget set
// per operation; when it runs out the operation ABORTS and the caller
// falls back to operand A (visible, editable) instead of hanging forever.

/// Thrown internally when a boolean operation exceeds its split budget.
class _CsgBudgetExceeded implements Exception {}

int _csgSplitBudget = 0;

void _spendSplit() {
  if (_csgSplitBudget-- < 0) throw _CsgBudgetExceeded();
}

// ── texture frames ─────────────────────────────────────────────────────
//
// A frame describes how points of a source face map to raw texture
// coordinates of the ORIGINAL face (the renderer's quad/ring UVs). Pieces
// clipped out of a face live in its plane, so the raw (u, v) of any piece
// vertex is a projection onto the frame's axes. The renderer then applies
// the material's stretch/tile/uvDir/flip semantics on top.

/// Planar (quad) frame: axes along the face's own edges.
class CsgQuadFrame {
  /// Face corner that carries renderer UV (u=0, v=1).
  final vm.Vector3 origin;
  final vm.Vector3 dirU; // unit, bottom row direction (u increases)
  final vm.Vector3 dirV; // unit, bottom→top row direction (v=1→0)
  final double spanU; // model length of a full bottom row (uExtent)
  final double spanV; // model length between rows (vExtent)

  CsgQuadFrame(this.origin, this.dirU, this.dirV, this.spanU, this.spanV);

  /// Raw coords in the [0..1] square of the original face.
  (double, double) raw(vm.Vector3 p) {
    final d = p - origin;
    return (d.dot(dirU) / spanU, d.dot(dirV) / spanV);
  }
}

/// Ring frame (cylinder/cone side facets): u runs around the circumference
/// as a fraction of the FULL ring ([s0]/[segments] .. [s0]+1/...), v is
/// vertical height. chord-based (u of an interior piece vertex is its
/// fraction along the facet's chord) — close to the renderer's angular wrap
/// for the editor's segment counts.
class CsgRingFrame {
  final vm.Vector3 origin; // facet bottom-left (ring s0, v=1)
  final vm.Vector3 dirChord; // unit, bottom row direction
  final double chordLen;
  final double spanV;
  final int s0;
  final int segments;
  final double maxR; // widest ring radius (texture wrap = 2π·maxR)

  CsgRingFrame(
    this.origin,
    this.dirChord,
    this.chordLen,
    this.spanV,
    this.s0,
    this.segments,
    this.maxR,
  );

  (double, double) raw(vm.Vector3 p) {
    final d = p - origin;
    final f = d.dot(dirChord) / chordLen;
    return ((s0 + f.clamp(0.0, 1.0)) / segments, d.dot(dirV()) / spanV);
  }

  vm.Vector3 dirV() => vm.Vector3(0, 1, 0);
}

/// Disc frame (cylinder caps): the cap's fixed UV puts the whole texture in
/// the circle: u = 0.5 + x/(2R), v = 0.5 − z/(2R) (v down keeps the disc
/// orientation consistent with the renderer's disc fan).
class CsgDiscFrame {
  final vm.Vector3 center;
  final double radius;
  CsgDiscFrame(this.center, this.radius);

  (double, double) raw(vm.Vector3 p) {
    final d = p - center;
    return (0.5 + d.x / (2 * radius), 0.5 - d.z / (2 * radius));
  }
}

/// Band frame (rounded-cuboid edge fillet): u runs across the quarter arc
/// as a fraction of the FULL arc ([s0]/[segments] .. [s0]+1/..., chord-based
/// per facet like the cylinder ring), v is the position along the rounded
/// edge (its [spanV] is the full edge length).
class CsgBandFrame {
  final vm.Vector3 origin; // facet corner at (arc start, edge start)
  final vm.Vector3 dirU; // unit, along the facet's arc chord (u increases)
  final double spanU; // the facet's chord length
  final vm.Vector3 dirV; // unit, edge start → edge end direction
  final double spanV; // the edge length
  final int s0; // the facet's arc step (0..segments−1)
  final int segments;

  CsgBandFrame(
    this.origin,
    this.dirU,
    this.spanU,
    this.dirV,
    this.spanV,
    this.s0,
    this.segments,
  );

  (double, double) raw(vm.Vector3 p) {
    final d = p - origin;
    final f = d.dot(dirU) / spanU;
    return ((s0 + f.clamp(0.0, 1.0)) / segments, d.dot(dirV) / spanV);
  }
}

/// Octant frame (rounded-cuboid corner): the sphere octant of radius
/// [radius] around [center] facing the sign octant (sx, sy, sz). raw() maps
/// the surface direction (p − center)/radius into the octant's spherical
/// square: u = azimuth fraction, v = polar fraction from the apex (+x).
class CsgOctantFrame {
  final vm.Vector3 center;
  final double radius;
  final int sx, sy, sz;

  CsgOctantFrame(this.center, this.radius, this.sx, this.sy, this.sz);

  (double, double) raw(vm.Vector3 p) {
    final d = (p - center) / radius;
    // Canonicalize into the +x+y+z octant (clamped for fp noise at the
    // boundary planes).
    final nx = (sx * d.x).clamp(0.0, 1.0);
    final ny = (sy * d.y).clamp(0.0, 1.0);
    final nz = (sz * d.z).clamp(0.0, 1.0);
    final phi = math.atan2(math.sqrt(ny * ny + nz * nz), nx);
    final psi = math.atan2(nz, ny);
    return (psi / (math.pi / 2), phi / (math.pi / 2));
  }
}

/// How one polygon's surface is textured (per-frame raw mapping).
sealed class CsgTex {}

class CsgTexQuad extends CsgTex {
  final CsgQuadFrame frame;
  final double uExtent; // model width for density scaling
  final double vExtent;
  final bool alwaysTile;
  CsgTexQuad(this.frame, this.uExtent, this.vExtent, this.alwaysTile);
}

class CsgTexRing extends CsgTex {
  final CsgRingFrame frame;
  final double height; // model height (v density)
  CsgTexRing(this.frame, this.height);
}

class CsgTexDisc extends CsgTex {
  final CsgDiscFrame frame;
  CsgTexDisc(this.frame);
}

/// Edge-fillet facets of a rounded cuboid: the texture tiles ALWAYS at the
/// tileScale — u around the arc (its full model length [arcLen] = π/2·r),
/// v along the edge (the facet frame's spanV).
class CsgTexBand extends CsgTex {
  final CsgBandFrame frame;
  final double arcLen;
  CsgTexBand(this.frame, this.arcLen);
}

/// Corner-octant facets of a rounded cuboid: like [CsgTexBand], the texture
/// tiles at the tileScale on the octant's spherical square, both axes with
/// the model length [arcLen] (π/2·r).
class CsgTexOctant extends CsgTex {
  final CsgOctantFrame frame;
  final double arcLen;
  CsgTexOctant(this.frame, this.arcLen);
}

/// The provenance of an input face: which leaf primitive + which face key.
class CsgSurface {
  final String objId;
  final String faceKey;
  const CsgSurface(this.objId, this.faceKey);
}

/// A planar convex polygon of a solid surface, wound so its normal points
/// OUTWARD of the solid it bounds (for polygon pieces produced by boolean
/// ops this is outward of the RESULT). [surface] and [tex] describe the
/// input face this piece was clipped from and survive every split.
class CsgPoly {
  List<vm.Vector3> vertices;
  final CsgSurface surface;
  final CsgTex tex;

  /// Plane normal + offset (n·x = w), recomputed lazily.
  vm.Vector3? _n;
  double _w = 0;

  CsgPoly(this.vertices, this.surface, this.tex);

  /// Plane normal (unit). Recomputed lazily and cached after mutations.
  vm.Vector3 get normal {
    final n = _n;
    if (n != null) return n;
    final a = vertices[1] - vertices[0];
    final b = vertices[2] - vertices[0];
    final c = a.cross(b).normalized();
    _n = c;
    _w = c.dot(vertices[0]);
    return c;
  }

  /// Plane offset such that n·x = w.
  double get w {
    normal;
    return _w;
  }

  CsgPoly clone() => CsgPoly(List.of(vertices), surface, tex)
    .._n = _n
    .._w = _w;

  /// Reverses the winding (used by BSP invert) and recomputes the plane.
  void flip() {
    vertices = vertices.reversed.toList();
    _n = null;
    _w = 0;
  }

  double area() {
    var a = 0.0;
    for (var i = 1; i < vertices.length - 1; i++) {
      a += (vertices[i] - vertices[0]).cross(vertices[i + 1] - vertices[0]).length;
    }
    return a / 2;
  }
}

// ── BSP node ───────────────────────────────────────────────────────────

class _CsgNode {
  vm.Vector3? planeN; // plane normal (unit) of this partition
  double planeW = 0;
  _CsgNode? front;
  _CsgNode? back;
  final List<CsgPoly> polygons = [];

  _CsgNode([List<CsgPoly>? polys]) {
    if (polys != null) build(polys);
  }

  void _setPlaneFrom(CsgPoly p) {
    planeN = p.normal;
    planeW = p.w;
  }

  /// The tree of a poly soup is built iteratively: leaves of faceted
  /// primitives (a rounded cuboid is ~4k polygons) would exhaust the native
  /// stack through recursive partition when planes come in near-parallel
  /// clusters.
  void invert() {
    final stack = <_CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      for (final p in node.polygons) {
        p.flip();
      }
      node.planeN = node.planeN == null ? null : -node.planeN!;
      node.planeW = -node.planeW;
      final t = node.front;
      node.front = node.back;
      node.back = t;
      final f = node.front;
      final b = node.back;
      if (f != null) stack.add(f);
      if (b != null) stack.add(b);
    }
  }

  List<CsgPoly> clipPolygons(List<CsgPoly> polys) {
    final out = <CsgPoly>[];
    final stack = <(_CsgNode, List<CsgPoly>)>[(this, polys)];
    while (stack.isNotEmpty) {
      final (node, list) = stack.removeLast();
      final n = node.planeN;
      if (n == null) {
        out.addAll(list);
        continue;
      }
      final frontList = <CsgPoly>[];
      final backList = <CsgPoly>[];
      for (final p in list) {
        _spendSplit();
        _splitPolygon(p, n, node.planeW, frontList, backList, frontList,
            backList);
      }
      // Fragments that fell into a subtree-less BACK side are inside the
      // solid bounded by this node's polygons and get removed; fragments on
      // the FRONT side always survive.
      final front = node.front;
      final back = node.back;
      if (back != null) stack.add((back, backList));
      if (front != null) {
        stack.add((front, frontList));
      } else {
        out.addAll(frontList);
      }
    }
    return out;
  }

  void clipTo(_CsgNode other) {
    final stack = <_CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      // NOTE: copy BEFORE mutating — the cascade below would otherwise clear
      // the very list the clip argument reads.
      final mine = List.of(node.polygons);
      node.polygons
        ..clear()
        ..addAll(other.clipPolygons(mine));
      final f = node.front;
      final b = node.back;
      if (f != null) stack.add(f);
      if (b != null) stack.add(b);
    }
  }

  List<CsgPoly> allPolygons() {
    final out = <CsgPoly>[];
    final stack = <_CsgNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      out.addAll(node.polygons);
      final f = node.front;
      final b = node.back;
      if (b != null) stack.add(b);
      if (f != null) stack.add(f);
    }
    return out;
  }

  /// The splitter of a poly list: the polygon whose plane normal is closest
  /// to the list's MEAN normal. Faceted leaves (rounded cuboids) feed their
  /// polygons in arc order — near-parallel planes in a row — and picking the
  /// first one builds a linear ladder (each level consumes a single facet,
  /// so a clip walks O(n) planes and fragments multiply); the mean normal
  /// picks a plane that partitions the cluster in halves.
  static CsgPoly _partitionOf(List<CsgPoly> list) {
    final sum = vm.Vector3.zero();
    for (final p in list) {
      sum.add(p.normal);
    }
    if (sum.length < 1e-9) return list.first;
    final dir = sum.normalized();
    var best = list.first;
    var bestDot = -1.0;
    for (final p in list) {
      final d = p.normal.dot(dir);
      if (d > bestDot) {
        bestDot = d;
        best = p;
      }
    }
    return best;
  }

  void build(List<CsgPoly> polys) {
    final work = <(_CsgNode, List<CsgPoly>)>[(this, polys)];
    while (work.isNotEmpty) {
      final (node, list) = work.removeLast();
      if (list.isEmpty) continue;
      if (node.planeN == null) node._setPlaneFrom(_partitionOf(list));
      final frontList = <CsgPoly>[];
      final backList = <CsgPoly>[];
      for (final p in list) {
        _spendSplit();
        _splitPolygon(p, node.planeN!, node.planeW, node.polygons,
            node.polygons, frontList, backList);
      }
      if (frontList.isNotEmpty) {
        final child = node.front ??= _CsgNode();
        work.add((child, frontList));
      }
      if (backList.isNotEmpty) {
        final child = node.back ??= _CsgNode();
        work.add((child, backList));
      }
    }
  }
}

/// Splits [p] by plane n·x = w into [front]/[back] (and stores coplanar
/// polygons into [coplanarFront]/[coplanarBack] — the two coplanar lists
/// receive same-orientation / opposite-orientation polygons respectively).
void _splitPolygon(
  CsgPoly p,
  vm.Vector3 n,
  double w,
  List<CsgPoly> coplanarFront,
  List<CsgPoly> coplanarBack,
  List<CsgPoly> front,
  List<CsgPoly> back,
) {
  const backType = 1;
  const frontType = 2;
  final verts = p.vertices;
  var type = 0;
  final types = <int>[];
  for (final v in verts) {
    final d = n.dot(v) - w;
    final t = d < -csgEpsilon ? backType : (d > csgEpsilon ? frontType : 0);
    type |= t;
    types.add(t);
  }
  switch (type) {
    case 0: // COPLANAR
      (n.dot(p.normal) > 0 ? coplanarFront : coplanarBack).add(p);
    case frontType:
      front.add(p);
    case backType:
      back.add(p);
    default:
      final f = <vm.Vector3>[];
      final b = <vm.Vector3>[];
      for (var i = 0; i < verts.length; i++) {
        final j = (i + 1) % verts.length;
        final ti = types[i];
        final tj = types[j];
        final vi = verts[i];
        final vj = verts[j];
        if (ti != backType) f.add(vi);
        if (ti != frontType) b.add(ti != backType ? vm.Vector3.copy(vi) : vi);
        if ((ti | tj) == (frontType | backType)) {
          final t = (w - n.dot(vi)) / n.dot(vj - vi);
          final v = vm.Vector3(
            vi.x + (vj.x - vi.x) * t,
            vi.y + (vj.y - vi.y) * t,
            vi.z + (vj.z - vi.z) * t,
          );
          f.add(v);
          b.add(vm.Vector3.copy(v));
        }
      }
      if (f.length >= 3) front.add(CsgPoly(f, p.surface, p.tex));
      if (b.length >= 3) back.add(CsgPoly(b, p.surface, p.tex));
  }
}

// ── boolean operations ─────────────────────────────────────────────────

/// Keeps [a]'s surface pieces outside [b]; used by union (and the invert
/// dance of subtract).
List<CsgPoly> _union(List<CsgPoly> a, List<CsgPoly> b) {
  final na = _CsgNode(a);
  final nb = _CsgNode(b);
  na.clipTo(nb);
  nb.clipTo(na);
  nb.invert();
  nb.clipTo(na);
  nb.invert();
  na.build(nb.allPolygons());
  return _clean(na.allPolygons());
}

List<CsgPoly> _subtract(List<CsgPoly> a, List<CsgPoly> b) {
  final na = _CsgNode(a);
  final nb = _CsgNode(b);
  na.invert();
  na.clipTo(nb);
  nb.clipTo(na);
  nb.invert();
  nb.clipTo(na);
  nb.invert();
  na.build(nb.allPolygons());
  na.invert();
  return _clean(na.allPolygons());
}
List<CsgPoly> _intersect(List<CsgPoly> a, List<CsgPoly> b) {
  final na = _CsgNode(a);
  final nb = _CsgNode(b);
  na.invert();
  nb.clipTo(na);
  nb.invert();
  na.clipTo(nb);
  nb.clipTo(na);
  na.build(nb.allPolygons());
  na.invert();
  return _clean(na.allPolygons());
}

/// Applies the boolean [op] over the two polygon soups. Every split spends
/// from the operation's budget ([csgBudgetBase] per input polygon): a
/// near-coplanar splitting storm aborts instead of growing forever — the
/// result then falls back to operand A (still visible and editable) and
/// [csgLastAborted] reports the abort.
List<CsgPoly> csgApply(
  String op,
  List<CsgPoly> a,
  List<CsgPoly> b, {
  int? splitBudget,
}) {
  final aC = [for (final p in a) p.clone()];
  final bC = [for (final p in b) p.clone()];
  csgLastAborted = false;
  final budget = splitBudget ?? csgBudgetBase(a.length + b.length);
  _csgSplitBudget = budget;
  try {
    switch (op) {
      case csgOpUnion:
        return _union(aC, bC);
      case csgOpDifference:
        return _subtract(aC, bC);
      case csgOpIntersect:
        return _intersect(aC, bC);
      default:
        return aC;
    }
  } on _CsgBudgetExceeded {
    csgLastAborted = true;
    // The attempted operation may have flipped the clones in place (e.g.
    // the invert dance of subtract/intersect) — return a pristine copy of
    // operand A, wound outward as it entered.
    return [for (final p in a) p.clone()];
  }
}

/// Default per-input-polygon budget of partition splits; a legit operation
/// spends a small multiple of its input count (measured ≤ ~60×), so the
/// wide headroom only ever triggers on storms.
int csgBudgetBase(int polygonCount) => 512 * polygonCount + 16384;

/// Whether the last [csgApply] hit its split budget and fell back to
/// operand A (a near-coplanar splitting storm was aborted).
bool csgLastAborted = false;

List<CsgPoly> _clean(List<CsgPoly> polys) => [
      for (final p in polys)
        if (p.vertices.length >= 3 && p.area() > csgAreaEpsilon) p,
    ];

// ── leaf solid builders ────────────────────────────────────────────────

vm.Matrix4 _rotationOf(ModelObject obj) {
  final rx = obj.rotX * math.pi / 180;
  final ry = obj.rotY * math.pi / 180;
  final rz = obj.rotZ * math.pi / 180;
  return vm.Matrix4.rotationZ(rz) * vm.Matrix4.rotationX(rx) * vm.Matrix4.rotationY(ry);
}

vm.Matrix4 _transformOf(ModelObject obj) =>
    vm.Matrix4.translation(vm.Vector3(obj.x, obj.y, obj.z)) * _rotationOf(obj);

vm.Vector3 _apply(vm.Matrix4 m, vm.Vector3 v) {
  final t = m.transform3(v);
  return t;
}

/// Orients [verts] as an outward CCW loop for the convex solid whose
/// interior contains [inside], then returns the loop.
List<vm.Vector3> _orient(List<vm.Vector3> verts, vm.Vector3 inside) {
  final c0 = verts[0], c1 = verts[1], c2 = verts[2];
  final n = (c1 - c0).cross(c2 - c0);
  // From inside to the vertex is roughly outward: a correct CCW (outward)
  // loop has the cross product pointing along that direction.
  return n.dot(c0 - inside) < 0 ? verts.reversed.toList() : List.of(verts);
}

/// Builds the model-space closed polygon soup for one convex leaf primitive
/// (cuboid — incl. its rounded form — /trapezoid/cylinder), each face tagged
/// with [objId] and its face key, plus the texture frame of the original
/// face.
List<CsgPoly> csgLeafPolys(ModelObject obj) {
  switch (obj.kind) {
    case 'cuboid':
      return isRoundedCuboid(obj) ? _roundedCuboidLeaf(obj) : _cuboidLeaf(obj);
    case 'trapezoid':
      return _trapezoidLeaf(obj);
    case 'cylinder':
      return _cylinderLeaf(obj);
    default:
      return const [];
  }
}

/// Replaces a csg node by the polygon soup of its whole subtree.
List<CsgPoly> csgEvaluate(ModelObject obj, ModelData model) {
  if (!obj.isCsg) return csgLeafPolys(obj);
  final ops = obj.operands ?? const <String>[];
  if (ops.length != 2) return const [];
  final a = model.objectById(ops[0]);
  final b = model.objectById(ops[1]);
  if (a == null || b == null) return const [];
  final op = csgOps.contains(obj.op) ? obj.op! : csgOpUnion;
  return csgApply(op, csgEvaluate(a, model), csgEvaluate(b, model));
}

// ── cuboid ─────────────────────────────────────────────────────────────

/// A fully-rounded cuboid (roundR > 0): every patch of `roundedBoxPatches`
/// becomes one polygon — planar faces keep their quad frames (texture CLIPS
/// to the inner rectangle at a uniform density), band and octant facets get
/// their own frames; all curved facets carry the [roundFaceKey] provenance.
List<CsgPoly> _roundedCuboidLeaf(ModelObject obj) {
  final w = obj.dim('w', 1);
  final h = obj.dim('h', 1);
  final d = obj.dim('d', 1);
  final r = cuboidRoundRadiusOf(obj);
  final segments = cuboidRoundSegments(obj);
  final m = _transformOf(obj);
  final arcLen = math.pi / 2 * r;
  final out = <CsgPoly>[];

  for (final patch in roundedBoxPatches(
    w: w,
    h: h,
    d: d,
    r: r,
    segments: segments,
  )) {
    // transform3 MUTATES its argument and returns it — patches share vertex
    // instances between neighboring polygons (octant fans), so each vertex
    // must be copied before the rigid transform.
    final texCorners = [for (final v in patch.loop) _apply(m, v.clone())];
    // Loops are already outward (rounded_box.dart) — orientation survives
    // the rigid transform, so texCorners double as the polygon vertices.
    switch (patch) {
      case RoundFacePatch():
        final key = patch.faceKey;
        final horizontal = key == '+y' || key == '-y';
        final (uExtent, vExtent) = switch (key) {
          '+x' || '-x' => (d, h),
          '+z' || '-z' => (w, h),
          _ => (w, d),
        };
        out.add(CsgPoly(
          texCorners,
          CsgSurface(obj.id, key),
          CsgTexQuad(_quadFrame(texCorners), uExtent, vExtent, !horizontal),
        ));
      case RoundBandPatch(:final arcIndex, :final segments):
        final frame = _bandFrame(texCorners, arcIndex, segments);
        out.add(CsgPoly(
          texCorners,
          CsgSurface(obj.id, roundFaceKey),
          CsgTexBand(frame, arcLen),
        ));
      case RoundOctantPatch(
          :final center,
          :final radius,
          :final sx,
          :final sy,
          :final sz
        ):
        out.add(CsgPoly(
          texCorners,
          CsgSurface(obj.id, roundFaceKey),
          CsgTexOctant(
            // Центр октанта общий для всех его патчей: transform3 мутирует
            // аргумент, поэтому его тоже нужно копировать, иначе после
            // первого патча рамка UV уезжает вместе с общим вектором.
            CsgOctantFrame(_apply(m, center.clone()), radius, sx, sy, sz),
            arcLen,
          ),
        ));
    }
  }
  return out;
}

/// The band frame of one fillet facet from its model-space corners (u row
/// along the arc, v row along the edge) plus its arc step [s0].
CsgBandFrame _bandFrame(
  List<vm.Vector3> corners,
  int s0,
  int segments,
) {
  final c0 = corners[0];
  final c1 = corners[1];
  final rowDelta = (corners[2] + corners[3]) / 2 - (c0 + c1) / 2;
  final uLen = (c1 - c0).length;
  final vLen = rowDelta.length;
  return CsgBandFrame(
    c0,
    uLen < 1e-12 ? vm.Vector3(1, 0, 0) : (c1 - c0) / uLen,
    math.max(uLen, 1e-12),
    vLen < 1e-12 ? vm.Vector3(0, 1, 0) : rowDelta / vLen,
    math.max(vLen, 1e-12),
    s0,
    segments,
  );
}

List<CsgPoly> _cuboidLeaf(ModelObject obj) {
  final w = obj.dim('w', 1);
  final h = obj.dim('h', 1);
  final d = obj.dim('d', 1);
  final hx = w / 2, hz = d / 2;
  final inside = vm.Vector3(obj.x, obj.y + h / 2, obj.z);
  final m = _transformOf(obj);

  // Face geometry in object-local space: corners in the renderer's order
  // (bottom-left, bottom-right, top-right, top-left of each quad).
  List<vm.Vector3> face(String key) {
    final local = switch (key) {
      '+z' => [
          vm.Vector3(-hx, 0, hz),
          vm.Vector3(hx, 0, hz),
          vm.Vector3(hx, h, hz),
          vm.Vector3(-hx, h, hz),
        ],
      '-z' => [
          vm.Vector3(hx, 0, -hz),
          vm.Vector3(-hx, 0, -hz),
          vm.Vector3(-hx, h, -hz),
          vm.Vector3(hx, h, -hz),
        ],
      '+x' => [
          vm.Vector3(hx, 0, hz),
          vm.Vector3(hx, 0, -hz),
          vm.Vector3(hx, h, -hz),
          vm.Vector3(hx, h, hz),
        ],
      '-x' => [
          vm.Vector3(-hx, 0, -hz),
          vm.Vector3(-hx, 0, hz),
          vm.Vector3(-hx, h, hz),
          vm.Vector3(-hx, h, -hz),
        ],
      '+y' => [
          vm.Vector3(-hx, h, hz),
          vm.Vector3(hx, h, hz),
          vm.Vector3(hx, h, -hz),
          vm.Vector3(-hx, h, -hz),
        ],
      _ => [
          vm.Vector3(-hx, 0, -hz),
          vm.Vector3(hx, 0, -hz),
          vm.Vector3(hx, 0, hz),
          vm.Vector3(-hx, 0, hz),
        ],
    };
    return [for (final v in local) _apply(m, v)];
  }

  final out = <CsgPoly>[];
  for (final key in faceKeys) {
    // The frame comes from the ORIGINAL renderer-ordered corners (bottom-
    // left → bottom-right → top-right → top-left); the polygon loop itself
    // is oriented outward independently.
    final texCorners = face(key);
    final corners = _orient(texCorners, inside);
    final horizontal = key == '+y' || key == '-y';
    // uExtent/vExtent of the ORIGINAL face (renderer conventions: sides
    // always tile at the tileScale, caps honor stretch/tile).
    final (uExtent, vExtent) = switch (key) {
      '+x' || '-x' => (d, h),
      '+z' || '-z' => (w, h),
      _ => (w, d),
    };
    final frame = _quadFrame(texCorners);
    out.add(CsgPoly(
      corners,
      CsgSurface(obj.id, key),
      CsgTexQuad(frame, uExtent, vExtent, !horizontal),
    ));
  }
  return out;
}

/// Builds the [CsgQuadFrame] for a face given its model-space corners in the
/// renderer's textured order (bottom-left → bottom-right → top-right →
/// top-left). Purely geometric — independent of the polygon's winding.
CsgQuadFrame _quadFrame(List<vm.Vector3> corners) {
  final c0 = corners[0];
  final c1 = corners[1];
  final rowDelta = (corners[2] + corners[3]) / 2 - (c0 + c1) / 2;
  final uLen = (c1 - c0).length;
  final vLen = rowDelta.length;
  return CsgQuadFrame(
    c0,
    uLen < 1e-12 ? vm.Vector3(1, 0, 0) : (c1 - c0) / uLen,
    vLen < 1e-12 ? vm.Vector3(0, 1, 0) : rowDelta / vLen,
    math.max(uLen, 1e-12),
    math.max(vLen, 1e-12),
  );
}

// ── trapezoid ──────────────────────────────────────────────────────────

List<CsgPoly> _trapezoidLeaf(ModelObject obj) {
  final bw = obj.dim('bottomW', 1);
  final bd = obj.dim('bottomD', 1);
  final tw = obj.dim('topW', bw);
  final td = obj.dim('topD', bd);
  final h = obj.dim('h', 0.5);
  final bhx = bw / 2, bhz = bd / 2;
  final thx = tw / 2, thz = td / 2;
  final inside = vm.Vector3(obj.x, obj.y + h / 2, obj.z);
  final m = _transformOf(obj);

  vm.Vector3 p(num x, num y, num z) => _apply(m, vm.Vector3(x.toDouble(), y.toDouble(), z.toDouble()));

  final bottom = [
    p(-bhx, 0, -bhz),
    p(bhx, 0, -bhz),
    p(bhx, 0, bhz),
    p(-bhx, 0, bhz),
  ];
  final top = [
    p(-thx, h, -thz),
    p(thx, h, -thz),
    p(thx, h, thz),
    p(-thx, h, thz),
  ];
  // Renderer order: bottom-left → bottom-right → top-right → top-left.
  final loops = <String, List<vm.Vector3>>{
    '-y': [bottom[0], bottom[1], bottom[2], bottom[3]],
    '+y': [top[0], top[1], top[2], top[3]],
    '-z': [bottom[0], bottom[1], top[1], top[0]],
    '+x': [bottom[1], bottom[2], top[2], top[1]],
    '+z': [bottom[2], bottom[3], top[3], top[2]],
    '-x': [bottom[3], bottom[0], top[0], top[3]],
  };
  final out = <CsgPoly>[];
  for (final e in loops.entries) {
    final key = e.key;
    final texCorners = e.value;
    final corners = _orient(texCorners, inside);
    final horizontal = key == '+y' || key == '-y';
    final (uExtent, vExtent) = switch (key) {
      '-y' => (bw, bd),
      '+y' => (tw, td),
      '-z' || '+z' => (bw, h),
      _ => (bd, h),
    };
    final frame = _quadFrame(texCorners);
    out.add(CsgPoly(
      corners,
      CsgSurface(obj.id, key),
      CsgTexQuad(frame, uExtent, vExtent, !horizontal),
    ));
  }
  return out;
}

// ── cylinder / cone ────────────────────────────────────────────────────

List<CsgPoly> _cylinderLeaf(ModelObject obj) {
  final bottomR = obj.dim('bottomR', 0.25);
  final topR = obj.dim('topR', bottomR);
  final h = obj.dim('h', 1);
  final segments = obj.dim('segments', 16).clamp(3, 64).toInt();
  final m = _transformOf(obj);
  final out = <CsgPoly>[];

  vm.Vector3 p(num x, num y, num z) => _apply(m, vm.Vector3(x.toDouble(), y.toDouble(), z.toDouble()));

  List<vm.Vector3> ring(double radius, double y) => [
        for (var s = 0; s < segments; s++)
          p(radius * math.cos(2 * math.pi * s / segments), y, radius * math.sin(2 * math.pi * s / segments)),
      ];

  final bottomRing = ring(bottomR, 0);
  final topRing = ring(topR, h);
  final maxR = math.max(bottomR, topR);
  final center = p(0, h / 2, 0);

  // Side facets.
  for (var s = 0; s < segments; s++) {
    final j = (s + 1) % segments;
    // Loop order matches the renderer strip quad (bottom-left, bottom-right,
    // top-right, top-left); outward orientation is canonicalized below.
    final corners = _orient(
      [bottomRing[s], bottomRing[j], topRing[j], topRing[s]],
      center,
    );
    final c0 = bottomRing[s];
    final c1 = bottomRing[j];
    final chord = c1 - c0;
    final chordLen = chord.length;
    final frame = CsgRingFrame(
      c0,
      chordLen < 1e-12 ? vm.Vector3(1, 0, 0) : chord / chordLen,
      math.max(chordLen, 1e-12),
      h,
      s,
      segments,
      maxR,
    );
    out.add(CsgPoly(
      corners,
      CsgSurface(obj.id, 'side'),
      CsgTexRing(frame, h),
    ));
  }

  // Caps: flat discs (fixed UV).
  if (bottomR > 0) {
    final verts = _orient(bottomRing, center);
    out.add(CsgPoly(
      verts,
      CsgSurface(obj.id, '-y'),
      CsgTexDisc(CsgDiscFrame(p(0, 0, 0), bottomR)),
    ));
  }
  if (topR > 0) {
    out.add(CsgPoly(
      _orient(topRing, center),
      CsgSurface(obj.id, '+y'),
      CsgTexDisc(CsgDiscFrame(p(0, h, 0), topR)),
    ));
  }
  return out;
}
