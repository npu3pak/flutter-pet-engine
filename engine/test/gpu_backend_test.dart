import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  group('classifyGpuBackend', () {
    test('Apple platforms are Metal regardless of mip render support', () {
      expect(
        classifyGpuBackend(isApple: true, supportsRenderToMipLevels: true),
        GpuBackend.metal,
      );
      expect(
        classifyGpuBackend(isApple: true, supportsRenderToMipLevels: false),
        GpuBackend.metal,
      );
    });

    test('non-Apple with mip render support is Vulkan', () {
      expect(
        classifyGpuBackend(isApple: false, supportsRenderToMipLevels: true),
        GpuBackend.vulkan,
      );
    });

    test('non-Apple without mip render support is OpenGL ES', () {
      expect(
        classifyGpuBackend(isApple: false, supportsRenderToMipLevels: false),
        GpuBackend.openglEs,
      );
    });

    test('labels are user-facing names', () {
      expect(GpuBackend.metal.label, 'Metal');
      expect(GpuBackend.vulkan.label, 'Vulkan');
      expect(GpuBackend.openglEs.label, 'OpenGL ES');
    });
  });
}
