import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' show Node, NodeCamera;
import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model_scene.dart';

/// Engine camera constants (mirror the editor's viewport defaults so a scene
/// framed in the editor looks the same in the game).
const double kFovY = 55 * 0.0174533;
const double kNearPlane = 0.05;
const double kFarPlane = 300.0;

/// Free-fly camera controller over a flutter_scene [NodeCamera]: eye/yaw/
/// pitch state, fly/orbit/pan/zoom gestures and model framing — the same
/// navigation math the editor's viewport uses, without any editor state.
///
/// The controller never touches the scene graph itself: apply it to a
/// [NodeCamera]'s node per frame via [apply] and read the movement helpers
/// for input handling. Coordinate conventions are identical to the renderer
/// (mirrored X — see `engine_compat/coords.dart`): yaw = π faces −Z.
class GameCamera {
  /// Camera position (world space).
  vm.Vector3 eye;

  /// Yaw around Y (standard right-handed rotationY); π looks toward −Z.
  double yaw;

  /// Pitch; positive looks DOWN (editor convention).
  double pitch;

  GameCamera({
    vm.Vector3? eye,
    this.yaw = math.pi,
    this.pitch = 0.45,
  }) : eye = eye ?? vm.Vector3(0, 8, 8);

  static const double _flySpeed = 12.0;
  final Set<int> _keys = {};
  bool _flying = false;

  bool get flying => _flying;
  void startFly() => _flying = true;
  void stopFly() {
    _flying = false;
    _keys.clear();
  }

  void keyDown(int logicalKey, {bool shift = false}) {
    _keys.add(logicalKey);
    if (_flying) _moveStep(0.016 * _flySpeed, shift);
  }

  void keyUp(int logicalKey) => _keys.remove(logicalKey);

  /// Applies the current eye/yaw/pitch to a camera node. Call every frame
  /// after the movement helpers.
  void applyTo(Node cameraNode) {
    cameraNode.localTransform =
        vm.Matrix4.translation(eye) * vm.Matrix4.rotationY(yaw) * vm.Matrix4.rotationX(pitch);
  }

  /// Frames a whole model (its grid) from the +Z side (yaw = π, looking
  /// toward −Z), camera distance and height scaling with the model's depth,
  /// width and height — the editor's framing for a model switch.
  void frameModel(ModelData model) {
    final w = model.size.w, l = model.size.l, h = model.size.h;
    final center = chunkWorld((w - 1) / 2, (l - 1) / 2, w, l);
    // Wide rows need backing away too: the vertical fov is 55° and the
    // viewport is wider than tall, so cover the width as well as the depth.
    final span = math.max(l.toDouble(), w * 0.8);
    final dist = span * 0.9 + 3;
    eye = vm.Vector3(
      center.x,
      math.max(2.5, h * 1.2 + 2).clamp(2.5, 60).toDouble(),
      center.z + dist,
    );
    eye.y = math.max(eye.y, span * 0.55).clamp(2.5, 120).toDouble();
    yaw = math.pi;
    pitch = 0.5;
  }

  /// Positions the camera at [pos] looking at [target] ([up] default +Y).
  void lookAt(vm.Vector3 pos, vm.Vector3 target, {vm.Vector3? up}) {
    eye = pos;
    final d = target - pos;
    final dir = d.length2 < 1e-9 ? vm.Vector3(0, 0, 1) : d.normalized();
    pitch = math.asin((-dir.y).clamp(-1.0, 1.0));
    yaw = math.atan2(dir.x, dir.z);
  }

  // ── vectors ──────────────────────────────────────────────────────────

  /// Horizontal part of the camera's forward (view) direction.
  vm.Vector3 get forwardH {
    final s = math.sin(yaw), c = math.cos(yaw);
    return vm.Vector3(s, 0, c).normalized();
  }

  /// The full (3D) camera view direction.
  vm.Vector3 get forward => flyForward(yaw, pitch);

  /// Horizontal part of the camera's local +X (screen-right).
  vm.Vector3 get rightH => horizontalRight(yaw);

  /// Pure helpers (kept public for tests / app-side math).
  static vm.Vector3 horizontalRight(double yaw) {
    final s = math.sin(yaw), c = math.cos(yaw);
    return vm.Vector3(c, 0, -s).normalized();
  }

  static vm.Vector3 flyForward(double yaw, double pitch) {
    final s = math.sin(yaw), c = math.cos(yaw);
    final sp = math.sin(pitch), cp = math.cos(pitch);
    return vm.Vector3(s * cp, -sp, c * cp).normalized();
  }

  // ── movement ─────────────────────────────────────────────────────────

  /// One flight step: W/S along the FULL view direction, A/D strafe
  /// horizontally, E/Q vertical (key codes 0x57/0x53/0x44/0x41/0x45/0x51;
  /// shift = ×2.5).
  void flyStep(double dt, {bool shift = false}) => _moveStep(dt, shift);

  void _moveStep(double speed, bool shift) {
    if (!_flying && _keys.isEmpty) return;
    final s = shift ? 2.5 : 1.0;
    final step = speed * s;
    if (_keys.isEmpty || _keys.contains(0x57)) eye.add(forward.scaled(step)); // W
    if (_keys.contains(0x53)) eye.sub(forward.scaled(step)); // S
    if (_keys.contains(0x44)) eye.add(rightH.scaled(step)); // D
    if (_keys.contains(0x41)) eye.sub(rightH.scaled(step)); // A
    if (_keys.contains(0x45)) eye.y += step; // E up
    if (_keys.contains(0x51)) eye.y -= step; // Q down
  }

  /// Look around (FPS-style): [dx]/[dy] in arbitrary units (0.005 per
  /// pixel at the editor's sensitivity). Dragging right turns right; up
  /// looks up.
  void flyLook(double dx, double dy, {double sensitivity = 0.005}) {
    yaw += dx * sensitivity;
    pitch = (pitch + dy * sensitivity).clamp(-1.55, 1.55);
  }

  // ── orbit around a pivot ─────────────────────────────────────────────

  double _orbitDist = 10.0;
  vm.Vector3 _orbitPivot = vm.Vector3.zero();
  bool _orbiting = false;

  bool get orbiting => _orbiting;

  /// Starts an orbit around [pivot] keeping the current eye→pivot
  /// direction (no snap/jump on the first move).
  void startOrbit(vm.Vector3 pivot) {
    _orbitPivot = pivot;
    _orbitDist = math.max((eye - pivot).length, 0.5);
    final (y, p) = orbitAngles(pivot, eye);
    yaw = y;
    pitch = p;
    _orbiting = true;
  }

  void stopOrbit() => _orbiting = false;

  void orbit(double dx, double dy, {double sensitivity = 0.005}) {
    if (!_orbiting) return;
    yaw += dx * sensitivity;
    pitch = (pitch - dy * sensitivity).clamp(-1.55, 1.55);
    eye = orbitEye(_orbitPivot, _orbitDist, yaw, pitch);
  }

  /// Pan the camera in the plane parallel to the screen (content follows
  /// the fingers: positive [dx] right / [dy] down).
  void pan(double dx, double dy, {required vm.Vector3 focus, required double viewportHeight}) {
    final dist = math.max((focus - eye).length, 0.5);
    final scale = panWorldPerPixel(dist, viewportHeight);
    eye -= rightH * (dx * scale);
    eye.y += dy * scale;
  }

  /// Smooth dolly along the eye→[focus] line. [delta] is the raw wheel dy
  /// (wheel-up is NEGATIVE in Flutter → positive delta zooms in).
  void scrollZoom(double delta, vm.Vector3 focus, {required double maxDistance}) {
    final to = focus - eye;
    final dist = to.length;
    if (dist < 1e-6) return;
    final (y, p) = orbitAngles(focus, eye);
    yaw = y;
    pitch = p;
    eye = zoomDolly(eye, focus, delta, maxDistance);
  }

  // ── pure math (public for tests) ─────────────────────────────────────

  /// The eye position for an orbit around [pivot] at [dist].
  static vm.Vector3 orbitEye(
      vm.Vector3 pivot, double dist, double yaw, double pitch) {
    final s = math.sin(yaw), c = math.cos(yaw);
    final sp = math.sin(pitch), cp = math.cos(pitch);
    final forward = vm.Vector3(s * cp, -sp, c * cp);
    return pivot - forward * dist;
  }

  /// Yaw/pitch that make a camera at [eye] look at [pivot].
  static (double, double) orbitAngles(vm.Vector3 pivot, vm.Vector3 eye) {
    final d = (pivot - eye);
    final dist = d.length;
    if (dist < 1e-9) return (0.0, 0.0);
    final dir = d / dist;
    final pitch = math.asin((-dir.y).clamp(-1.0, 1.0));
    final yaw = math.atan2(dir.x, dir.z);
    return (yaw, pitch);
  }

  /// World units per screen pixel at distance [dist] of a viewport
  /// [viewportHeight] tall.
  static double panWorldPerPixel(double dist, double viewportHeight) =>
      2 * dist * math.tan(kFovY / 2) / viewportHeight;

  /// Eye position after a dolly along eye→[focus]; [delta] raw wheel dy.
  static vm.Vector3 zoomDolly(
    vm.Vector3 eye,
    vm.Vector3 focus,
    double delta,
    double maxDist, {
    double minDist = 0.05,
  }) {
    final to = focus - eye;
    final dist = to.length;
    if (dist < 1e-6) return eye;
    final step = (-delta * 0.08).clamp(-0.45, 0.45);
    final dir = to / dist;
    final newDist = (dist - step).clamp(minDist, maxDist);
    return focus - dir * newDist;
  }

  /// Reasonable zoom-out cap for a [w]×[l]×[h] model grid.
  static double zoomMaxDistance(int w, int l, int h) {
    final diag = math.sqrt(w * w + l * l + h * h);
    return math.max(60.0, diag * 3.0);
  }

  /// Distance that frames an object of AABB diagonal [diag] at ~1/3 of the
  /// screen (fovY = 55°).
  static double focusDistance(double diag) => math.max(2.5, diag * 3.2);
}
