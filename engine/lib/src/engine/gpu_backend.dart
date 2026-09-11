import 'dart:io';

import 'package:flutter_scene/scene.dart' show GpuCapabilities;

/// The graphics API the active Flutter GPU backend renders with.
enum GpuBackend {
  /// Apple platforms — Impeller Metal.
  metal('Metal'),

  /// Android with a working Vulkan driver — Impeller Vulkan.
  vulkan('Vulkan'),

  /// Impeller OpenGL ES: the Android fallback (and the engine's choice on
  /// known-bad Vulkan SOCs).
  openglEs('OpenGL ES'),

  /// Unrecognized platform/backend combination.
  unknown('Unknown');

  const GpuBackend(this.label);

  /// Human-readable name for UI.
  final String label;
}

/// Pure classification from platform facts (no GPU needed): Apple platforms
/// always run Metal; elsewhere the backend is Vulkan when it can render into
/// non-zero mip levels and OpenGL ES otherwise.
GpuBackend classifyGpuBackend({
  required bool isApple,
  required bool supportsRenderToMipLevels,
}) {
  if (isApple) return GpuBackend.metal;
  return supportsRenderToMipLevels ? GpuBackend.vulkan : GpuBackend.openglEs;
}

/// Detects the active backend of this process.
///
/// Call after `Scene.initializeStaticResources()` (or the first `Scene`):
/// the probe reads the live Flutter GPU context. On Android the mip-render
/// capability distinguishes Impeller Vulkan from Impeller OpenGL ES; Apple
/// platforms are Metal by definition.
GpuBackend detectGpuBackend() {
  if (Platform.isIOS || Platform.isMacOS) return GpuBackend.metal;
  return classifyGpuBackend(
    isApple: false,
    supportsRenderToMipLevels: GpuCapabilities.supportsRenderToMipLevels,
  );
}
