import 'dart:ui' show FilterQuality;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('antiAliasingModeOf', () {
    test('maps every game mode to the fork mode', () {
      expect(antiAliasingModeOf(GameAntiAliasing.none), AntiAliasingMode.none);
      expect(antiAliasingModeOf(GameAntiAliasing.fxaa), AntiAliasingMode.fxaa);
      expect(antiAliasingModeOf(GameAntiAliasing.msaa), AntiAliasingMode.msaa);
      expect(antiAliasingModeOf(GameAntiAliasing.auto), AntiAliasingMode.auto);
    });
  });

  group('GameFog', () {
    test('applies linear fog and clears the sky/sun extras', () {
      final fog = Fog()
        ..skyColorInfluence = 0.5
        ..cutoffDistance = 10
        ..heightFalloff = 2
        ..sunInScatter = 1;

      final settings = GameFog(
        color: vm.Vector3(0.1, 0.4, 0.15),
        start: 1,
        end: 8,
        minOpacity: 0.005,
        maxOpacity: 0.05,
      );
      settings.applyTo(fog);

      expect(fog.enabled, isTrue);
      expect(fog.mode, FogMode.linear);
      expect(fog.color, vm.Vector3(0.1, 0.4, 0.15));
      expect(fog.start, 1);
      expect(fog.end, 8);
      expect(fog.minOpacity, 0.005);
      expect(fog.maxOpacity, 0.05);
      expect(fog.skyColorInfluence, 0);
      expect(fog.cutoffDistance, 0);
      expect(fog.heightFalloff, 0);
      expect(fog.sunInScatter, 0);
    });
  });

  group('GamePictureSettings', () {
    test('has sensible defaults', () {
      const settings = GamePictureSettings();
      expect(settings.fog, isNull);
      expect(settings.antiAliasing, GameAntiAliasing.auto);
      expect(settings.renderScale, 1.0);
      expect(settings.filterQuality, FilterQuality.none);
      expect(settings.environmentIntensity, 1.0);
    });

    test('carries every knob', () {
      final settings = GamePictureSettings(
        fog: GameFog(color: vm.Vector3(1, 1, 1), start: 2, end: 12),
        antiAliasing: GameAntiAliasing.fxaa,
        renderScale: 0.5,
        filterQuality: FilterQuality.low,
        environmentIntensity: 0.4,
      );
      expect(settings.fog!.start, 2);
      expect(settings.antiAliasing, GameAntiAliasing.fxaa);
      expect(settings.renderScale, 0.5);
      expect(settings.filterQuality, FilterQuality.low);
      expect(settings.environmentIntensity, 0.4);
    });
  });
}
