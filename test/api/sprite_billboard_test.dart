import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/api/pick_geometry.dart' show buildObjectPickParts;
import 'package:vector_math/vector_math.dart' as vm;

ModelObject _sprite() => ModelObject(
  id: 'sprite',
  name: 'sprite',
  kind: 'sprite',
  x: 2,
  y: 0,
  z: 2,
  dims: const {'w': 1, 'h': 1},
  material: ModelMaterial(type: MaterialType.sprite, key: 's.png'),
);

void main() {
  test('the billboard normal faces the camera horizontally', () {
    for (final yaw in [0.0, math.pi / 2, math.pi, -1.2, 2.4]) {
      final matrix = spriteBillboardMatrix(vm.Vector3(1, 2, 3), yaw);
      final normal = matrix.rotate3(vm.Vector3(0, 0, 1)).normalized();
      // The camera forward that produces this yaw is
      // (sin yaw, 0, −cos yaw); the card faces the opposite way.
      expect(normal.x, closeTo(-math.sin(yaw), 1e-6));
      expect(normal.y, closeTo(0, 1e-6));
      expect(normal.z, closeTo(math.cos(yaw), 1e-6));
    }
  });

  test('the pick quad uses the same billboard transform', () {
    const yaw = 0.7;
    final parts = buildObjectPickParts(
      ModelData(id: 'm', name: 'M', size: ModelSize(w: 4, l: 4, h: 3)),
      _sprite(),
      billboardYaw: yaw,
    );
    expect(parts, hasLength(1));
    final normals = parts.single.geometry.data.normals!;
    final pickNormal = vm.Vector3(normals[0], normals[1], normals[2])
        .normalized();
    final expected = spriteBillboardMatrix(vm.Vector3.zero(), yaw)
        .rotate3(vm.Vector3(0, 0, 1))
        .normalized();
    // The mirror flips the stored normal's sign; the card plane must match.
    expect(pickNormal.dot(expected).abs(), closeTo(1, 1e-5));
  });
}
