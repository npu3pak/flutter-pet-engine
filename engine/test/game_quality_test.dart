import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';

void main() {
  group('GameQualitySettings.recommendedFor', () {
    test('desktop always runs full quality at native scale', () {
      for (final backend in GpuBackend.values) {
        final settings =
            GameQualitySettings.recommendedFor(backend, isDesktop: true);
        expect(settings.renderScale, 1.0);
        expect(settings.ssao, isTrue);
        expect(settings.shadows, isTrue);
        expect(settings.sustainedPerformance, isFalse);
      }
    });

    test('GLES mobile preset trades shadows and scale for framerate', () {
      final settings =
          GameQualitySettings.recommendedFor(GpuBackend.openglEs, isDesktop: false);
      expect(settings.renderScale, 0.33);
      expect(settings.ssao, isTrue);
      expect(settings.shadows, isFalse);
      expect(settings.sustainedPerformance, isTrue);
    });

    test('Vulkan and Metal mobile presets keep shadows and skip SPM', () {
      for (final backend in [GpuBackend.vulkan, GpuBackend.metal]) {
        final settings =
            GameQualitySettings.recommendedFor(backend, isDesktop: false);
        expect(settings.renderScale, 0.66);
        expect(settings.ssao, isTrue);
        expect(settings.shadows, isTrue);
        expect(settings.sustainedPerformance, isFalse);
      }
    });

    test('unknown mobile backend keeps the conservative default', () {
      final settings =
          GameQualitySettings.recommendedFor(GpuBackend.unknown, isDesktop: false);
      expect(settings.renderScale, 0.5);
      expect(settings.ssao, isTrue);
      expect(settings.shadows, isTrue);
      expect(settings.sustainedPerformance, isFalse);
    });
  });
}
