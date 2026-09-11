import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'engine_mesh.dart';

/// The engine's geometry-assembly facade: games append primitives into a
/// batch and build one [EngineGeometry] per material group (many small parts
/// merge into ONE draw item). All the fork's `GeometryBuilder` math and the
/// game's world-scaled UV conventions live here.
///
/// Coordinates are world (mirrored) space. The primitives preserve the
/// project's sacred conventions: wall faces sample the texture at world scale
/// (one tile per 1.0 unit), vertical quads carry world-anchored UVs, and the
/// winding matches the engine's front-face rule.
class PrimitiveBatch {
  PrimitiveBatch({bool deduplicate = false})
      : _builder = GeometryBuilder(deduplicate: deduplicate);

  final GeometryBuilder _builder;

  /// The number of vertices added so far.
  int get vertexCount => _builder.vertexCount;

  /// The number of triangles added so far.
  int get triangleCount => _builder.triangleCount;

  /// Builds and GPU-uploads the accumulated geometry.
  EngineGeometry build() => EngineGeometry.wrap(_builder.build());

  /// Packs the accumulated vertices into the engine's interleaved layout
  /// (48 bytes per vertex: position, normal, UV, color). Pure and GPU-free —
  /// used by geometry tests.
  Uint8List packVertices() => _builder.packVertices();

  // ── raw vertices ─────────────────────────────────────────────────────

  /// Appends a vertex with the sticky attribute values set by [normal],
  /// [texCoord] and [color]; returns its index.
  int addVertex(vm.Vector3 position) => _builder.addVertex(position);

  /// Adds a triangle referencing three previously added vertex indices.
  void addTriangle(int a, int b, int c) => _builder.addTriangle(a, b, c);

  /// Sets the normal applied to vertices added after this call.
  PrimitiveBatch normal(vm.Vector3 value) {
    _builder.normal(value);
    return this;
  }

  /// Sets the texture coordinate applied to vertices added after this call.
  PrimitiveBatch texCoord(vm.Vector2 value) {
    _builder.texCoord(value);
    return this;
  }

  /// Sets the color applied to vertices added after this call.
  PrimitiveBatch color(vm.Vector4 value) {
    _builder.color(value);
    return this;
  }

  /// Appends [geometry]'s vertices with [transform] baked in (positions
  /// translated+rotated, normals rotated — the transforms are rigid: rotation
  /// + translation, never scale). Indices are rebased onto the batch's
  /// accumulated vertex count.
  void addGeometry(EngineGeometry geometry, vm.Matrix4 transform) {
    final data = geometry.raw.extractMeshData();
    final positions = data.positions;
    final normals = data.normals;
    final texCoords = data.texCoords;
    final base = _builder.vertexCount;
    for (var i = 0; i < data.vertexCount; i++) {
      if (normals != null) {
        _builder.normal(transform.rotate3(vm.Vector3(
          normals[i * 3],
          normals[i * 3 + 1],
          normals[i * 3 + 2],
        )));
      }
      if (texCoords != null) {
        _builder.texCoord(vm.Vector2(texCoords[i * 2], texCoords[i * 2 + 1]));
      }
      _builder.addVertex(transform.transform3(vm.Vector3(
        positions[i * 3],
        positions[i * 3 + 1],
        positions[i * 3 + 2],
      )));
    }
    final indices = data.indices;
    if (indices != null) {
      for (var t = 0; t + 2 < indices.length; t += 3) {
        _builder.addTriangle(
          base + indices[t],
          base + indices[t + 1],
          base + indices[t + 2],
        );
      }
    } else {
      // Non-indexed geometry draws vertices in order — replicate by indexing
      // them explicitly.
      for (var i = 0; i + 2 < data.vertexCount; i += 3) {
        _builder.addTriangle(base + i, base + i + 1, base + i + 2);
      }
    }
  }

  /// Appends one quad from explicit corners, UVs and a normal. [reverse] flips
  /// the triangle order for corner lists wound CCW-from-outside (see
  /// [addWallBox]).
  void addQuad(
    vm.Vector3 normal,
    List<vm.Vector3> corners,
    List<vm.Vector2> uv, {
    bool reverse = false,
  }) {
    final base = _builder.vertexCount;
    for (var i = 0; i < 4; i++) {
      _builder.normal(normal).texCoord(uv[i]).addVertex(corners[i]);
    }
    if (reverse) {
      _builder.addTriangle(base, base + 2, base + 1);
      _builder.addTriangle(base, base + 3, base + 2);
    } else {
      _builder.addTriangle(base, base + 1, base + 2);
      _builder.addTriangle(base, base + 2, base + 3);
    }
  }

  // ── world-UV primitives ──────────────────────────────────────────────

  /// Appends one vertical rock quad on a constant world plane, spanning
  /// [along0]..[along1] along the border and [y0]..[y1] vertically.
  /// World-anchored UVs (one wall-texture tile per world unit) make adjacent
  /// pieces tile seamlessly. [verticalZ] selects the plane orientation:
  /// z = [plane] with the span along x, or x = [plane] with the span along z.
  void addVerticalQuad({
    required double along0,
    required double along1,
    required double y0,
    required double y1,
    required double plane,
    required bool verticalZ,
  }) {
    if (along1 <= along0 || y1 <= y0) return;
    final u0 = along0;
    final u1 = along1;
    final v0 = y0; // v = 1 at the image bottom (glTF convention)
    final v1 = y1;
    // addTriangle uses GLOBAL vertex indices, so the base of this quad's four
    // vertices must offset them — otherwise every quad of a merged mesh would
    // re-reference the first quad's vertices and vanish.
    final base = _builder.vertexCount;
    if (verticalZ) {
      _builder
          .normal(vm.Vector3(0, 0, 1))
        ..texCoord(vm.Vector2(u0, v0)).addVertex(vm.Vector3(along0, y0, plane))
        ..texCoord(vm.Vector2(u1, v0)).addVertex(vm.Vector3(along1, y0, plane))
        ..texCoord(vm.Vector2(u1, v1)).addVertex(vm.Vector3(along1, y1, plane))
        ..texCoord(vm.Vector2(u0, v1)).addVertex(vm.Vector3(along0, y1, plane))
        ..addTriangle(base, base + 1, base + 2)
        ..addTriangle(base, base + 2, base + 3);
    } else {
      _builder
          .normal(vm.Vector3(1, 0, 0))
        ..texCoord(vm.Vector2(u0, v0)).addVertex(vm.Vector3(plane, y0, along0))
        ..texCoord(vm.Vector2(u1, v0)).addVertex(vm.Vector3(plane, y0, along1))
        ..texCoord(vm.Vector2(u1, v1)).addVertex(vm.Vector3(plane, y1, along1))
        ..texCoord(vm.Vector2(u0, v1)).addVertex(vm.Vector3(plane, y1, along0))
        ..addTriangle(base, base + 1, base + 2)
        ..addTriangle(base, base + 2, base + 3);
    }
  }

  /// Appends a vertical quad centered at ([lx], [ly], [lz]) facing +Z
  /// (north/south) or +X (east/west) — the wall skin/decal quad. [uMin]..
  /// [uMax] / [vMin]..[vMax] select the sampled texture range.
  void addFacingQuad({
    required double lx,
    required double ly,
    required double lz,
    required double width,
    required double height,
    required bool northSouth,
    double uMin = 0.0,
    double uMax = 1.0,
    double vMin = 0.0,
    double vMax = 1.0,
  }) {
    final base = _builder.vertexCount;
    if (northSouth) {
      _builder
          .normal(vm.Vector3(0, 0, 1))
        ..texCoord(vm.Vector2(uMin, vMax))
            .addVertex(vm.Vector3(lx - width / 2, ly - height / 2, lz))
        ..texCoord(vm.Vector2(uMax, vMax))
            .addVertex(vm.Vector3(lx + width / 2, ly - height / 2, lz))
        ..texCoord(vm.Vector2(uMax, vMin))
            .addVertex(vm.Vector3(lx + width / 2, ly + height / 2, lz))
        ..texCoord(vm.Vector2(uMin, vMin))
            .addVertex(vm.Vector3(lx - width / 2, ly + height / 2, lz))
        ..addTriangle(base, base + 1, base + 2)
        ..addTriangle(base, base + 2, base + 3);
    } else {
      _builder
          .normal(vm.Vector3(1, 0, 0))
        ..texCoord(vm.Vector2(uMin, vMax))
            .addVertex(vm.Vector3(lx, ly - height / 2, lz - width / 2))
        ..texCoord(vm.Vector2(uMax, vMax))
            .addVertex(vm.Vector3(lx, ly - height / 2, lz + width / 2))
        ..texCoord(vm.Vector2(uMax, vMin))
            .addVertex(vm.Vector3(lx, ly + height / 2, lz + width / 2))
        ..texCoord(vm.Vector2(uMin, vMin))
            .addVertex(vm.Vector3(lx, ly + height / 2, lz - width / 2))
        ..addTriangle(base, base + 1, base + 2)
        ..addTriangle(base, base + 2, base + 3);
    }
  }

  /// Appends an axis-aligned wall box with world-scaled face UVs and optional
  /// end-cap faces (the wall slabs and door/window pieces).
  ///
  /// Every face samples the wall tile AT WORLD SCALE (u across the face's
  /// horizontal extent per 1.0 unit, v = 1 on the bottom edge per the
  /// glTF/cuboid convention), so narrow faces — a slab's end caps (0.12), the
  /// top/bottom caps — show a thin crop of the tile with the same texel
  /// density as the full-height faces instead of crushing the whole tile onto
  /// the strip. Vertical faces map the tile's vertical band
  /// [yBase + (y0-yBase)/wallH]. The [skipX0]/[skipX1]/[skipZ0]/[skipZ1]
  /// flags drop the box's end-cap faces at the −x/+x/−z/+z sides (a wall slab
  /// whose corner-flush end reaches the perpendicular wall's face plane must
  /// not carry a cap there).
  void addWallBox({
    required double x0,
    required double x1,
    required double z0,
    required double z1,
    required double y0,
    required double y1,
    required double wallH,
    double yBase = 0,
    bool topCap = false,
    bool bottomCap = false,
    bool skipX0 = false,
    bool skipX1 = false,
    bool skipZ0 = false,
    bool skipZ1 = false,
  }) {
    final sx = x1 - x0;
    final sz = z1 - z0;
    final vBottom = 1 - (y0 - yBase) / wallH;
    final vTop = 1 - (y1 - yBase) / wallH;
    // +z face (at z1): u along x, 0 at the +x side (CuboidGeometry's +Z).
    if (!skipZ1) {
      addQuad(
        vm.Vector3(0, 0, 1),
        [
          vm.Vector3(x0, y0, z1),
          vm.Vector3(x1, y0, z1),
          vm.Vector3(x1, y1, z1),
          vm.Vector3(x0, y1, z1),
        ],
        [
          vm.Vector2(sx, vBottom),
          vm.Vector2(0, vBottom),
          vm.Vector2(0, vTop),
          vm.Vector2(sx, vTop),
        ],
        reverse: true,
      );
    }
    // −z face (at z0): u along x, 0 at the −x side (CuboidGeometry's −Z).
    if (!skipZ0) {
      addQuad(
        vm.Vector3(0, 0, -1),
        [
          vm.Vector3(x1, y0, z0),
          vm.Vector3(x0, y0, z0),
          vm.Vector3(x0, y1, z0),
          vm.Vector3(x1, y1, z0),
        ],
        [
          vm.Vector2(sx, vBottom),
          vm.Vector2(0, vBottom),
          vm.Vector2(0, vTop),
          vm.Vector2(sx, vTop),
        ],
        reverse: true,
      );
    }
    // +x face (at x1): u along z, 0 at the −z side (CuboidGeometry's +X).
    if (!skipX1) {
      addQuad(
        vm.Vector3(1, 0, 0),
        [
          vm.Vector3(x1, y0, z1),
          vm.Vector3(x1, y0, z0),
          vm.Vector3(x1, y1, z0),
          vm.Vector3(x1, y1, z1),
        ],
        [
          vm.Vector2(sz, vBottom),
          vm.Vector2(0, vBottom),
          vm.Vector2(0, vTop),
          vm.Vector2(sz, vTop),
        ],
        reverse: true,
      );
    }
    // −x face (at x0): u along z, 0 at the +z side (CuboidGeometry's −X).
    if (!skipX0) {
      addQuad(
        vm.Vector3(-1, 0, 0),
        [
          vm.Vector3(x0, y0, z0),
          vm.Vector3(x0, y0, z1),
          vm.Vector3(x0, y1, z1),
          vm.Vector3(x0, y1, z0),
        ],
        [
          vm.Vector2(sz, vBottom),
          vm.Vector2(0, vBottom),
          vm.Vector2(0, vTop),
          vm.Vector2(sz, vTop),
        ],
        reverse: true,
      );
    }
    if (topCap) {
      addQuad(
        vm.Vector3(0, 1, 0),
        [
          vm.Vector3(x0, y1, z0),
          vm.Vector3(x1, y1, z0),
          vm.Vector3(x1, y1, z1),
          vm.Vector3(x0, y1, z1),
        ],
        [
          vm.Vector2(0, sz),
          vm.Vector2(sx, sz),
          vm.Vector2(sx, 0),
          vm.Vector2(0, 0),
        ],
      );
    }
    if (bottomCap) {
      addQuad(
        vm.Vector3(0, -1, 0),
        [
          vm.Vector3(x1, y0, z0),
          vm.Vector3(x0, y0, z0),
          vm.Vector3(x0, y0, z1),
          vm.Vector3(x1, y0, z1),
        ],
        [
          vm.Vector2(sx, 0),
          vm.Vector2(0, 0),
          vm.Vector2(0, sz),
          vm.Vector2(sx, sz),
        ],
      );
    }
  }

  /// Appends one big horizontal quad (XZ plane, normal +Y) with the texture
  /// tiled at [tileSize] world units per repeat — the engine's cheap
  /// large-area ground fill. UVs are anchored to the world origin so the tile
  /// grid lines up with per-cell floors ([tileSize] = 1 keeps 1 cell = 1 tile).
  void addTiledPlane({
    required double x,
    required double z,
    required double width,
    required double depth,
    required double y,
    required double tileSize,
  }) {
    final u0 = x / tileSize;
    final v0 = z / tileSize;
    final u1 = (x + width) / tileSize;
    final v1 = (z + depth) / tileSize;
    final base = _builder.vertexCount;
    _builder
        .normal(vm.Vector3(0, 1, 0))
      ..texCoord(vm.Vector2(u0, v0)).addVertex(vm.Vector3(x, y, z))
      ..texCoord(vm.Vector2(u1, v0)).addVertex(vm.Vector3(x + width, y, z))
      ..texCoord(vm.Vector2(u1, v1)).addVertex(vm.Vector3(x + width, y, z + depth))
      ..texCoord(vm.Vector2(u0, v1)).addVertex(vm.Vector3(x, y, z + depth))
      ..addTriangle(base, base + 1, base + 2)
      ..addTriangle(base, base + 2, base + 3);
  }
}
