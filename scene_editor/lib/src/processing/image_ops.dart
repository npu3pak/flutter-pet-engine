import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'background_remover.dart';

/// Decode PNG/JPEG bytes into an [img.Image].
img.Image decodeImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Не удалось декодировать изображение');
  }
  return image;
}

Uint8List encodePng(img.Image image) => Uint8List.fromList(img.encodePng(image));

/// Auto-detect the background colour of a PNG/JPEG image.
RgbColor detectBackgroundFromBytes(Uint8List bytes) {
  final image = decodeImage(bytes);
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  final rgb = flattenToWhiteRgb(rgba);
  return detectBackground(rgb, image.width, image.height);
}

/// Remove the background of a PNG/JPEG image and return new PNG bytes.
///
/// [tolerance] is a percentage (0–100), matching the Python script's `-t`
/// flag; it is converted to the 0–1 fraction expected by
/// [removeBackground] before processing.
Uint8List removeBackgroundFromBytes({
  required Uint8List bytes,
  required RgbColor bg,
  required double tolerance,
}) {
  final image = decodeImage(bytes);
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  final w = image.width;
  final h = image.height;
  final outRgba = removeBackground(
    rgba: rgba,
    w: w,
    h: h,
    bg: bg,
    tolerance: tolerance / 100.0,
  );
  final out = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: outRgba.buffer,
    numChannels: 4,
  );
  return encodePng(out);
}

/// Resize a PNG/JPEG image to [width]×[height] using nearest-neighbour
/// interpolation (no smoothing), returning new PNG bytes.
Uint8List resizeNearestFromBytes({
  required Uint8List bytes,
  required int width,
  required int height,
}) {
  final image = decodeImage(bytes);
  final resized = img.copyResize(
    image,
    width: width,
    height: height,
    interpolation: img.Interpolation.nearest,
  );
  return encodePng(resized);
}

/// Fit the image INSIDE the [maxWidth]×[maxHeight] box keeping the aspect
/// ratio (no cropping): one side lands on the box edge, the other is
/// smaller or equal. The box never grows the result beyond the source
/// proportions. Pure — unit-tested.
Uint8List resizeContainFromBytes({
  required Uint8List bytes,
  required int maxWidth,
  required int maxHeight,
}) {
  final image = decodeImage(bytes);
  final scale = _fitScale(image.width, image.height, maxWidth, maxHeight);
  final resized = img.copyResize(
    image,
    width: _px(image.width * scale),
    height: _px(image.height * scale),
    interpolation: img.Interpolation.nearest,
  );
  return encodePng(resized);
}

/// Fill the [width]×[height] box completely keeping the aspect ratio: the
/// image scales by the LARGER side and the excess is center-cropped. Pure —
/// unit-tested.
Uint8List resizeCoverFromBytes({
  required Uint8List bytes,
  required int width,
  required int height,
}) {
  final image = decodeImage(bytes);
  final sw = _px(image.width * _coverScale(image.width, image.height, width, height));
  final sh = _px(image.height * _coverScale(image.width, image.height, width, height));
  final resized = img.copyResize(
    image,
    width: sw,
    height: sh,
    interpolation: img.Interpolation.nearest,
  );
  final cropped = img.copyCrop(
    resized,
    x: (sw - width) ~/ 2,
    y: (sh - height) ~/ 2,
    width: width,
    height: height,
  );
  return encodePng(cropped);
}

/// Trim the empty (fully transparent) pixels around the visible content and
/// add [left]/[top]/[right]/[bottom] transparent pixels as new margins.
///
/// The content is cut to its bounding box (alpha > 0, same definition as
/// [alignFromBytes]) and re-placed at the [left]/[top] corner of a canvas
/// whose size is `bbox + margins` on each axis, so the result is usually
/// smaller than the source. Semi-transparent AA pixels count as content.
/// A fully transparent image or one whose margins already match the request
/// is returned unchanged (same bytes object).
Uint8List trimAndPadFromBytes({
  required Uint8List bytes,
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final clampedL = left.clamp(0, _maxPad);
  final clampedT = top.clamp(0, _maxPad);
  final clampedR = right.clamp(0, _maxPad);
  final clampedB = bottom.clamp(0, _maxPad);

  final image = decodeImage(bytes);
  final w = image.width;
  final h = image.height;
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0) return bytes; // Fully transparent.

  // Nothing changes when the requested margins equal the current empties.
  if (clampedL == minX &&
      clampedT == minY &&
      clampedR == (w - 1) - maxX &&
      clampedB == (h - 1) - maxY) {
    return bytes;
  }

  final cropW = maxX - minX + 1;
  final cropH = maxY - minY + 1;
  final outW = clampedL + cropW + clampedR;
  final outH = clampedT + cropH + clampedB;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < cropH; y++) {
    final srcRow = (minY + y) * w * 4 + minX * 4;
    final dstRow = (clampedT + y) * outW * 4 + clampedL * 4;
    for (var x = 0; x < cropW; x++) {
      final s = srcRow + x * 4;
      final d = dstRow + x * 4;
      out[d] = rgba[s];
      out[d + 1] = rgba[s + 1];
      out[d + 2] = rgba[s + 2];
      out[d + 3] = rgba[s + 3];
    }
  }
  // Pixels outside the copied content stay zero (transparent).

  final result = img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    numChannels: 4,
  );
  return encodePng(result);
}

/// Upper bound for one side's trim/pad margin.
const _maxPad = 1024;

/// The fit-inside scale factor (min of the two axis ratios).
double _fitScale(int w, int h, int maxW, int maxH) {
  final sx = maxW / w;
  final sy = maxH / h;
  return sx < sy ? sx : sy;
}

/// The fill-scale factor (max of the two axis ratios).
double _coverScale(int w, int h, int outW, int outH) {
  final sx = outW / w;
  final sy = outH / h;
  return sx > sy ? sx : sy;
}

int _px(double v) => v.round().clamp(1, 1 << 20);

/// Where to push an image's visible content when aligning it.
enum AlignTarget {
  /// Push straight up until the topmost pixel hits the top row.
  top,

  /// Push straight down until the lowest pixel hits the bottom row.
  bottom,

  /// Push straight left until the leftmost pixel hits the left column.
  left,

  /// Push straight right until the rightmost pixel hits the right column.
  right,

  /// Center the content on both axes (equal margins left/right and top/bottom).
  center,
}

/// Translate all visible content (alpha > 0) so the content's [target] edge
/// lands on the matching canvas edge, or centers it on both axes.
///
/// The content is moved as a rigid block — relative positions are preserved;
/// the vacated rows/columns become transparent. Images that are already
/// aligned to [target] (or fully transparent) are returned unchanged.
Uint8List alignFromBytes(Uint8List bytes, AlignTarget target) {
  final image = decodeImage(bytes);
  final w = image.width;
  final h = image.height;
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0) return bytes; // Fully transparent.

  final (dx, dy) = switch (target) {
    AlignTarget.top => (0, -minY),
    AlignTarget.bottom => (0, (h - 1) - maxY),
    AlignTarget.left => (-minX, 0),
    AlignTarget.right => ((w - 1) - maxX, 0),
    AlignTarget.center => (
      ((w - (maxX - minX + 1)) ~/ 2) - minX,
      ((h - (maxY - minY + 1)) ~/ 2) - minY,
    ),
  };

  if (dx == 0 && dy == 0) return bytes;

  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final dstY = y + dy;
    if (dstY < 0 || dstY >= h) continue;
    final srcRow = y * w * 4;
    final dstRow = dstY * w * 4;
    for (var x = 0; x < w; x++) {
      final dstX = x + dx;
      if (dstX < 0 || dstX >= w) continue;
      final s = srcRow + x * 4;
      final d = dstRow + dstX * 4;
      out[d] = rgba[s];
      out[d + 1] = rgba[s + 1];
      out[d + 2] = rgba[s + 2];
      out[d + 3] = rgba[s + 3];
    }
  }
  // Pixels outside the destination region stay zero (transparent).

  final result = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: out.buffer,
    numChannels: 4,
  );
  return encodePng(result);
}
