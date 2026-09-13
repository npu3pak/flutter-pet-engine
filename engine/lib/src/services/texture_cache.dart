import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';

import '../engine_compat/materials.dart';
import 'app_log.dart';

/// Loads PNG files from an arbitrary directory into flutter_scene textures
/// (nearest sampling, like the game's sprite/texture assets).
class TextureCache {
  /// Futures keyed by `'t:<name>'` (textures) / `'s:<name>'` (sprites) —
  /// the family prefix prevents a file name present in BOTH folders from
  /// resolving to the wrong file's texture.
  final Map<String, Future<Texture2D?>> _futures = {};

  /// Synchronously readable copies of the resolved textures (keyed by
  /// `'t:<name>'`/`'s:<name>'`) — the level loader preloads through the
  /// futures and the renderer can then pick them up without a gray frame.
  final Map<String, Texture2D> _ready = {};

  /// Keys that resolved to «missing» (file absent, bytes null, decode
  /// failure), keyed by `'t:<name>'`/`'s:<name>'`. Lets the renderer render
  /// the fuchsia placeholder synchronously during a bake — without waiting
  /// for the async ready callback a baked level would keep gray.
  final Set<String> _missing = {};

  /// Decoded pixel sizes of successfully loaded textures/sprites, keyed by
  /// `'t:<name>'`/`'s:<name>'` (the editor's resource panels read them).
  final Map<String, (int, int)> _sizes = {};

  String? _dir;

  /// [texturesDir] and [spritesDir] — absolute paths; empty string means
  /// the resource family is absent.
  String? texturesDir;
  String? spritesDir;

  /// Optional byte loader for environments without direct file access
  /// (bundled/network assets): when set, [texturesDir]/[spritesDir] carry the
  /// FAMILY-RELATIVE roots ('textures'/'sprites') and every read goes through
  /// this callback instead of dart:io. A null result means "missing file".
  Future<Uint8List?> Function(String path)? byteLoader;

  TextureCache({this.texturesDir, this.spritesDir, this.byteLoader});

  bool get ready => _dir != null;

  /// Ensures [dir] is the current asset root; drops cache when it changes.
  void setRoot(String dir) {
    if (_dir == dir) return;
    _dir = dir;
    _futures.clear();
    _ready.clear();
    _missing.clear();
    _sizes.clear();
  }

  /// Drops every cached texture — call after importing/renaming/deleting a
  /// resource so the editor picks up the new file.
  void invalidate() {
    _futures.clear();
    _ready.clear();
    _missing.clear();
    _sizes.clear();
  }

  /// Loads a texture by file name from [texturesDir].
  Future<Texture2D?> texture(String key) =>
      _load('t', _path(texturesDir, key), key);

  /// Loads a sprite by file name from [spritesDir].
  Future<Texture2D?> sprite(String key) =>
      _load('s', _path(spritesDir, key), key);

  /// Already-resolved texture, or null (not loaded yet) — synchronous.
  Texture2D? peekTexture(String key) => _ready['t:$key'];

  /// Already-resolved sprite, or null (not loaded yet) — synchronous.
  Texture2D? peekSprite(String key) => _ready['s:$key'];

  /// Whether the texture already settled as missing — synchronous.
  bool isTextureMissing(String key) => _missing.contains('t:$key');

  /// Whether the sprite already settled as missing — synchronous.
  bool isSpriteMissing(String key) => _missing.contains('s:$key');

  /// Decoded pixel size of a loaded texture, or null (unknown/not loaded).
  (int, int)? textureSize(String key) => _sizes['t:$key'];

  /// Decoded pixel size of a loaded sprite, or null (unknown/not loaded).
  (int, int)? spriteSize(String key) => _sizes['s:$key'];

  /// Marks a texture as ready before the first build (the level loader marks
  /// decoded textures so no frame ever shows the gray placeholder).
  void markTextureReady(String key, Texture2D texture) {
    _ready['t:$key'] = texture;
    _futures['t:$key'] = Future.value(texture);
    _missing.remove('t:$key');
  }

  /// Marks a sprite as ready before the first build.
  void markSpriteReady(String key, Texture2D texture) {
    _ready['s:$key'] = texture;
    _futures['s:$key'] = Future.value(texture);
    _missing.remove('s:$key');
  }

  String? _path(String? dir, String key) {
    if (dir == null || dir.isEmpty) return null;
    return '$dir/$key';
  }

  Future<Texture2D?> _load(String family, String? path, String key) {
    if (path == null) return Future.value(null);
    final cacheKey = '$family:$key';
    final cached = _futures[cacheKey];
    if (cached != null) return cached;
    final future = _decode(path, family, key);
    _futures[cacheKey] = future;
    return future;
  }

  Future<Texture2D?> _decode(String path, String family, String key) async {
    final sw = Stopwatch()..start();
    try {
      final loader = byteLoader;
      Uint8List? bytes;
      if (loader != null) {
        bytes = await loader(path);
        if (bytes == null) {
          _missing.add('$family:$key');
          logStage('textures', 'missing $family $key -> $path');
          return null;
        }
      } else {
        final file = File(path);
        if (!file.existsSync()) {
          _missing.add('$family:$key');
          logStage('textures', 'missing $family $key -> $path');
          return null;
        }
        bytes = await file.readAsBytes();
      }
      final readMs = sw.elapsedMilliseconds;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final decodeMs = sw.elapsedMilliseconds;
      final image = frame.image;
      final size = (image.width, image.height);
      final tex = await Texture2D.fromImage(image, sampling: pixelatedSampler);
      image.dispose();
      _ready['$family:$key'] = tex;
      _sizes['$family:$key'] = size;
      _missing.remove('$family:$key');
      logStage(
        'textures',
        'loaded $family $key ${bytes.length ~/ 1024}KB'
            ' (read ${readMs}ms decode ${decodeMs - readMs}ms '
            'tex ${sw.elapsedMilliseconds - decodeMs}ms)',
      );
      return tex;
    } catch (e) {
      _missing.add('$family:$key');
      logStage('textures', 'FAIL $family $key ($path): $e');
      return null;
    }
  }
}
