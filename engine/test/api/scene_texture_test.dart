import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

Future<ui.Image> _makeImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromImage exposes size and filter without a GPU', () async {
    final image = await _makeImage(4, 3);
    final texture = SceneTexture.fromImage(image);
    expect(texture.width, 4);
    expect(texture.height, 3);
    expect(texture.filter, SceneTextureFilter.pixelated);

    await texture.ready;
    if (texture.raw == null) {
      expect(texture.error, isNotNull);
    } else {
      expect(texture.isReady, isTrue);
    }
    texture.dispose();
    image.dispose();
  });

  test('fromBytes decodes PNG bytes', () async {
    final image = await _makeImage(2, 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final texture = await SceneTexture.fromBytes(bytes!.buffer.asUint8List());
    expect(texture.width, 2);
    expect(texture.height, 2);
    expect(texture.filter, SceneTextureFilter.pixelated);
    await texture.ready;
    texture.dispose();
  });

  test('linear filter is preserved', () async {
    final image = await _makeImage(1, 1);
    final texture = SceneTexture.fromImage(
      image,
      filter: SceneTextureFilter.linear,
    );
    expect(texture.filter, SceneTextureFilter.linear);
    await texture.ready;
    texture.dispose();
    image.dispose();
  });
}
