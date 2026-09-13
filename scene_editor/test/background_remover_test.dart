import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scene_editor/src/processing/background_remover.dart';
import 'package:scene_editor/src/processing/image_ops.dart';

void main() {
  group('detectBackground', () {
    test('finds the corner background colour', () {
      final rgb = _makeImage(8, 8, (x, y) {
        if (x >= 3 && x <= 4 && y >= 3 && y <= 4) return (255, 255, 255);
        return (255, 0, 255); // magenta background
      });

      final bg = detectBackground(rgb, 8, 8);
      expect(bg.r, 255);
      expect(bg.g, 0);
      expect(bg.b, 255);
    });
  });

  group('removeBackground', () {
    test('makes background transparent, keeps sprite interior opaque', () {
      final rgba = _makeRgba(8, 8, (x, y) {
        if (x >= 2 && x <= 5 && y >= 2 && y <= 5) return (255, 255, 255);
        return (255, 0, 255);
      });

      final out = removeBackground(
        rgba: rgba,
        w: 8,
        h: 8,
        bg: const RgbColor(255, 0, 255),
        tolerance: 0.30,
      );

      expect(_alpha(out, 8, 0, 0), 0); // corner: fully transparent
      expect(_alpha(out, 8, 2, 2), 0); // sprite edge touching bg: eroded 1px
      expect(_alpha(out, 8, 3, 3), 255); // sprite interior: opaque
      expect(_color(out, 8, 3, 3), (255, 255, 255)); // colour preserved
    });

    test('erodes the anti-aliased halo ring that tolerance cannot remove', () {
      // 10×10: magenta bg, white sprite [3..6], plus a 1px "blend" ring
      // (255,0,77) between them — 70% sprite / 30% bg. Its distance to the
      // background is 0.403 > tolerance 0.30, so a colour mask alone would
      // keep it as an opaque halo. The 1px erosion must cut it.
      final rgba = _makeRgba(10, 10, (x, y) {
        if (x >= 3 && x <= 6 && y >= 3 && y <= 6) return (255, 255, 255);
        if (x >= 2 && x <= 7 && y >= 2 && y <= 7) return (255, 0, 77);
        return (255, 0, 255);
      });

      final out = removeBackground(
        rgba: rgba,
        w: 10,
        h: 10,
        bg: const RgbColor(255, 0, 255),
        tolerance: 0.30,
      );

      // The halo ring is gone.
      expect(_alpha(out, 10, 2, 4), 0);
      expect(_alpha(out, 10, 7, 4), 0);
      expect(_alpha(out, 10, 4, 2), 0);
      expect(_alpha(out, 10, 4, 7), 0);
      // The sprite itself stays intact (it was shielded by the ring, so the
      // erosion only cut the halo, not the object).
      expect(_alpha(out, 10, 3, 4), 255);
      expect(_alpha(out, 10, 6, 4), 255);
      expect(_alpha(out, 10, 3, 3), 255);
      expect(_alpha(out, 10, 6, 6), 255);
      // The sprite interior keeps its original colour.
      expect(_color(out, 10, 4, 4), (255, 255, 255));
    });

    test('alpha is only ever 0 or 255 (no semi-transparent object parts)', () {
      final rgba = _makeRgba(8, 8, (x, y) {
        final c = (x * 17 + y * 31) % 256;
        return (255, c, 255); // various colours near the magenta bg
      });

      final out = removeBackground(
        rgba: rgba,
        w: 8,
        h: 8,
        bg: const RgbColor(255, 0, 255),
        tolerance: 0.30,
      );

      for (var i = 3; i < out.length; i += 4) {
        expect(out[i] == 0 || out[i] == 255, isTrue,
            reason: 'unexpected partial alpha ${out[i]} at byte $i');
      }
    });
  });

  group('removeBackgroundFromBytes', () {
    test('interprets tolerance as a percentage, not a fraction', () {
      // 8×8: magenta background with a white 3×3 sprite in the middle.
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final inSprite = x >= 3 && x <= 5 && y >= 3 && y <= 5;
          image.setPixelRgba(x, y, 255, inSprite ? 255 : 0, 255, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(image));

      final out = removeBackgroundFromBytes(
        bytes: bytes,
        bg: const RgbColor(255, 0, 255),
        tolerance: 30, // percent — must behave like 0.30, not 30.0
      );

      final dec = decodeImage(out);
      expect(dec.getPixel(0, 0).a.toInt(), 0); // bg removed
      expect(dec.getPixel(4, 4).a.toInt(), 255); // sprite interior kept
    });
  });
}

Uint8List _makeImage(
  int w,
  int h,
  (int, int, int) Function(int x, int y) colorAt,
) {
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = colorAt(x, y);
      final i = (y * w + x) * 3;
      rgb[i] = c.$1;
      rgb[i + 1] = c.$2;
      rgb[i + 2] = c.$3;
    }
  }
  return rgb;
}

Uint8List _makeRgba(
  int w,
  int h,
  (int, int, int) Function(int x, int y) colorAt,
) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = colorAt(x, y);
      final i = (y * w + x) * 4;
      rgba[i] = c.$1;
      rgba[i + 1] = c.$2;
      rgba[i + 2] = c.$3;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

int _alpha(Uint8List rgba, int w, int x, int y) => rgba[(y * w + x) * 4 + 3];

(int, int, int) _color(Uint8List rgba, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return (rgba[i], rgba[i + 1], rgba[i + 2]);
}
