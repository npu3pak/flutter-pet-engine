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

  /// The default clip planes and fly speed (kept for scene-sized scenes;
  /// large imported maps call [setClip]/raise [flySpeed]).
  static const double defaultNear = eng.kNearPlane;
  static const double defaultFar = eng.kFarPlane;
  static const double defaultFlySpeed = 12.0;

  /// The reference diagonal of the legacy scene grid (64×64×32 ≈ 94.3
  /// units): [configureForExtent] keeps [defaultFlySpeed] at this scale and
  /// scales the speed proportionally beyond it, so a 1:1 imported map flies
  /// at the same relative pace as a small scene.
  static const double flySpeedReferenceExtent = 94.0;

  final eng.GameCamera _camera;

  CameraProjection _projection = CameraProjection(
    fovY: kFovY,
    near: eng.kNearPlane,
    far: eng.kFarPlane,
  );

  /// World units per second while flying; [configureForExtent] scales it
  /// with the scene size (12 units/s per [flySpeedReferenceExtent] of
  /// diagonal).
  double flySpeed = defaultFlySpeed;

  @override
  CameraProjection get projection => _projection;

  /// Adjusts the near/far clip planes (values ≤ 0 are ignored). Scenes with
  /// extents far beyond the defaults (1:1 imported maps) must widen [far] or
  /// the content disappears; values that match the current ones keep the
  /// projection object identity.
  void setClip({double? near, double? far}) {
    final n = near == null || near <= 0 ? _projection.near : near;
    final f = far == null || far <= 0 ? _projection.far : far;
    if (n == _projection.near && f == _projection.far) return;
    _projection = CameraProjection(fovY: kFovY, near: n, far: f);
    notifyListeners();
  }

  /// Adapts the camera to the world extent (usually the scene diagonal) of
  /// the loaded model: widens the clip planes and scales the fly speed for
  /// large 1:1 maps. Scenes up to 200 units diagonal — comfortably above
  /// the legacy 64×64×32 grid (~94 units) — keep the default values exactly;
  /// beyond that the speed grows proportionally to the size
  /// (`defaultFlySpeed · extent / flySpeedReferenceExtent`), so crossing a
  /// 1:1 imported map takes about as long as crossing a legacy scene.
  void configureForExtent(double extent) {
    final e = extent.isFinite && extent > 0 ? extent : 1.0;
    if (e <= 200) {
      setClip(near: defaultNear, far: defaultFar);
      if (flySpeed == defaultFlySpeed) return;
      flySpeed = defaultFlySpeed;
      notifyListeners();
      return;
    }
    setClip(
      near: (e * 1e-4).clamp(defaultNear, 1.0),
      far: math.max(defaultFar, e * 4.0),
    );
    final speed = math.max(
      defaultFlySpeed,
      defaultFlySpeed * e / flySpeedReferenceExtent,
    );
    if (speed == flySpeed) return;
    flySpeed = speed;
    notifyListeners();
  }

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

  /// The horizontal part of the camera's local +X (screen-right).
  vm.Vector3 get rightH => _camera.rightH;

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
    _camera.keyDown(logicalKey, shift: shift, speed: flySpeed);
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
