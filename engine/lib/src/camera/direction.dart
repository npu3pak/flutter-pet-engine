import 'animation_type.dart';

/// Cardinal facing of the game camera, clockwise starting north.
enum Direction { north, east, south, west }

/// The facing a camera had *before* a [AnimationType.turnLeft]/turnRight
/// animation that ends facing [to] (or null when [anim] is not a turn).
///
/// During a turn the game already sets the destination facing, so the start
/// facing must be derived to keep the old side visible until the rotation
/// finishes.
Direction? turnFrom(Direction to, AnimationType anim) => switch (anim) {
      AnimationType.turnLeft => Direction.values[(to.index + 1) % 4],
      AnimationType.turnRight => Direction.values[(to.index + 3) % 4],
      _ => null,
    };
