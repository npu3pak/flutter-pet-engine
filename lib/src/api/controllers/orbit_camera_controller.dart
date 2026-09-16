// Private fields behind public getters cannot use initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/game_camera.dart' as eng;
import '../nodes/scene_node.dart';
import 'camera_controller.dart';

/// The orbit camera: looks at [target] from [distance] with [yaw]/[pitch],
/// and supports orbit, pan, zoom and framing.
class OrbitCameraController extends ChangeNotifier implements CameraController {
  OrbitCameraController({
    vm.Vector3? target,
    double distance = 10,
    double yaw = 0,
    double pitch = 0.45,
  }) : target = target ?? vm.Vector3.zero(),
       _distance = distance,
       _yaw = yaw,
       _pitch = pitch;

  /// The pivot the camera looks at.
  vm.Vector3 target;

  double _distance;

  /// The distance from the pivot.
  double get distance => _distance;
  set distance(double value) {
    final clamped = value.clamp(0.05, 1e6);
    if (_distance == clamped) return;
    _distance = clamped;
    notifyListeners();
  }

  double _yaw;

  double get yaw => _yaw;
  set yaw(double value) {
    if (_yaw == value) return;
    _yaw = value;
    notifyListeners();
  }

  double _pitch;

  double get pitch => _pitch;
  set pitch(double value) {
    final clamped = value.clamp(-1.55, 1.55);
    if (_pitch == clamped) return;
    _pitch = clamped;
    notifyListeners();
  }

  final CameraProjection _projection = CameraProjection(
    fovY: kFovY,
    near: eng.kNearPlane,
    far: eng.kFarPlane,
  );

  @override
  CameraProjection get projection => _projection;

  /// The camera position derived from the orbit parameters.
  vm.Vector3 get eye =>
      eng.GameCamera.orbitEye(target, _distance, _yaw, _pitch);

  /// The camera node transform of the current orbit.
  vm.Matrix4 get matrix =>
      vm.Matrix4.translation(eye) *
      vm.Matrix4.rotationY(_yaw) *
      vm.Matrix4.rotationX(_pitch);

  @override
  vm.Vector3 get forwardH => _normalizeOrZero();

  vm.Vector3 _normalizeOrZero() {
    final v = target - eye;
    v.y = 0;
    return v.length2 < 1e-12 ? vm.Vector3(0, 0, -1) : v.normalized();
  }

  @override
  void update(double dt) {}

  /// Starts orbiting from the current camera position without a jump.
  void startFromCurrent() {
    final angles = eng.GameCamera.orbitAngles(target, eye);
    _yaw = angles.$1;
    _pitch = angles.$2;
    notifyListeners();
  }

  /// Orbits around [target] by screen deltas.
  void orbit(double dx, double dy, {double sensitivity = 0.005}) {
    _yaw += dx * sensitivity;
    _pitch = (_pitch - dy * sensitivity).clamp(-1.55, 1.55);
    notifyListeners();
  }

  /// Pans the pivot parallel to the screen.
  void pan(double dx, double dy, {double viewportHeight = 800}) {
    final scale = eng.GameCamera.panWorldPerPixel(_distance, viewportHeight);
    final right = eng.GameCamera.horizontalRight(_yaw);
    target -= right * (dx * scale);
    target.y += dy * scale;
    notifyListeners();
  }

  /// Changes the distance; [delta] is the raw wheel dy.
  void zoom(double delta) {
    distance = _distance - (-delta * 0.08).clamp(-0.45, 0.45) * _distance;
  }

  /// Frames world-space [bounds].
  void frameBounds(vm.Aabb3 bounds) {
    target = bounds.center;
    _distance = eng.GameCamera.focusDistance((bounds.max - bounds.min).length);
    notifyListeners();
  }

  /// Frames a node's world bounds (no-op when they cannot be computed).
  void focusNode(SceneNode node) {
    final bounds = node.worldBounds;
    if (bounds != null) frameBounds(bounds);
  }
}
