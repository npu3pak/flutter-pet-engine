import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Visual-test screenshots as an engine feature (migration plan 13.8): games
/// capture their viewport in-process — no OS screenshot API — write PNG and
/// a JSON sidecar next to it, and can check the frame for placeholder colors.
///
/// The capture path is the same one the engine example uses: a
/// [RenderRepaintBoundary] around the scene is rasterized through
/// `toImage`, which works on desktop without `screencapture` and on hidden
/// windows (the last painted frame is used when no new frame arrives).

/// Captures the area marked by [boundaryKey] as PNG bytes. Null when the
/// boundary is not mounted or rasterization fails.
Future<Uint8List?> captureBoundary(
  GlobalKey boundaryKey,
  double pixelRatio,
) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  WidgetsBinding.instance.scheduleFrame();
  try {
    // A hidden or occluded window may never get a frame: take the last
    // painted layer instead of waiting forever.
    await WidgetsBinding.instance.endOfFrame
        .timeout(const Duration(seconds: 5));
  } on TimeoutException {
    // No frame arrived — capture what is already painted.
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Writes `name.png` plus the `name.json` sidecar (the frame's metadata) into
/// [dir] and returns the PNG path. The directory is created when missing.
Future<String> saveScreenshot(
  Directory dir,
  String name,
  Uint8List pngBytes,
  Map<String, Object?> meta,
) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(pngBytes, flush: true);
  final data = <String, Object?>{'name': name, 'file': file.path, ...meta};
  final sidecar = File('${dir.path}/$name.json');
  await sidecar.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
    flush: true,
  );
  return file.path;
}

/// Pixel statistics of a captured frame: how many sampled pixels look like
/// the missing-resource fuchsia or the neutral gray placeholder.
class PlaceholderReport {
  const PlaceholderReport({
    required this.sampled,
    required this.fuchsia,
    required this.gray,
  });

  /// Number of sampled pixels (the analyzer samples evenly, not every pixel).
  final int sampled;

  /// Sampled pixels close to fuchsia `(1, 0, 1)` — a lost resource.
  final int fuchsia;

  /// Sampled neutral-gray pixels — likely the `0.78` not-loaded placeholder,
  /// but real gray textures trigger it too (heuristic).
  final int gray;

  bool get hasFuchsia => fuchsia > 0;
  bool get hasGray => gray > 0;

  Map<String, Object?> toJson() => {
        'sampled': sampled,
        'fuchsia': fuchsia,
        'gray': gray,
      };

  @override
  String toString() =>
      'pixels=$sampled fuchsia=$fuchsia gray=$gray';
}

/// Analyzes a PNG frame for placeholder colors. Returns null when the bytes
/// are not decodable.
///
/// [fuchsiaTolerance] is the max distance (0..255) from `(255, 0, 255)` for a
/// pixel to count as fuchsia. Gray is a neutral pixel (`|r-g|`, `|g-b|` within
/// [grayNeutralTolerance]) whose value lies in `[grayMin, grayMax]` — the
/// heuristic band around the sRGB rendering of the `0.78` placeholder; real
/// gray textures also land there, so treat it as a hint, not a hard failure.
Future<PlaceholderReport?> analyzePlaceholders(
  Uint8List pngBytes, {
  int fuchsiaTolerance = 60,
  int grayMin = 180,
  int grayMax = 250,
  int grayNeutralTolerance = 8,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final w = image.width, h = image.height;
      final total = w * h;
      final stride = (total / 200000).ceil().clamp(1, 1024);
      var sampled = 0, fuchsia = 0, gray = 0;
      for (var y = 0; y < h; y += stride) {
        final row = y * w * 4;
        for (var x = 0; x < w; x += stride) {
          final i = row + x * 4;
          final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
          sampled++;
          if ((r - 255).abs() <= fuchsiaTolerance &&
              g <= fuchsiaTolerance &&
              (b - 255).abs() <= fuchsiaTolerance) {
            fuchsia++;
            continue;
          }
          if ((r - g).abs() <= grayNeutralTolerance &&
              (g - b).abs() <= grayNeutralTolerance &&
              r >= grayMin &&
              r <= grayMax) {
            gray++;
          }
        }
      }
      return PlaceholderReport(
        sampled: sampled,
        fuchsia: fuchsia,
        gray: gray,
      );
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// How "filled" a captured frame is: the share of sampled pixels that differ
/// from the frame's dominant (background) color. A black/empty frame scores
/// near 0; a real scene scores well above it. Used by the automated visual
/// test as a safety net against scenes that stop rendering (a regression the
/// placeholder-color check alone cannot see).
class FrameContentReport {
  const FrameContentReport({
    required this.sampled,
    required this.content,
    required this.background,
  });

  final int sampled;

  /// Share of sampled pixels unlike [background], 0..1.
  final double content;

  /// The dominant color `(r, g, b)`.
  final (int, int, int) background;

  Map<String, Object?> toJson() => {
        'content': content,
        'contentBackground': [background.$1, background.$2, background.$3],
      };

  @override
  String toString() =>
      'content=${content.toStringAsFixed(3)} background=${background.$1},'
      '${background.$2},${background.$3}';
}

/// Analyzes the frame's content share (see [FrameContentReport]). Pixels are
/// quantized into 16-value buckets to find the dominant color, then counted
/// as content when any channel differs from the bucket's center by more than
/// [tolerance]. Returns null when the bytes are not decodable.
Future<FrameContentReport?> analyzeFrameContent(
  Uint8List pngBytes, {
  int tolerance = 24,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final w = image.width, h = image.height;
      final total = w * h;
      final stride = (total / 200000).ceil().clamp(1, 1024);

      // Pass 1: histogram of 16-value color buckets.
      final buckets = <int, int>{};
      final samples = <int>[];
      for (var y = 0; y < h; y += stride) {
        final row = y * w * 4;
        for (var x = 0; x < w; x += stride) {
          final i = row + x * 4;
          final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
          final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
          buckets[key] = (buckets[key] ?? 0) + 1;
          samples.add(key);
        }
      }
      if (buckets.isEmpty) return null;
      var modalKey = 0, modalCount = 0;
      for (final e in buckets.entries) {
        if (e.value > modalCount) {
          modalKey = e.key;
          modalCount = e.value;
        }
      }
      final br = ((modalKey >> 8) & 0xF) * 16 + 8;
      final bg = ((modalKey >> 4) & 0xF) * 16 + 8;
      final bb = (modalKey & 0xF) * 16 + 8;
      // Pass 2: share of samples unlike the modal bucket's center.
      var content = 0;
      for (final key in samples) {
        final r = ((key >> 8) & 0xF) * 16 + 8;
        final g = ((key >> 4) & 0xF) * 16 + 8;
        final b = (key & 0xF) * 16 + 8;
        if ((r - br).abs() > tolerance ||
            (g - bg).abs() > tolerance ||
            (b - bb).abs() > tolerance) {
          content++;
        }
      }
      return FrameContentReport(
        sampled: samples.length,
        content: samples.isEmpty ? 0 : content / samples.length,
        background: (br, bg, bb),
      );
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}
