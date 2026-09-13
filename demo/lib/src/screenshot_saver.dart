import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'paths.dart';

/// Сохраняет снимок и возвращает путь к PNG. В автотестах подменяется, чтобы
/// не писать файлы во время проверки интерфейса.
typedef ScreenshotSaver = Future<String> Function(
  String name,
  Uint8List pngBytes,
  Map<String, Object?> meta,
);

/// Результат захвата: PNG и карточка снимка. Захват и запись разделены, чтобы
/// снимок можно было вернуть по каналу управления, не трогая диск.
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
///
/// Сам захват — фича движка ([captureBoundary] из `pet_engine_v2`); тип
/// оставлен здесь, потому что через него тесты подменяют захват.
typedef ScreenshotCapture = Future<Uint8List?> Function(
  GlobalKey boundaryKey,
  double pixelRatio,
);

/// Пишет PNG в `temp/screenshots` и рядом карточку `<имя>.json` со сведениями
/// о сцене. Возвращает путь к PNG (движковая [saveScreenshot]).
Future<String> writeScreenshotFiles(
  AppPaths paths,
  String name,
  Uint8List pngBytes,
  Map<String, Object?> meta,
) => saveScreenshot(paths.screenshotsDir, name, pngBytes, meta);
