import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controllers/camera_controller.dart';
import '../scene_controller.dart';

/// The viewport geometry and scene a [SceneInput] handler works with.
class SceneViewportInfo {
  SceneViewportInfo({
    required this.size,
    required this.pixelRatio,
    required this.controller,
  });

  /// The viewport size in logical pixels.
  final Size size;

  /// The viewport pixel ratio.
  final double pixelRatio;

  /// The scene controller of the viewport.
  final SceneController controller;

  /// The active camera controller.
  CameraController get camera => controller.camera;
}

/// The default (no-op) input handler: the viewport still forms taps and
/// forwards events, but nothing reacts.
class SceneInput {
  const SceneInput();

  /// An input handler that ignores everything; the application handles raw
  /// pointer events around the viewport itself.
  const SceneInput.none();

  void onPointerDown(PointerDownEvent event, SceneViewportInfo info) {}
  void onPointerMove(PointerMoveEvent event, SceneViewportInfo info) {}
  void onPointerUp(PointerUpEvent event, SceneViewportInfo info) {}
  void onPointerCancel(PointerCancelEvent event, SceneViewportInfo info) {}
  void onPointerSignal(PointerSignalEvent event, SceneViewportInfo info) {}
  void onPanZoomStart(PointerPanZoomStartEvent event, SceneViewportInfo info) {}
  void onPanZoomUpdate(
    PointerPanZoomUpdateEvent event,
    SceneViewportInfo info,
  ) {}
  void onPanZoomEnd(PointerPanZoomEndEvent event, SceneViewportInfo info) {}
  void onHover(PointerHoverEvent event, SceneViewportInfo info) {}

  /// Keyboard events; the default ignores them so application shortcuts keep
  /// working.
  KeyEventResult onKey(
    FocusNode node,
    KeyEvent event,
    SceneViewportInfo info,
  ) => KeyEventResult.ignored;
}

/// A tap (or double tap) formed by the viewport: position, buttons and the
/// world ray under the pointer.
class SceneTapEvent {
  SceneTapEvent({
    required this.screenPosition,
    required this.viewportSize,
    required this.buttons,
    required this.ray,
  });

  /// The tap position in viewport coordinates.
  final Offset screenPosition;

  /// The viewport size at the moment of the tap.
  final Size viewportSize;

  /// The pressed mouse buttons (or touch pointer button).
  final int buttons;

  /// The world ray from the camera through the tap point.
  final vm.Ray ray;

  /// Whether the primary button/touch formed the tap.
  bool get isPrimary => (buttons & kPrimaryButton) != 0;
}
