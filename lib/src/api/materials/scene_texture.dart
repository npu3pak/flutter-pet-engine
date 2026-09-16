// Private fields behind public getters cannot use initializing formals in
// named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

/// Sampling presets of a [SceneTexture].
enum SceneTextureFilter {
  /// Nearest min/mag/mip filtering (the game's pixel-art look).
  pixelated,

  /// Linear filtering with mipmaps (photos, UI).
  linear,
}

/// A texture of the new API: a decoded image plus its sampling preset.
///
/// The GPU upload is lazy and asynchronous, so the object can be created and
/// inspected (size, filter) without a rendering device — tests and tools can
/// work headlessly. Materials pick the GPU texture up as soon as it is ready
/// ([raw] turns non-null and listeners are notified).
class SceneTexture extends ChangeNotifier {
  /// Wraps an already decoded [image]. Starts the asynchronous GPU upload.
  SceneTexture.fromImage(
    ui.Image image, {
    this.filter = SceneTextureFilter.pixelated,
  }) : _image = image,
       _width = image.width,
       _height = image.height {
    _uploadFuture = _upload();
  }

  /// Wraps an already uploaded GPU texture (a resource-session cache entry).
  /// Plumbing: the size is unknown unless the caller passes it.
  SceneTexture.fromGpu(
    Texture2D texture, {
    this.filter = SceneTextureFilter.pixelated,
    int width = 0,
    int height = 0,
  }) : _image = null,
       _width = width,
       _height = height,
       _gpu = texture {
    _uploadFuture = Future.value();
  }

  /// Loads a bundled asset (`assets/...png`) and wraps it.
  static Future<SceneTexture> fromAsset(
    String assetPath, {
    SceneTextureFilter filter = SceneTextureFilter.pixelated,
  }) async {
    final data = await rootBundle.load(assetPath);
    return fromBytes(data.buffer.asUint8List(), filter: filter);
  }

  /// Decodes PNG/JPEG [bytes] and wraps the result.
  static Future<SceneTexture> fromBytes(
    Uint8List bytes, {
    SceneTextureFilter filter = SceneTextureFilter.pixelated,
  }) async {
    final image = await decodeImageFromList(bytes);
    return SceneTexture.fromImage(image, filter: filter);
  }

  final ui.Image? _image;
  final SceneTextureFilter filter;
  final int _width;
  final int _height;

  Texture2D? _gpu;
  Object? _error;
  late final Future<void> _uploadFuture;

  /// The decoded CPU image, or null for a GPU-wrapped texture.
  ui.Image? get image => _image;

  /// The pixel width of the texture (0 when unknown).
  int get width => _width;

  /// The pixel height of the texture (0 when unknown).
  int get height => _height;

  /// The uploaded GPU texture, or null until the upload finishes (or when it
  /// failed — headless tests have no rendering device).
  Texture2D? get raw => _gpu;

  /// Whether the GPU upload finished successfully.
  bool get isReady => _gpu != null;

  /// The upload error, when the GPU rejected the texture.
  Object? get error => _error;

  /// Completes when the upload attempt finishes, successfully or not.
  Future<void> get ready => _uploadFuture;

  Future<void> _upload() async {
    final image = _image;
    if (image == null) return;
    try {
      _gpu = await Texture2D.fromImage(image, sampling: _samplingOf(filter));
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  /// Releases the GPU texture. The decoded image is owned by the caller and
  /// is not disposed here.
  @override
  void dispose() {
    _gpu = null;
    super.dispose();
  }

  static TextureSampling _samplingOf(SceneTextureFilter filter) =>
      switch (filter) {
        SceneTextureFilter.pixelated => const TextureSampling(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
          mipFilter: gpu.MipFilter.nearest,
        ),
        SceneTextureFilter.linear => const TextureSampling(),
      };
}
