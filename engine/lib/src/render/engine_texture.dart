import 'dart:typed_data';

import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

/// Sampling presets for engine textures: the game look is nearest-neighbour
/// with a mip chain (crisp pixel art at any distance); UI-style textures can
/// opt into linear sampling.
enum EngineTextureFilter {
  /// Nearest min/mag/mip filtering (pixel art).
  pixelated,

  /// Linear filtering with mipmaps (photos, UI).
  linear,
}

/// Opaque handle to a GPU texture owned by pet_engine. Games load textures
/// through [EngineTexture.fromAsset] (or the resource manager) and pass the
/// handle to materials — they never touch the fork's texture types.
class EngineTexture {
  EngineTexture.wrap(this.raw);

  /// The underlying fork texture. Engine-internal plumbing only; game code
  /// passes the handle around instead of naming this type.
  final Texture2D raw;

  /// Loads a bundled asset (`assets/...png`) into a texture. [filter]
  /// selects the sampling preset; the default is the game's pixel-art look.
  static Future<EngineTexture> fromAsset(
    String assetPath, {
    EngineTextureFilter filter = EngineTextureFilter.pixelated,
  }) async {
    final texture = await Texture2D.fromAsset(
      assetPath,
      sampling: _samplingFor(filter),
    );
    return EngineTexture.wrap(texture);
  }

  /// Decodes already-loaded bytes (a project texture) into a texture.
  static Future<EngineTexture> fromBytes(
    Uint8List bytes, {
    EngineTextureFilter filter = EngineTextureFilter.pixelated,
  }) async {
    final image = await decodeImageFromList(bytes);
    try {
      final texture = await Texture2D.fromImage(
        image,
        sampling: _samplingFor(filter),
      );
      return EngineTexture.wrap(texture);
    } finally {
      image.dispose();
    }
  }

  static TextureSampling _samplingFor(EngineTextureFilter filter) =>
      switch (filter) {
        EngineTextureFilter.pixelated => const TextureSampling(
            minFilter: gpu.MinMagFilter.nearest,
            magFilter: gpu.MinMagFilter.nearest,
            mipFilter: gpu.MipFilter.nearest,
          ),
        EngineTextureFilter.linear => const TextureSampling(),
      };
}
