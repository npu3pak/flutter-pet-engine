import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_engine/pet_engine.dart';

Uint8List _png(int w, int h, void Function(img.Image im) draw) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  draw(image);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('analyzePlaceholders counts fuchsia and neutral gray pixels', () async {
    final bytes = _png(20, 20, (im) {
      img.fill(im, color: img.ColorRgba8(30, 120, 30, 255));
      img.fillRect(im, x1: 0, y1: 0, x2: 4, y2: 4,
          color: img.ColorRgba8(255, 0, 255, 255));
      img.fillRect(im, x1: 10, y1: 10, x2: 14, y2: 14,
          color: img.ColorRgba8(210, 210, 210, 255));
    });
    final report = await analyzePlaceholders(bytes);
    expect(report, isNotNull);
    expect(report!.sampled, 400);
    expect(report.fuchsia, 25);
    expect(report.gray, 25);
    expect(report.hasFuchsia, isTrue);
  });

  test('a clean frame has no placeholder pixels', () async {
    final bytes = _png(16, 16, (im) {
      img.fill(im, color: img.ColorRgba8(30, 120, 30, 255));
    });
    final report = await analyzePlaceholders(bytes);
    expect(report, isNotNull);
    expect(report!.fuchsia, 0);
    expect(report.gray, 0);
  });

  test('undecodable bytes return null', () async {
    final report = await analyzePlaceholders(Uint8List.fromList([1, 2, 3]));
    expect(report, isNull);
  });

  test('saveScreenshot writes the PNG and the sidecar', () async {
    final dir = await Directory.systemTemp.createTemp('pet_shot_test');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = _png(4, 4, (im) {
      img.fill(im, color: img.ColorRgba8(1, 2, 3, 255));
    });
    final path = await saveScreenshot(dir, 'frame', bytes, {'biome': 'streets'});
    expect(File(path).existsSync(), isTrue);
    final sidecar = File('${dir.path}/frame.json');
    expect(sidecar.existsSync(), isTrue);
    expect(await sidecar.readAsString(), contains('streets'));
  });

  test('analyzeFrameContent: a black frame is empty', () async {
    final bytes = _png(32, 32, (im) {
      img.fill(im, color: img.ColorRgba8(0, 0, 0, 255));
    });
    final report = await analyzeFrameContent(bytes);
    expect(report, isNotNull);
    expect(report!.content, lessThan(0.02));
    expect(report.background, (8, 8, 8));
  });

  test('analyzeFrameContent: a half-filled frame reports about half', () async {
    final bytes = _png(32, 32, (im) {
      img.fill(im, color: img.ColorRgba8(0, 0, 0, 255));
      img.fillRect(im, x1: 0, y1: 0, x2: 31, y2: 15,
          color: img.ColorRgba8(220, 210, 200, 255));
    });
    final report = await analyzeFrameContent(bytes);
    expect(report, isNotNull);
    expect(report!.content, closeTo(0.5, 0.1));
  });

  test('analyzeFrameContent: undecodable bytes return null', () async {
    expect(await analyzeFrameContent(Uint8List.fromList([9, 9])), isNull);
  });
}
