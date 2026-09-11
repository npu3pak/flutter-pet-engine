import 'dart:ui' show FilterQuality;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Engine-side anti-aliasing choice, mapped to the fork's [AntiAliasingMode].
enum GameAntiAliasing { none, fxaa, msaa, auto }

/// The fork's mode for a [GameAntiAliasing] value.
AntiAliasingMode antiAliasingModeOf(GameAntiAliasing mode) => switch (mode) {
      GameAntiAliasing.none => AntiAliasingMode.none,
      GameAntiAliasing.fxaa => AntiAliasingMode.fxaa,
      GameAntiAliasing.msaa => AntiAliasingMode.msaa,
      GameAntiAliasing.auto => AntiAliasingMode.auto,
    };

/// The engine-facing value for a fork [AntiAliasingMode].
GameAntiAliasing gameAntiAliasingOf(AntiAliasingMode mode) => switch (mode) {
      AntiAliasingMode.none => GameAntiAliasing.none,
      AntiAliasingMode.fxaa => GameAntiAliasing.fxaa,
      AntiAliasingMode.msaa => GameAntiAliasing.msaa,
      AntiAliasingMode.auto => GameAntiAliasing.auto,
    };

/// Linear distance fog settings (the game's biome haze): geometry blends
/// toward the linear-RGB [color] from [start] to [end], capped by
/// [maxOpacity] with [minOpacity] at [start].
class GameFog {
  const GameFog({
    required this.color,
    this.start = 0,
    this.end = 200,
    this.minOpacity = 0,
    this.maxOpacity = 1,
  });

  final vm.Vector3 color; // linear RGB
  final double start;
  final double end;
  final double minOpacity;
  final double maxOpacity;

  /// Writes these settings into a fork [Fog], forcing linear mode and
  /// clearing the sky/sun extras (the game's look).
  void applyTo(Fog fog) {
    fog
      ..enabled = true
      ..mode = FogMode.linear
      ..color = color
      ..start = start
      ..end = end
      ..minOpacity = minOpacity
      ..maxOpacity = maxOpacity
      ..skyColorInfluence = 0.0
      ..cutoffDistance = 0.0
      ..heightFalloff = 0.0
      ..sunInScatter = 0.0;
  }
}

/// A full picture-quality preset: fog, anti-aliasing, render scale + filter
/// quality and environment (IBL) intensity. Apply through
/// [GameScene.applyPictureSettings].
class GamePictureSettings {
  const GamePictureSettings({
    this.fog,
    this.antiAliasing = GameAntiAliasing.auto,
    this.renderScale = 1.0,
    this.filterQuality = FilterQuality.none,
    this.environmentIntensity = 1.0,
  });

  /// Null disables fog.
  final GameFog? fog;
  final GameAntiAliasing antiAliasing;

  /// Render resolution multiplier (0..1+); a low scale keeps the pixel-art
  /// look cheap on mobile GPUs.
  final double renderScale;

  /// How the low-resolution render target is upscaled ([FilterQuality.none]
  /// = nearest, the pixel-art default).
  final FilterQuality filterQuality;

  /// Environment/IBL light multiplier.
  final double environmentIntensity;
}
