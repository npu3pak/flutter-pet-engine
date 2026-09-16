import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

/// Loads a decoded image for one atlas key.
typedef AtlasImageLoader = Future<ui.Image> Function(String key);

/// Nearest-sampling for pixel-art atlases; no mipmaps so atlas cells never
/// bleed into each other. Mapped from [AtlasSampling.nearest].
const TextureSampling kAtlasNearestSampling = TextureSampling(
  mipmaps: false,
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  mipFilter: gpu.MipFilter.nearest,
);

/// Linear-sampling atlas for soft sprites (fog, wind wisps) — nearest would
/// look blocky. Mapped from [AtlasSampling.linear].
const TextureSampling kAtlasLinearSampling = TextureSampling(
  mipmaps: false,
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  mipFilter: gpu.MipFilter.linear,
);

/// Sampling preset of a composed atlas. Cell atlases never use mipmaps, so
/// the presets differ only in min/mag filtering: [nearest] keeps pixel art
/// crisp, [linear] softens soft sprites (fog, wind wisps).
enum AtlasSampling { nearest, linear }

/// A composed flipbook atlas texture plus the resolved keys in cell order.
class SpriteAtlas {
  /// Plumbing: atlases are built by [buildSpriteAtlas].
  @internal
  SpriteAtlas({
    required this.texture,
    required this.keys,
    int? columns,
    int? rows,
  }) : columns = columns ?? keys.length,
       rows = rows ?? 1;

  /// The uploaded GPU texture. Plumbing: the engine's layers pass it straight
  /// to their batches; applications use `SceneTexture` if they need a public
  /// texture handle.
  final Texture2D texture;

  /// Resolved keys, one per atlas cell (unresolvable keys were skipped).
  final List<String> keys;

  /// The atlas grid: cell index `i` lives at
  /// `(i % columns, i ~/ columns)`. A single-row atlas uses `rows == 1`.
  final int columns;
  final int rows;

  /// The cell index of [key], or null when the key did not resolve.
  int? indexOf(String key) {
    final index = keys.indexOf(key);
    return index < 0 ? null : index;
  }
}

/// Maps semantic sprite keys to atlas cell indices by their ASSET PATHS.
///
/// [buildSpriteAtlas] returns the paths it resolved (its [SpriteAtlas.keys]
/// are paths, not semantic keys); a layer that thinks in semantic keys (game
/// sprite ids like `fog_1`) pairs each key with the path it loaded and looks
/// the cell up here. Sprites whose path did not resolve are skipped — exactly
/// the game's old keyed atlas behavior, shared by [ParticleLayer] and the
/// ground-fog layer.
Map<String, int> spriteFrameMap(
  Iterable<({String key, String path})> sprites,
  List<String> atlasKeys,
) {
  final frames = <String, int>{};
  for (final sprite in sprites) {
    final index = atlasKeys.indexOf(sprite.path);
    if (index >= 0) frames[sprite.key] = index;
  }
  return frames;
}

/// Composes [keys] into `cellSize`² cells with a 1 px inset (so bilinear
/// sampling never bleeds between neighbours), using [load] for the decoded
/// images. Unresolvable keys are skipped. Returns null when nothing resolves.
///
/// The cells form a grid: [maxWidth] caps the texture width (rows wrap when
/// the keys do not fit in one row). `maxWidth <= 0` keeps the legacy
/// single-row layout. GPU texture-width limits (typically 16 384) are the
/// reason to cap: a long row would silently fail to upload.
Future<({ui.Image image, List<String> keys, int columns, int rows})?>
composeSpriteAtlas(
  List<String> keys,
  AtlasImageLoader load, {
  int cellSize = 256,
  int inset = 1,
  int maxWidth = 0,
}) async {
  final images = <ui.Image>[];
  final resolved = <String>[];
  for (final key in keys) {
    try {
      images.add(await load(key));
      resolved.add(key);
    } catch (_) {
      // Unresolvable key: skipped, like the game's atlas builder.
    }
  }
  if (images.isEmpty) return null;

  final maxColumns = maxWidth > 0
      ? (maxWidth ~/ cellSize).clamp(1, images.length)
      : images.length;
  final columns = images.length < maxColumns ? images.length : maxColumns;
  final rows = (images.length + columns - 1) ~/ columns;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  for (var i = 0; i < images.length; i++) {
    final img = images[i];
    final column = i % columns;
    final row = i ~/ columns;
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(
        (column * cellSize + inset).toDouble(),
        (row * cellSize + inset).toDouble(),
        (cellSize - 2 * inset).toDouble(),
        (cellSize - 2 * inset).toDouble(),
      ),
      paint,
    );
    img.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(columns * cellSize, rows * cellSize);
  picture.dispose();
  return (image: image, keys: resolved, columns: columns, rows: rows);
}

/// Builds a GPU flipbook atlas from Flutter asset keys ([assetPaths] in cell
/// order); returns null when nothing resolves. Requires an initialized scene
/// (the texture upload touches the GPU). [maxWidth] caps the texture width:
/// the cells wrap into rows beyond it (`<= 0` keeps one row).
Future<SpriteAtlas?> buildSpriteAtlas(
  List<String> assetPaths, {
  AssetBundle? bundle,
  AtlasSampling sampling = AtlasSampling.nearest,
  int cellSize = 256,
  int inset = 1,
  int maxWidth = 0,
}) async {
  final composed = await composeSpriteAtlas(
    assetPaths,
    (path) => imageFromAsset(path, bundle: bundle ?? rootBundle),
    cellSize: cellSize,
    inset: inset,
    maxWidth: maxWidth,
  );
  if (composed == null) return null;
  try {
    final texture = await Texture2D.fromImage(
      composed.image,
      sampling: switch (sampling) {
        AtlasSampling.nearest => kAtlasNearestSampling,
        AtlasSampling.linear => kAtlasLinearSampling,
      },
    );
    return SpriteAtlas(
      texture: texture,
      keys: composed.keys,
      columns: composed.columns,
      rows: composed.rows,
    );
  } finally {
    composed.image.dispose();
  }
}
