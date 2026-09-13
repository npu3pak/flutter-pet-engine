import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A classic transparency checkerboard.
class Checkerboard extends StatelessWidget {
  const Checkerboard({
    super.key,
    this.cellSize = 10,
    this.colorA = const Color(0xFF8A8A8A),
    this.colorB = const Color(0xFF5C5C5C),
  });

  final double cellSize;
  final Color colorA;
  final Color colorB;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CheckerPainter(cellSize, colorA, colorB));
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter(this.cellSize, this.colorA, this.colorB);

  final double cellSize;
  final Color colorA;
  final Color colorB;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final isDark = (x + y) % 2 == 0;
        paint.color = isDark ? colorA : colorB;
        canvas.drawRect(
          Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize ||
      oldDelegate.colorA != colorA ||
      oldDelegate.colorB != colorB;
}

/// An image drawn on top of a transparency checkerboard.
class CheckerboardImage extends StatelessWidget {
  const CheckerboardImage({
    super.key,
    this.bytes,
    this.fit = BoxFit.contain,
    this.cellSize = 10,
    this.cacheWidth,
  });

  final Uint8List? bytes;
  final BoxFit fit;
  final double cellSize;

  /// Decode the image at this width to keep memory low (thumbnails).
  /// `null` decodes at native resolution.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Checkerboard(cellSize: cellSize),
        if (bytes != null)
          Image.memory(
            bytes!,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.none,
            cacheWidth: cacheWidth,
          ),
      ],
    );
  }
}
