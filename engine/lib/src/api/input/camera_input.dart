import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controllers/fly_camera_controller.dart';
import 'scene_input.dart';

/// The default camera input: the look button drags the view and enables
/// keyboard flight, the pan button drags the scene sideways, the wheel
/// zooms, the keyboard moves (WASD/QE, Shift = faster).
///
/// The handler is stateless per event and only reacts when the active camera
/// is a [FlyCameraController]; other cameras ignore it.
class CameraInput extends SceneInput {
  CameraInput({
    this.pointerLookButton = kSecondaryButton,
    this.pointerFlyButton = kSecondaryButton,
    this.pointerPanButton = kPrimaryButton,
    this.tapSlop = 8,
    this.tapTimeout = const Duration(milliseconds: 300),
    this.lookSensitivity = 0.005,
    this.keyFlyCodes = const {0x57, 0x41, 0x53, 0x44, 0x45, 0x51},
  });

  /// The mouse button whose drag looks around.
  final int pointerLookButton;

  /// The mouse button that enables flight (WASD/QE move while it is held).
  final int pointerFlyButton;

  /// The mouse button whose drag pans the scene sideways.
  final int pointerPanButton;

  /// Tap thresholds (the viewport forms taps itself).
  final double tapSlop;
  final Duration tapTimeout;

  /// Look sensitivity in radians per pixel.
  final double lookSensitivity;

  /// The engine key codes that fly (W/A/S/D/Q/E).
  final Set<int> keyFlyCodes;

  int? _lookPointer;
  int? _flyPointer;
  int? _panPointer;

  @override
  void onPointerDown(PointerDownEvent event, SceneViewportInfo info) {
    final camera = _flyCamera(info);
    if (camera == null) return;
    if (event.kind == PointerDeviceKind.touch) {
      if (_lookPointer == null) {
        _lookPointer = event.pointer;
      } else if (_flyPointer == null) {
        _flyPointer = event.pointer;
        camera.startFly();
      }
      return;
    }
    if ((event.buttons & pointerLookButton) != 0 && _lookPointer == null) {
      _lookPointer = event.pointer;
    }
    if ((event.buttons & pointerFlyButton) != 0 && _flyPointer == null) {
      _flyPointer = event.pointer;
      camera.startFly();
    }
    if ((event.buttons & pointerPanButton) != 0 && _panPointer == null) {
      _panPointer = event.pointer;
    }
  }

  @override
  void onPointerMove(PointerMoveEvent event, SceneViewportInfo info) {
    final camera = _flyCamera(info);
    if (camera == null) return;
    if (event.pointer == _lookPointer) {
      camera.flyLook(
        event.delta.dx,
        event.delta.dy,
        sensitivity: lookSensitivity,
      );
    } else if (event.pointer == _panPointer) {
      camera.pan(
        event.delta.dx,
        event.delta.dy,
        focus: camera.eye + camera.forward * 10,
        viewportHeight: info.size.height,
      );
    }
  }

  @override
  void onPointerUp(PointerUpEvent event, SceneViewportInfo info) {
    _release(event.pointer, info);
  }

  @override
  void onPointerCancel(PointerCancelEvent event, SceneViewportInfo info) {
    _release(event.pointer, info);
  }

  void _release(int pointer, SceneViewportInfo info) {
    if (_lookPointer == pointer) _lookPointer = null;
    if (_panPointer == pointer) _panPointer = null;
    if (_flyPointer == pointer) {
      _flyPointer = null;
      _flyCamera(info)?.stopFly();
    }
  }

  @override
  void onPointerSignal(PointerSignalEvent event, SceneViewportInfo info) {
    if (event is! PointerScrollEvent) return;
    final camera = _flyCamera(info);
    camera?.scrollZoom(event.scrollDelta.dy);
  }

  @override
  KeyEventResult onKey(FocusNode node, KeyEvent event, SceneViewportInfo info) {
    final camera = _flyCamera(info);
    if (camera == null) return KeyEventResult.ignored;
    final code = _codeOf(event.logicalKey);
    if (code == null || !keyFlyCodes.contains(code)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      camera.keyDown(code, shift: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      camera.keyUp(code);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  FlyCameraController? _flyCamera(SceneViewportInfo info) {
    final camera = info.camera;
    return camera is FlyCameraController ? camera : null;
  }

  static int? _codeOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.keyW => 0x57,
    LogicalKeyboardKey.keyA => 0x41,
    LogicalKeyboardKey.keyS => 0x53,
    LogicalKeyboardKey.keyD => 0x44,
    LogicalKeyboardKey.keyE => 0x45,
    LogicalKeyboardKey.keyQ => 0x51,
    _ => null,
  };
}
