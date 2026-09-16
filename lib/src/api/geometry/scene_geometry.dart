import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../models/model_scene.dart';
import '../../scene/csg.dart';

/// Vertex/index data of the new API: primitives, custom builder output, or
/// geometry converted from the document.
///
/// The object holds pure CPU data ([data]) and uploads the GPU buffers lazily
/// on the first [raw] access, so geometry can be created, measured and tested
/// without a rendering device.
class SceneGeometry {
  SceneGeometry._(this._data);

  /// Wraps raw CPU vertex [data] (the geometry builder's output). Plumbing.
  factory SceneGeometry.fromData(MeshData data) => SceneGeometry._(data);

  final MeshData _data;

  /// The pure vertex data. Plumbing only.
  MeshData get data => _data;

  Geometry? _raw;

  /// The compiled fork geometry. Plumbing only; built lazily.
  Geometry get raw => _raw ??= MeshGeometry.fromMeshData(_data);

  /// The local-space axis-aligned bounds, or null for empty geometry.
  vm.Aabb3? get localBounds {
    final positions = _data.positions;
    if (positions.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var i = 0; i + 2 < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ),
    );
  }

  // ── primitives ───────────────────────────────────────────────────────

  /// An axis-aligned box centered on the origin.
  static SceneGeometry cuboid(vm.Vector3 size) =>
      SceneGeometry._(_dataOf(buildCuboidArrays(size)));

  /// A flat quad in the XZ plane facing +Y, centered on the origin.
  static SceneGeometry plane({required double width, required double depth}) =>
      SceneGeometry._(
        _dataOf(
          buildPlaneArrays(
            width: width,
            depth: depth,
            segmentsX: 1,
            segmentsZ: 1,
          ),
        ),
      );

  /// A Y-aligned cylinder/frustum centered on the origin. `topRadius = 0`
  /// produces a cone.
  static SceneGeometry cylinder({
    required double bottomRadius,
    double topRadius = 0,
    required double height,
    int radialSegments = 16,
  }) => SceneGeometry._(
    _dataOf(
      buildCylinderArrays(
        bottomRadius: bottomRadius,
        topRadius: topRadius,
        height: height,
        radialSegments: radialSegments,
        heightSegments: 1,
        bottomCap: true,
        topCap: true,
      ),
    ),
  );

  /// A Y-aligned cone centered on the origin (a cylinder with a zero top
  /// radius).
  static SceneGeometry cone({
    required double radius,
    required double height,
    int radialSegments = 16,
  }) => cylinder(
    bottomRadius: radius,
    topRadius: 0,
    height: height,
    radialSegments: radialSegments,
  );

  /// A sphere centered on the origin.
  static SceneGeometry sphere({required double radius, int segments = 16}) =>
      SceneGeometry._(
        _dataOf(
          buildSphereArrays(
            radius: radius,
            segments: math.max(3, segments),
            rings: math.max(2, (segments / 2).round()),
          ),
        ),
      );

  /// A fully rounded box centered on the origin (the document's rounded
  /// cuboid geometry).
  static SceneGeometry roundedBox({
    required vm.Vector3 size,
    required double radius,
    required int segments,
  }) {
    final object = ModelObject(id: 'rounded', name: '', kind: 'cuboid')
      ..setDim('w', size.x)
      ..setDim('h', size.y)
      ..setDim('d', size.z)
      ..setDim('roundR', radius)
      ..setDim('roundSegments', segments);
    return _fromCsgPolys(
      csgLeafPolys(object),
      smooth: true,
      centerY: size.y / 2,
    );
  }

  /// A frustum with rectangular bottom and top, centered on the origin.
  static SceneGeometry trapezoid({
    required double bottomWidth,
    required double topWidth,
    required double height,
    required double depth,
  }) {
    final object = ModelObject(id: 'trapezoid', name: '', kind: 'trapezoid')
      ..setDim('bottomW', bottomWidth)
      ..setDim('topW', topWidth)
      ..setDim('bottomD', depth)
      ..setDim('topD', depth)
      ..setDim('h', height);
    return _fromCsgPolys(
      csgLeafPolys(object),
      smooth: false,
      centerY: height / 2,
    );
  }

  /// A torus (a round ring) in the XZ plane centered on the origin.
  static SceneGeometry ring({
    required double radius,
    required double tubeRadius,
    int segments = 24,
  }) => SceneGeometry._(
    _dataOf(
      buildTorusArrays(
        radius: radius,
        tubeRadius: tubeRadius,
        radialSegments: math.max(3, segments),
        tubularSegments: math.max(3, (segments / 2).round()),
      ),
    ),
  );

  /// A flat annulus in the XZ plane centered on the origin (marker rings).
  static SceneGeometry annulus({
    required double innerRadius,
    required double outerRadius,
    int segments = 32,
  }) => SceneGeometry._(
    _dataOf(
      buildRingArrays(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        segments: segments,
      ),
    ),
  );

  // ── conversion ───────────────────────────────────────────────────────

  static MeshData _dataOf(PrimitiveArrays arrays) => MeshData(
    positions: arrays.positions,
    vertexCount: arrays.positions.length ~/ 3,
    normals: arrays.normals,
    texCoords: arrays.texCoords,
    colors: arrays.colors,
    indices: arrays.indices,
  );

  /// Triangulates document CSG polygons into world-space geometry exactly the
  /// way the model renderer does: X is mirrored (the world frame), normals are
  /// mirrored with it, and triangles fan in the renderer's order.
  static SceneGeometry _fromCsgPolys(
    List<CsgPoly> polys, {
    required bool smooth,
    required double centerY,
  }) {
    final smoothNormals = smooth ? _vertexNormals(polys) : null;
    final positions = <double>[];
    final normals = <double>[];
    final texCoords = <double>[];
    final colors = <double>[];
    final indices = <int>[];
    var base = 0;
    for (final poly in polys) {
      final normal = poly.normal;
      for (final vertex in poly.vertices) {
        final vn = smoothNormals?[_vertexKey(vertex)] ?? normal;
        positions.addAll([-vertex.x, vertex.y - centerY, vertex.z]);
        normals.addAll([-vn.x, vn.y, vn.z]);
        final (u, v) = _rawUv(poly.tex, vertex);
        texCoords.addAll([u, v]);
        colors.addAll([1.0, 1.0, 1.0, 1.0]);
      }
      for (var i = 1; i + 1 < poly.vertices.length; i++) {
        indices.addAll([base, base + i, base + i + 1]);
      }
      base += poly.vertices.length;
    }
    return SceneGeometry._(
      MeshData(
        positions: Float32List.fromList(positions),
        vertexCount: positions.length ~/ 3,
        normals: Float32List.fromList(normals),
        texCoords: Float32List.fromList(texCoords),
        colors: Float32List.fromList(colors),
        indices: indices,
      ),
    );
  }

  static (double, double) _rawUv(CsgTex tex, vm.Vector3 point) => switch (tex) {
    CsgTexQuad(:final frame) => frame.raw(point),
    CsgTexRing(:final frame) => frame.raw(point),
    CsgTexDisc(:final frame) => frame.raw(point),
    CsgTexBand(:final frame) => frame.raw(point),
    CsgTexOctant(:final frame) => frame.raw(point),
  };

  /// Averaged normals of the vertices shared by the group's polygons (same
  /// position key), so a rounded surface shades smoothly.
  static Map<String, vm.Vector3> _vertexNormals(List<CsgPoly> polys) {
    final accum = <String, vm.Vector3>{};
    for (final poly in polys) {
      final normal = poly.normal;
      for (final vertex in poly.vertices) {
        final key = _vertexKey(vertex);
        final current = accum[key];
        if (current == null) {
          accum[key] = normal.clone();
        } else {
          current.add(normal);
        }
      }
    }
    for (final normal in accum.values) {
      if (normal.length2 > 1e-18) normal.normalize();
    }
    return accum;
  }

  static String _vertexKey(vm.Vector3 v) => '${v.x}|${v.y}|${v.z}';
}
