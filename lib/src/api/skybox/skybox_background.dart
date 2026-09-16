import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controllers/camera_controller.dart';
import '../controllers/camera_types.dart';
import '../controllers/first_person_camera_controller.dart';
import '../nodes/skybox_node.dart';

/// Fraction `[0, 1)` of a full 360° rotation the sky shows at the view
/// center for [camera]: a first-person camera uses its deterministic
/// facing/turn state, any other camera derives the heading from its forward
/// direction (north = the center of the first panel = 1/8).
double skyRotationFor(CameraController camera) {
  if (camera is FirstPersonCameraController) {
    final center =
        camera.facing.index +
        0.5 +
        switch (camera.animation) {
          AnimationType.turnLeft => camera.moveProgress,
          AnimationType.turnRight => -camera.moveProgress,
          _ => 0.0,
        };
    return (center / 4) % 1.0;
  }
  final forward = camera.forwardH;
  final heading = math.atan2(-forward.x, -forward.z);
  return ((heading + math.pi / 4) / (2 * math.pi)) % 1.0;
}

/// The 2D sky drawn behind the scene: the background color plus the layers of
/// a [SkyboxNode] (gradient, panoramas, clouds, stars, sun/moon).
///
/// The sky follows the active camera when [SkyboxNode.followCamera] is on:
/// a first-person camera uses its deterministic facing/turn state, any other
/// camera derives the heading from its forward direction. Clouds scroll with
/// time. The scene covers the sky, so caves and interiors look right.
class SkyboxBackground extends StatefulWidget {
  const SkyboxBackground({super.key, required this.node, required this.camera});

  /// The sky node whose layers are drawn.
  final SkyboxNode node;

  /// The camera the sky follows.
  final CameraController camera;

  @override
  State<SkyboxBackground> createState() => _SkyboxBackgroundState();
}

class _SkyboxBackgroundState extends State<SkyboxBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _rotation = 0;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _rotation = _cameraRotation();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(SkyboxBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.camera, widget.camera) ||
        !identical(oldWidget.node, widget.node)) {
      _rotation = _cameraRotation();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    _time = elapsed.inMicroseconds / 1000000.0;
    final rotation = widget.node.followCamera
        ? _cameraRotation()
        : widget.node.skyRotation;
    final hasMotion = widget.node.layers.whereType<SkyboxCloudsLayer>().any(
      (l) => l.visible,
    );
    if (hasMotion || (rotation - _rotation).abs() > 1e-4) {
      setState(() => _rotation = rotation);
    }
  }

  double _cameraRotation() => skyRotationFor(widget.camera);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        size: Size.infinite,
        painter: _SkyboxPainter(
          node: widget.node,
          rotation: _rotation,
          time: _time,
        ),
      ),
    );
  }
}

class _SkyboxPainter extends CustomPainter {
  _SkyboxPainter({
    required this.node,
    required this.rotation,
    required this.time,
  });

  final SkyboxNode node;
  final double rotation;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = node.backgroundColor,
    );
    for (final layer in node.layers) {
      if (!layer.visible || layer.opacity <= 0) continue;
      switch (layer) {
        case SkyboxColorLayer():
          _paintColor(canvas, w, h, layer);
        case SkyboxImageLayer():
          _paintImage(canvas, w, h, layer);
        case SkyboxCloudsLayer():
          _paintClouds(canvas, w, h, layer);
        case SkyboxStarsLayer():
          _paintStars(canvas, w, h, layer);
        case SkyboxBodyLayer():
          _paintBody(canvas, w, h, layer);
      }
    }
  }

  void _paintColor(Canvas canvas, double w, double h, SkyboxColorLayer layer) {
    final top = layer.topColor.withValues(
      alpha: layer.topColor.a * layer.opacity,
    );
    final bottom = layer.bottomColor.withValues(
      alpha: layer.bottomColor.a * layer.opacity,
    );
    final shader = ui.Gradient.linear(Offset(0, 0), Offset(0, h), [
      top,
      bottom,
    ]);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
  }

  void _paintImage(Canvas canvas, double w, double h, SkyboxImageLayer layer) {
    final img = layer.image;
    final aspect = img.width / img.height;
    final strip = math.max(aspect, w / h) * h;
    if (strip <= 0) return;

    final turn = ((rotation + layer.offset) % 1 + 1) % 1;
    final cx = turn * strip;
    final dx = w / 2 - cx;
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = const Color(0xFFFFFFFF).withValues(alpha: layer.opacity);

    if (layer.tile) {
      final kStart = ((0 - dx) / strip).floor();
      final kEnd = ((w - dx) / strip).ceil();
      for (var k = kStart; k <= kEnd; k++) {
        canvas.drawImageRect(
          img,
          src,
          Rect.fromLTWH(dx + k * strip, 0, strip, h),
          paint,
        );
      }
    } else {
      canvas.drawImageRect(img, src, Rect.fromLTWH(dx, 0, strip, h), paint);
    }

    final fog = layer.fogColor;
    if (fog != null && layer.fogStrength > 0) {
      final bottom = (layer.fogStrength * layer.opacity).clamp(0.0, 1.0);
      final shader = ui.Gradient.linear(Offset(0, h), Offset(0, 0), [
        fog.withValues(alpha: bottom),
        fog.withValues(alpha: bottom * 0.3),
      ]);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
    }
  }

  void _paintClouds(
    Canvas canvas,
    double w,
    double h,
    SkyboxCloudsLayer layer,
  ) {
    final img = layer.texture.image;
    if (img == null) return;
    final aspect = img.width / img.height;
    final scale = layer.scale <= 0 ? 1.0 : layer.scale;
    final strip = math.max(aspect, w / h) * h / scale;
    if (strip <= 0) return;

    final scroll = ((time * layer.speed + rotation) % 1 + 1) % 1;
    final dx = w / 2 - scroll * strip;
    final cloudHeight = h * 0.6;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(layer.color, BlendMode.modulate)
      ..color = layer.color.withValues(
        alpha: layer.coverage.clamp(0.0, 1.0) * layer.opacity,
      );
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final kStart = ((0 - dx) / strip).floor();
    final kEnd = ((w - dx) / strip).ceil();
    for (var k = kStart; k <= kEnd; k++) {
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(dx + k * strip, 0, strip, cloudHeight),
        paint,
      );
    }
  }

  void _paintStars(Canvas canvas, double w, double h, SkyboxStarsLayer layer) {
    final count = layer.count.clamp(0, 5000);
    if (count == 0) return;
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
          .withValues(alpha: layer.brightness.clamp(0.0, 1.0) * layer.opacity);
    final shift = rotation * w;
    for (var i = 0; i < count; i++) {
      final x = ((_hash(i, 1) * w - shift) % w + w) % w;
      final y = _hash(i, 2) * h * 0.65;
      final radius = 0.5 + _hash(i, 3) * 1.2;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _paintBody(Canvas canvas, double w, double h, SkyboxBodyLayer layer) {
    final direction = layer.direction;
    if (direction.length2 <= 1e-12) return;
    final length = math.sqrt(direction.length2);
    final heading = math.atan2(-direction.x / length, -direction.z / length);
    final turn = ((heading + math.pi / 4) / (2 * math.pi)) % 1.0;
    final u = ((turn - rotation) % 1 + 1) % 1;
    final elevation = math.asin((direction.y / length).clamp(-1.0, 1.0));
    final x = u * w;
    final y = h / 2 - elevation / (math.pi / 2) * (h / 2);
    final radius = math.max(4.0, layer.size * h * 0.04);
    final opacity = layer.opacity;

    if (layer.glow > 0) {
      final glow = ui.Gradient.radial(
        Offset(x, y),
        radius * (2 + layer.glow * 3),
        [
          layer.color.withValues(alpha: 0.6 * layer.glow * opacity),
          layer.color.withValues(alpha: 0.0),
        ],
      );
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = glow);
    }
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()..color = layer.color.withValues(alpha: opacity),
    );
    if (layer.moon) {
      canvas.drawCircle(
        Offset(x - radius * 0.35, y - radius * 0.2),
        radius * 0.18,
        Paint()
          ..color = const Color(0x33000000).withValues(alpha: 0.2 * opacity),
      );
    }
  }

  static double _hash(int index, int salt) {
    final value = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453;
    return value - value.floorToDouble();
  }

  @override
  bool shouldRepaint(_SkyboxPainter oldDelegate) =>
      oldDelegate.node != node ||
      oldDelegate.rotation != rotation ||
      oldDelegate.time != time;
}
