import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes panorama bytes into a [ui.Image]; null for empty bytes or a
/// decoding failure. Used to preload the skybox before it is shown so the
/// panorama never appears «дорастает» after the level is revealed.
Future<ui.Image?> loadSkyboxImage(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}
