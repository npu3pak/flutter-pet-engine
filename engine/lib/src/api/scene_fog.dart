import 'dart:ui' show Color;

/// Distance fog of the scene (the former `GameFog`/`EngineFog`).
class SceneFog {
  const SceneFog({
    required this.color,
    this.start = 0,
    this.end = 200,
    this.minOpacity = 0,
    this.maxOpacity = 1,
  });

  /// The fog color (sRGB; converted to linear when applied to the renderer).
  final Color color;

  /// The distance the fog starts at.
  final double start;

  /// The distance the fog reaches [maxOpacity] at.
  final double end;

  /// The fog opacity at [start].
  final double minOpacity;

  /// The fog opacity at [end].
  final double maxOpacity;
}
