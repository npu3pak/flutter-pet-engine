import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/src/camera/animation_type.dart';
import 'package:pet_engine_v2/src/camera/direction.dart';
import 'package:pet_engine_v2/src/camera/game_camera_math.dart';
import 'package:pet_engine_v2/src/engine_compat/coords.dart' show facingAngle;
import 'package:vector_math/vector_math.dart' as vm;

void _expectMatrixClose(vm.Matrix4 a, vm.Matrix4 b, {double tolerance = 1e-12}) {
  for (var i = 0; i < 16; i++) {
    expect(a.storage[i], closeTo(b.storage[i], tolerance), reason: 'index $i');
  }
}

void main() {
  group('gameCameraNodeTransformAnimated', () {
    test('is deterministic', () {
      final a = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.moveForward,
        moveProgress: 0.37,
      );
      final b = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.moveForward,
        moveProgress: 0.37,
      );
      _expectMatrixClose(a, b);
    });

    test('interpolates a forward step from the destination back one cell', () {
      final start = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.moveForward,
        moveProgress: 1.0,
      );
      final done = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.moveForward,
        moveProgress: 0.0,
      );
      final startPos = start.getTranslation();
      final donePos = done.getTranslation();
      expect(donePos.x, -3);
      expect(donePos.z, 5);
      expect(startPos.z, closeTo(6, 1e-12));
    });

    test('adds a deterministic head bob only while moving', () {
      final moving = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.moveForward,
        moveProgress: 0.0,
      );
      final still = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        moveProgress: 0.0,
      );
      final bob = moving.getTranslation().y - still.getTranslation().y;
      expect(bob, inInclusiveRange(kHeadBobAmplitude * 0.7, kHeadBobAmplitude * 1.3));

      final turned = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.turnLeft,
        moveProgress: 0.0,
      );
      expect(turned.getTranslation().y, closeTo(kGameCameraY, 1e-12));
    });

    test('interpolates a turn between the two facings', () {
      final half = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.turnLeft,
        moveProgress: 0.5,
      );
      final expected = cameraNodeTransform(
        angle: facingAngle(Direction.north.index) + 3.141592653589793 / 4,
        x: -3,
        z: 5,
      );
      _expectMatrixClose(half, expected);
    });

    test('strafing shifts along the facing left/right', () {
      final left = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.strafeLeft,
        moveProgress: 1.0,
      );
      final right = gameCameraNodeTransformAnimated(
        Direction.north,
        5,
        3,
        animationType: AnimationType.strafeRight,
        moveProgress: 1.0,
      );
      // Facing north, left is +X (mirrored frame): the step starts one cell
      // to the right of the destination, so progress 1 sits at −4.
      expect(left.getTranslation().x, closeTo(-4, 1e-12));
      expect(right.getTranslation().x, closeTo(-2, 1e-12));
    });
  });

  group('skyboxRotation', () {
    test('north at rest is the first panel center', () {
      expect(skyboxRotation(Direction.north, AnimationType.none, 0), 0.125);
    });

    test('turn interpolation advances and stays in [0, 1)', () {
      final start = skyboxRotation(Direction.north, AnimationType.turnLeft, 0);
      final mid = skyboxRotation(Direction.north, AnimationType.turnLeft, 0.5);
      final end = skyboxRotation(Direction.north, AnimationType.turnLeft, 1);
      expect(start, 0.125);
      expect(mid, greaterThan(start));
      expect(end, 0.375);
      for (var t = 0.0; t <= 1.0; t += 0.1) {
        final r = skyboxRotation(Direction.west, AnimationType.turnRight, t);
        expect(r, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('turnFrom', () {
    test('derives the pre-turn facing', () {
      expect(turnFrom(Direction.north, AnimationType.turnLeft), Direction.east);
      expect(
          turnFrom(Direction.north, AnimationType.turnRight), Direction.west);
      expect(turnFrom(Direction.south, AnimationType.moveForward), isNull);
    });
  });
}
