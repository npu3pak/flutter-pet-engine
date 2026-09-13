import 'dart:ui' show Color, FilterQuality;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  group('QualitySettings', () {
    test('copyWith and equality', () {
      const base = QualitySettings();
      final changed = base.copyWith(renderScale: 0.5, ssao: true);
      expect(changed.renderScale, 0.5);
      expect(changed.ssao, isTrue);
      expect(changed, isNot(base));
      expect(changed.copyWith(), changed);
    });

    test('presets are ordered low → high', () {
      expect(QualityPreset.low.settings.renderScale, lessThan(1));
      expect(QualityPreset.medium.settings.shadows, isTrue);
      expect(QualityPreset.high.settings.ssao, isTrue);
      expect(QualityPreset.high.settings.filterQuality, FilterQuality.high);
    });

    test('recommendedFor picks by backend and cores', () {
      expect(
        QualityPreset.recommendedFor(
          GpuBackend.openglEs,
          const DeviceCapabilities(cores: 8),
        ),
        QualityPreset.low.settings,
      );
      expect(
        QualityPreset.recommendedFor(
          GpuBackend.metal,
          const DeviceCapabilities(cores: 4),
        ),
        QualityPreset.medium.settings,
      );
      expect(
        QualityPreset.recommendedFor(
          GpuBackend.metal,
          const DeviceCapabilities(cores: 10),
        ),
        QualityPreset.high.settings,
      );
    });
  });

  group('QualityController adaptation', () {
    QualityController makeController() => QualityController(
      ceiling: QualityPreset.high.settings,
      policy: const QualityPolicy(
        window: Duration(seconds: 2),
        cooldown: Duration.zero,
        upscaleHold: Duration(seconds: 3),
      ),
    );

    void report(QualityController controller, int frames, Duration frame) {
      for (var i = 0; i < frames; i++) {
        controller.reportFrame(frame);
      }
    }

    test('initialize detects backend and capabilities', () async {
      final controller = makeController();
      await controller.initialize();
      expect(controller.backend, isNot(GpuBackend.unknown));
      expect(controller.capabilities.cores, greaterThan(0));
      controller.dispose();
    });

    test('drops quality after a slow window', () async {
      final controller = makeController();
      await controller.initialize();
      expect(controller.settings.renderScale, 1.0);

      report(controller, 50, const Duration(milliseconds: 40));
      expect(controller.settings.renderScale, lessThan(1.0));
      controller.dispose();
    });

    test('raises quality after a sustained fast window', () async {
      final controller = makeController();
      await controller.initialize();
      report(controller, 50, const Duration(milliseconds: 40));
      final dropped = controller.settings;
      expect(dropped.shadows, isTrue);

      report(controller, 700, const Duration(milliseconds: 10));
      expect(controller.settings, isNot(dropped));
      controller.dispose();
    });

    test('pauseAdaptation freezes the ladder', () async {
      final controller = makeController();
      await controller.initialize();
      controller.pauseAdaptation('test');
      report(controller, 200, const Duration(milliseconds: 40));
      expect(controller.settings.renderScale, 1.0);
      controller.resumeAdaptation('test');
      report(controller, 50, const Duration(milliseconds: 40));
      expect(controller.settings.renderScale, lessThan(1.0));
      controller.dispose();
    });

    test('manual apply pauses adaptation and notifies', () async {
      final controller = makeController();
      await controller.initialize();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.apply(QualityPreset.low.settings);
      expect(controller.settings, QualityPreset.low.settings);
      expect(notified, greaterThan(0));

      report(controller, 200, const Duration(milliseconds: 40));
      expect(controller.settings, QualityPreset.low.settings);
      controller.dispose();
    });

    test('applyPreset auto resolves from the device', () async {
      final controller = QualityController();
      await controller.initialize();
      controller.applyPreset(QualityPreset.auto);
      expect(controller.settings, isNot(const QualitySettings()));
      controller.dispose();
    });

    test('floor clamps the ladder', () async {
      final controller = QualityController(
        floor: const QualitySettings(renderScale: 0.8),
        ceiling: QualityPreset.high.settings,
        policy: const QualityPolicy(
          window: Duration(seconds: 1),
          cooldown: Duration.zero,
        ),
      );
      await controller.initialize();
      report(controller, 100, const Duration(milliseconds: 100));
      expect(controller.settings.renderScale, greaterThanOrEqualTo(0.8));
      controller.dispose();
    });

    test('attach pushes settings into the scene', () async {
      final controller = makeController();
      await controller.initialize();
      final scene = SceneController();
      controller.attach(scene);
      expect(scene.quality, same(controller));
      expect(scene.settings, controller.settings);
      scene.dispose();
      controller.dispose();
    });

    test('changes stream reports applied steps', () async {
      final controller = makeController();
      await controller.initialize();
      final changes = <QualityChange>[];
      controller.changes.listen(changes.add);
      report(controller, 50, const Duration(milliseconds: 40));
      await Future<void>.delayed(Duration.zero);
      expect(changes, isNotEmpty);
      expect(changes.first.reason, contains('fps'));
      controller.dispose();
    });

    test('stats summarise the reported frames', () async {
      final controller = makeController();
      await controller.initialize();
      report(controller, 10, const Duration(milliseconds: 16));
      final stats = controller.stats;
      expect(stats.fps, closeTo(62.5, 1));
      expect(stats.averageFrameTime, const Duration(milliseconds: 16));
      expect(stats.jankFrames, 0);

      controller.reportFrame(const Duration(milliseconds: 100));
      expect(controller.stats.jankFrames, 1);
      controller.dispose();
    });
  });

  group('SceneController settings', () {
    test('setShadows/setSsao/setRenderScale update the settings', () {
      final controller = SceneController();
      controller.setShadows(true);
      expect(controller.settings.shadows, isTrue);
      controller.setSsao(true);
      expect(controller.settings.ssao, isTrue);
      controller.setRenderScale(0.5);
      expect(controller.renderScale, 0.5);
      controller.setAntiAliasing(SceneAntiAliasing.fxaa);
      expect(controller.settings.antiAliasing, SceneAntiAliasing.fxaa);
      controller.setShadowCascades(3);
      expect(controller.shadowCascades, 3);
      controller.setShadowDistance(42);
      expect(controller.shadowDistance, 42);
      controller.dispose();
    });

    test('setEnvironmentIntensity and setFog are stored', () {
      final controller = SceneController();
      controller.setEnvironmentIntensity(2);
      expect(controller.environmentIntensity, 2);
      controller.setFog(const SceneFog(color: Color(0xFF808080), end: 50));
      expect(controller.fog, isNotNull);
      expect(controller.fog!.end, 50);
      controller.setFog(null);
      expect(controller.fog, isNull);
      controller.dispose();
    });
  });
}
