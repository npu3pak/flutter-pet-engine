import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Capability probes for the active Flutter GPU backend.
///
/// These read the live context created by [Scene.initializeStaticResources]
/// (or the first [Scene]), so query them after initialization.
class GpuCapabilities {
  GpuCapabilities._();

  /// Whether the backend can attach a non-zero mip level of a texture as a
  /// render target.
  ///
  /// True on Metal and Vulkan; currently false on the GLES backend, where
  /// rendering into non-zero mip levels is not implemented yet. On Android
  /// this makes the probe a reliable "Vulkan vs GLES" signal.
  static bool get supportsRenderToMipLevels =>
      gpu.gpuContext.doesSupportFramebufferRenderMipmap;
}
