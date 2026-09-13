import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// What a [ParticleConfig] layer depicts. One layer is one instanced billboard
/// batch with its own sprite atlas, facing mode and blend behavior.
enum ParticleKind {
  /// Falling rain — hard-edged streaks, velocity-stretched billboards.
  rain,

  /// Snowfall — slowly falling flakes that sway and spin around their cell
  /// anchor.
  snow,

  /// Wind draught — soft translucent streaks and glitter motes drifting along
  /// the wind direction.
  wind,
}

/// One sprite of a particle layer's flipbook atlas: [weight] picks it per
/// particle; [assetPath] is the Flutter asset key the engine composes into the
/// atlas (null = not resolvable by the engine, the layer stays hidden).
class ParticleDef {
  const ParticleDef({
    required this.spriteKey,
    required this.weight,
    required this.width,
    required this.height,
    this.assetPath,
  });

  final String spriteKey;
  final double weight;
  final double width;
  final double height;
  final String? assetPath;
}

/// Engine-side parameters of one world-space particle layer (rain, snow, wind
/// draught): instanced billboards anchored to the world grid — each particle
/// belongs to its cell and animates by a closed-form function of a per-frame
/// `time`, so particles never follow the camera. [ParticleLayer] renders it;
/// this class only says *what* to draw, *how many*, and how they move.
///
/// The defaults mirror the game's weather configs; [ParticlePresets] ships the
/// concrete rain/snow/wind layers, and a game may pass its own.
class ParticleConfig {
  ParticleConfig({
    required this.kind,
    required this.sprites,
    this.maxPerCell = 8,
    this.fullDensityRings = 2,
    this.viewRadius = 12,
    this.spawnChance = 1.0,
    this.bottomY = -0.8,
    this.topY = 6.5,
    this.fallSpeedMin = 0,
    this.fallSpeedMax = 0,
    this.swayAmp = 0,
    this.swayFreq = 0,
    this.windSpeed = 0,
    this.slantDrift = 0,
    this.opacity = 1.0,
    this.rotationSpin = 0,
    this.velocityStretch = 0,
    this.crisp = true,
    this.additive = false,
    this.blendOrder = 0,
    vm.Vector3? windDirection,
    vm.Vector3? color,
  })  : windDirection = windDirection ?? vm.Vector3.zero(),
        color = color ?? vm.Vector3(1, 1, 1);

  final ParticleKind kind;

  /// Sprites of the layer's flipbook atlas ([ParticleDef.weight] picks one per
  /// particle).
  final List<ParticleDef> sprites;

  /// Particle count in the focus cell; every Chebyshev ring beyond
  /// [fullDensityRings] drops one particle down to zero at
  /// [fullDensityRings] + [maxPerCell] rings ([viewRadius] caps the domain).
  final int maxPerCell;
  final int fullDensityRings;

  /// Chebyshev rings from the focus cell within which the layer draws at all.
  final int viewRadius;

  /// Chance (0..1) that a cell contributes any particle at all — sparse
  /// fields (wind wisps) skip whole cells deterministically.
  final double spawnChance;

  /// Vertical world band the particles live in. Falling layers cycle through
  /// the band — the hidden wrap happens just below [bottomY] (under the floor)
  /// and just above [topY]; drifting wind hovers within it.
  final double bottomY;
  final double topY;

  /// Vertical speed of a falling particle (m/s), and the per-particle spread.
  /// 0 = hovering layer (wind).
  final double fallSpeedMin;
  final double fallSpeedMax;

  /// Sway around the cell anchor: amplitude (world units) and frequency
  /// (rad/s) of a two-axis wobble.
  final double swayAmp;
  final double swayFreq;

  /// Horizontal world drift direction (only x/z are used; normalized) and
  /// drift speed in m/s. Rain drops drift along it while falling (and their
  /// streaks slant with the full velocity); snow falls slanting along it (see
  /// [slantDrift]); wind wisps/glints ride the draught as a repeating dash.
  final vm.Vector3 windDirection;
  final double windSpeed;

  /// Falling-layer (snow) slant: horizontal world units a flake drifts along
  /// the normalized wind over ONE full fall cycle. The offset is a closed form
  /// of the fall phase, so the field stays bounded and the reset coincides
  /// with the hidden under-floor wrap.
  final double slantDrift;

  /// Per-instance tint (multiplies the sprite) and opacity.
  final vm.Vector3 color;
  final double opacity;

  /// In-plane spin speed for snow flakes (rad/s); 0 = no spin.
  final double rotationSpin;

  /// Rain streaks only: world units of extra billboard length per m/s of fall
  /// speed (`BillboardFacing.velocityStretched`).
  final double velocityStretch;

  /// Hard-edged pixel look: the batch renders opaque with an alpha test
  /// (writes depth — exact z against walls/sprites). False = translucent soft
  /// batch (wind wisps/glints).
  final bool crisp;

  /// Soft wind glints: additive blending instead of alpha.
  final bool additive;

  /// Translucent-pass layering vs other decor: negative keeps a draught
  /// behind, positive over it, 0 = pure depth sort.
  final double blendOrder;

  static const int maxPerCellCap = 32;
  static const int fullDensityRingsCap = 10;
  static const int viewRadiusCap = 20;
  static const int intensityCap = 4;

  /// The tallest sprite of the layer (hidden loop margin reference).
  double get maxSpriteHeight =>
      sprites.fold<double>(0, (s, d) => math.max(s, d.height));

  /// Intensity multiplier copy: scales the per-cell density ([maxPerCell],
  /// clamped to [maxPerCellCap]); opacity is unscaled. [m] is clamped to
  /// 0..[intensityCap].
  ParticleConfig withIntensity(double m) => ParticleConfig(
        kind: kind,
        sprites: sprites,
        maxPerCell: (maxPerCell * m.clamp(0.0, intensityCap.toDouble()))
            .round()
            .clamp(0, maxPerCellCap),
        fullDensityRings: fullDensityRings,
        viewRadius: viewRadius,
        spawnChance: spawnChance,
        bottomY: bottomY,
        topY: topY,
        fallSpeedMin: fallSpeedMin,
        fallSpeedMax: fallSpeedMax,
        swayAmp: swayAmp,
        swayFreq: swayFreq,
        windDirection: windDirection,
        windSpeed: windSpeed,
        slantDrift: slantDrift,
        color: color,
        opacity: opacity,
        rotationSpin: rotationSpin,
        velocityStretch: velocityStretch,
        crisp: crisp,
        additive: additive,
        blendOrder: blendOrder,
      );
}
