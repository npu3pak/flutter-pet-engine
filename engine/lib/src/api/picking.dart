import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import 'geometry/scene_geometry.dart';
import 'nodes/scene_node.dart';

/// A hit of a scene ray: the node, optional document face, distance and the
/// world/local intersection points.
class SceneHit {
  SceneHit({
    required this.node,
    required this.distance,
    required this.worldPoint,
    required this.localPoint,
    this.face,
    this.worldNormal,
  });

  /// The node the ray hit.
  final SceneNode node;

  /// The document face, when the node is a document object with faces.
  final FaceRef? face;

  /// The distance from the ray origin to the hit.
  final double distance;

  /// The intersection in world space.
  final vm.Vector3 worldPoint;

  /// The intersection in the node's local space.
  final vm.Vector3 localPoint;

  /// The world-space surface normal, when known.
  final vm.Vector3? worldNormal;
}

/// A document face reference: the face key, its live node and the document
/// material of the face.
class FaceRef {
  FaceRef({required this.key, required this.node, this.material});

  /// The face key (`+z`, `-x`, `round`, …).
  final String key;

  /// The node the face belongs to.
  final SceneNode node;

  /// The document material of the face, when the face has its own.
  final ModelMaterial? material;
}

/// Filters and ordering for [SceneController.raycast].
class RaycastOptions {
  const RaycastOptions({
    this.includeInvisible = false,
    this.skipNodeIds = const {},
    this.where,
    this.nearest = true,
    this.respectCulling = true,
  });

  /// Whether invisible nodes take part in the raycast.
  final bool includeInvisible;

  /// Node ids to skip (for example the current selection).
  final Set<String> skipNodeIds;

  /// An extra node filter.
  final bool Function(SceneNode node)? where;

  /// Whether to return only the nearest hit.
  final bool nearest;

  /// Whether to skip hits on the invisible side of a face (the same culling
  /// the renderer applies); `false` makes every face double-sided.
  final bool respectCulling;
}

/// The nearest triangle hit of a local-space ray against [geometry], or null.
///
/// Pure CPU math over the geometry's [MeshData]; used by the controller's
/// raycast and testable without a rendering device. Plumbing: not part of the
/// public API surface.
///
/// [side] mirrors the renderer's face culling: `outer`/`inner` skip hits on
/// the invisible side, `double`/`both` keeps every hit.
({double distance, vm.Vector3 point, vm.Vector3 normal})? intersectGeometry(
  SceneGeometry geometry,
  vm.Vector3 origin,
  vm.Vector3 direction, {
  String side = 'double',
}) {
  final bounds = geometry.localBounds;
  if (bounds == null) return null;
  final hit = _intersectAabb(bounds, origin, direction);
  if (hit == null) return null;

  final cull = side != 'double' && side != 'both';
  final data = geometry.data;
  final positions = data.positions;
  final indices = data.indices;
  var bestT = double.infinity;
  vm.Vector3? bestPoint;
  vm.Vector3? bestNormal;

  void testTriangle(int ia, int ib, int ic) {
    final a = vm.Vector3(
      positions[ia * 3],
      positions[ia * 3 + 1],
      positions[ia * 3 + 2],
    );
    final b = vm.Vector3(
      positions[ib * 3],
      positions[ib * 3 + 1],
      positions[ib * 3 + 2],
    );
    final c = vm.Vector3(
      positions[ic * 3],
      positions[ic * 3 + 1],
      positions[ic * 3 + 2],
    );
    final edge1 = b - a;
    final edge2 = c - a;
    final pvec = direction.cross(edge2);
    final det = edge1.dot(pvec);
    if (det.abs() < 1e-12) return;
    final invDet = 1 / det;
    final tvec = origin - a;
    final u = tvec.dot(pvec) * invDet;
    if (u < 0 || u > 1) return;
    final qvec = tvec.cross(edge1);
    final v = direction.dot(qvec) * invDet;
    if (v < 0 || u + v > 1) return;
    final t = edge2.dot(qvec) * invDet;
    if (t < 0 || t >= bestT) return;
    final normal = edge1.cross(edge2);
    if (normal.length2 < 1e-18) return;
    normal.normalize();
    if (cull) {
      // The authored vertex normals point to the semantic outward side (the
      // renderer's `side` is relative to it): 'outer' is visible when the
      // outward normal faces the ray, 'inner' when it faces away.
      final normals = data.normals;
      var outward = normal;
      if (normals != null && normals.length >= positions.length) {
        outward = vm.Vector3(
          normals[ia * 3] + normals[ib * 3] + normals[ic * 3],
          normals[ia * 3 + 1] + normals[ib * 3 + 1] + normals[ic * 3 + 1],
          normals[ia * 3 + 2] + normals[ib * 3 + 2] + normals[ic * 3 + 2],
        );
        if (outward.length2 < 1e-18) {
          outward = normal;
        } else {
          outward.normalize();
        }
      }
      final visible = side == 'inner'
          ? outward.dot(direction) > 0
          : outward.dot(direction) < 0;
      if (!visible) return;
    }
    if (normal.dot(direction) > 0) normal.negate();
    bestT = t;
    bestPoint = origin + direction * t;
    bestNormal = normal;
  }

  if (indices != null) {
    for (var i = 0; i + 2 < indices.length; i += 3) {
      testTriangle(indices[i], indices[i + 1], indices[i + 2]);
    }
  } else {
    for (var i = 0; i + 2 < data.vertexCount; i += 3) {
      testTriangle(i, i + 1, i + 2);
    }
  }

  final point = bestPoint;
  final normal = bestNormal;
  if (point == null || normal == null) return null;
  return (distance: bestT, point: point, normal: normal);
}

/// The ray/AABB entry parameter, or null when the ray misses.
double? _intersectAabb(
  vm.Aabb3 bounds,
  vm.Vector3 origin,
  vm.Vector3 direction,
) {
  var tMin = double.negativeInfinity;
  var tMax = double.infinity;
  for (var axis = 0; axis < 3; axis++) {
    final o = origin[axis];
    final d = direction[axis];
    final min = bounds.min[axis];
    final max = bounds.max[axis];
    if (d.abs() < 1e-12) {
      if (o < min || o > max) return null;
      continue;
    }
    var t1 = (min - o) / d;
    var t2 = (max - o) / d;
    if (t1 > t2) {
      final swap = t1;
      t1 = t2;
      t2 = swap;
    }
    if (t1 > tMin) tMin = t1;
    if (t2 < tMax) tMax = t2;
    if (tMin > tMax) return null;
  }
  return tMax < 0 ? null : (tMin < 0 ? 0 : tMin);
}
