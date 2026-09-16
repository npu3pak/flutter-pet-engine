import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

Future<ui.Image> _solid(int width, int height, ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  group('composeSpriteAtlas', () {
    test('lays out one row of 256px cells and reports resolved keys', () async {
      final composed = await composeSpriteAtlas([
        'a',
        'b',
      ], (key) => _solid(key == 'a' ? 10 : 40, 20, const ui.Color(0xFFFF0000)));

      expect(composed, isNotNull);
      expect(composed!.keys, ['a', 'b']);
      expect(composed.image.width, 512);
      expect(composed.image.height, 256);
      composed.image.dispose();
    });

    test('skips keys the loader cannot resolve', () async {
      final composed = await composeSpriteAtlas(['ok', 'missing'], (key) async {
        if (key == 'missing') throw StateError('no asset');
        return _solid(8, 8, const ui.Color(0xFF00FF00));
      });

      expect(composed, isNotNull);
      expect(composed!.keys, ['ok']);
      expect(composed.image.width, 256);
      composed.image.dispose();
    });

    test('returns null when nothing resolves', () async {
      final composed = await composeSpriteAtlas([
        'a',
        'b',
      ], (key) => throw StateError('no asset'));
      expect(composed, isNull);
    });

    test('honours a custom cell size', () async {
      final composed = await composeSpriteAtlas(
        ['a', 'b', 'c'],
        (key) => _solid(4, 4, const ui.Color(0xFF0000FF)),
        cellSize: 32,
      );
      expect(composed!.image.width, 96);
      expect(composed.image.height, 32);
      composed.image.dispose();
    });

    test('wraps into rows beyond maxWidth (GPU width limit)', () async {
      final composed = await composeSpriteAtlas(
        ['a', 'b', 'c'],
        (key) => _solid(4, 4, const ui.Color(0xFF00FFFF)),
        cellSize: 32,
        maxWidth: 64,
      );
      expect(composed, isNotNull);
      expect(composed!.columns, 2);
      expect(composed.rows, 2);
      expect(composed.image.width, 64);
      expect(composed.image.height, 64);
      composed.image.dispose();
    });

    test('a single row stays a single row without maxWidth', () async {
      final composed = await composeSpriteAtlas(
        ['a', 'b', 'c'],
        (key) => _solid(4, 4, const ui.Color(0xFF00FFFF)),
        cellSize: 32,
      );
      expect(composed!.columns, 3);
      expect(composed.rows, 1);
      composed.image.dispose();
    });
  });

  group('spriteFrameMap', () {
    test('maps semantic keys by asset path, not by atlas position', () {
      final frames = spriteFrameMap(
        const [
          (key: 'fog_1', path: 'assets/fog_1.png'),
          (key: 'fog_2', path: 'assets/fog_2.png'),
        ],
        const ['assets/fog_2.png', 'assets/fog_1.png'],
      );
      expect(frames, {'fog_2': 0, 'fog_1': 1});
    });

    test('skips sprites whose path did not resolve', () {
      final frames = spriteFrameMap(
        const [
          (key: 'ok', path: 'assets/ok.png'),
          (key: 'lost', path: 'assets/lost.png'),
        ],
        const ['assets/ok.png'],
      );
      expect(frames, {'ok': 0});
    });

    test('an empty atlas or sprite list gives an empty map', () {
      expect(spriteFrameMap(const [], const []), isEmpty);
      expect(
        spriteFrameMap(const [(key: 'a', path: 'a.png')], const []),
        isEmpty,
      );
    });
  });
}
