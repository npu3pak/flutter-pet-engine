import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android host controls for sustained performance (see MainActivity).
///
/// `setSustained(true)` asks the platform not to throttle the app's
/// performance while it runs (API 24+); unsupported platforms are no-ops.
class DevicePerformance {
  DevicePerformance._();

  static const MethodChannel _channel = MethodChannel('example/performance');
  static bool? _supported;

  static Future<bool> get isSupported async {
    if (_supported != null) return _supported!;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _supported = false;
      return false;
    }
    try {
      _supported =
          await _channel.invokeMethod<bool>(
            'isSustainedPerformanceSupported',
          ) ??
          false;
    } on PlatformException {
      _supported = false;
    } on MissingPluginException {
      _supported = false;
    }
    return _supported!;
  }

  static Future<void> setSustained(bool enabled) async {
    if (!await isSupported) return;
    try {
      await _channel.invokeMethod<void>('setSustainedPerformance', {
        'enabled': enabled,
      });
    } on PlatformException {
      // The platform refused the request; nothing to do.
    } on MissingPluginException {
      // Host without the channel (e.g. tests).
    }
  }
}
