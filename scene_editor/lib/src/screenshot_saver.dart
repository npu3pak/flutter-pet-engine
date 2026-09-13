import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'paths.dart';

/// Сохраняет снимок и возвращает путь к PNG. В автотестах подменяется,
/// чтобы не писать файлы.
typedef ScreenshotSaver = Future<String> Function(
  String name,
  Uint8List pngBytes,
  Map<String, Object?> meta,
);

/// Результат захвата: PNG и карточка снимка.
class ScreenshotResult {
  const ScreenshotResult({
    required this.name,
    required this.pngBytes,
    required this.meta,
  });

  final String name;
  final Uint8List pngBytes;
  final Map<String, Object?> meta;
}

/// Снимает область, помеченную [boundaryKey], как PNG. В автотестах
/// подменяется: захват кадра требует настоящего видеоконтура.
typedef ScreenshotCapture = Future<Uint8List?> Function(
  GlobalKey boundaryKey,
  double pixelRatio,
);

/// Пишет PNG в `temp/screenshots` и рядом карточку `<имя>.json`.
Future<String> writeScreenshotFiles(
  AppPaths paths,
  String name,
  Uint8List pngBytes,
  Map<String, Object?> meta,
) => saveScreenshot(paths.screenshotsDir, name, pngBytes, meta);
