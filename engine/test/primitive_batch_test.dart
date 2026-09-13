import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/src/render/primitive_batch.dart'
    show PrimitiveBatch;
import 'package:vector_math/vector_math.dart' as vm;

List<double> _floats(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.length ~/ 4; i++)
      data.getFloat32(i * 4, Endian.host),
  ];
}

/// The (x, y, z) position of vertex [index] in a packed interleaved buffer.
vm.Vector3 _position(List<double> floats, int index) {
  final base = index * 12;
  return vm.Vector3(floats[base], floats[base + 1], floats[base + 2]);
}

/// The (u, v) texture coordinate of vertex [index].
vm.Vector2 _uv(List<double> floats, int index) {
  final base = index * 12 + 6;
  return vm.Vector2(floats[base], floats[base + 1]);
}

void main() {
  group('PrimitiveBatch.addWallBox', () {
    test('builds six faces and honours cap skips', () {
      final full = PrimitiveBatch();
      full.addWallBox(
        x0: -0.5,
        x1: 0.5,
        z0: -0.06,
        z1: 0.06,
        y0: 0,
        y1: 1,
        wallH: 1,
        topCap: true,
        bottomCap: true,
      );
      expect(full.vertexCount, 24);
      expect(full.triangleCount, 12);

      final skipped = PrimitiveBatch();
      skipped.addWallBox(
        x0: -0.5,
        x1: 0.5,
        z0: -0.06,
        z1: 0.06,
        y0: 0,
        y1: 1,
        wallH: 1,
        skipZ1: true,
      );
      expect(skipped.vertexCount, 12);
      expect(skipped.triangleCount, 6);
    });

    test('samples the wall tile at world scale', () {
      final batch = PrimitiveBatch();
      batch.addWallBox(
        x0: 0,
        x1: 1,
        z0: 0,
        z1: 0.12,
        y0: 0,
        y1: 1,
        wallH: 1,
        skipX0: true,
        skipX1: true,
        skipZ0: true,
      );
      final floats = _floats(batch.packVertices());
      // +z face, 1.0 wide and full height: u 1..0, v 1..0.
      expect(_uv(floats, 0), vm.Vector2(1.0, 1.0));
      expect(_uv(floats, 1), vm.Vector2(0.0, 1.0));
      expect(_uv(floats, 2), vm.Vector2(0.0, 0.0));
      expect(_uv(floats, 3), vm.Vector2(1.0, 0.0));
      expect(_position(floats, 0), vm.Vector3(0, 0, 0.12));
      expect(_position(floats, 3), vm.Vector3(0, 1, 0.12));
    });

    test('a sliced band samples the matching vertical tile range', () {
      final batch = PrimitiveBatch();
      batch.addWallBox(
        x0: 0,
        x1: 1,
        z0: 0,
        z1: 0.12,
        y0: 0.2,
        y1: 0.8,
        wallH: 1,
        skipX0: true,
        skipX1: true,
        skipZ0: true,
      );
      final floats = _floats(batch.packVertices());
      // The band samples the tile slice the full-height wall would show
      // (v = 1 - y / wallH): bottom 0.8, top 0.2.
      expect(_uv(floats, 0).y, closeTo(0.8, 1e-6));
      expect(_uv(floats, 2).y, closeTo(0.2, 1e-6));
    });
  });

  group('PrimitiveBatch world quads', () {
    test('addVerticalQuad rebases indices across calls', () {
      final batch = PrimitiveBatch();
      batch.addVerticalQuad(
        along0: 0,
        along1: 1,
        y0: 0,
        y1: 1,
        plane: 0,
        verticalZ: true,
      );
      batch.addVerticalQuad(
        along0: 2,
        along1: 3,
        y0: 0,
        y1: 1,
        plane: 0,
        verticalZ: true,
      );
      expect(batch.vertexCount, 8);
      expect(batch.triangleCount, 4);
      final floats = _floats(batch.packVertices());
      expect(_position(floats, 4), vm.Vector3(2, 0, 0));
      expect(_position(floats, 5), vm.Vector3(3, 0, 0));
      // World-anchored UVs: u follows the along axis, v follows y.
      expect(_uv(floats, 4), vm.Vector2(2.0, 0.0));
      expect(_uv(floats, 6), vm.Vector2(3.0, 1.0));
    });

    test('addTiledPlane anchors UVs to the world origin', () {
      final batch = PrimitiveBatch();
      batch.addTiledPlane(x: 2, z: 3, width: 2, depth: 2, y: 0.5, tileSize: 1);
      final floats = _floats(batch.packVertices());
      expect(_uv(floats, 0), vm.Vector2(2.0, 3.0));
      expect(_uv(floats, 1), vm.Vector2(4.0, 3.0));
      expect(_uv(floats, 2), vm.Vector2(4.0, 5.0));
      expect(_uv(floats, 3), vm.Vector2(2.0, 5.0));
      expect(_position(floats, 0), vm.Vector3(2, 0.5, 3));
    });

    test('addFacingQuad rebases after an earlier primitive', () {
      final batch = PrimitiveBatch();
      batch.addTiledPlane(x: 0, z: 0, width: 1, depth: 1, y: 0, tileSize: 1);
      batch.addFacingQuad(
        lx: 0,
        ly: 0.5,
        lz: 0,
        width: 1,
        height: 1,
        northSouth: true,
      );
      expect(batch.vertexCount, 8);
      expect(batch.triangleCount, 4);
      final floats = _floats(batch.packVertices());
      expect(_position(floats, 4), vm.Vector3(-0.5, 0, 0));
      expect(_position(floats, 5), vm.Vector3(0.5, 0, 0));
    });
  });
}
