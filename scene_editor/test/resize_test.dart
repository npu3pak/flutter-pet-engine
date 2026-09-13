import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scene_editor/src/processing/image_ops.dart';

void main() {
  group('resizeNearestFromBytes', () {
    test('scales up by duplicating pixels (no blending)', () {
      final src = img.Image(width: 2, height: 2, numChannels: 4);
      src.setPixelRgb(0, 0, 255, 0, 0);
      src.setPixelRgb(1, 0, 0, 255, 0);
      src.setPixelRgb(0, 1, 0, 0, 255);
      src.setPixelRgb(1, 1, 255, 255, 0);

      final bytes = Uint8List.fromList(img.encodePng(src));
      final resized =
          resizeNearestFromBytes(bytes: bytes, width: 4, height: 4);
      final dec = decodeImage(resized);

      expect(dec.width, 4);
      expect(dec.height, 4);

      // Each 2×2 block must be an exact copy of its source pixel.
      expect(_px(dec, 0, 0), (255, 0, 0));
      expect(_px(dec, 1, 0), (255, 0, 0));
      expect(_px(dec, 0, 1), (255, 0, 0));
      expect(_px(dec, 3, 0), (0, 255, 0));
      expect(_px(dec, 0, 3), (0, 0, 255));
      expect(_px(dec, 3, 3), (255, 255, 0));
      expect(_px(dec, 2, 2), (255, 255, 0));
    });

    test('preserves alpha channel', () {
      final src = img.Image(width: 1, height: 1, numChannels: 4);
      src.setPixelRgba(0, 0, 10, 20, 30, 128);

      final bytes = Uint8List.fromList(img.encodePng(src));
      final resized =
          resizeNearestFromBytes(bytes: bytes, width: 64, height: 64);
      final dec = decodeImage(resized);

      final p = dec.getPixel(32, 32);
      expect(p.r.toInt(), 10);
      expect(p.g.toInt(), 20);
      expect(p.b.toInt(), 30);
      expect(p.a.toInt(), 128);
    });
  });

  group('resizeContainFromBytes', () {
    Uint8List makePng(int w, int h) =>
        Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

    test('fits inside the box keeping the aspect ratio', () {
      // 400×200 (2:1) into a 256×256 box → 256×128.
      final out = decodeImage(resizeContainFromBytes(
        bytes: makePng(400, 200),
        maxWidth: 256,
        maxHeight: 256,
      ));
      expect(out.width, 256);
      expect(out.height, 128);
    });

    test('exact fit stays exact', () {
      final out = decodeImage(resizeContainFromBytes(
        bytes: makePng(200, 100),
        maxWidth: 200,
        maxHeight: 100,
      ));
      expect(out.width, 200);
      expect(out.height, 100);
    });

    test('tall image limits by height', () {
      final out = decodeImage(resizeContainFromBytes(
        bytes: makePng(100, 200),
        maxWidth: 100,
        maxHeight: 200,
      ));
      expect(out.width, 100);
      expect(out.height, 200);
    });

    test('smaller target shrinks proportionally on the limiting axis', () {
      final out = decodeImage(resizeContainFromBytes(
        bytes: makePng(400, 200),
        maxWidth: 100,
        maxHeight: 200,
      ));
      // scale = min(100/400, 200/200) = 0.25 → 100×50.
      expect(out.width, 100);
      expect(out.height, 50);
    });

    test('never produces a zero dimension', () {
      final out = decodeImage(resizeContainFromBytes(
        bytes: makePng(400, 200),
        maxWidth: 1,
        maxHeight: 1,
      ));
      expect(out.width, 1);
      expect(out.height, 1);
    });
  });

  group('resizeCoverFromBytes', () {
    Uint8List makePng(int w, int h) =>
        Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

    test('fills the box and center-crops the excess', () {
      // 400×200 (2:1) into 256×256: scale by height (256/200=1.28) →
      // 512×256 → center crop to 256×256.
      final out = decodeImage(resizeCoverFromBytes(
        bytes: makePng(400, 200),
        width: 256,
        height: 256,
      ));
      expect(out.width, 256);
      expect(out.height, 256);
    });

    test('exact fit stays exact', () {
      final out = decodeImage(resizeCoverFromBytes(
        bytes: makePng(200, 100),
        width: 200,
        height: 100,
      ));
      expect(out.width, 200);
      expect(out.height, 100);
    });

    test('tall source into a wide box crops top/bottom', () {
      final out = decodeImage(resizeCoverFromBytes(
        bytes: makePng(100, 200),
        width: 200,
        height: 100,
      ));
      expect(out.width, 200);
      expect(out.height, 100);
    });
  });
}

(int, int, int) _px(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return (p.r.toInt(), p.g.toInt(), p.b.toInt());
}
