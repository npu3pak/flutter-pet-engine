/// Cardinal direction in the mirrored world frame.
enum Direction { north, east, south, west }

/// The first-person camera animation currently playing.
enum AnimationType {
  none,
  stepForward,
  stepBackward,
  strafeLeft,
  strafeRight,
  turnLeft,
  turnRight,
}
