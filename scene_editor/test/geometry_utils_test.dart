import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:scene_editor/src/scene/geometry_utils.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('packSegmentPairs', () {
    test('each consecutive pair becomes one segment with distinct ends', () {
      final floats = packSegmentPairs([
        (0.0, 0.0, 0.0), (1.0, 2.0, 3.0), // segment 1
        (4.0, 5.0, 6.0), (7.0, 8.0, 9.0), // segment 2
      ]);
      expect(floats, hasLength(12));
      expect(floats.sublist(0, 6), [0, 0, 0, 1, 2, 3]);
      expect(floats.sublist(6, 12), [4, 5, 6, 7, 8, 9]);
      // Ends are distinct — not a degenerate zero-length segment.
      expect(floats.sublist(0, 3), isNot(equals(floats.sublist(3, 6))));
    });

    test('odd trailing point is dropped', () {
      final floats = packSegmentPairs([
        (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), // segment 1
        (9.0, 9.0, 9.0), // orphan
      ]);
      expect(floats, hasLength(6));
    });

    test('empty input yields empty buffer', () {
      expect(packSegmentPairs(const []), isEmpty);
    });
  });

  group('lineSegments', () {
    test('each consecutive pair becomes one LineGeometry segment', () {
      final geometry = lineSegments([
        (0.0, 0.0, 0.0), (1.0, 2.0, 3.0), // segment 1
        (4.0, 5.0, 6.0), (7.0, 8.0, 9.0), // segment 2
      ], width: 0.02);
      expect(geometry, isA<LineGeometry>());
      expect(geometry.segmentCount, 2);
      expect(geometry.width, 0.02);
      expect(geometry.data.positions, [0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('odd trailing point is dropped', () {
      final geometry = lineSegments([
        (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), // segment 1
        (9.0, 9.0, 9.0), // orphan
      ]);
      expect(geometry.segmentCount, 1);
      expect(geometry.data.positions, [0, 0, 0, 1, 0, 0]);
    });
  });

  group('ringTubeGeometry', () {
    test('builds an open torus with one quad per ring/tube cell', () {
      const ringSegments = 6, tubeSegments = 4;
      final geometry = ringTubeGeometry(
        radius: 1,
        tubeRadius: 0.1,
        ringSegments: ringSegments,
        tubeSegments: tubeSegments,
      );
      expect(geometry, isA<SceneGeometry>());
      final data = geometry.data;
      expect(data.vertexCount, ringSegments * tubeSegments * 4);
      expect(data.indices, hasLength(ringSegments * tubeSegments * 2 * 3));
      // No caps: every index refers to a quad vertex.
      expect(data.indices!.every((i) => i >= 0 && i < data.vertexCount), isTrue);
      // The first quad matches the pure vertex list.
      final verts = ringTubeVertices(
        radius: 1,
        tubeRadius: 0.1,
        ringSegments: ringSegments,
        tubeSegments: tubeSegments,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          data.positions[i],
          closeTo(<double>[verts[0].x, verts[0].y, verts[0].z][i], 1e-6),
        );
      }
      expect(geometry.localBounds, isNotNull);
    });
  });

  group('wireframeBox', () {
    test('returns a LineNode with 12 segments and the requested width', () {
      final node = wireframeBox(
        vm.Vector3(1, 2, 3),
        vm.Vector3(2, 4, 6),
        width: 0.03,
      );
      expect(node, isA<LineNode>());
      expect(node.width, 0.03);
      expect(node.geometry.segmentCount, 12);
      expect(node.color, const Color(0xFFFFFFFF));
      expect(node.material.alphaMode, SceneAlphaMode.opaque);
    });

    test('converts the Vector4 color and the alphaBlend mode', () {
      final node = wireframeBox(
        vm.Vector3.zero(),
        vm.Vector3(1, 1, 1),
        color: vm.Vector4(1, 0.85, 0, 0.5),
        alphaBlend: true,
      );
      // 0.85 → 217, 0.5 → 128 (round half away from zero).
      expect(node.color, const Color(0x80FFD900));
      expect(node.material.alphaMode, SceneAlphaMode.blend);
    });
  });
}
