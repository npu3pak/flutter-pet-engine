import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('ParticlePresets', () {
    test('every preset is a well-formed layer', () {
      final presets = [
        ParticlePresets.streetRain,
        ParticlePresets.passSnow,
        ParticlePresets.passWind,
        ParticlePresets.caveWindStreak,
        ParticlePresets.caveWindGlint,
      ];
      for (final config in presets) {
        expect(config.sprites, isNotEmpty);
        expect(config.maxPerCell, greaterThan(0));
        expect(config.viewRadius, greaterThan(0));
        expect(config.topY, greaterThan(config.bottomY));
        expect(config.color, isNotNull);
        for (final def in config.sprites) {
          expect(def.weight, greaterThan(0));
          expect(def.width, greaterThan(0));
          expect(def.height, greaterThan(0));
          expect(
            def.assetPath,
            startsWith('packages/pet_engine/assets/particles/'),
          );
        }
      }
    });

    test('presets cover the game layer kinds', () {
      expect(ParticlePresets.streetRain.kind, ParticleKind.rain);
      expect(ParticlePresets.streetRain.crisp, isTrue);
      expect(ParticlePresets.passSnow.kind, ParticleKind.snow);
      expect(ParticlePresets.passSnow.sprites.length, 2);
      expect(ParticlePresets.passSnow.slantDrift, greaterThan(0));
      expect(ParticlePresets.passWind.kind, ParticleKind.wind);
      expect(ParticlePresets.passWind.crisp, isFalse);
      expect(ParticlePresets.passWind.blendOrder, -1);
      expect(ParticlePresets.caveWindStreak.kind, ParticleKind.wind);
      expect(ParticlePresets.caveWindGlint.additive, isTrue);
    });

    test('rain streaks stretch with velocity and fall fast', () {
      expect(ParticlePresets.streetRain.velocityStretch, greaterThan(0));
      expect(ParticlePresets.streetRain.fallSpeedMin, greaterThan(0));
    });

    test('cave draughts carry a default direction and move', () {
      expect(
        ParticlePresets.caveWindStreak.windDirection,
        vm.Vector3(0.0, 0.0, -1.0),
      );
      expect(
        ParticlePresets.caveWindGlint.windDirection,
        ParticlePresets.caveWindStreak.windDirection,
      );
    });
  });

  group('ParticleConfig.withIntensity', () {
    test('scales density and clamps to the caps', () {
      final base = ParticlePresets.streetRain;
      expect(base.withIntensity(0).maxPerCell, 0);
      expect(
        base.withIntensity(0.5).maxPerCell,
        (base.maxPerCell * 0.5).round(),
      );
      expect(base.withIntensity(100).maxPerCell, ParticleConfig.maxPerCellCap);
    });

    test('keeps the other fields untouched', () {
      final base = ParticlePresets.passSnow;
      final scaled = base.withIntensity(2);
      expect(scaled.kind, base.kind);
      expect(scaled.opacity, base.opacity);
      expect(scaled.bottomY, base.bottomY);
      expect(scaled.topY, base.topY);
      expect(scaled.windDirection, base.windDirection);
      expect(scaled.sprites, same(base.sprites));
    });

    test('maxSpriteHeight is the tallest sprite', () {
      expect(ParticlePresets.passSnow.maxSpriteHeight, closeTo(0.10, 1e-12));
    });
  });

  group('ParticleDef', () {
    test('keeps engine asset paths optional for game-supplied sprites', () {
      const def = ParticleDef(
        spriteKey: 'custom',
        weight: 1,
        width: 1,
        height: 1,
      );
      expect(def.assetPath, isNull);
    });

    test('direction vectors default to zero', () {
      final config = ParticleConfig(
        kind: ParticleKind.wind,
        sprites: const [
          ParticleDef(spriteKey: 'w', weight: 1, width: 1, height: 1),
        ],
      );
      expect(config.windDirection, vm.Vector3.zero());
      expect(config.color, vm.Vector3(1, 1, 1));
    });
  });
}
