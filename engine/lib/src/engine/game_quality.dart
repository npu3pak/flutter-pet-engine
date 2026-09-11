import 'gpu_backend.dart';

/// Recommended render settings for one backend/platform combination.
///
/// The mobile values were tuned on a low-end Android device (Exynos 9611 /
/// Mali-G72): OpenGL ES trades shadows and render resolution for framerate,
/// while Vulkan and Metal keep the full scene at a moderate scale. Desktop
/// always runs full quality at native scale.
class GameQualitySettings {
  const GameQualitySettings({
    required this.renderScale,
    required this.ssao,
    required this.shadows,
    required this.sustainedPerformance,
  });

  /// `Scene.renderScale` — the internal render resolution multiplier.
  final double renderScale;

  /// Whether screen-space ambient occlusion is on.
  final bool ssao;

  /// Whether directional shadows are on.
  final bool shadows;

  /// Android-only hint: request sustained performance mode
  /// (`Window.setSustainedPerformanceMode`). The engine has no platform
  /// channel, so the app applies it; false means "do not enable".
  final bool sustainedPerformance;

  /// The recommended settings for [backend] on desktop ([isDesktop]) or
  /// mobile.
  static GameQualitySettings recommendedFor(
    GpuBackend backend, {
    required bool isDesktop,
  }) {
    if (isDesktop) {
      return const GameQualitySettings(
        renderScale: 1.0,
        ssao: true,
        shadows: true,
        sustainedPerformance: false,
      );
    }
    switch (backend) {
      case GpuBackend.openglEs:
        return const GameQualitySettings(
          renderScale: 0.33,
          ssao: true,
          shadows: false,
          sustainedPerformance: true,
        );
      case GpuBackend.vulkan:
      case GpuBackend.metal:
        return const GameQualitySettings(
          renderScale: 0.66,
          ssao: true,
          shadows: true,
          sustainedPerformance: false,
        );
      case GpuBackend.unknown:
        return const GameQualitySettings(
          renderScale: 0.5,
          ssao: true,
          shadows: true,
          sustainedPerformance: false,
        );
    }
  }
}
