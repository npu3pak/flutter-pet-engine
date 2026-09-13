import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../services/app_log.dart';

/// A professional full-screen model viewer: loads a glTF/GLB model from the
/// project's `3d_models/` catalog, offers a user-orbitable camera (drag /
/// wheel / pinch), and plays every animation of the model with crossfade
/// blending, loop and speed controls.
///
/// Rendering goes through the v2 API: a dedicated [SceneController] with a
/// [GltfNode] built from a runtime [GltfAsset], displayed by a
/// [SceneViewport]. The animation transport drives the node's
/// [AnimationPlayer].
class ModelViewerScreen extends StatefulWidget {
  const ModelViewerScreen({super.key, required this.entry});

  /// The catalog entry to view (resolved against the project's `3d_models/`).
  final Model3dEntry entry;

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  final SceneController _controller = SceneController(mergeStatic: false);

  GltfNode? _node;
  OrbitCameraController? _camera;
  String? _error;
  bool _ready = false;

  bool _loop = true;
  double _speed = 1.0;

  /// Approximate playback time of the active clip (the player does not
  /// expose the clip's clock; the frame listener accumulates it).
  double _time = 0;
  int _uiAccumMs = 0;

  // Mouse/touch interaction state.
  bool _dragOrbit = false;
  bool _dragPan = false;
  final Map<int, Offset> _touches = {};
  bool _singleTouchOrbiting = false;
  Offset? _touchStart;
  double _pinchLastDist = 0;
  Offset _pinchMidLast = Offset.zero;

  /// True while the user drags the scrubber (stops the throttled UI
  /// refresh so the slider isn't yanked out from under the finger).
  bool _scrubbing = false;

  Model3dEntry get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _controller.addFrameListener(_onFrame);
    _load();
  }

  @override
  void dispose() {
    _node?.player.removeListener(_onPlayerChanged);
    _node = null;
    _controller.removeFrameListener(_onFrame);
    _controller.dispose();
    super.dispose();
  }

  // ── loading ─────────────────────────────────────────────────────────

  /// [reset] clears the current model first (used by «Повторить» after an
  /// error; the initial load starts from empty state anyway).
  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _clearScene();
      setState(() {
        _ready = false;
        _error = null;
      });
    }
    try {
      final asset = await GltfAsset.fromFile(File(entry.sourcePath));
      if (!mounted) return;
      _clearScene();
      final node = GltfNode.fromAsset(asset, name: entry.name);
      node.player.addListener(_onPlayerChanged);
      _controller.add(node);
      _node = node;
      _controller.add(
        LightNode.directional(
          direction: vm.Vector3(-0.4, -1, -0.35),
          intensity: 2.2,
        ),
      );
      final camera = OrbitCameraController(yaw: 0.7, pitch: 0.35);
      final bounds = asset.bounds;
      if (bounds != null) {
        camera.frameBounds(bounds);
      } else {
        // Skinned models report no bounds; keep the default framing and let
        // the user zoom/dolly.
        logStage('models', 'viewer ${entry.name}: no bounds (skinned?)');
      }
      _controller.camera = camera;
      _camera = camera;
      _time = 0;
      final clips = node.player.clips;
      if (clips.isNotEmpty) {
        final first = _pickDefaultAnimation(clips);
        node.player.play(first.fullName, loop: _loop, speed: _speed);
      }
      setState(() => _ready = true);
      logStage(
        'models',
        'viewer loaded ${entry.name} (${entry.kindLabel}) '
            'animations=${clips.length}',
      );
    } catch (e) {
      logStage('models', 'viewer FAIL ${entry.name}: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _ready = false;
      });
    }
  }

  /// Removes every node of the previous load (the controller itself is
  /// reused).
  void _clearScene() {
    final node = _node;
    if (node != null) {
      node.player.removeListener(_onPlayerChanged);
      _node = null;
    }
    for (final n in List.of(_controller.nodes)) {
      n.remove();
    }
    _time = 0;
    _uiAccumMs = 0;
  }

  /// Prefers an idle/rest animation, then the T-pose, then the first one —
  /// the standing frames are the most useful starting point for a viewer.
  GltfAnimInfo _pickDefaultAnimation(List<GltfAnimInfo> anims) {
    for (final a in anims) {
      final n = a.shortName.toLowerCase();
      if (n.contains('idle')) return a;
    }
    for (final a in anims) {
      final n = a.shortName.toLowerCase();
      if (n.contains('tpose') || n.contains('t-pose')) return a;
    }
    return anims.first;
  }

  // ── animation control ───────────────────────────────────────────────

  /// The descriptor of the player's current clip, or null for the rest pose.
  GltfAnimInfo? get _active {
    final player = _node?.player;
    final current = player?.current;
    if (player == null || current == null) return null;
    for (final clip in player.clips) {
      if (clip.fullName == current) return clip;
    }
    return null;
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  /// Re-applies the player's loop/speed to the current clip without losing
  /// its time (the player only accepts them through [AnimationPlayer.play]).
  void _applyParams() {
    final player = _node?.player;
    final current = player?.current;
    if (player == null || current == null) return;
    if (player.loop == _loop && player.speed == _speed) return;
    player.play(current, loop: _loop, speed: _speed);
    player.seek(_time);
  }

  void _activate(GltfAnimInfo anim) {
    final player = _node?.player;
    if (player == null) return;
    if (player.current == null) {
      _time = 0;
      player.play(anim.fullName, loop: _loop, speed: _speed);
    } else {
      // crossFade inherits loop/speed from the player — keep them current
      // while the outgoing clip keeps its own time; the target starts at 0.
      _applyParams();
      _time = 0;
      player.crossFade(anim.fullName);
    }
    setState(() {});
  }

  void _onFrame(Duration elapsed, double dt) {
    final player = _node?.player;
    if (player == null || !player.playing || _scrubbing) return;
    final active = _active;
    if (active == null) return;
    _time += dt * player.speed;
    final duration = active.duration;
    if (duration > 0 && _time >= duration) {
      _time = player.loop ? _time % duration : duration;
    }
    // Throttled UI refresh (playback time label + scrubber).
    _uiAccumMs += (dt * 1000).round();
    if (_uiAccumMs >= 100) {
      _uiAccumMs = 0;
      if (mounted) setState(() {});
    }
  }

  void _togglePlay() {
    final player = _node?.player;
    if (player == null || player.current == null) return;
    if (player.playing) {
      player.pause();
    } else {
      player.resume();
    }
    setState(() {});
  }

  void _stopPlayback() {
    final player = _node?.player;
    if (player == null || player.current == null) return;
    player.pause();
    player.seek(0);
    _time = 0;
    setState(() {});
  }

  /// Applies loop/speed without changing the paused/playing state (the
  /// player's [AnimationPlayer.play] always resumes).
  void _applyParamsPreservingPlayback() {
    final player = _node?.player;
    if (player == null) return;
    final wasPlaying = player.playing;
    _applyParams();
    if (!wasPlaying) player.pause();
  }

  void _toggleLoop(bool value) {
    _loop = value;
    _applyParamsPreservingPlayback();
    setState(() {});
  }

  void _setSpeed(double value) {
    _speed = value;
    _applyParamsPreservingPlayback();
    setState(() {});
  }

  void _seek(double fraction) {
    final active = _active;
    if (active == null) return;
    _time = fraction * active.duration;
    _node?.player.seek(_time);
  }

  // ── viewport input ──────────────────────────────────────────────────

  double get _viewportHeight {
    final height = _controller.viewportSize.height;
    return height > 0 ? height : 800;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _onTouchDown(e);
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final buttons = e.buttons;
    final panMode =
        shift ||
        (buttons & kSecondaryMouseButton) != 0 ||
        (buttons & kMiddleMouseButton) != 0;
    if ((buttons &
            (kPrimaryMouseButton |
                kSecondaryMouseButton |
                kMiddleMouseButton)) ==
        0) {
      return;
    }
    _dragOrbit = !panMode;
    _dragPan = panMode;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _onTouchMove(e);
      return;
    }
    final camera = _camera;
    if (camera == null) return;
    if (_dragOrbit) camera.orbit(e.delta.dx, e.delta.dy);
    if (_dragPan) camera.pan(e.delta.dx, e.delta.dy, viewportHeight: _viewportHeight);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touchEnd(e.pointer);
      return;
    }
    _dragOrbit = false;
    _dragPan = false;
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _touchEnd(e.pointer);
      return;
    }
    _dragOrbit = false;
    _dragPan = false;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _camera?.zoom(e.scrollDelta.dy);
    }
  }

  /// Pinch zoom: [scale] > 1 zooms in (mirrors the old viewer's camera).
  void _zoomScale(double scale) {
    final camera = _camera;
    if (camera == null || scale <= 0) return;
    camera.distance = camera.distance / scale;
  }

  // Touch: 1 finger = orbit (after a slop), 2 fingers = pan + pinch zoom —
  // the same layering as the editor viewport.
  void _onTouchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.position;
    if (_touches.length == 2) {
      _singleTouchOrbiting = false;
      final pts = _touches.values.toList();
      _pinchLastDist = (pts[0] - pts[1]).distance;
      _pinchMidLast = (pts[0] + pts[1]) / 2;
      return;
    }
    if (_touches.length == 1) {
      _touchStart = e.position;
    }
  }

  void _onTouchMove(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.position;
    if (_touches.length == 2) {
      final pts = _touches.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final mid = (pts[0] + pts[1]) / 2;
      if (_pinchLastDist > 0 && dist > 0) {
        _zoomScale(dist / _pinchLastDist);
        _pinchLastDist = dist;
      }
      final midDelta = mid - _pinchMidLast;
      _pinchMidLast = mid;
      if (midDelta.dx != 0 || midDelta.dy != 0) {
        _camera?.pan(midDelta.dx, midDelta.dy, viewportHeight: _viewportHeight);
      }
      return;
    }
    if (_touches.length == 1) {
      if (_singleTouchOrbiting) {
        _camera?.orbit(e.delta.dx, e.delta.dy);
      } else if (_touchStart != null) {
        if ((e.position - _touchStart!).distance > kTouchSlop) {
          _singleTouchOrbiting = true;
        }
      }
    }
  }

  void _touchEnd(int pointer) {
    final hadTwo = _touches.length == 2;
    _touches.remove(pointer);
    if (_touches.isEmpty) {
      _singleTouchOrbiting = false;
      _touchStart = null;
      _pinchLastDist = 0;
    } else if (hadTwo && _touches.length == 1) {
      _pinchLastDist = 0;
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF20242C),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.name,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            Text(
              '${entry.kindLabel} • ${entry.sizeLabel} — 3d_models/',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
      body: _error != null
          ? _errorView()
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : _viewer(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'Не удалось открыть модель',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewer() {
    return Column(
      children: [
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Neutral studio backdrop behind the transparent viewport.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.2),
                      radius: 1.1,
                      colors: [Color(0xFF2E3542), Color(0xFF181B21)],
                    ),
                  ),
                ),
                SceneViewport(
                  controller: _controller,
                  input: CameraInput(),
                ),
              ],
            ),
          ),
        ),
        _transportBar(),
      ],
    );
  }

  /// Bottom control bar: animation chips, transport, loop, speed, scrubber.
  Widget _transportBar() {
    final player = _node?.player;
    final clips = player?.clips ?? const <GltfAnimInfo>[];
    final active = _active;
    final playing = player?.playing ?? false;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF262B34),
        border: Border(top: BorderSide(color: Color(0xFF3A4250))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: clips.isEmpty
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'В модели нет анимаций',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: clips.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final anim = clips[i];
                          return _AnimChip(
                            label: anim.shortName,
                            selected: anim.fullName == player?.current,
                            onTap: () => _activate(anim),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _CtrlIconButton(
                    tooltip: playing ? 'Пауза' : 'Играть',
                    icon: playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onPressed: active == null ? null : _togglePlay,
                  ),
                  _CtrlIconButton(
                    tooltip: 'Стоп (в начало)',
                    icon: Icons.stop_rounded,
                    onPressed: active == null ? null : _stopPlayback,
                  ),
                  _CtrlIconButton(
                    tooltip: _loop ? 'Повтор: вкл' : 'Повтор: выкл',
                    icon: _loop ? Icons.repeat : Icons.repeat_one,
                    onPressed: () => _toggleLoop(!_loop),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<double>(
                    tooltip: 'Скорость',
                    initialValue: _speed,
                    color: const Color(0xFF2E3542),
                    onSelected: _setSpeed,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 0.25,
                        child: Text(
                          '× 0.25',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 0.5,
                        child: Text(
                          '× 0.5',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 1,
                        child: Text(
                          '× 1',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 1.5,
                        child: Text(
                          '× 1.5',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      PopupMenuItem(
                        value: 2,
                        child: Text(
                          '× 2',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        '×${_speed == _speed.roundToDouble() ? _speed.round() : _speed}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: active == null
                        ? const SizedBox.shrink()
                        : _scrubber(active),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrubber(GltfAnimInfo active) {
    final time = _time.clamp(0.0, active.duration).toDouble();
    return Row(
      children: [
        Text(
          _fmtTime(time),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: active.duration <= 0
                  ? 0
                  : (time / active.duration).clamp(0.0, 1.0).toDouble(),
              onChangeStart: (_) => _scrubbing = true,
              onChanged: _seek,
              onChangeEnd: (_) => _scrubbing = false,
            ),
          ),
        ),
        Text(
          _fmtTime(active.duration),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  String _fmtTime(double t) {
    final m = t ~/ 60;
    final s = t - m * 60;
    return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
  }
}

/// A selectable chip in the animation strip.
class _AnimChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AnimChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Воспроизвести',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: selected ? const Color(0xFF2E5F8F) : const Color(0xFF2E333D),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4D8FD9)
                  : const Color(0xFF3A4250),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _CtrlIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _CtrlIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        icon: Icon(
          icon,
          color: onPressed == null ? Colors.white24 : Colors.white,
        ),
      ),
    );
  }
}
