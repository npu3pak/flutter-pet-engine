import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scene_editor/src/processing/image_ops.dart';

void main() {
  group('trimAndPadFromBytes', () {
    test('crops empty borders and adds the requested padding on each side',
        () {
      // 12×10 canvas, content occupies columns 2..6 and rows 1..4.
      final bytes = _boxPng(12, 10, x0: 2, y0: 1, x1: 6, y1: 4);
      final out = trimAndPadFromBytes(
        bytes: bytes,
        left: 3,
        top: 2,
        right: 1,
        bottom: 4,
      );
      final dec = decodeImage(out);

      // Content is 5×4; canvas = 3+5+1 × 2+4+4 = 9×10.
      expect(dec.width, 9);
      expect(dec.height, 10);

      // Content corner lands at (left, top) = (3, 2).
      expect(dec.getPixel(3, 2).a.toInt(), 255);
      expect(dec.getPixel(7, 5).a.toInt(), 255);
      expect(dec.getPixel(2, 2).a.toInt(), 0); // left margin
      expect(dec.getPixel(8, 2).a.toInt(), 0); // right margin
      expect(dec.getPixel(3, 0).a.toInt(), 0); // top margin
      expect(dec.getPixel(3, 9).a.toInt(), 0); // bottom margin
    });

    test('zero padding is a pure crop to the content bounds', () {
      final bytes = _boxPng(16, 16, x0: 4, y0: 5, x1: 10, y1: 7);
      final out = trimAndPadFromBytes(
        bytes: bytes,
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
      );
      final dec = decodeImage(out);

      expect(dec.width, 7); // 10 - 4 + 1
      expect(dec.height, 3); // 7 - 5 + 1
      expect(dec.getPixel(0, 0).a.toInt(), 255);
      expect(dec.getPixel(6, 2).a.toInt(), 255);
    });

    test('preserves colours and alpha of the content', () {
      final image = img.Image(width: 6, height: 6, numChannels: 4);
      image.setPixelRgba(3, 2, 10, 20, 30, 128); // AA-edge pixel
      image.setPixelRgba(4, 2, 255, 0, 0, 255);
      final bytes = Uint8List.fromList(img.encodePng(image));

      final out = decodeImage(trimAndPadFromBytes(
        bytes: bytes,
        left: 1,
        top: 1,
        right: 1,
        bottom: 1,
      ));

      expect(out.width, 4); // 1 + 2 + 1
      expect(out.height, 3); // 1 + 1 + 1
      final p = out.getPixel(1, 1);
      expect(p.r.toInt(), 10);
      expect(p.g.toInt(), 20);
      expect(p.b.toInt(), 30);
      expect(p.a.toInt(), 128);
      expect(out.getPixel(2, 1).r.toInt(), 255);
    });

    test('margins already matching the request are a no-op (same bytes)', () {
      // Content columns 2..5, rows 1..3 → left 2, top 1, right 2, bottom 2.
      final bytes = _boxPng(8, 6, x0: 2, y0: 1, x1: 5, y1: 3);
      expect(
        identical(
          trimAndPadFromBytes(
            bytes: bytes,
            left: 2,
            top: 1,
            right: 2,
            bottom: 2,
          ),
          bytes,
        ),
        isTrue,
      );
    });

    test('fully transparent is a no-op (same bytes)', () {
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      final bytes = Uint8List.fromList(img.encodePng(image));
      expect(
        identical(
          trimAndPadFromBytes(
            bytes: bytes,
            left: 4,
            top: 4,
            right: 4,
            bottom: 4,
          ),
          bytes,
        ),
        isTrue,
      );
    });
  });
}

/// Fills the inclusive rectangle (x0,y0)-(x1,y1) with opaque white.
Uint8List _boxPng(
  int w,
  int h, {
  required int x0,
  required int y0,
  required int x1,
  required int y1,
}) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      image.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
