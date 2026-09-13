import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

ParticleField _field({
  int rows = 7,
  int columns = 7,
  int seed = 3,
  vm.Vector3? origin,
  bool Function(int row, int col)? allowsCell,
}) =>
    ParticleField(
      rows: rows,
      columns: columns,
      seed: seed,
      origin: origin,
      allowsCell: allowsCell,
    );

ParticleConfig _rain({
  double speed = 1.0,
  int maxPerCell = 1,
  int fullDensityRings = 100,
  int viewRadius = 100,
  double swayAmp = 0,
  double windSpeed = 0,
  vm.Vector3? windDirection,
}) =>
    ParticleConfig(
      kind: ParticleKind.rain,
      sprites: const [
        ParticleDef(spriteKey: 'rain', weight: 1, width: 0.05, height: 0.4),
      ],
      maxPerCell: maxPerCell,
      fullDensityRings: fullDensityRings,
      viewRadius: viewRadius,
      bottomY: 0,
      topY: 10,
      fallSpeedMin: speed,
      fallSpeedMax: speed,
      swayAmp: swayAmp,
      windSpeed: windSpeed,
      windDirection: windDirection,
    );

ParticleConfig _wind({
  int maxPerCell = 1,
  int fullDensityRings = 0,
  int viewRadius = 0,
  double windSpeed = 1,
  vm.Vector3? windDirection,
}) =>
    ParticleConfig(
      kind: ParticleKind.wind,
      sprites: const [
        ParticleDef(spriteKey: 'wisp', weight: 1, width: 1, height: 0.2),
      ],
      maxPerCell: maxPerCell,
      fullDensityRings: fullDensityRings,
      viewRadius: viewRadius,
      bottomY: 0,
      topY: 1,
      windSpeed: windSpeed,
      windDirection: windDirection ?? vm.Vector3(1, 0, 0),
    );

List<double> _flat(List<ParticleInstance> particles) => [
      for (final p in particles) ...[
        p.x, p.y, p.z, p.width, p.height, p.rotation, p.opacity,
        p.vx, p.vy, p.vz,
      ],
    ];

void main() {
  group('ParticleField', () {
    test('cell centers follow the mirrored-X cell convention plus origin', () {
      final field = _field(origin: vm.Vector3(10, 0.5, 20));
      expect(field.cellCenter(0, 0), vm.Vector3(10, 0.5, 20));
      expect(field.cellCenter(0, 2), vm.Vector3(8, 0.5, 20));
      expect(field.cellCenter(3, 0), vm.Vector3(10, 0.5, 23));
    });
  });

  group('placeParticles', () {
    test('is deterministic for the same inputs', () {
      final field = _field();
      final config = _rain(maxPerCell: 3, fullDensityRings: 2);
      final a = placeParticles(field, config,
          focusRow: 3, focusColumn: 3, time: 1.25);
      final b = placeParticles(field, config,
          focusRow: 3, focusColumn: 3, time: 1.25);
      expect(_flat(a), _flat(b));
    });

    test('is world-anchored: focus does not move particles', () {
      final field = _field();
      final config = _rain(maxPerCell: 2, fullDensityRings: 100);
      final a = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.5);
      final b = placeParticles(field, config,
          focusRow: 6, focusColumn: 6, time: 0.5);
      expect(_flat(a), _flat(b));
    });

    test('rain falls monotonically and wraps inside the band', () {
      final field = _field(rows: 1, columns: 1);
      final config = _rain(speed: 2.0, maxPerCell: 1);
      final a = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.0);
      final b = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.1);
      expect(b.single.y, closeTo(a.single.y - 0.2, 1e-9));

      for (var t = 0.0; t < 10.0; t += 0.13) {
        final p = placeParticles(field, config,
            focusRow: 0, focusColumn: 0, time: t).single;
        expect(p.y, lessThanOrEqualTo(config.topY + 0.5));
        expect(p.y, greaterThanOrEqualTo(config.bottomY - 1.0));
        expect(p.vy, -2.0);
      }
    });

    test('rain velocity carries the wind slant', () {
      final field = _field(rows: 1, columns: 1);
      final config = _rain(
        maxPerCell: 1,
        windSpeed: 3,
        windDirection: vm.Vector3(0, 0, -2),
      );
      final p = placeParticles(field, config,
              focusRow: 0, focusColumn: 0, time: 0.3)
          .single;
      expect(p.vx, 0);
      expect(p.vz, -3);
    });

    test('rain drifts downwind over the fall phase, never upwind', () {
      final field = _field(rows: 1, columns: 1);
      final still = _rain(speed: 2.0, maxPerCell: 1);
      final drifting = _rain(
        speed: 2.0,
        maxPerCell: 1,
        windSpeed: 4,
        windDirection: vm.Vector3(1, 0, 0),
      );

      var maxDelta = 0.0;
      for (var t = 0.0; t < 5.0; t += 0.1) {
        final moving = placeParticles(field, drifting,
            focusRow: 0, focusColumn: 0, time: t).single;
        final base = placeParticles(field, still,
            focusRow: 0, focusColumn: 0, time: t).single;
        final delta = moving.x - base.x;
        expect(delta, greaterThanOrEqualTo(-1e-9));
        if (delta > maxDelta) maxDelta = delta;
      }
      expect(maxDelta, greaterThan(0.0));
    });

    test('snow drifts along the wind over the fall phase', () {
      final field = _field(rows: 1, columns: 1);
      final config = ParticleConfig(
        kind: ParticleKind.snow,
        sprites: const [
          ParticleDef(spriteKey: 'flake', weight: 1, width: 0.1, height: 0.1),
        ],
        maxPerCell: 1,
        fullDensityRings: 0,
        viewRadius: 0,
        bottomY: 0,
        topY: 10,
        fallSpeedMin: 1,
        fallSpeedMax: 1,
        windDirection: vm.Vector3(0, 0, -1),
        slantDrift: 2,
      );
      final early = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.1).single;
      final late = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.6).single;
      expect(late.z, lessThan(early.z));
      // Drift stays bounded by the configured slant per fall cycle.
      expect((late.z - early.z).abs(), lessThanOrEqualTo(2.0));
    });

    test('snow spins when rotationSpin is set', () {
      final field = _field(rows: 1, columns: 1);
      final config = ParticleConfig(
        kind: ParticleKind.snow,
        sprites: const [
          ParticleDef(spriteKey: 'flake', weight: 1, width: 0.1, height: 0.1),
        ],
        maxPerCell: 1,
        fullDensityRings: 0,
        viewRadius: 0,
        bottomY: 0,
        topY: 10,
        fallSpeedMin: 1,
        fallSpeedMax: 1,
        rotationSpin: 1.5,
      );
      final a = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.0).single;
      final b = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.5).single;
      expect(a.rotation, isNot(closeTo(b.rotation, 1e-9)));
    });

    test('wind dash stays bounded and fades at both ends', () {
      final field = _field(rows: 1, columns: 1);
      final drifting = _wind(windSpeed: 1);
      final still = _wind(windSpeed: 0);

      var maxOffset = 0.0;
      var minOpacity = 1.0;
      var maxOpacity = 0.0;
      for (var t = 0.0; t < 4.8; t += 0.05) {
        final dash = placeParticles(field, drifting,
            focusRow: 0, focusColumn: 0, time: t).single;
        final base = placeParticles(field, still,
            focusRow: 0, focusColumn: 0, time: t).single;
        maxOffset = (dash.x - base.x).abs() > maxOffset
            ? (dash.x - base.x).abs()
            : maxOffset;
        minOpacity = dash.opacity < minOpacity ? dash.opacity : minOpacity;
        maxOpacity = dash.opacity > maxOpacity ? dash.opacity : maxOpacity;
      }
      expect(maxOffset, lessThanOrEqualTo(1.2 + 1e-9));
      expect(minOpacity, lessThan(0.05));
      expect(maxOpacity, closeTo(1.0, 1e-9));
    });

    test('ring density falls off from the focus cell', () {
      final field = _field();
      final config = _wind(
        maxPerCell: 3,
        fullDensityRings: 1,
        viewRadius: 10,
        windSpeed: 0,
      );
      final particles = placeParticles(field, config,
          focusRow: 3, focusColumn: 3, time: 0.0);
      // ring 0: 1×3, ring 1: 8×3, ring 2: 16×2, ring 3 (perimeter): 24×1.
      expect(particles.length, 3 + 24 + 32 + 24);
    });

    test('view radius caps the drawn domain', () {
      final field = _field();
      final config = _wind(
        maxPerCell: 1,
        fullDensityRings: 0,
        viewRadius: 1,
        windSpeed: 0,
      );
      final particles = placeParticles(field, config,
          focusRow: 3, focusColumn: 3, time: 0.0);
      // ring 0: 1 particle; ring 1 density is zero.
      expect(particles.length, 1);
    });

    test('honours the per-cell filter', () {
      final field = _field(
        allowsCell: (r, c) => r == 5 && c == 1,
      );
      final config = _wind(
        maxPerCell: 2,
        fullDensityRings: 10,
        viewRadius: 10,
        windSpeed: 0,
      );
      final particles = placeParticles(field, config,
          focusRow: 0, focusColumn: 0, time: 0.0);
      expect(particles.length, 2);
      final anchor = field.cellCenter(5, 1);
      for (final p in particles) {
        expect((p.x - anchor.x).abs(), lessThanOrEqualTo(0.5));
        expect((p.z - anchor.z).abs(), lessThanOrEqualTo(0.5));
      }
    });

    test('spawn chance skips whole cells deterministically', () {
      final field = _field(rows: 20, columns: 20);
      final config = ParticleConfig(
        kind: ParticleKind.wind,
        sprites: const [
          ParticleDef(spriteKey: 'wisp', weight: 1, width: 1, height: 0.2),
        ],
        maxPerCell: 1,
        fullDensityRings: 20,
        viewRadius: 20,
        spawnChance: 0.2,
        bottomY: 0,
        topY: 1,
      );
      final a = placeParticles(field, config,
          focusRow: 10, focusColumn: 10, time: 0.0);
      final b = placeParticles(field, config,
          focusRow: 10, focusColumn: 10, time: 0.0);
      expect(a.length, b.length);
      expect(a.length, lessThan(400));
      expect(a.length, greaterThan(0));
    });

    test('intensity zero disables the layer', () {
      final field = _field();
      final config = _wind(maxPerCell: 4).withIntensity(0);
      expect(config.maxPerCell, 0);
      expect(
        placeParticles(field, config,
            focusRow: 3, focusColumn: 3, time: 0.0),
        isEmpty,
      );
    });

    test('empty sprite list or zero density yields nothing', () {
      final field = _field();
      final noSprites = ParticleConfig(
        kind: ParticleKind.rain,
        sprites: const [],
        maxPerCell: 4,
      );
      expect(
        placeParticles(field, noSprites,
            focusRow: 3, focusColumn: 3, time: 0.0),
        isEmpty,
      );
    });
  });

  group('particleCellSeed', () {
    test('is deterministic and non-negative', () {
      expect(particleCellSeed(7, 3, 4), particleCellSeed(7, 3, 4));
      expect(particleCellSeed(7, 3, 4), greaterThanOrEqualTo(0));
    });

    test('changes with every input', () {
      final base = particleCellSeed(7, 3, 4);
      expect(particleCellSeed(8, 3, 4), isNot(base));
      expect(particleCellSeed(7, 4, 4), isNot(base));
      expect(particleCellSeed(7, 3, 5), isNot(base));
    });

    test('does not collide the old arithmetic pair (0,50)/(1,0)', () {
      // The game's original `seed*100000 + r*500 + c*10` repeated here.
      expect(particleCellSeed(7, 0, 50), isNot(particleCellSeed(7, 1, 0)));
    });
  });

  group('particleBatchCapacity', () {
    test('clamps the field by the view-radius window', () {
      final field = _field(rows: 100, columns: 100);
      final config = _wind(
        maxPerCell: 2,
        fullDensityRings: 0,
        viewRadius: 5,
        windSpeed: 0,
      );
      expect(particleBatchCapacity(field, config), 11 * 11 * 2);
    });

    test('uses the allowed domain when it is smaller', () {
      final field = _field(
        rows: 3,
        columns: 3,
        allowsCell: (r, c) => r == 0,
      );
      final config = _wind(
        maxPerCell: 2,
        fullDensityRings: 0,
        viewRadius: 10,
        windSpeed: 0,
      );
      expect(particleBatchCapacity(field, config), 3 * 2);
    });

    test('is zero for zero density or an empty domain', () {
      final config = _wind(maxPerCell: 0, viewRadius: 5);
      expect(particleBatchCapacity(_field(), config), 0);
      final blocked = _field(allowsCell: (r, c) => false);
      expect(
        particleBatchCapacity(blocked, _wind(maxPerCell: 2, viewRadius: 5)),
        0,
      );
    });

    test('covers every particle placeParticles can emit', () {
      final field = _field(rows: 100, columns: 100);
      final config = _wind(
        maxPerCell: 3,
        fullDensityRings: 1,
        viewRadius: 6,
        windSpeed: 0,
      );
      final particles = placeParticles(field, config,
          focusRow: 50, focusColumn: 50, time: 0.0);
      expect(
        particles.length,
        lessThanOrEqualTo(particleBatchCapacity(field, config)),
      );
    });
  });
}
