import 'package:flutter/foundation.dart';

/// Timed stage logging for the model editor.
///
/// Every entry carries the monotonic elapsed time since the first log, so a
/// hang leaves its last «start» line (or the line right before it) without a
/// matching «done» — that stage is where the main isolate stalled.
final Stopwatch _clock = Stopwatch()..start();

/// Logs one stage marker: `[Scene Editor +1234ms] stage: message (37ms)`.
/// [ms] is the stage's own duration when measured by the caller.
void logStage(String stage, String message, {int? ms}) {
  final tail = ms == null ? '' : ' (${ms}ms)';
  debugPrint('[Scene Editor +${_clock.elapsedMilliseconds}ms] $stage: $message$tail');
}

/// Runs [fn] synchronously and logs how long it took; returns its result.
T timed<T>(String stage, String message, T Function() fn) {
  final sw = Stopwatch()..start();
  final result = fn();
  logStage(stage, message, ms: sw.elapsedMilliseconds);
  return result;
}
