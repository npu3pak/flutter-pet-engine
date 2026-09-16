// Private fields behind public getters cannot use initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../camera/animation_type.dart' as eng;
import '../../camera/direction.dart' as eng;
import '../../camera/game_camera_math.dart' as math;
import 'camera_controller.dart';
import 'camera_types.dart';

/// The first-person game camera: fixed at a cell of the mirrored world grid
/// (`(−column, y, row)`), looking along [facing], with the deterministic
/// step/turn animation and head bob.
class FirstPersonCameraController extends ChangeNotifier
    implements CameraController {
  FirstPersonCameraController({
    Direction facing = Direction.north,
    int row = 0,
    int column = 0,
    double y = math.kGameCameraY,
  }) : _facing = facing,
       _row = row,
       _column = column,
       _y = y;

  Direction _facing;

  /// The destination facing (during a turn the animation ends here).
  Direction get facing => _facing;
  set facing(Direction value) {
    if (_facing == value) return;
    _facing = value;
    notifyListeners();
  }

  int _row;

  /// The destination row while animating.
  int get row => _row;
  set row(int value) {
    if (_row == value) return;
    _row = value;
    notifyListeners();
  }

  int _column;

  /// The destination column while animating.
  int get column => _column;
  set column(int value) {
    if (_column == value) return;
    _column = value;
    notifyListeners();
  }

  double _y;

  /// The eye height.
  double get y => _y;
  set y(double value) {
    if (_y == value) return;
    _y = value;
    notifyListeners();
  }

  AnimationType _animation = AnimationType.none;

  /// The step/turn animation currently playing.
  AnimationType get animation => _animation;
  set animation(AnimationType value) {
    if (_animation == value) return;
    _animation = value;
    notifyListeners();
  }

  double _moveProgress = 0;

  /// Animation progress: 0 at the start, 1 when done.
  double get moveProgress => _moveProgress;
  set moveProgress(double value) {
    if (_moveProgress == value) return;
    _moveProgress = value;
    notifyListeners();
  }

  /// Duration of one step/turn animation (seconds). The controller advances
  /// [moveProgress] itself in [update] so the frame that renders the step
  /// already shows the interpolated pose.
  double stepDuration = 0.3;

  final CameraProjection _projection = CameraProjection(
    fovY: math.kGameCameraFovY,
    near: math.kGameCameraNear,
    far: math.kGameCameraFar,
  );

  @override
  CameraProjection get projection => _projection;

  /// The camera node transform of the current cell, facing and animation.
  vm.Matrix4 get matrix => math.gameCameraNodeTransformAnimated(
    _engineFacing,
    _row,
    _column,
    animationType: _engineAnimation,
    moveProgress: _moveProgress,
    y: _y,
  );

  @override
  vm.Vector3 get forwardH {
    final matrix = this.matrix;
    final v = vm.Vector3(matrix.storage[8], 0, matrix.storage[10]);
    final length = v.length;
    return length < 1e-9 ? vm.Vector3(0, 0, -1) : v / length;
  }

  @override
  void update(double dt) {
    if (_animation == AnimationType.none) return;
    final duration = stepDuration > 0 ? stepDuration : 0.3;
    // The visual runs from the previous pose (progress 1) to the
    // destination cell (progress 0) — the same convention as
    // `gameCameraNodeTransformAnimated`.
    final next = _moveProgress - dt / duration;
    if (next <= 0) {
      _moveProgress = 0;
      _animation = AnimationType.none;
    } else {
      _moveProgress = next;
    }
    notifyListeners();
  }

  eng.Direction get _engineFacing => switch (_facing) {
    Direction.north => eng.Direction.north,
    Direction.east => eng.Direction.east,
    Direction.south => eng.Direction.south,
    Direction.west => eng.Direction.west,
  };

  eng.AnimationType get _engineAnimation => switch (_animation) {
    AnimationType.none => eng.AnimationType.none,
    AnimationType.stepForward => eng.AnimationType.moveForward,
    AnimationType.stepBackward => eng.AnimationType.moveBackward,
    AnimationType.strafeLeft => eng.AnimationType.strafeLeft,
    AnimationType.strafeRight => eng.AnimationType.strafeRight,
    AnimationType.turnLeft => eng.AnimationType.turnLeft,
    AnimationType.turnRight => eng.AnimationType.turnRight,
  };
}
