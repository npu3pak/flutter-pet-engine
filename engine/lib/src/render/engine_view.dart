import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show SceneView, SceneTickCallback;

import '../engine/game_scene.dart';
import 'engine_scene.dart';

/// Renders an [EngineScene] and drives its per-frame repaint — the engine
/// wrapper over the fork's `SceneView`, so games never import the fork widget.
///
/// The scene is app-owned and mutated imperatively; this view is a view onto
/// it. Place it where it receives bounded constraints.
class EngineSceneView extends StatelessWidget {
  const EngineSceneView({
    super.key,
    required this.scene,
    this.onTick,
    this.autoTick = true,
    this.pixelRatio,
    this.warmUp = false,
  });

  /// The scene to render.
  final EngineScene scene;

  /// Called once per frame while ticking (see `SceneTickCallback`).
  final SceneTickCallback? onTick;

  /// Whether to drive a repaint every frame with an internal ticker.
  final bool autoTick;

  /// Logical-to-physical pixel multiplier for the offscreen target.
  final double? pixelRatio;

  /// Whether to compile the pipelines before the first visible frame.
  final bool warmUp;

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene.raw,
      camera: scene.camera,
      onTick: onTick,
      autoTick: autoTick,
      pixelRatio: pixelRatio,
      warmUp: warmUp,
    );
  }
}

/// Renders a [GameScene] (model scenes, glTF, dynamic objects) through the
/// engine facade. [onTick] is forwarded as-is: the caller drives
/// [GameScene.update] (and any game logic) inside it.
class GameSceneView extends StatelessWidget {
  const GameSceneView({
    super.key,
    required this.game,
    this.onTick,
    this.autoTick = true,
    this.pixelRatio,
    this.warmUp = false,
  });

  /// The game scene to render.
  final GameScene game;

  /// Called once per frame while ticking.
  final SceneTickCallback? onTick;

  /// Whether to drive a repaint every frame with an internal ticker.
  final bool autoTick;

  /// Logical-to-physical pixel multiplier for the offscreen target.
  final double? pixelRatio;

  /// Whether to compile the pipelines before the first visible frame.
  final bool warmUp;

  @override
  Widget build(BuildContext context) {
    return SceneView(
      game.scene,
      camera: game.camera,
      onTick: onTick,
      autoTick: autoTick,
      pixelRatio: pixelRatio,
      warmUp: warmUp,
    );
  }
}
