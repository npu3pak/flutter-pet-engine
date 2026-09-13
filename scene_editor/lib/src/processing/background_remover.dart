import 'dart:math';
import 'dart:typed_data';

/// An opaque RGB colour (channels 0–255).
class RgbColor {
  const RgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  factory RgbColor.fromRecord((int, int, int) record) =>
      RgbColor(record.$1, record.$2, record.$3);

  int toArgb32() => (0xFF << 24) | (r << 16) | (g << 8) | b;

  String toHex() =>
      '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is RgbColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'RgbColor($r, $g, $b)';
}

const _maxDist = 441.67295593; // sqrt(3 * 255^2)

double _colourDist((int, int, int) c1, (int, int, int) c2) {
  final dr = c1.$1 - c2.$1;
  final dg = c1.$2 - c2.$2;
  final db = c1.$3 - c2.$3;
  return sqrt(dr * dr + dg * dg + db * db) / _maxDist;
}

bool _matches((int, int, int) px, (int, int, int) ref, double tol) =>
    _colourDist(px, ref) <= tol;

// ---------------------------------------------------------------------------
// Background detection (port of scripts/remove_background.py)
// ---------------------------------------------------------------------------

(int, int, int) _px(Uint8List rgb, int w, int x, int y) {
  final i = (y * w + x) * 3;
  return (rgb[i], rgb[i + 1], rgb[i + 2]);
}

/// Average of the 3×3 blocks at each of the four corners.
(int, int, int) _sampleCorners(Uint8List rgb, int w, int h) {
  var r = 0, g = 0, b = 0, n = 0;
  for (final (cx, cy) in [(0, 0), (w - 3, 0), (0, h - 3), (w - 3, h - 3)]) {
    for (var dy = 0; dy < 3; dy++) {
      for (var dx = 0; dx < 3; dx++) {
        final x = min(max(cx + dx, 0), w - 1);
        final y = min(max(cy + dy, 0), h - 1);
        final p = _px(rgb, w, x, y);
        r += p.$1;
        g += p.$2;
        b += p.$3;
        n++;
      }
    }
  }
  return (r ~/ n, g ~/ n, b ~/ n);
}

List<(int, int, int)> _perimeterPixels(Uint8List rgb, int w, int h) {
  final result = <(int, int, int)>[];
  for (var x = 0; x < w; x++) {
    result.add(_px(rgb, w, x, 0));
    result.add(_px(rgb, w, x, h - 1));
  }
  for (var y = 1; y < h - 1; y++) {
    result.add(_px(rgb, w, 0, y));
    result.add(_px(rgb, w, w - 1, y));
  }
  return result;
}

/// Cluster perimeter pixels; return the centre of the largest cluster.
(int, int, int) _dominantPerimeter(Uint8List rgb, int w, int h) {
  final perimeter = _perimeterPixels(rgb, w, h);
  if (perimeter.isEmpty) return (0, 0, 0);

  const clusterTol = 0.05;
  final step = max(1, perimeter.length ~/ 300);
  var best = 0;
  var bestCol = (0, 0, 0);
  for (var i = 0; i < perimeter.length; i += step) {
    final cand = perimeter[i];
    var cnt = 0;
    for (final p in perimeter) {
      if (_matches(p, cand, clusterTol)) cnt++;
    }
    if (cnt > best) {
      best = cnt;
      bestCol = cand;
    }
  }
  return bestCol;
}

/// Detect the background colour from a 3-channel (RGB) byte buffer.
RgbColor detectBackground(Uint8List rgb, int w, int h) {
  final corner = _sampleCorners(rgb, w, h);
  final perimeter = _dominantPerimeter(rgb, w, h);

  if (_matches(corner, perimeter, 0.08)) return RgbColor.fromRecord(corner);

  final periPx = _perimeterPixels(rgb, w, h);
  var matches = 0;
  for (final p in periPx) {
    if (_matches(p, perimeter, 0.05)) matches++;
  }
  if (matches / max(periPx.length, 1) > 0.30) {
    return RgbColor.fromRecord(perimeter);
  }
  return RgbColor.fromRecord(perimeter);
}

// ---------------------------------------------------------------------------
// Background removal (hard mask + 1px edge erosion)
// ---------------------------------------------------------------------------

/// Flatten the alpha channel onto white, mirroring remove_background.py
/// (which pastes RGBA onto a white background before chroma-keying).
Uint8List flattenToWhiteRgb(Uint8List rgba) {
  final rgb = Uint8List((rgba.length ~/ 4) * 3);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
    final a = rgba[i + 3] / 255.0;
    rgb[o] = (rgba[i] * a + 255 * (1 - a)).round();
    rgb[o + 1] = (rgba[i + 1] * a + 255 * (1 - a)).round();
    rgb[o + 2] = (rgba[i + 2] * a + 255 * (1 - a)).round();
  }
  return rgb;
}

/// Remove the background of an RGBA image by colour matching against [bg].
///
/// 1. A hard mask: a pixel becomes transparent when its colour distance to
///    [bg] is within [tolerance] (0–1). Interior pixels are therefore either
///    fully removed or fully opaque — they never turn semi-transparent.
/// 2. A 1px erosion of the surviving content: every pixel adjacent to a
///    fully-transparent pixel is also made transparent. This cuts the thin
///    anti-aliased "halo" ring that colour-distance keying alone cannot
///    remove (edge pixels are sprite/background blends with a colour too far
///    from the background for the mask, yet tinted enough to be visible).
///
/// The sprite is shrunk by ~1px with a clean hard edge. Output keeps the
/// original colours of surviving pixels.
Uint8List removeBackground({
  required Uint8List rgba,
  required int w,
  required int h,
  required RgbColor bg,
  required double tolerance,
}) {
  final rgb = flattenToWhiteRgb(rgba);
  final bgRec = (bg.r, bg.g, bg.b);

  // Hard mask (0 or 255).
  final mask = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final px = (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]);
    mask[i] = _colourDist(px, bgRec) <= tolerance ? 0 : 255;
  }

  // 1px erosion of the outer ring.
  final eroded = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      final touchesBg = (x > 0 && mask[i - 1] == 0) ||
          (x < w - 1 && mask[i + 1] == 0) ||
          (y > 0 && mask[i - w] == 0) ||
          (y < h - 1 && mask[i + w] == 0);
      eroded[i] = touchesBg ? 0 : 255;
    }
  }

  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    out[o] = rgba[o];
    out[o + 1] = rgba[o + 1];
    out[o + 2] = rgba[o + 2];
    out[o + 3] = eroded[i];
  }
  return out;
}
