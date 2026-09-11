import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../camera/camera_controller.dart';
import '../camera/game_camera_math.dart';

/// Decodes panorama bytes into a [ui.Image]; null for empty bytes or a
/// decoding failure. Used to preload the static skybox before it is shown so
/// the panorama never appears «дорастает» after the level is revealed.
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

/// Fraction `[0, 1)` of a full 360° rotation the panorama shows at the view
/// center for the current camera state. The game camera uses the existing
/// `skyboxRotation` (linear turn interpolation); a free camera derives the
/// heading from [CameraController.forwardH] with the same north = 1/8
/// convention (north = the center of the first panel).
double staticSkyboxRotation(CameraController controller) {
  if (controller is GameViewController) {
    return skyboxRotation(
      controller.facing,
      controller.animation,
      controller.moveProgress,
    );
  }
  final f = controller.forwardH;
  final heading = math.atan2(-f.x, -f.z);
  return ((heading + math.pi / 4) / (2 * math.pi)) % 1.0;
}

/// Static skybox: a 2D panorama drawn behind the three-dimensional scene and
/// panned as the camera turns (migration plan §3.25.3). The image is preloaded
/// by the caller ([loadSkyboxImage]); until it is ready nothing is drawn, so
/// the widget never shows a half-loaded panorama.
///
/// The image is scaled to the widget height; one scaled image width equals one
/// full 360° rotation, so the panorama tiles seamlessly. When a [fogColor] is
/// given the horizon is hazed with a vertical gradient (densest at the bottom,
/// thinning toward the zenith) matching the scene fog.
class StaticSkybox extends StatelessWidget {
  const StaticSkybox({
    super.key,
    required this.image,
    required this.rotation,
    this.fogColor,
    this.fogStrength = 0.0,
  });

  /// Preloaded panorama (null — nothing is drawn yet).
  final ui.Image? image;

  /// Pan in `[0, 1)`: the fraction of a full rotation at the view center
  /// (see [staticSkyboxRotation]).
  final double rotation;

  /// sRGB fog color, or null to leave the sky unfogged.
  final ui.Color? fogColor;

  /// Fog opacity at the horizon (0..1); fades toward the zenith.
  final double fogStrength;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: CustomPaint(
            size: Size(w, h),
            painter: _StaticSkyboxPainter(
              image: image,
              rotation: rotation,
              w: w,
              h: h,
              fogColor: fogColor,
              fogStrength: fogStrength,
            ),
          ),
        );
      },
    );
  }
}

class _StaticSkyboxPainter extends CustomPainter {
  _StaticSkyboxPainter({
    required this.image,
    required this.rotation,
    required this.w,
    required this.h,
    this.fogColor,
    this.fogStrength = 0.0,
  });

  final ui.Image? image;
  final double rotation;
  final double w;
  final double h;
  final ui.Color? fogColor;
  final double fogStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || w <= 0 || h <= 0) return;

    final aspect = img.width / img.height;
    // One full 360° rotation = one scaled image width. Never narrower than the
    // view, so a narrow image is stretched to cover instead of repeating.
    final strip = math.max(aspect, w / h) * h;
    if (strip <= 0) return;

    final cx = (((rotation % 1) + 1) % 1) * strip; // strip-x of the view center
    final dx = w / 2 - cx; // left edge of the tiled row
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;

    final kStart = ((0 - dx) / strip).floor();
    final kEnd = ((w - dx) / strip).ceil();
    for (var k = kStart; k <= kEnd; k++) {
      canvas.drawImageRect(
          img, src, Rect.fromLTWH(dx + k * strip, 0, strip, h), paint);
    }

    final fog = fogColor;
    if (fog != null && fogStrength > 0) {
      final opacityBottom = fogStrength.clamp(0.0, 1.0);
      final opacityTop = opacityBottom * 0.3;
      final shader = ui.Gradient.linear(
        Offset(0, h),
        Offset(0, 0),
        [
          fog.withValues(alpha: opacityBottom),
          fog.withValues(alpha: opacityTop),
        ],
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..shader = shader,
      );
    }
  }

  @override
  bool shouldRepaint(_StaticSkyboxPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.rotation != rotation ||
      oldDelegate.w != w ||
      oldDelegate.h != h ||
      oldDelegate.fogColor != fogColor ||
      oldDelegate.fogStrength != fogStrength;
}
