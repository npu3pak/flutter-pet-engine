import 'package:vector_math/vector_math.dart' as vm;

import 'particle_config.dart';

/// Engine defaults for the world-weather layers: the game's rain (streets),
/// snow and ground wind (mountain pass) and the ice-cave draught. Sprites are
/// the engine package assets under `assets/particles/` (copied from the game).
///
/// A game may use these as-is, tweak copies (`withIntensity`), or pass its own
/// [ParticleConfig] with its own sprite assets.
class ParticlePresets {
  ParticlePresets._();

  /// The streets rain: dense hard-edged streaks over the whole grid, falling
  /// in a breeze (the game adds the wet-surface look separately).
  static final ParticleConfig streetRain = ParticleConfig(
    kind: ParticleKind.rain,
    sprites: const [
      ParticleDef(
        spriteKey: 'rain',
        weight: 1,
        width: 0.05,
        height: 0.4,
        assetPath: 'packages/pet_engine_v2/assets/particles/rain.png',
      ),
    ],
    maxPerCell: 10,
    fullDensityRings: 2,
    viewRadius: 11,
    bottomY: -0.9,
    topY: 6.5,
    fallSpeedMin: 5.7,
    fallSpeedMax: 7.0,
    velocityStretch: 0.07,
    color: vm.Vector3(0.80, 0.85, 1.0),
    opacity: 1.0,
  );

  /// The mountain-pass snowfall: slow pixel flakes that sway and spin high
  /// above the ground, falling slanted along [ParticleConfig.windDirection].
  static final ParticleConfig passSnow = ParticleConfig(
    kind: ParticleKind.snow,
    sprites: const [
      ParticleDef(
        spriteKey: 'snowflake_1',
        weight: 1,
        width: 0.10,
        height: 0.10,
        assetPath: 'packages/pet_engine_v2/assets/particles/snowflake_1.png',
      ),
      ParticleDef(
        spriteKey: 'snowflake_2',
        weight: 1,
        width: 0.08,
        height: 0.08,
        assetPath: 'packages/pet_engine_v2/assets/particles/snowflake_2.png',
      ),
    ],
    maxPerCell: 5,
    fullDensityRings: 2,
    viewRadius: 14,
    bottomY: -0.6,
    topY: 14,
    fallSpeedMin: 0.3,
    fallSpeedMax: 0.6,
    swayAmp: 0.5,
    swayFreq: 1.0,
    windDirection: vm.Vector3(0.0, 0.0, -1.0),
    slantDrift: 6.0,
    rotationSpin: 1.4,
    color: vm.Vector3(0.92, 0.96, 1.0),
    opacity: 1.0,
  );

  /// The mountain-pass wind: a ground-level snow drift — sparse soft white
  /// wisps blown along the same direction as the slanted snowfall.
  static final ParticleConfig passWind = ParticleConfig(
    kind: ParticleKind.wind,
    sprites: const [
      ParticleDef(
        spriteKey: 'wind_wisp',
        weight: 1,
        width: 3.6,
        height: 0.3,
        assetPath: 'packages/pet_engine_v2/assets/particles/wind_wisp.png',
      ),
    ],
    maxPerCell: 1,
    fullDensityRings: 12,
    viewRadius: 12,
    spawnChance: 0.10,
    bottomY: 0.02,
    topY: 0.22,
    swayAmp: 0.04,
    swayFreq: 1.4,
    windDirection: vm.Vector3(0.0, 0.0, -1.0),
    windSpeed: 1.0,
    color: vm.Vector3(0.97, 0.98, 1.0),
    opacity: 0.6,
    crisp: false,
    blendOrder: -1,
  );

  /// Ice-cave wind, layer one: soft translucent wisps that slowly draught
  /// through the halls. The direction is per-floor — the game passes the
  /// center→exit vector (see `ParticleLayer.windDirection`).
  static final ParticleConfig caveWindStreak = ParticleConfig(
    kind: ParticleKind.wind,
    sprites: const [
      ParticleDef(
        spriteKey: 'wind_wisp',
        weight: 1,
        width: 2.6,
        height: 0.6,
        assetPath: 'packages/pet_engine_v2/assets/particles/wind_wisp.png',
      ),
    ],
    maxPerCell: 1,
    fullDensityRings: 8,
    viewRadius: 8,
    spawnChance: 0.14,
    bottomY: 0.10,
    topY: 0.72,
    swayAmp: 0.10,
    swayFreq: 0.6,
    windSpeed: 0.6,
    color: vm.Vector3(0.78, 0.90, 1.0),
    opacity: 0.55,
    crisp: false,
    blendOrder: -1,
  );

  /// Ice-cave wind, layer two: additive glitter motes riding the same
  /// draught — the visible shimmer of cold air.
  static final ParticleConfig caveWindGlint = ParticleConfig(
    kind: ParticleKind.wind,
    sprites: const [
      ParticleDef(
        spriteKey: 'wind_glint',
        weight: 1,
        width: 0.08,
        height: 0.08,
        assetPath: 'packages/pet_engine_v2/assets/particles/wind_glint.png',
      ),
    ],
    maxPerCell: 1,
    fullDensityRings: 8,
    viewRadius: 8,
    spawnChance: 0.35,
    bottomY: 0.12,
    topY: 0.74,
    swayAmp: 0.05,
    swayFreq: 2.2,
    windSpeed: 1.07,
    color: vm.Vector3(0.70, 0.88, 1.0),
    opacity: 0.9,
    crisp: false,
    additive: true,
  );
}
