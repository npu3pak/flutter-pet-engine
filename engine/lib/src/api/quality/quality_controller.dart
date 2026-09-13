// Private fields behind public getters cannot use initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:ui' show FilterQuality;

import 'package:flutter/foundation.dart';

import '../../engine/gpu_backend.dart';
import '../scene_controller.dart';
import 'quality_settings.dart';

/// The performance controller: measures frame times, decides the quality
/// level and applies it to the attached scene.
///
/// The policy is a hysteresis ladder (`QualityPolicy.steps`): quality drops
/// after a slow measurement window and rises only after a sustained fast
/// window. Frame times can be injected directly ([reportFrame]) so the
/// policy is testable without a GPU.
class QualityController extends ChangeNotifier {
  QualityController({
    QualitySettings? floor,
    QualitySettings? ceiling,
    this.targetFps = 60,
    bool adaptive = true,
    this.policy = const QualityPolicy(),
  }) : _floor = floor,
       _ceiling = ceiling,
       _adaptive = adaptive,
       _settings = ceiling ?? const QualitySettings();

  /// The lowest allowed settings.
  final QualitySettings? _floor;

  /// The highest allowed settings.
  final QualitySettings? _ceiling;

  /// The target frame rate.
  final double targetFps;

  /// The adaptation policy.
  final QualityPolicy policy;

  bool _adaptive;
  QualitySettings _settings;
  SceneController? _scene;
  GpuBackend _backend = GpuBackend.unknown;
  DeviceCapabilities _capabilities = const DeviceCapabilities();
  bool _initialized = false;

  final StreamController<QualityChange> _changes =
      StreamController<QualityChange>.broadcast();

  final List<Duration> _frames = [];
  final List<Duration> _rasterTimes = [];
  Duration _clock = Duration.zero;
  Duration _windowStart = Duration.zero;
  Duration _lastChange = Duration.zero;
  Duration? _goodSince;
  final Set<Object> _pauseReasons = {};

  /// The detected graphics backend.
  GpuBackend get backend => _backend;

  /// The detected device capabilities.
  DeviceCapabilities get capabilities => _capabilities;

  /// The current settings.
  QualitySettings get settings => _settings;

  /// Whether automatic adaptation is enabled.
  bool get adaptive => _adaptive;
  set adaptive(bool value) {
    if (_adaptive == value) return;
    _adaptive = value;
    _goodSince = null;
    notifyListeners();
  }

  /// The measured frame statistics.
  FrameStats get stats => _stats();

  /// The applied quality changes.
  Stream<QualityChange> get changes => _changes.stream;

  /// Detects the backend and device capabilities (call once at startup).
  Future<void> initialize() async {
    _backend = detectGpuBackend();
    _capabilities = DeviceCapabilities.detect();
    _initialized = true;
    if (_adaptive && _settings == const QualitySettings()) {
      _apply(
        QualityPreset.recommendedFor(_backend, _capabilities),
        'стартовый пресет',
      );
    }
    notifyListeners();
  }

  /// Applies [settings] manually and pauses adaptation.
  void apply(QualitySettings settings) {
    pauseAdaptation('manual');
    _apply(settings, 'ручная установка');
  }

  /// Applies a preset ([QualityPreset.auto] resolves from the device).
  void applyPreset(QualityPreset preset) {
    final resolved = preset == QualityPreset.auto
        ? QualityPreset.recommendedFor(_backend, _capabilities)
        : preset.settings;
    apply(resolved);
  }

  /// Attaches the scene and pushes the current settings into it.
  void attach(SceneController scene) {
    _scene = scene;
    scene.quality = this;
    scene.applySettings(_settings);
  }

  /// Reports one frame; drives the adaptation policy.
  void reportFrame(Duration frameTime, {Duration? rasterTime}) {
    _frames.add(frameTime);
    if (rasterTime != null) _rasterTimes.add(rasterTime);
    _clock += frameTime;
    if (_frames.length > 600) {
      _frames.removeRange(0, _frames.length - 600);
    }
    if (_rasterTimes.length > 600) {
      _rasterTimes.removeRange(0, _rasterTimes.length - 600);
    }
    _adapt();
  }

  /// Pauses adaptation (loading, screenshots, measurements).
  void pauseAdaptation(Object reason) {
    _pauseReasons.add(reason);
  }

  /// Resumes adaptation after [pauseAdaptation].
  void resumeAdaptation(Object reason) {
    _pauseReasons.remove(reason);
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }

  // ── adaptation ───────────────────────────────────────────────────────

  void _adapt() {
    if (!_adaptive || _pauseReasons.isNotEmpty || !_initialized) return;
    final window = policy.window;
    if (_clock - _windowStart < window) return;
    final windowFrames = _framesSince(_windowStart);
    _windowStart = _clock;
    if (windowFrames.isEmpty) return;

    var elapsed = Duration.zero;
    for (final frame in windowFrames) {
      elapsed += frame;
    }
    final fps =
        windowFrames.length /
        (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
    if (fps < targetFps * policy.downscaleFpsFactor) {
      _goodSince = null;
      _stepDown(fps);
      return;
    }
    if (fps > targetFps * policy.upscaleFpsFactor) {
      _goodSince ??= _clock;
      if (_clock - _goodSince! >= policy.upscaleHold) {
        _goodSince = null;
        _stepUp(fps);
      }
      return;
    }
    _goodSince = null;
  }

  List<Duration> _framesSince(Duration mark) {
    // Frame times are the only clock; the window boundary falls inside the
    // list only approximately, which is enough for a 2-second policy.
    var total = Duration.zero;
    final out = <Duration>[];
    for (final frame in _frames.reversed) {
      total += frame;
      if (_clock - total < mark) break;
      out.add(frame);
    }
    return out;
  }

  void _stepDown(double fps) {
    if (_clock - _lastChange < policy.cooldown) return;
    final next = _lower(_settings);
    if (next == null) return;
    _apply(
      next,
      'fps ${fps.toStringAsFixed(1)} < '
      '${(targetFps * policy.downscaleFpsFactor).toStringAsFixed(1)}',
    );
  }

  void _stepUp(double fps) {
    if (_clock - _lastChange < policy.cooldown) return;
    final next = _raise(_settings);
    if (next == null) return;
    _apply(
      next,
      'fps ${fps.toStringAsFixed(1)} > '
      '${(targetFps * policy.upscaleFpsFactor).toStringAsFixed(1)}',
    );
  }

  QualitySettings? _lower(QualitySettings settings) {
    for (final step in policy.steps) {
      final lowered = switch (step) {
        QualityStep.renderScale when settings.renderScale > 0.5 =>
          settings.copyWith(
            renderScale: (settings.renderScale - 0.15).clamp(0.5, 1.0),
          ),
        QualityStep.antiAliasing
            when settings.antiAliasing != SceneAntiAliasing.none =>
          settings.copyWith(antiAliasing: SceneAntiAliasing.none),
        QualityStep.maxPointLights when settings.maxPointLights != 0 =>
          settings.copyWith(
            maxPointLights: settings.maxPointLights < 0
                ? 8
                : (settings.maxPointLights ~/ 2).clamp(0, 8),
          ),
        QualityStep.ssao when settings.ssao => settings.copyWith(ssao: false),
        QualityStep.shadows when settings.shadows => settings.copyWith(
          shadows: false,
        ),
        _ => null,
      };
      if (lowered != null) return _clamp(lowered);
    }
    return null;
  }

  QualitySettings? _raise(QualitySettings settings) {
    for (final step in policy.steps.reversed) {
      final raised = switch (step) {
        QualityStep.shadows when !settings.shadows => settings.copyWith(
          shadows: true,
        ),
        QualityStep.ssao when !settings.ssao => settings.copyWith(ssao: true),
        QualityStep.maxPointLights when settings.maxPointLights != -1 =>
          settings.copyWith(
            maxPointLights: settings.maxPointLights <= 0
                ? 4
                : (settings.maxPointLights * 2).clamp(0, 64),
          ),
        QualityStep.antiAliasing
            when settings.antiAliasing == SceneAntiAliasing.none =>
          settings.copyWith(antiAliasing: SceneAntiAliasing.auto),
        QualityStep.renderScale when settings.renderScale < 1.0 =>
          settings.copyWith(
            renderScale: (settings.renderScale + 0.15).clamp(0.5, 1.0),
          ),
        _ => null,
      };
      if (raised != null) return _clamp(raised);
    }
    return null;
  }

  QualitySettings _clamp(QualitySettings settings) {
    final floor = _floor;
    final ceiling = _ceiling;
    var out = settings;
    if (floor != null) {
      out = out.copyWith(
        renderScale: out.renderScale < floor.renderScale
            ? floor.renderScale
            : null,
        maxPointLights: out.maxPointLights < floor.maxPointLights
            ? floor.maxPointLights
            : null,
        antiAliasing: _lowerAa(out.antiAliasing, floor.antiAliasing),
      );
    }
    if (ceiling != null) {
      out = out.copyWith(
        renderScale: out.renderScale > ceiling.renderScale
            ? ceiling.renderScale
            : null,
        maxPointLights: out.maxPointLights < 0 || ceiling.maxPointLights < 0
            ? null
            : (out.maxPointLights > ceiling.maxPointLights
                  ? ceiling.maxPointLights
                  : null),
        ssao: out.ssao && !ceiling.ssao ? false : null,
        shadows: out.shadows && !ceiling.shadows ? false : null,
      );
    }
    return out;
  }

  SceneAntiAliasing _lowerAa(SceneAntiAliasing value, SceneAntiAliasing floor) {
    if (value == SceneAntiAliasing.none || floor == SceneAntiAliasing.none) {
      return value;
    }
    if (floor == SceneAntiAliasing.fxaa && value == SceneAntiAliasing.msaa) {
      return SceneAntiAliasing.fxaa;
    }
    return value;
  }

  void _apply(QualitySettings settings, String reason) {
    if (settings == _settings) return;
    final from = _settings;
    _settings = settings;
    _lastChange = _clock;
    _scene?.applySettings(settings);
    if (!_changes.isClosed) {
      _changes.add(QualityChange(from: from, to: settings, reason: reason));
    }
    notifyListeners();
  }

  FrameStats _stats() {
    if (_frames.isEmpty) {
      return const FrameStats(
        fps: 0,
        averageFrameTime: Duration.zero,
        p95FrameTime: Duration.zero,
        averageRasterTime: null,
        jankFrames: 0,
      );
    }
    final sorted = List<Duration>.of(_frames)..sort((a, b) => a.compareTo(b));
    var total = Duration.zero;
    for (final frame in _frames) {
      total += frame;
    }
    final average = total ~/ _frames.length;
    final p95 =
        sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    Duration? raster;
    if (_rasterTimes.isNotEmpty) {
      var rasterTotal = Duration.zero;
      for (final time in _rasterTimes) {
        rasterTotal += time;
      }
      raster = rasterTotal ~/ _rasterTimes.length;
    }
    final target = Duration(
      microseconds: (Duration.microsecondsPerSecond / targetFps).round(),
    );
    final jank = _frames
        .where((frame) => frame.inMicroseconds > target.inMicroseconds * 2)
        .length;
    final fps = Duration.microsecondsPerSecond / average.inMicroseconds;
    return FrameStats(
      fps: fps,
      averageFrameTime: average,
      p95FrameTime: p95,
      averageRasterTime: raster,
      jankFrames: jank,
    );
  }
}

/// Kept for API compatibility with the fork's filter quality type.
typedef QualityFilterQuality = FilterQuality;
