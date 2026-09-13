// Private fields behind public getters cannot use initializing formals in
// named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'scene_geometry.dart';

/// Assembles geometry from raw vertices and engine primitives.
///
/// All operations preserve the engine's winding convention: triangles wind so
/// their right-hand cross product points inward, while the stored normal
/// points outward (the fork's front-face rule).
class GeometryBuilder {
  GeometryBuilder({bool deduplicate = false}) : _deduplicate = deduplicate;

  final bool _deduplicate;
  final Map<String, int> _dedup = {};

  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _texCoords = [];
  final List<double> _colors = [];
  final List<int> _indices = [];

  vm.Vector3 _normal = vm.Vector3(0, 0, 1);
  vm.Vector2 _texCoord = vm.Vector2.zero();
  vm.Vector4 _color = vm.Vector4(1, 1, 1, 1);

  /// The number of vertices added so far.
  int get vertexCount => _positions.length ~/ 3;

  /// The number of triangles added so far.
  int get triangleCount => _indices.length ~/ 3;

  // ── raw vertices ─────────────────────────────────────────────────────

  /// Sets the normal applied to vertices added after this call.
  void setNormal(vm.Vector3 normal) => _normal = normal.clone();

  /// Sets the texture coordinate applied to vertices added after this call.
  void setTexCoord(double u, double v) => _texCoord = vm.Vector2(u, v);

  /// Sets the vertex color applied to vertices added after this call.
  void setColor(vm.Vector4 color) => _color = color.clone();

  /// Appends a vertex with the current sticky attributes; returns its index.
  int addVertex(vm.Vector3 position) {
    if (_deduplicate) {
      final key =
          '${position.x},${position.y},${position.z}|'
          '${_normal.x},${_normal.y},${_normal.z}|'
          '${_texCoord.x},${_texCoord.y}|'
          '${_color.x},${_color.y},${_color.z},${_color.w}';
      final existing = _dedup[key];
      if (existing != null) return existing;
      final index = _append(position);
      _dedup[key] = index;
      return index;
    }
    return _append(position);
  }

  int _append(vm.Vector3 position) {
    final index = vertexCount;
    _positions.addAll([position.x, position.y, position.z]);
    _normals.addAll([_normal.x, _normal.y, _normal.z]);
    _texCoords.addAll([_texCoord.x, _texCoord.y]);
    _colors.addAll([_color.x, _color.y, _color.z, _color.w]);
    return index;
  }

  /// Adds a triangle referencing three previously added vertex indices.
  void addTriangle(int a, int b, int c) => _indices.addAll([a, b, c]);

  // ── geometry operations ──────────────────────────────────────────────

  /// Appends [geometry]'s vertices with [transform] baked in (positions,
  /// normals, and a winding flip when the transform mirrors).
  void addGeometry(SceneGeometry geometry, vm.Matrix4 transform) {
    final data = geometry.data;
    final positions = data.positions;
    final normals = data.normals;
    final texCoords = data.texCoords;
    final colors = data.colors;
    final flip = transform.determinant() < 0;
    final base = vertexCount;
    for (var i = 0; i < data.vertexCount; i++) {
      if (normals != null) {
        final normal = vm.Vector3(
          normals[i * 3],
          normals[i * 3 + 1],
          normals[i * 3 + 2],
        );
        transform.rotate3(normal);
        if (normal.length2 > 1e-18) normal.normalize();
        setNormal(normal);
      }
      if (texCoords != null) {
        setTexCoord(texCoords[i * 2], texCoords[i * 2 + 1]);
      }
      if (colors != null) {
        setColor(
          vm.Vector4(
            colors[i * 4],
            colors[i * 4 + 1],
            colors[i * 4 + 2],
            colors[i * 4 + 3],
          ),
        );
      }
      final position = vm.Vector3(
        positions[i * 3],
        positions[i * 3 + 1],
        positions[i * 3 + 2],
      );
      transform.transform3(position);
      addVertex(position);
    }
    final indices = data.indices;
    if (indices != null) {
      for (var t = 0; t + 2 < indices.length; t += 3) {
        final a = base + indices[t];
        final b = base + indices[t + 1];
        final c = base + indices[t + 2];
        if (flip) {
          addTriangle(a, c, b);
        } else {
          addTriangle(a, b, c);
        }
      }
    } else {
      for (var i = 0; i + 2 < data.vertexCount; i += 3) {
        final a = base + i;
        if (flip) {
          addTriangle(a, a + 2, a + 1);
        } else {
          addTriangle(a, a + 1, a + 2);
        }
      }
    }
  }

  /// Appends one quad from explicit corners, given counter-clockwise as seen
  /// from outside. UVs run (0,1)…(1,0) in corner order; [color] tints all four
  /// vertices.
  void addQuad({
    required vm.Vector3 a,
    required vm.Vector3 b,
    required vm.Vector3 c,
    required vm.Vector3 d,
    vm.Vector4? color,
  }) {
    final normal = (b - a).cross(c - a);
    if (normal.length2 > 1e-18) normal.normalize();
    final base = vertexCount;
    if (color != null) setColor(color);
    setNormal(normal);
    setTexCoord(0, 1);
    addVertex(a);
    setTexCoord(1, 1);
    addVertex(b);
    setTexCoord(1, 0);
    addVertex(c);
    setTexCoord(0, 0);
    addVertex(d);
    addTriangle(base, base + 2, base + 1);
    addTriangle(base, base + 3, base + 2);
  }

  /// Appends one big horizontal quad (XZ plane, normal +Y) with the texture
  /// tiled at [tileSize] world units per repeat; UVs anchor to the world
  /// origin.
  void addTiledPlane({
    required double x,
    required double z,
    required double width,
    required double depth,
    required double y,
    double tileSize = 1.0,
  }) {
    final size = tileSize <= 0 ? 1.0 : tileSize;
    final u0 = x / size;
    final v0 = z / size;
    final u1 = (x + width) / size;
    final v1 = (z + depth) / size;
    final base = vertexCount;
    setNormal(vm.Vector3(0, 1, 0));
    setTexCoord(u0, v0);
    addVertex(vm.Vector3(x, y, z));
    setTexCoord(u1, v0);
    addVertex(vm.Vector3(x + width, y, z));
    setTexCoord(u1, v1);
    addVertex(vm.Vector3(x + width, y, z + depth));
    setTexCoord(u0, v1);
    addVertex(vm.Vector3(x, y, z + depth));
    addTriangle(base, base + 1, base + 2);
    addTriangle(base, base + 2, base + 3);
  }

  /// Appends an axis-aligned box with world-scaled face UVs (one tile per
  /// world unit; v runs down from the top edge). Optional end caps fill the
  /// top and bottom.
  void addWallBox({
    required vm.Vector3 min,
    required vm.Vector3 max,
    bool topCap = false,
    bool bottomCap = false,
  }) {
    final x0 = min.x, x1 = max.x, z0 = min.z, z1 = max.z;
    final y0 = min.y, y1 = max.y;
    final sx = x1 - x0;
    final sz = z1 - z0;
    final vBottom = 1 - y0;
    final vTop = 1 - y1;
    // +z face: u along x, 0 at the +x side (the cuboid convention).
    _addQuadRaw(
      [
        vm.Vector3(x0, y0, z1),
        vm.Vector3(x1, y0, z1),
        vm.Vector3(x1, y1, z1),
        vm.Vector3(x0, y1, z1),
      ],
      vm.Vector3(0, 0, 1),
      [
        vm.Vector2(sx, vBottom),
        vm.Vector2(0, vBottom),
        vm.Vector2(0, vTop),
        vm.Vector2(sx, vTop),
      ],
    );
    // −z face: u along x, 0 at the −x side.
    _addQuadRaw(
      [
        vm.Vector3(x1, y0, z0),
        vm.Vector3(x0, y0, z0),
        vm.Vector3(x0, y1, z0),
        vm.Vector3(x1, y1, z0),
      ],
      vm.Vector3(0, 0, -1),
      [
        vm.Vector2(sx, vBottom),
        vm.Vector2(0, vBottom),
        vm.Vector2(0, vTop),
        vm.Vector2(sx, vTop),
      ],
    );
    // +x face: u along z, 0 at the −z side.
    _addQuadRaw(
      [
        vm.Vector3(x1, y0, z1),
        vm.Vector3(x1, y0, z0),
        vm.Vector3(x1, y1, z0),
        vm.Vector3(x1, y1, z1),
      ],
      vm.Vector3(1, 0, 0),
      [
        vm.Vector2(sz, vBottom),
        vm.Vector2(0, vBottom),
        vm.Vector2(0, vTop),
        vm.Vector2(sz, vTop),
      ],
    );
    // −x face: u along z, 0 at the +z side.
    _addQuadRaw(
      [
        vm.Vector3(x0, y0, z0),
        vm.Vector3(x0, y0, z1),
        vm.Vector3(x0, y1, z1),
        vm.Vector3(x0, y1, z0),
      ],
      vm.Vector3(-1, 0, 0),
      [
        vm.Vector2(sz, vBottom),
        vm.Vector2(0, vBottom),
        vm.Vector2(0, vTop),
        vm.Vector2(sz, vTop),
      ],
    );
    if (topCap) {
      _addQuadRaw(
        [
          vm.Vector3(x0, y1, z0),
          vm.Vector3(x1, y1, z0),
          vm.Vector3(x1, y1, z1),
          vm.Vector3(x0, y1, z1),
        ],
        vm.Vector3(0, 1, 0),
        [
          vm.Vector2(0, sz),
          vm.Vector2(sx, sz),
          vm.Vector2(sx, 0),
          vm.Vector2(0, 0),
        ],
      );
    }
    if (bottomCap) {
      _addQuadRaw(
        [
          vm.Vector3(x1, y0, z0),
          vm.Vector3(x0, y0, z0),
          vm.Vector3(x0, y0, z1),
          vm.Vector3(x1, y0, z1),
        ],
        vm.Vector3(0, -1, 0),
        [
          vm.Vector2(sx, 0),
          vm.Vector2(0, 0),
          vm.Vector2(0, sz),
          vm.Vector2(sx, sz),
        ],
      );
    }
  }

  /// Appends an upright quad centered at [center], [width] wide and [height]
  /// tall, rotated around Y by [yaw] (radians; 0 faces +Z).
  void addVerticalQuad({
    required vm.Vector3 center,
    required double width,
    required double height,
    required double yaw,
  }) {
    final half = width / 2;
    final up = vm.Vector3(0, height / 2, 0);
    final along = vm.Vector3(math.cos(yaw), 0, -math.sin(yaw)) * half;
    final normal = vm.Vector3(math.sin(yaw), 0, math.cos(yaw));
    final bottomLeft = center - along - up;
    final bottomRight = center + along - up;
    final topRight = center + along + up;
    final topLeft = center - along + up;
    _addQuadRaw(
      [bottomLeft, bottomRight, topRight, topLeft],
      normal,
      [vm.Vector2(0, 1), vm.Vector2(1, 1), vm.Vector2(1, 0), vm.Vector2(0, 0)],
    );
  }

  /// Appends an upright quad facing a compass direction: `north`/`south` are
  /// ±Z, `east`/`west` are ∓X. Axis tokens (`+z`, `-x`, …) are accepted too.
  void addFacingQuad({
    required vm.Vector3 center,
    required double width,
    required double height,
    required String facing,
  }) {
    final yaw = _yawOf(facing);
    addVerticalQuad(center: center, width: width, height: height, yaw: yaw);
  }

  /// Builds the accumulated geometry. Pure: no GPU work happens here.
  SceneGeometry build() => SceneGeometry.fromData(
    MeshData(
      positions: Float32List.fromList(_positions),
      vertexCount: vertexCount,
      normals: Float32List.fromList(_normals),
      texCoords: Float32List.fromList(_texCoords),
      colors: Float32List.fromList(_colors),
      indices: List<int>.from(_indices),
    ),
  );

  void _addQuadRaw(
    List<vm.Vector3> corners,
    vm.Vector3 normal,
    List<vm.Vector2> uv,
  ) {
    final base = vertexCount;
    setNormal(normal);
    for (var i = 0; i < 4; i++) {
      setTexCoord(uv[i].x, uv[i].y);
      addVertex(corners[i]);
    }
    addTriangle(base, base + 2, base + 1);
    addTriangle(base, base + 3, base + 2);
  }

  static double _yawOf(String facing) => switch (facing.toLowerCase()) {
    'north' || 'n' || '+z' || 'z' => 0.0,
    'south' || 's' || '-z' => math.pi,
    'east' || 'e' || '-x' => -math.pi / 2,
    'west' || 'w' || '+x' => math.pi / 2,
    _ => 0.0,
  };
}
