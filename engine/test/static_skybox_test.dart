import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/src/skybox/static_skybox.dart';

/// 1×1 transparent PNG.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadSkyboxImage', () {
    test('decodes panorama bytes', () async {
      final image = await loadSkyboxImage(_pngBytes);
      expect(image, isNotNull);
      expect((image!.width, image.height), (1, 1));
      image.dispose();
    });

    test('empty bytes and garbage decode to null', () async {
      expect(await loadSkyboxImage(null), isNull);
      expect(await loadSkyboxImage(Uint8List(0)), isNull);
      expect(await loadSkyboxImage(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}
