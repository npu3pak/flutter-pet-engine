// Covers the pure math of the line-segments rendering paths: the static
// screen-pixel scale of LineSegmentsGeometry (GPU expansion) and the CPU
// expansion used as the Windows/Linux and debug fallback. Both are pure and
// run without a GPU context; the GPU instanced path itself is exercised by
// the example app.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

ui.Offset _toScreen(Matrix4 viewProjection, Vector3 world, ui.Size size) {
  final clip = viewProjection.transformed(
    Vector4(world.x, world.y, world.z, 1.0),
  );
  return ui.Offset(
    (clip.x / clip.w * 0.5 + 0.5) * size.width,
    (clip.y / clip.w * 0.5 + 0.5) * size.height,
  );
}

Vector3 _vertex(Float32List positions, int index) => Vector3(
  positions[index * 3],
  positions[index * 3 + 1],
  positions[index * 3 + 2],
);

void main() {
  group('LineSegmentsGeometry pixel scale', () {
    test('pixelScaleFor matches the perspective pixel size', () {
      const fovY = math.pi / 3; // 60 degrees
      const height = 1000.0;
      final scale = LineSegmentsGeometry.pixelScaleFor(
        fovY: fovY,
        viewportHeight: height,
      );
      expect(scale, closeTo(2 * math.tan(fovY / 2) / height, 1e-12));

      // A 3 px ribbon at distance 10 covers this many world units.
      const pixels = 3.0;
      const distance = 10.0;
      expect(
        pixels * scale * distance,
        closeTo(pixels * 2 * math.tan(fovY / 2) * distance / height, 1e-12),
      );
    });

    test('pixelScaleFor guards against an empty viewport', () {
      expect(
        LineSegmentsGeometry.pixelScaleFor(fovY: 1, viewportHeight: 0),
        0,
      );
      expect(
        LineSegmentsGeometry.pixelScaleFor(fovY: 1, viewportHeight: -5),
        0,
      );
    });
  });

  group('expandLineSegments', () {
    const size = ui.Size(800, 600);
    final camera = PerspectiveCamera(
      position: Vector3(0, 0, 5),
      target: Vector3(0, 0, 0),
    );
    final viewProjection = camera.getViewTransform(size);

    test('emits two triangles per visible segment', () {
      final expanded = expandLineSegments(
        [Vector3(-1, 0, 0), Vector3(1, 0, 0)],
        widthPx: 3,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      expect(expanded.positions, hasLength(6 * 3));
      expect(expanded.normals, hasLength(6 * 3));
    });

    test('the quad spans the requested pixel width', () {
      const widthPx = 3.0;
      final expanded = expandLineSegments(
        [Vector3(-1, 0, 0), Vector3(1, 0, 0)],
        widthPx: widthPx,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      // Vertices 0 and 1 are the two corners at the first endpoint.
      final left = _toScreen(viewProjection, _vertex(expanded.positions, 0), size);
      final right = _toScreen(viewProjection, _vertex(expanded.positions, 1), size);
      expect((left - right).distance, closeTo(widthPx, 1e-3));
      // The ribbon is centered on the segment endpoint.
      final center = _toScreen(viewProjection, Vector3(-1, 0, 0), size);
      expect(((left + right) / 2 - center).distance, lessThan(1e-3));
    });

    test('collapses segments fully behind the camera to zero area', () {
      final expanded = expandLineSegments(
        [Vector3(0, 0, 6), Vector3(0, 0, 7)],
        widthPx: 3,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      // The vertex count stays stable for in-place updates.
      expect(expanded.positions, hasLength(6 * 3));
      final first = _vertex(expanded.positions, 0);
      for (var v = 1; v < 6; v++) {
        expect(_vertex(expanded.positions, v).distanceTo(first), lessThan(1e-9));
      }
    });

    test('clips a segment crossing the near plane', () {
      final expanded = expandLineSegments(
        [Vector3(0, 0, 4), Vector3(0, 0, 6)],
        widthPx: 3,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      expect(expanded.positions, hasLength(6 * 3));
      for (final value in expanded.positions) {
        expect(value.isFinite, isTrue);
      }
    });

    test('handles several disjoint segments and an empty viewport', () {
      final expanded = expandLineSegments(
        [
          Vector3(-1, 0, 0),
          Vector3(1, 0, 0),
          Vector3(0, -1, 0),
          Vector3(0, 1, 0),
        ],
        widthPx: 3,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: size,
      );
      expect(expanded.positions, hasLength(12 * 3));

      final empty = expandLineSegments(
        [Vector3(-1, 0, 0), Vector3(1, 0, 0)],
        widthPx: 3,
        viewProjection: viewProjection,
        cameraPosition: camera.position,
        viewportSize: ui.Size.zero,
      );
      expect(empty.positions, isEmpty);
    });
  });
}
