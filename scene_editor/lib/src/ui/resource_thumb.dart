import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Decodes a PNG from disk and shows it nearest-sampled on a checkerboard.
class ResourceThumb extends StatefulWidget {
  final String path;
  const ResourceThumb({super.key, required this.path});

  @override
  State<ResourceThumb> createState() => _ResourceThumbState();
}

class _ResourceThumbState extends State<ResourceThumb> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ResourceThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final file = File(widget.path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return CustomPaint(
      painter: _CheckerPainter(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555B66), width: 1),
        ),
        child: image == null
            ? const Center(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              )
            : RawImage(
                image: image,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 4.0;
    final colors = [const Color(0xFF3A3F48), const Color(0xFF2A2E36)];
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          Paint()..color = colors[(x + y) % 2],
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}
