import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scene_editor/src/processing/image_ops.dart';

void main() {
  group('alignFromBytes', () {
    test('bottom: moves content down until the lowest pixel hits the bottom',
        () {
      final bytes = _boxPng(8, 8, x0: 4, y0: 1, x1: 4, y1: 4);
      final out = alignFromBytes(bytes, AlignTarget.bottom);
      final dec = decodeImage(out);

      expect(dec.getPixel(4, 7).a.toInt(), 255); // was row 4
      expect(dec.getPixel(4, 4).a.toInt(), 255); // was row 1
      expect(dec.getPixel(4, 3).a.toInt(), 0); // vacated (was row 0)
      expect(dec.getPixel(4, 0).a.toInt(), 0); // vacated
      expect(dec.getPixel(0, 7).a.toInt(), 0); // nothing else appears
    });

    test('top: moves content up until the topmost pixel hits the top', () {
      final bytes = _boxPng(8, 8, x0: 4, y0: 1, x1: 4, y1: 4);
      final out = alignFromBytes(bytes, AlignTarget.top);
      final dec = decodeImage(out);

      expect(dec.getPixel(4, 0).a.toInt(), 255); // was row 1
      expect(dec.getPixel(4, 3).a.toInt(), 255); // was row 4
      expect(dec.getPixel(4, 4).a.toInt(), 0); // vacated
      expect(dec.getPixel(4, 7).a.toInt(), 0); // vacated
      expect(dec.getPixel(0, 0).a.toInt(), 0); // nothing else appears
    });

    test('left: moves content left until the leftmost pixel hits the left edge',
        () {
      final bytes = _boxPng(8, 8, x0: 4, y0: 1, x1: 4, y1: 4);
      final out = alignFromBytes(bytes, AlignTarget.left);
      final dec = decodeImage(out);

      expect(dec.getPixel(0, 2).a.toInt(), 255); // was column 4
      expect(dec.getPixel(4, 2).a.toInt(), 0); // vacated
      expect(dec.getPixel(7, 2).a.toInt(), 0); // vacated
      expect(dec.getPixel(0, 0).a.toInt(), 0); // nothing else appears
    });

    test(
        'right: moves content right until the rightmost pixel hits the '
        'right edge', () {
      final bytes = _boxPng(8, 8, x0: 4, y0: 1, x1: 4, y1: 4);
      final out = alignFromBytes(bytes, AlignTarget.right);
      final dec = decodeImage(out);

      expect(dec.getPixel(7, 2).a.toInt(), 255); // was column 4
      expect(dec.getPixel(4, 2).a.toInt(), 0); // vacated
      expect(dec.getPixel(0, 2).a.toInt(), 0); // vacated
      expect(dec.getPixel(7, 0).a.toInt(), 0); // nothing else appears
    });

    test('center: centers the content with equal margins on both axes', () {
      final bytes = _boxPng(8, 8, x0: 1, y0: 1, x1: 2, y1: 2);
      final out = alignFromBytes(bytes, AlignTarget.center);
      final dec = decodeImage(out);

      expect(dec.getPixel(3, 3).a.toInt(), 255); // was (1, 1)
      expect(dec.getPixel(4, 4).a.toInt(), 255); // was (2, 2)
      expect(dec.getPixel(1, 1).a.toInt(), 0); // vacated
      expect(dec.getPixel(0, 3).a.toInt(), 0); // left margin empty
      expect(dec.getPixel(5, 3).a.toInt(), 0); // right margin empty
      expect(dec.getPixel(3, 0).a.toInt(), 0); // top margin empty
      expect(dec.getPixel(3, 5).a.toInt(), 0); // bottom margin empty
    });

    test('already aligned is a no-op (same bytes)', () {
      final bottom = _boxPng(8, 8, x0: 4, y0: 6, x1: 4, y1: 7);
      expect(identical(alignFromBytes(bottom, AlignTarget.bottom), bottom),
          isTrue);

      final top = _boxPng(8, 8, x0: 4, y0: 0, x1: 4, y1: 2);
      expect(identical(alignFromBytes(top, AlignTarget.top), top), isTrue);

      final left = _boxPng(8, 8, x0: 0, y0: 1, x1: 2, y1: 1);
      expect(identical(alignFromBytes(left, AlignTarget.left), left), isTrue);

      final right = _boxPng(8, 8, x0: 6, y0: 1, x1: 7, y1: 1);
      expect(identical(alignFromBytes(right, AlignTarget.right), right),
          isTrue);

      final centered = _boxPng(7, 7, x0: 3, y0: 3, x1: 3, y1: 3);
      expect(identical(alignFromBytes(centered, AlignTarget.center), centered),
          isTrue);
    });

    test('fully transparent is a no-op for every target', () {
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      final bytes = Uint8List.fromList(img.encodePng(image));
      for (final target in AlignTarget.values) {
        expect(identical(alignFromBytes(bytes, target), bytes), isTrue,
            reason: '$target');
      }
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
