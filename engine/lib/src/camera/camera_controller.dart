import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../engine/game_camera.dart';
import 'animation_type.dart';
import 'direction.dart';
import 'game_camera_math.dart';

/// The pluggable camera driver of a [GameScene]: it owns the camera node's
/// transform, its projection and the horizontal forward used for billboard
/// orientation. The engine ships [FreeCameraController] (the editor-style
/// free-fly camera) and [GameViewController] (the first-person game camera
/// with turn/step animation); a game may implement its own.
abstract class CameraController {
  /// The lens paired with this controller; [GameScene] applies it to its
  /// [NodeCamera].
  CameraProjection get projection;

  /// Horizontal view direction (local +Z of the camera node) — billboards
  /// reorient against it.
  vm.Vector3 get forwardH;

  /// Optional per-frame state advance (input-driven controllers need none).
  void update(double dt) {}

  /// Writes the current camera transform into [cameraNode].
  void applyTo(Node cameraNode);
}

/// Wraps the engine's free-fly [GameCamera] (fly/orbit/pan/zoom) as a
/// controller — the default of [GameScene].
class FreeCameraController implements CameraController {
  FreeCameraController([GameCamera? camera]) : camera = camera ?? GameCamera();

  final GameCamera camera;

  final PerspectiveProjection _projection = PerspectiveProjection(
    fovRadiansY: kFovY,
    near: kNearPlane,
    far: kFarPlane,
  );

  @override
  CameraProjection get projection => _projection;

  @override
  vm.Vector3 get forwardH => camera.forwardH;

  @override
  void update(double dt) {}

  @override
  void applyTo(Node cameraNode) => camera.applyTo(cameraNode);
}

/// The first-person game camera: fixed at a cell of the mirrored world grid
/// (`(−column, y, row)`), looking along [facing], with the turn/step
/// animation (`animation` + `moveProgress`) and the deterministic head bob
/// from [gameCameraNodeTransformAnimated].
///
/// The controller holds no clock: the game (or the stand) drives
/// `animation`/`moveProgress` itself, then [GameScene.update] applies the
/// resulting transform and projection.
class GameViewController implements CameraController {
  GameViewController({
    this.facing = Direction.north,
    this.row = 0,
    this.column = 0,
    this.y = kGameCameraY,
  });

  /// Destination facing (during a turn the animation ends at this facing).
  Direction facing;

  /// Destination cell while animating.
  int row;
  int column;

  /// Eye height (biomes may raise it).
  double y;

  /// The step/turn animation currently playing.
  AnimationType animation = AnimationType.none;

  /// Animation progress, 0 (start) … 1 (done).
  double moveProgress = 0.0;

  /// The current camera node transform.
  vm.Matrix4 get matrix => gameCameraNodeTransformAnimated(
        facing,
        row,
        column,
        animationType: animation,
        moveProgress: moveProgress,
        y: y,
      );

  final PerspectiveProjection _projection = PerspectiveProjection(
    fovRadiansY: kGameCameraFovY,
    near: kGameCameraNear,
    far: kGameCameraFar,
  );

  @override
  CameraProjection get projection => _projection;

  @override
  vm.Vector3 get forwardH {
    final m = matrix;
    final v = vm.Vector3(m.storage[8], 0, m.storage[10]);
    final length = v.length;
    return length < 1e-9 ? vm.Vector3(0, 0, -1) : v / length;
  }

  @override
  void update(double dt) {}

  @override
  void applyTo(Node cameraNode) => cameraNode.localTransform = matrix;
}
