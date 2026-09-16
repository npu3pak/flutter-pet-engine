import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../../visual/screenshot.dart';
import '../geometry/line_geometry.dart';
import '../input/camera_input.dart';
import '../input/scene_input.dart';
import '../scene_controller.dart';
import '../scene_load_status.dart';
import '../skybox/skybox_background.dart';
import 'scene_view_spec.dart';

/// Prepares the engine's static render resources (the shader bundle).
///
/// Geometry and materials can only be built after this completes; the
/// viewport waits for it internally, but applications that build geometry
/// before the first frame should await it themselves.
///
/// [lineWidthBackend] overrides the platform default for screen-pixel line
/// widths (GPU shader on macOS/iOS/Android, CPU polyline on Windows/Linux);
/// it is also settable at runtime with `setLineWidthBackend` for debugging.
/// The `PET_LINE_WIDTH_BACKEND=polyline` define forces the CPU fallback.
Future<void> initializeEngine({LineWidthBackend? lineWidthBackend}) async {
  if (lineWidthBackend != null) {
    setLineWidthBackend(lineWidthBackend);
  } else if (_kLineWidthBackendDefine == 'polyline') {
    setLineWidthBackend(LineWidthBackend.polyline);
  } else {
    setLineWidthBackend(defaultLineWidthBackend());
  }
  await fs.Scene.initializeStaticResources();
}

const String _kLineWidthBackendDefine = String.fromEnvironment(
  'PET_LINE_WIDTH_BACKEND',
);

/// Builds a 2D widget under or over the 3D scene.
typedef SceneOverlayBuilder = Widget Function(BuildContext context, Size size);

/// Builds the loading indicator shown while the controller is loading.
typedef SceneLoadingBuilder = Widget Function(
  BuildContext context,
  SceneLoadStatus status,
);

/// Receives taps formed by the viewport.
typedef SceneTapCallback = void Function(SceneTapEvent event);

/// Everything a [SceneViewportBackend] needs to build one frame.
class SceneViewportContext {
  const SceneViewportContext({
    required this.controller,
    required this.views,
    required this.pixelRatio,
    required this.warmUp,
  });

  final SceneController controller;
  final List<SceneViewSpec> views;
  final double pixelRatio;
  final bool warmUp;
}

/// The rendering seam of [SceneViewport].
///
/// The default [ForkSceneViewportBackend] renders through the fork and needs
/// a GPU. Tests substitute a fake backend and exercise the viewport logic
/// (size, tick, input, overlays, capture) headlessly.
abstract class SceneViewportBackend {
  const SceneViewportBackend();

  /// Builds the render surface of the viewport.
  Widget build(BuildContext context, SceneViewportContext viewport);

  /// Captures the viewport contents as PNG bytes.
  Future<Uint8List> capture(
    SceneViewportContext viewport, {
    double? pixelRatio,
  });
}

/// The production backend: renders through the fork's `SceneView` and
/// captures through a repaint boundary.
class ForkSceneViewportBackend extends SceneViewportBackend {
  ForkSceneViewportBackend();

  final GlobalKey _boundaryKey = GlobalKey();

  @override
  Widget build(BuildContext context, SceneViewportContext viewport) {
    final scene = viewport.controller.ensureRenderScene();
    final camera = viewport.controller.renderCamera;
    return RepaintBoundary(
      key: _boundaryKey,
      child: fs.SceneView(
        scene,
        viewsBuilder: camera == null
            ? null
            : (_) => [
                for (final spec in viewport.views)
                  fs.RenderView(
                    camera: camera,
                    layerMask: spec.layerMask,
                    order: spec.order,
                  ),
              ],
        pixelRatio: viewport.pixelRatio,
        warmUp: viewport.warmUp,
      ),
    );
  }

  @override
  Future<Uint8List> capture(
    SceneViewportContext viewport, {
    double? pixelRatio,
  }) async {
    final bytes = await captureBoundary(
      _boundaryKey,
      pixelRatio ?? viewport.pixelRatio,
    );
    return bytes ?? Uint8List(0);
  }
}

/// The 3D viewport widget: embeds a [SceneController] in the widget tree.
///
/// The viewport owns its size, frame and input: it reports the layout size to
/// the controller, drives `controller.update(dt)` each frame (unless
/// [autoTick] is false), forwards pointer/keyboard events to [input] and
/// forms taps itself. The controller is owned by the application and is not
/// disposed by the widget.
class SceneViewport extends StatefulWidget {
  const SceneViewport({
    super.key,
    required this.controller,
    this.views,
    this.input,
    this.overlayBuilder,
    this.backgroundBuilder,
    this.loadingBuilder,
    this.onTap,
    this.onDoubleTap,
    this.autoTick = true,
    this.pixelRatio,
    this.warmUp = false,
    this.focusNode,
    this.autofocus = true,
    this.backend,
  });

  /// The scene to render.
  final SceneController controller;

  /// The views (layer masks and order); null means one full view.
  final List<SceneViewSpec>? views;

  /// The input handler; null means the default [CameraInput].
  ///
  /// The handler instance owns the pointer state of a gesture. While
  /// pointers are held the viewport keeps serving the instance that received
  /// their `onPointerDown`, even if the widget is rebuilt with a new one; a
  /// deferred swap applies once the last pointer is released. Still, prefer
  /// a stable instance (a `State` field) over constructing one in `build`.
  final SceneInput? input;

  /// 2D widgets drawn over the scene.
  final SceneOverlayBuilder? overlayBuilder;

  /// 2D widgets drawn under the scene (for example a sky).
  final SceneOverlayBuilder? backgroundBuilder;

  /// The loading indicator; null means a plain dark placeholder.
  final SceneLoadingBuilder? loadingBuilder;

  /// Called on a tap on the scene.
  final SceneTapCallback? onTap;

  /// Called on a double tap on the scene.
  final SceneTapCallback? onDoubleTap;

  /// Whether the viewport drives `controller.update(dt)` itself.
  final bool autoTick;

  /// The target texture pixel ratio; null means the device pixel ratio.
  final double? pixelRatio;

  /// Whether to warm up the render pipelines on the first frame.
  final bool warmUp;

  /// The focus node for keyboard input.
  final FocusNode? focusNode;

  /// Whether to take focus when the viewport appears.
  final bool autofocus;

  /// The rendering backend; tests substitute a fake one.
  final SceneViewportBackend? backend;

  @override
  State<SceneViewport> createState() => SceneViewportState();
}

/// The state of a [SceneViewport]; use a `GlobalKey<SceneViewportState>` to
/// call [capture].
class SceneViewportState extends State<SceneViewport>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final SceneViewportBackend _backend =
      widget.backend ?? ForkSceneViewportBackend();
  late final SceneInput _defaultInput = CameraInput();

  /// The handler serving the events right now. While pointers are held it
  /// stays the handler that received their `onPointerDown`, even if the
  /// widget is rebuilt with another instance: a fresh [CameraInput] has no
  /// pointer state and would silently drop the gesture.
  late SceneInput _activeInput;

  /// The handler to switch to when the last pointer is released.
  SceneInput? _pendingInput;

  /// How many pointers the viewport is currently tracking.
  int _activePointers = 0;

  Duration _lastTick = Duration.zero;
  Duration _lastTapAt = Duration.zero;
  Offset? _lastTapPosition;
  int? _primaryPointer;
  Offset _downPosition = Offset.zero;
  Duration _downTime = Duration.zero;
  int _downButtons = 0;
  Size _size = Size.zero;
  double _pixelRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _activeInput = widget.input ?? _defaultInput;
    _ticker = createTicker(_onTick);
    if (widget.autoTick) {
      _ticker.start();
    }
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SceneViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.autoTick != widget.autoTick) {
      widget.autoTick ? _ticker.start() : _ticker.stop();
    }
    if (!identical(oldWidget.input, widget.input)) {
      _swapInput(widget.input ?? _defaultInput);
    }
  }

  /// Switches to [next]: immediately when no pointers are held, otherwise
  /// deferred until the current gesture ends.
  void _swapInput(SceneInput next) {
    if (_activePointers == 0) {
      _activeInput = next;
      _pendingInput = null;
    } else {
      _pendingInput = next;
    }
  }

  /// Releases one tracked pointer and applies a deferred input swap after
  /// the last one is up.
  void _releasePointer() {
    if (_activePointers > 0) _activePointers--;
    if (_activePointers > 0) return;
    final pending = _pendingInput;
    if (pending != null) {
      _activeInput = pending;
      _pendingInput = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // The controller may notify while a widget build is in progress (a
    // screen mounting a panel that adds nodes, texture-ready callbacks).
    // Rebuilding the viewport synchronously would call setState during that
    // build; the refresh is deferred to the end of the frame instead.
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  bool _rebuildScheduled = false;

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    if (dt <= 0) return;
    widget.controller.update(dt);
  }

  /// The current viewport size in logical pixels.
  Size get viewportSize => _size;

  /// Captures the viewport contents as PNG bytes.
  Future<Uint8List> capture({double? pixelRatio}) =>
      _backend.capture(_context, pixelRatio: pixelRatio);

  SceneViewportContext get _context => SceneViewportContext(
    controller: widget.controller,
    views: _effectiveViews,
    pixelRatio: _pixelRatio,
    warmUp: widget.warmUp,
  );

  /// The views to render: the explicit widget list, or the main view plus
  /// the service views the scene actually needs (overlay content and
  /// top-layer gizmos/wireframes draw in their own passes so they show
  /// through the scene).
  List<SceneViewSpec> get _effectiveViews {
    final views = widget.views;
    if (views != null) return views;
    final controller = widget.controller;
    return [
      SceneViewSpec.main(),
      if (controller.hasOverlayContent) SceneViewSpec.overlay(),
      if (controller.hasTopContent) SceneViewSpec.top(),
    ];
  }

  SceneViewportInfo get _info => SceneViewportInfo(
    size: _size,
    pixelRatio: _pixelRatio,
    controller: widget.controller,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        _pixelRatio =
            widget.pixelRatio ?? MediaQuery.devicePixelRatioOf(context);
        // Reported synchronously: `setViewport` only stores the values (no
        // notifications), and deferring it to a post-frame callback left the
        // controller with the previous size for a frame — a ray cast in
        // between used stale viewport geometry.
        widget.controller.setViewport(_size, _pixelRatio);

        final status = widget.controller.status;
        final showLoading =
            status.phase != SceneLoadPhase.idle &&
            !status.isReady &&
            !status.hasError;

        final scene = _backend.build(context, _context);
        final skybox = widget.controller.skybox;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: (event) => _input.onPointerMove(event, _info),
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: (event) => _input.onPointerSignal(event, _info),
          onPointerPanZoomStart: (event) => _input.onPanZoomStart(event, _info),
          onPointerPanZoomUpdate: (event) =>
              _input.onPanZoomUpdate(event, _info),
          onPointerPanZoomEnd: (event) => _input.onPanZoomEnd(event, _info),
          onPointerHover: (event) => _input.onHover(event, _info),
          child: Focus(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onKeyEvent: (node, event) => _input.onKey(node, event, _info),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (skybox != null)
                  SkyboxBackground(
                    node: skybox,
                    camera: widget.controller.camera,
                  ),
                if (widget.backgroundBuilder != null)
                  widget.backgroundBuilder!(context, _size),
                scene,
                if (showLoading)
                  widget.loadingBuilder?.call(context, status) ??
                      const ColoredBox(color: Color(0xFF202020)),
                if (widget.overlayBuilder != null)
                  widget.overlayBuilder!(context, _size),
              ],
            ),
          ),
        );
      },
    );
  }

  SceneInput get _input => _activeInput;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_primaryPointer == null) {
      _primaryPointer = event.pointer;
      _downPosition = event.localPosition;
      _downTime = event.timeStamp;
      _downButtons = event.buttons;
    }
    _input.onPointerDown(event, _info);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer == _primaryPointer) {
      _primaryPointer = null;
      final slop = (event.localPosition - _downPosition).distance;
      final elapsed = event.timeStamp - _downTime;
      final isPrimary = (_downButtons & kPrimaryButton) != 0;
      if (isPrimary &&
          slop <= kTouchSlop &&
          elapsed <= const Duration(milliseconds: 300)) {
        _formTap(event.localPosition, _size);
      }
    }
    _input.onPointerUp(event, _info);
    _releasePointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _input.onPointerCancel(event, _info);
    _releasePointer();
  }

  void _formTap(Offset position, Size viewportSize) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final isDouble =
        _lastTapPosition != null &&
        now - _lastTapAt <= kDoubleTapTimeout &&
        (position - _lastTapPosition!).distance <= kDoubleTapSlop;
    final event = SceneTapEvent(
      screenPosition: position,
      viewportSize: viewportSize,
      buttons: _downButtons,
      ray: _screenRay(position),
    );
    if (isDouble) {
      _lastTapPosition = null;
      widget.onDoubleTap?.call(event);
    } else {
      _lastTapPosition = position;
      _lastTapAt = now;
      widget.onTap?.call(event);
    }
  }

  /// The tap ray: the controller owns the screen→world math (camera pose,
  /// viewport size), so taps and `SceneController.screenPointToRay` can never
  /// drift apart.
  vm.Ray _screenRay(Offset position) =>
      widget.controller.screenPointToRay(position);
}
