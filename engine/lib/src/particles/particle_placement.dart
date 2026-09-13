import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import 'particle_config.dart';

/// The world-space cell grid a [ParticleLayer] spawns over: `rows × columns`
/// unit cells whose centers are `origin + cellWorld(row, col)` — the engine's
/// mirrored-X cell convention, so a game maps its maze 1:1.
class ParticleField {
  ParticleField({
    required this.rows,
    required this.columns,
    vm.Vector3? origin,
    this.allowsCell,
    this.seed = 0,
  }) : origin = origin ?? vm.Vector3.zero();

  /// Cell (row, col) center = [origin] + `cellWorld(row, col)`.
  final vm.Vector3 origin;
  final int rows;
  final int columns;

  /// Optional per-cell filter (`pathOnly` domains: the game maps its walkable
  /// cells here). Null allows every cell.
  final bool Function(int row, int col)? allowsCell;

  /// Per-field seed of the deterministic particle layout (replaces the game's
  /// maze index).
  final int seed;

  bool allows(int row, int col) => allowsCell?.call(row, col) ?? true;

  vm.Vector3 cellCenter(int row, int col) {
    final w = cellWorld(row, col);
    return vm.Vector3(origin.x + w.x, origin.y + w.y, origin.z + w.z);
  }
}

/// One placed particle of a [ParticleLayer] frame: world position and size,
/// in-plane rotation, opacity and the per-instance velocity (rain streaks
/// stretch along it).
class ParticleInstance {
  const ParticleInstance({
    required this.spriteKey,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.vx = 0,
    this.vy = 0,
    this.vz = 0,
  });

  final String spriteKey;
  final double x, y, z;
  final double width, height;
  final double rotation;
  final double opacity;
  final double vx, vy, vz;
}

/// The deterministic per-cell seed of the particle layout: a 31-bit hash of
/// the field seed and the cell coordinates. Unlike the game's original
/// `seed*100000 + row*500 + col*10` arithmetic, this cannot collide two
/// different cells (the old formula repeated at column ≥ 50).
int particleCellSeed(int fieldSeed, int row, int col) {
  var h = (fieldSeed * 73856093) ^ (row * 19349663) ^ (col * 83492791);
  h = (h ^ (h >> 13)) * 0x5bd1e995;
  h ^= h >> 15;
  return h & 0x7FFFFFFF;
}

/// The upper bound of instances a particle batch must hold: a focus can only
/// draw cells within [ParticleConfig.viewRadius] Chebyshev rings, so the
/// allowed domain is clamped by the `(2·viewRadius+1)²` window (a whole-field
/// count would over-allocate massively on large fields).
int particleBatchCapacity(ParticleField field, ParticleConfig config) {
  var domainCells = 0;
  for (var r = 0; r < field.rows; r++) {
    for (var c = 0; c < field.columns; c++) {
      if (field.allows(r, c)) domainCells++;
    }
  }
  final window = (2 * config.viewRadius + 1) * (2 * config.viewRadius + 1);
  final maxCount = config.maxPerCell.clamp(0, ParticleConfig.maxPerCellCap);
  return math.min(domainCells, window) * maxCount;
}

/// The rain sprite's art inside its 256×256 cell (authored by the game's
/// `scripts/generate_weather.py`): the drop head starts 48/256 below the
/// texture top, so the billboard center sits below the head by
/// `(0.5 − headFrac) × len`.
const double _rainHeadFrac = 48 / 256;

/// Places the particles of one [ParticleConfig] layer for the current frame:
/// instanced billboards anchored to the world grid (each particle belongs to
/// its cell — moving the focus never rebuilds the field, only the
/// focus-centered ring domain decides which cells draw). All motion is a
/// closed-form function of [time] + a per-particle phase, so a particle's
/// world position is a pure function of its cell: it never follows the camera.
///
/// Motion by kind:
/// - [ParticleKind.rain]: hard streaks fall at
///   [ParticleConfig.fallSpeedMin]..[fallSpeedMax] m/s, cycling the vertical
///   band [ParticleConfig.bottomY]..[topY] (the hidden wrap sits below the
///   floor and above the top bound). The per-instance velocity carries the
///   fall (the streak billboard stretches along it), plus the horizontal
///   breeze: the drops drift along the wind over the fall phase and the
///   streak slants with the full velocity.
/// - [ParticleKind.snow]: slow flakes fall the same way, swaying and spinning
///   around their cell anchor. With [ParticleConfig.slantDrift] they
///   additionally drift along the wind over one full fall cycle — the offset
///   is a closed form of the fall phase, so the field stays bounded.
/// - [ParticleKind.wind]: wisps/glints ride the wind stream — a repeating
///   dash along the wind direction with opacity fading at both ends (no
///   visible teleport), hovering within the band.
///
/// Deterministic per (cell, particle index): each cell draws from its own
/// seeded RNG and particle `i` always consumes the same draws (jitter x,
/// jitter z, sprite, speed, phase, wind-y roll), so movement keeps particles
/// stable.
List<ParticleInstance> placeParticles(
  ParticleField field,
  ParticleConfig config, {
  required int focusRow,
  required int focusColumn,
  required double time,
  vm.Vector3? windDirection,
  List<ParticleInstance>? out,
}) {
  final result = out ?? <ParticleInstance>[];
  result.clear();
  if (config.maxPerCell <= 0 || config.sprites.isEmpty) return result;

  final totalWeight = config.sprites.fold<double>(0, (s, d) => s + d.weight);
  final span = config.topY - config.bottomY;
  final isWind = config.kind == ParticleKind.wind;
  final drifting = config.windSpeed > 0;

  // Horizontal wind direction, normalized.
  final source = windDirection ?? config.windDirection;
  var dirX = 0.0;
  var dirZ = 0.0;
  final m = math.sqrt(source.x * source.x + source.z * source.z);
  if (m > 1e-9) {
    dirX = source.x / m;
    dirZ = source.z / m;
  }

  // Wind dashes: a particle rides [streamDist] world units along the wind
  // before its dash restarts; the last [dashFadeFrac] of each end fades the
  // sprite out so the restart is never a visible teleport.
  const streamDist = 2.4;
  const dashFadeFrac = 0.22;

  final swayAmp = config.swayAmp;
  final swayFreq = config.swayFreq;
  final rotationSpin = config.rotationSpin;

  for (var r = 0; r < field.rows; r++) {
    for (var c = 0; c < field.columns; c++) {
      if (!field.allows(r, c)) continue;

      final ring = math.max((r - focusRow).abs(), (c - focusColumn).abs());
      if (ring > config.viewRadius) continue;
      final count = config.maxPerCell - math.max(0, ring - config.fullDensityRings);
      if (count <= 0) continue;

      final rng = math.Random(particleCellSeed(field.seed, r, c));
      if (config.spawnChance < 1.0) {
        // Cell contribution roll — consumed before the particle loop so the
        // loop draws are index-stable regardless of the chance.
        if (rng.nextDouble() > config.spawnChance) continue;
      }
      final anchor = field.cellCenter(r, c);
      final wx = anchor.x;
      final wz = anchor.z;

      for (var i = 0; i < count; i++) {
        // Frozen draw order: jitter x, jitter z, sprite, speed, phase,
        // wind-y roll. Always the same draws per index.
        final jx = (rng.nextDouble() - 0.5) * 0.9;
        final jz = (rng.nextDouble() - 0.5) * 0.9;
        final roll = rng.nextDouble() * totalWeight;
        var acc = 0.0;
        var chosen = config.sprites.first;
        for (final d in config.sprites) {
          acc += d.weight;
          if (roll <= acc) {
            chosen = d;
            break;
          }
        }
        final speed = config.fallSpeedMin +
            (config.fallSpeedMax - config.fallSpeedMin) * rng.nextDouble();
        final phase = rng.nextDouble();

        // Sway around the world anchor: two detuned sine axes.
        final swayX = swayAmp * math.sin(time * swayFreq + phase * 2 * math.pi);
        final swayZ = swayAmp *
            math.sin(time * swayFreq * 1.37 + phase * 2 * math.pi * 1.7);

        var px = wx + jx + swayX;
        var pz = wz + jz + swayZ;
        var py = 0.0;
        var opacity = config.opacity;
        var rot = 0.0;
        var vx = 0.0;
        var vy = 0.0;
        var vz = 0.0;

        if (isWind) {
          // Wind layer: hover within the band and ride the wind stream as a
          // repeating dash with faded ends (invisible restart).
          final yMid =
              config.bottomY + rng.nextDouble() * (config.topY - config.bottomY);
          py = yMid +
              math.sin(time * 0.7 + phase * 2 * math.pi) *
                  (config.swayAmp > 0 ? config.swayAmp * 0.5 : 0.05);
          if (drifting && (dirX != 0 || dirZ != 0)) {
            final cycle =
                (time * config.windSpeed / streamDist + phase) % 1.0;
            final off = (cycle - 0.5) * streamDist;
            px += dirX * off;
            pz += dirZ * off;
            final edge = math.min(1.0, cycle / dashFadeFrac);
            final tail = math.min(1.0, (1.0 - cycle) / dashFadeFrac);
            final fade = math.min(edge, tail).clamp(0.0, 1.0);
            opacity *= fade * fade;
          }
        } else {
          // Falling layer: cycle the vertical band; the wrap happens with
          // the particle hidden under the floor (rain shafts) or far below it
          // (snow).
          final fall = time * speed + phase * span;
          if (config.kind == ParticleKind.rain) {
            // The loop variable is the drop HEAD; the billboard center sits
            // behind it along the velocity by the top blank of the rain
            // texture (BillboardFacing.velocityStretched aligns the sprite's
            // up axis with the full velocity, so under wind the offset has
            // horizontal components as well). The stretch follows the full
            // speed for the same reason.
            final vx0 = dirX * config.windSpeed;
            final vz0 = dirZ * config.windSpeed;
            final speedTotal = math.sqrt(speed * speed + vx0 * vx0 + vz0 * vz0);
            final stretch = config.velocityStretch * speedTotal;
            final head = config.topY - fall % span;
            final len = chosen.height + stretch;
            // Wind drift: the drop rides the wind while it falls; the offset
            // is a closed form of the fall phase, so the wrap coincides with
            // the hidden under-floor reset and no teleport is visible.
            final frac = (config.topY - head) / span;
            final fallTime = speed > 1e-9 ? span / speed : 0.0;
            px += vx0 * fallTime * frac;
            pz += vz0 * fallTime * frac;
            final back = speedTotal > 1e-9
                ? (0.5 - _rainHeadFrac) * len / speedTotal
                : 0.0;
            px += back * vx0;
            pz += back * vz0;
            py = head - back * speed;
            vx = vx0;
            vy = -speed;
            vz = vz0;
          } else {
            // Snow: the loop variable is the flake center. Flakes stay in
            // their cell — the slant below is bounded per fall cycle.
            final fallPhase = fall % span;
            py = config.topY - fallPhase;
            rot = (time * rotationSpin + phase * 2 * math.pi) % (2 * math.pi);
            if (config.slantDrift > 0 && (dirX != 0 || dirZ != 0)) {
              final frac = fallPhase / span;
              px += dirX * config.slantDrift * frac;
              pz += dirZ * config.slantDrift * frac;
            }
          }
        }

        result.add(ParticleInstance(
          spriteKey: chosen.spriteKey,
          x: px,
          y: py,
          z: pz,
          width: chosen.width,
          height: chosen.height,
          rotation: rot,
          opacity: opacity.clamp(0.0, 1.0),
          vx: vx,
          vy: vy,
          vz: vz,
        ));
      }
    }
  }
  return result;
}
