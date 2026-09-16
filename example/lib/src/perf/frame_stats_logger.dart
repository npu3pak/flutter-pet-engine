import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// On-device frame-timing logger for performance sessions.
///
/// Enabled at compile time with `--dart-define=perf.log=true`; the session is
/// named with `--dart-define=perf.tag=<name>`. One `[perf]` line is printed
/// per two-second window, so `adb logcat` captures fps plus the UI/raster
/// split without DevTools:
///
/// `[perf] tag=baseline t=12.3s frames=118 fps=59.0 ui_avg=1.20 ui_p95=2.30
/// ui_max=5.10 raster_avg=8.30 raster_p95=11.10 raster_max=14.20
/// span_avg=10.10 span_max=16.40 jank=0.0% rss_mb=412.3`
class FrameStatsLogger {
  FrameStatsLogger._(this.tag);

  final String tag;

  static const bool enabled = bool.fromEnvironment('perf.log');
  static const String sessionTag = String.fromEnvironment(
    'perf.tag',
    defaultValue: 'run',
  );

  static const int _windowUs = 2 * 1000 * 1000;
  static const double _vsyncBudgetMs = 1000 / 60;

  /// Starts logging when the app was built with `perf.log`; else returns null.
  static FrameStatsLogger? start() {
    if (!enabled) return null;
    final logger = FrameStatsLogger._(sessionTag);
    SchedulerBinding.instance.addTimingsCallback(logger._onTimings);
    debugPrint('[perf] tag=$sessionTag session-start');
    return logger;
  }

  /// Logs the on-screen FPS meter value as a cross-check line.
  static void logMeter(String label) {
    if (!enabled) return;
    debugPrint('[perf] tag=$sessionTag meter=$label');
  }

  /// Marks a benchmark phase boundary in the log.
  static void phase(String name) {
    if (!enabled) return;
    debugPrint('[perf] tag=$sessionTag phase=$name');
  }

  /// Logs a one-off session fact (settings, modes).
  static void info(String message) {
    if (!enabled) return;
    debugPrint('[perf] tag=$sessionTag info: $message');
  }

  final List<FrameTiming> _window = <FrameTiming>[];
  int _windowStartUs = 0;
  int _sessionStartUs = 0;

  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _flush();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final vsyncUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_sessionStartUs == 0) _sessionStartUs = vsyncUs;
      if (_windowStartUs == 0) _windowStartUs = vsyncUs;
      _window.add(timing);
      if (vsyncUs - _windowStartUs >= _windowUs) _flush();
    }
  }

  void _flush() {
    if (_window.isEmpty) return;
    final lastUs = _window.last.timestampInMicroseconds(FramePhase.vsyncStart);
    final firstUs = _window.first.timestampInMicroseconds(
      FramePhase.vsyncStart,
    );
    final elapsedUs = math.max(lastUs - firstUs, 1);
    final fps = _window.length * 1000000 / elapsedUs;
    final ui = _sortedMs((t) => t.buildDuration);
    final raster = _sortedMs((t) => t.rasterDuration);
    final span = _sortedMs((t) => t.totalSpan);
    final janky = span.where((ms) => ms > _vsyncBudgetMs).length;
    final rss = ProcessInfo.currentRss;
    final rssField = rss > 0
        ? ' rss_mb=${(rss / (1024 * 1024)).toStringAsFixed(1)}'
        : '';
    final elapsed = (lastUs - _sessionStartUs) / 1000000;
    debugPrint(
      '[perf] tag=$tag t=${elapsed.toStringAsFixed(1)}s'
      ' frames=${_window.length} fps=${fps.toStringAsFixed(1)}'
      ' ui_avg=${_avg(ui).toStringAsFixed(2)}'
      ' ui_p95=${_p95(ui).toStringAsFixed(2)}'
      ' ui_max=${ui.last.toStringAsFixed(2)}'
      ' raster_avg=${_avg(raster).toStringAsFixed(2)}'
      ' raster_p95=${_p95(raster).toStringAsFixed(2)}'
      ' raster_max=${raster.last.toStringAsFixed(2)}'
      ' span_avg=${_avg(span).toStringAsFixed(2)}'
      ' span_max=${span.last.toStringAsFixed(2)}'
      ' jank=${(100 * janky / span.length).toStringAsFixed(1)}%'
      '$rssField',
    );
    _window.clear();
    _windowStartUs = lastUs;
  }

  List<double> _sortedMs(Duration Function(FrameTiming) select) {
    final values = [
      for (final timing in _window) select(timing).inMicroseconds / 1000,
    ];
    values.sort();
    return values;
  }

  static double _avg(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _p95(List<double> sorted) => sorted.isEmpty
      ? 0
      : sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
}
