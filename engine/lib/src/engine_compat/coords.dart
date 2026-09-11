import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Coordinate helpers copied from the main game (`lib/shared/camera_math.dart`)
/// so model-local geometry renders identically in the editor and in-game.
///
/// The game's flutter_scene fork inverts left/right in its look-at, so world
/// x is **negated**: `cellWorld(r, c) = (-c, 0, r)`. Never draw a raw model
/// column as +X — always go through [cellWorld].

/// Maps a grid (row, col) cell to a world position. Chunk-local coords map
/// with row = z, col = x.
vm.Vector3 cellWorld(int row, int col) =>
    vm.Vector3(-col.toDouble(), 0.0, row.toDouble());

/// Chunk-local (x, z) → world. x = column, z = row.
///
/// The model origin (0, 0) is the center of the bottom-left cell — a fixed
/// anchor: enlarging the model extends the grid in +x/+z and the origin
/// (and every existing object) keeps its cell. Cell centers sit on the
/// integers (0, 1, 2, …) for ANY model size, so the snap grid (multiples of
/// the step from 0) always lands inside cells.
///
/// The [w]×[l] model is centered in world space (the same footprint as the
/// old center-origin system): model x ∈ [−0.5, w−0.5] → world x ∈ [−w/2, w/2].
vm.Vector3 chunkWorld(double x, double z, int w, int l) =>
    vm.Vector3(-(x - (w - 1) / 2), 0.0, z - (l - 1) / 2);

/// Inverse of [chunkWorld] for X: world x → model x (the mirror convention).
double modelXFromWorld(double worldX, int w) => (w - 1) / 2 - worldX;

/// Inverse of [chunkWorld] for Z: world z → model z.
double modelZFromWorld(double worldZ, int l) => worldZ + (l - 1) / 2;

/// Compass angle for a direction index (0=north, 1=east, 2=south, 3=west),
/// the same formula the game uses for its fixed camera.
double facingAngle(int dirIndex) =>
    (math.pi + dirIndex * math.pi / 2) % (2 * math.pi);

/// Yaw that makes a screen-parallel billboard face the player/camera with
/// the given camera-local forward (fx, fz) — copied from the game.
double screenParallelYaw(double fx, double fz) =>
    math.pi - math.atan2(fx, fz);
