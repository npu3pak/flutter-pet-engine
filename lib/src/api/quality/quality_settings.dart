import 'dart:io';
import 'dart:ui' show FilterQuality;

import '../../engine/gpu_backend.dart';

/// Anti-aliasing mode of the scene.
enum SceneAntiAliasing { none, msaa, fxaa, auto }

/// Immutable picture-quality settings. The controller owns one instance and
/// applies it to the render scene; `QualityController` adapts it over time.
class QualitySettings {
  const QualitySettings({
    this.renderScale = 1.0,
    this.ssao = false,
    this.shadows = false,
    this.shadowCascades = 1,
    this.shadowDistance = 30,
    this.antiAliasing = SceneAntiAliasing.auto,
    this.filterQuality = FilterQuality.medium,
    this.maxPointLights = -1,
    this.sustainedPerformance = false,
  });

  /// The internal render resolution multiplier.
  final double renderScale;

  /// Whether screen-space ambient occlusion is on.
  final bool ssao;

  /// Whether directional shadows are on.
  final bool shadows;

  /// The number of shadow cascades.
  final int shadowCascades;

  /// The shadow distance.
  final double shadowDistance;

  /// The anti-aliasing mode.
  final SceneAntiAliasing antiAliasing;

  /// The render-target filtering quality.
  final FilterQuality filterQuality;

  /// The punctual-light budget: -1 means no limit, 0 disables point lights.
  final int maxPointLights;

  /// Platform hint for the application (Android sustained performance mode).
  final bool sustainedPerformance;

  QualitySettings copyWith({
    double? renderScale,
    bool? ssao,
    bool? shadows,
    int? shadowCascades,
    double? shadowDistance,
    SceneAntiAliasing? antiAliasing,
    FilterQuality? filterQuality,
    int? maxPointLights,
    bool? sustainedPerformance,
  }) => QualitySettings(
    renderScale: renderScale ?? this.renderScale,
    ssao: ssao ?? this.ssao,
    shadows: shadows ?? this.shadows,
    shadowCascades: shadowCascades ?? this.shadowCascades,
    shadowDistance: shadowDistance ?? this.shadowDistance,
    antiAliasing: antiAliasing ?? this.antiAliasing,
    filterQuality: filterQuality ?? this.filterQuality,
    maxPointLights: maxPointLights ?? this.maxPointLights,
    sustainedPerformance: sustainedPerformance ?? this.sustainedPerformance,
  );

  @override
  bool operator ==(Object other) =>
      other is QualitySettings &&
      other.renderScale == renderScale &&
      other.ssao == ssao &&
      other.shadows == shadows &&
      other.shadowCascades == shadowCascades &&
      other.shadowDistance == shadowDistance &&
      other.antiAliasing == antiAliasing &&
      other.filterQuality == filterQuality &&
      other.maxPointLights == maxPointLights &&
      other.sustainedPerformance == sustainedPerformance;

  @override
  int get hashCode => Object.hash(
    renderScale,
    ssao,
    shadows,
    shadowCascades,
    shadowDistance,
    antiAliasing,
    filterQuality,
    maxPointLights,
    sustainedPerformance,
  );
}

/// A ready-made quality level.
enum QualityPreset {
  low,
  medium,
  high,
  auto;

  /// The settings of the preset; [auto] needs the device facts and is
  /// resolved by [recommendedFor].
  QualitySettings get settings => switch (this) {
    QualityPreset.low => const QualitySettings(
      renderScale: 0.75,
      antiAliasing: SceneAntiAliasing.none,
      filterQuality: FilterQuality.low,
      maxPointLights: 0,
    ),
    QualityPreset.medium => const QualitySettings(
      renderScale: 1.0,
      antiAliasing: SceneAntiAliasing.fxaa,
      shadows: true,
      shadowCascades: 1,
      maxPointLights: 4,
    ),
    QualityPreset.high => const QualitySettings(
      renderScale: 1.0,
      antiAliasing: SceneAntiAliasing.msaa,
      ssao: true,
      shadows: true,
      shadowCascades: 3,
      shadowDistance: 45,
      maxPointLights: -1,
      filterQuality: FilterQuality.high,
    ),
    QualityPreset.auto => const QualitySettings(),
  };

  /// The preset recommended for a backend and device.
  static QualitySettings recommendedFor(
    GpuBackend backend,
    DeviceCapabilities capabilities,
  ) {
    if (backend == GpuBackend.openglEs) return QualityPreset.low.settings;
    if (capabilities.cores <= 4) return QualityPreset.medium.settings;
    return QualityPreset.high.settings;
  }
}

/// Device facts for the preset choice.
class DeviceCapabilities {
  const DeviceCapabilities({
    this.cores = 0,
    this.memoryMb = 0,
    this.platform = 'unknown',
  });

  /// Logical processor cores.
  final int cores;

  /// Approximate memory in megabytes (0 when unknown).
  final int memoryMb;

  /// `Platform.operatingSystem`.
  final String platform;

  /// Detects the facts of the current process.
  static DeviceCapabilities detect() {
    try {
      return DeviceCapabilities(
        cores: Platform.numberOfProcessors,
        platform: Platform.operatingSystem,
      );
    } catch (_) {
      return const DeviceCapabilities();
    }
  }
}

/// One rung of the adaptation ladder.
enum QualityStep {
  renderScale,
  antiAliasing,
  maxPointLights,
  ssao,
  shadows;

  /// The default ladder: resolution first, lighting last.
  static const List<QualityStep> fullLadder = [
    QualityStep.renderScale,
    QualityStep.antiAliasing,
    QualityStep.maxPointLights,
    QualityStep.ssao,
    QualityStep.shadows,
  ];
}

/// Thresholds and timing of the adaptation policy.
class QualityPolicy {
  const QualityPolicy({
    this.window = const Duration(seconds: 2),
    this.cooldown = const Duration(seconds: 3),
    this.downscaleFpsFactor = 0.9,
    this.upscaleFpsFactor = 1.15,
    this.upscaleHold = const Duration(seconds: 3),
    this.steps = QualityStep.fullLadder,
  });

  /// The measurement window.
  final Duration window;

  /// The minimum pause between two quality changes.
  final Duration cooldown;

  /// Drop quality when the average fps is below `targetFps × this`.
  final double downscaleFpsFactor;

  /// Raise quality when the average fps is above `targetFps × this`.
  final double upscaleFpsFactor;

  /// How long the good fps must hold before raising quality.
  final Duration upscaleHold;

  /// The enabled ladder rungs and their order.
  final List<QualityStep> steps;
}

/// A snapshot of the measured frame statistics.
class FrameStats {
  const FrameStats({
    required this.fps,
    required this.averageFrameTime,
    required this.p95FrameTime,
    required this.averageRasterTime,
    required this.jankFrames,
  });

  /// The average frames per second over the sample.
  final double fps;

  /// The average frame time.
  final Duration averageFrameTime;

  /// The 95th-percentile frame time.
  final Duration p95FrameTime;

  /// The average raster time, when the frames carried one.
  final Duration? averageRasterTime;

  /// Frames slower than twice the target frame time.
  final int jankFrames;
}

/// One applied quality change.
class QualityChange {
  const QualityChange({
    required this.from,
    required this.to,
    required this.reason,
  });

  final QualitySettings from;
  final QualitySettings to;
  final String reason;
}
