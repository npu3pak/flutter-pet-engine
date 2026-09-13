import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/game_camera.dart' as eng;
import '../../models/model_scene.dart';
import '../nodes/scene_node.dart';
import 'camera_controller.dart';

/// The free-fly camera: flight (WASD/QE), look, orbit, pan, zoom and model
/// framing — the editor-style navigation reused by games.
class FlyCameraController extends ChangeNotifier implements CameraController {
  FlyCameraController({
    vm.Vector3? eye,
    double yaw = math.pi,
    double pitch = 0.45,
  }) : _camera = eng.GameCamera(eye: eye, yaw: yaw, pitch: pitch);

  /// The default vertical field of view (55°).
  static const double fovY = kFovY;

  final eng.GameCamera _camera;

  final CameraProjection _projection = CameraProjection(
    fovY: kFovY,
    near: eng.kNearPlane,
    far: eng.kFarPlane,
  );

  /// World units per second while flying.
  double flySpeed = 12.0;

  @override
  CameraProjection get projection => _projection;

  /// The camera position in world space.
  vm.Vector3 get eye => _camera.eye;
  set eye(vm.Vector3 value) {
    _camera.eye = value;
    notifyListeners();
  }

  /// The yaw around Y (π looks toward −Z).
  double get yaw => _camera.yaw;
  set yaw(double value) {
    _camera.yaw = value;
    notifyListeners();
  }

  /// The pitch; positive looks down.
  double get pitch => _camera.pitch;
  set pitch(double value) {
    _camera.pitch = value;
    notifyListeners();
  }

  /// Whether the fly mode is active (keyboard movement applies).
  bool get flying => _camera.flying;

  /// The camera node transform of the current state.
  vm.Matrix4 get matrix =>
      vm.Matrix4.translation(eye) *
      vm.Matrix4.rotationY(yaw) *
      vm.Matrix4.rotationX(pitch);

  @override
  vm.Vector3 get forwardH => _camera.forwardH;

  /// The full view direction.
  vm.Vector3 get forward => _camera.forward;

  @override
  void update(double dt) {
    if (_camera.flying) {
      _camera.flyStep(dt * flySpeed);
    }
  }

  /// Positions the camera at the current [eye] looking at [target].
  void lookAt(vm.Vector3 target) {
    _camera.lookAt(eye, target);
    notifyListeners();
  }

  /// Frames a whole model document.
  void frameModel(ModelData model) {
    _camera.frameModel(model);
    notifyListeners();
  }

  /// Frames world-space [bounds].
  void frameBounds(vm.Aabb3 bounds) {
    final center = bounds.center;
    final radius = bounds.max - bounds.min;
    final diag = radius.length;
    final distance = eng.GameCamera.focusDistance(diag);
    _camera.eye = center + vm.Vector3(0, diag * 0.35 + 1, distance);
    _camera.lookAt(_camera.eye, center);
    notifyListeners();
  }

  /// Frames a node's world bounds (no-op when they cannot be computed).
  void focusNode(SceneNode node) {
    final bounds = node.worldBounds;
    if (bounds != null) frameBounds(bounds);
  }

  /// One flight step (also called by [update] while flying).
  void flyStep(double dt, {bool shift = false}) {
    _camera.flyStep(dt, shift: shift);
    notifyListeners();
  }

  /// Looks around: [dx]/[dy] in screen pixels.
  void flyLook(double dx, double dy, {double sensitivity = 0.005}) {
    _camera.flyLook(dx, dy, sensitivity: sensitivity);
    notifyListeners();
  }

  void startFly() {
    _camera.startFly();
    notifyListeners();
  }

  void stopFly() {
    _camera.stopFly();
    notifyListeners();
  }

  void keyDown(int logicalKey, {bool shift = false}) {
    _camera.keyDown(logicalKey, shift: shift);
    notifyListeners();
  }

  void keyUp(int logicalKey) {
    _camera.keyUp(logicalKey);
    notifyListeners();
  }

  /// Starts an orbit around [pivot] without snapping.
  void startOrbit(vm.Vector3 pivot) {
    _camera.startOrbit(pivot);
    notifyListeners();
  }

  void orbit(double dx, double dy, {double sensitivity = 0.005}) {
    _camera.orbit(dx, dy, sensitivity: sensitivity);
    notifyListeners();
  }

  void stopOrbit() {
    _camera.stopOrbit();
    notifyListeners();
  }

  /// Pans parallel to the screen.
  void pan(
    double dx,
    double dy, {
    required vm.Vector3 focus,
    required double viewportHeight,
  }) {
    _camera.pan(dx, dy, focus: focus, viewportHeight: viewportHeight);
    notifyListeners();
  }

  /// Dollies along the eye→focus line; [delta] is the raw wheel dy.
  void scrollZoom(double delta, {vm.Vector3? focus, double? maxDistance}) {
    final pivot = focus ?? eye + forward * 10;
    _camera.scrollZoom(
      delta,
      pivot,
      maxDistance: maxDistance ?? zoomMaxDistance(64, 64, 32),
    );
    notifyListeners();
  }

  /// A reasonable zoom-out cap for a [w]×[l]×[h] model grid.
  static double zoomMaxDistance(int w, int l, int h) =>
      eng.GameCamera.zoomMaxDistance(w, l, h);

  /// The distance that frames an object of the given diagonal.
  static double focusDistance(double diag) =>
      eng.GameCamera.focusDistance(diag);
}
