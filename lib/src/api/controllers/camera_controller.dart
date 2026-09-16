import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The default vertical field of view of the free camera (55°).
const double kFovY = 55 * math.pi / 180;

/// Perspective projection parameters of a camera controller.
class CameraProjection {
  CameraProjection({required this.fovY, this.near = 0.05, this.far = 300});

  double fovY;
  double near;
  double far;
}

/// A camera of the scene: owns the projection and the view transform, and
/// updates itself each frame.
///
/// Applications either use one of the engine controllers
/// (`FlyCameraController`, `FirstPersonCameraController`,
/// `OrbitCameraController`, `MatrixCameraController`) or implement this
/// interface to drive the camera with their own math.
abstract class CameraController extends ChangeNotifier {
  /// The projection parameters.
  CameraProjection get projection;

  /// The horizontal forward direction, used to reorient billboards.
  vm.Vector3 get forwardH;

  /// Advances time-based camera behaviour (fly inertia, step animation).
  void update(double dt);
}

/// A camera driven by an externally supplied view matrix.
class MatrixCameraController extends ChangeNotifier
    implements CameraController {
  MatrixCameraController({
    double fovY = kFovY,
    double near = 0.05,
    double far = 300,
  }) : _projection = CameraProjection(fovY: fovY, near: near, far: far);

  /// The camera node transform, written by the application every frame.
  vm.Matrix4 matrix = vm.Matrix4.identity();

  final CameraProjection _projection;

  @override
  CameraProjection get projection => _projection;

  double get fovY => _projection.fovY;
  set fovY(double value) {
    _projection.fovY = value;
    notifyListeners();
  }

  double get near => _projection.near;
  set near(double value) {
    _projection.near = value;
    notifyListeners();
  }

  double get far => _projection.far;
  set far(double value) {
    _projection.far = value;
    notifyListeners();
  }

  @override
  vm.Vector3 get forwardH {
    final v = vm.Vector3(matrix.storage[8], 0, matrix.storage[10]);
    final length = v.length;
    return length < 1e-9 ? vm.Vector3(0, 0, -1) : v / length;
  }

  @override
  void update(double dt) {}
}
