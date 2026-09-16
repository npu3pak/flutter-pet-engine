import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart' show facingAngle;
import 'animation_type.dart';
import 'direction.dart';

/// Game-camera constants: a 75° first-person lens with a short far plane (the
/// game rebuilds geometry instead of moving the camera far).
const double kGameCameraFovY = 75 * 0.0174533;
const double kGameCameraNear = 0.05;
const double kGameCameraFar = 50.0;
const double kGameCameraY = 0.5;

/// Subtle head-bob while stepping (cell = 1.0, cameraY = 0.5).
const double kHeadBobAmplitude = 0.008; // vertical bob height
const double kHeadBobRollRad = 0.003; // roll around the view axis (~0.17°)
const double kHeadBobJitter = 0.3; // per-step amplitude jitter (±30%)
const double kHeadBobCyclesPerCell = 0.25; // bob cycles per cell (period = 4)

/// World-space forward of a facing in the game's mirrored world frame:
/// north = −Z, east = −X (the engine's X mirror), south = +Z, west = +X.
(double, double) gameCameraForward(Direction d) => switch (d) {
      Direction.north => (0.0, -1.0),
      Direction.east => (-1.0, 0.0),
      Direction.south => (0.0, 1.0),
      Direction.west => (1.0, 0.0),
    };

(double, double) _leftOf(Direction d) => switch (d) {
      Direction.north => (1.0, 0.0),
      Direction.east => (0.0, -1.0),
      Direction.south => (-1.0, 0.0),
      Direction.west => (0.0, 1.0),
    };

/// Deterministic per-step seed: constant during a step (row/col are the
/// destination cell while animating) so the bob never flickers within a step,
/// but changes as the player moves to new cells / changes direction.
int _stepSeed(Direction facing, int row, int col, AnimationType anim) {
  var h = (row * 73856093) ^
      (col * 19349663) ^
      (facing.index * 83492791) ^
      (anim.index * 31);
  h = (h ^ (h >> 13)) * 0x5bd1e995;
  h ^= h >> 15;
  return h;
}

double _hash01(int seed) => (seed & 0x7FFFFFFF) / 0x7FFFFFFF;

/// The camera node transform: translation + yaw (+ optional roll).
vm.Matrix4 cameraNodeTransform({
  required double angle,
  required double x,
  required double z,
  double y = kGameCameraY,
  double roll = 0.0,
}) {
  final m = vm.Matrix4.translation(vm.Vector3(x, y, z)) *
      vm.Matrix4.rotationY(angle);
  if (roll != 0.0) m.multiply(vm.Matrix4.rotationZ(roll));
  return m;
}

/// The animated camera node transform: a step/turn interpolated by
/// [moveProgress] (0 = start, 1 = done), with the deterministic head bob
/// applied during movement. World position of cell (row, col) is
/// `(-col, y, row)` — the game's mirrored frame.
vm.Matrix4 gameCameraNodeTransformAnimated(
  Direction facing,
  int row,
  int col, {
  AnimationType animationType = AnimationType.none,
  double moveProgress = 0.0,
  double y = kGameCameraY,
}) {
  final theta = facingAngle(facing.index);
  final px = -col.toDouble();
  final pz = row.toDouble();
  final t = moveProgress;

  final (ox, oz) = switch (animationType) {
    AnimationType.moveForward => () {
        final (fx, fz) = gameCameraForward(facing);
        return (px - t * fx, pz - t * fz);
      }(),
    AnimationType.moveBackward => () {
        final (fx, fz) = gameCameraForward(facing);
        return (px + t * fx, pz + t * fz);
      }(),
    AnimationType.strafeLeft => () {
        final (lx, lz) = _leftOf(facing);
        return (px - t * lx, pz - t * lz);
      }(),
    AnimationType.strafeRight => () {
        final (lx, lz) = _leftOf(facing);
        return (px + t * lx, pz + t * lz);
      }(),
    AnimationType.turnLeft => (px, pz),
    AnimationType.turnRight => (px, pz),
    AnimationType.none => (px, pz),
  };

  final animAngle = switch (animationType) {
    AnimationType.turnLeft => theta + t * math.pi / 2,
    AnimationType.turnRight => theta - t * math.pi / 2,
    _ => theta,
  };

  // Subtle, slightly-random head bob while stepping. The phase is a single
  // full cycle per cell (sin is 0 at both step boundaries), so the bob stays
  // continuous across consecutive steps; only the per-step amplitude jitters
  // (seeded by the destination cell) for a natural, non-repeating feel.
  final isMoving = animationType == AnimationType.moveForward ||
      animationType == AnimationType.moveBackward ||
      animationType == AnimationType.strafeLeft ||
      animationType == AnimationType.strafeRight;
  double roll = 0.0;
  if (isMoving) {
    final seed = _stepSeed(facing, row, col, animationType);
    final ampMul = 1.0 + kHeadBobJitter * (2 * _hash01(seed ^ 0x51ab) - 1);
    final rollMul = 1.0 + kHeadBobJitter * (2 * _hash01(seed ^ 0xa7c2) - 1);
    final phase = (1 - t) * 2 * math.pi * kHeadBobCyclesPerCell;
    y += kHeadBobAmplitude * ampMul * math.sin(phase);
    roll = kHeadBobRollRad * rollMul * math.sin(2 * phase);
  }

  return cameraNodeTransform(angle: animAngle, x: ox, z: oz, y: y, roll: roll);
}

/// Fraction `[0, 1)` of a full 360° rotation the sky should show at the view
/// center for the current camera state (linear turn interpolation, matching
/// [gameCameraNodeTransformAnimated]).
double skyboxRotation(
  Direction facing,
  AnimationType anim,
  double moveProgress,
) {
  final center = facing.index +
      0.5 +
      switch (anim) {
        AnimationType.turnLeft => moveProgress,
        AnimationType.turnRight => -moveProgress,
        _ => 0.0,
      };
  return center / 4 % 1;
}
