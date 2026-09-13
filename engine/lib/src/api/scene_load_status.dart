import '../level/load_status.dart';

export '../level/load_status.dart'
    show SceneLoadError, SceneLoadPhase, SceneLoadPhaseLabel;

/// The current loading status of a `SceneController`: phase, progress, label
/// and the collected errors.
class SceneLoadStatus {
  const SceneLoadStatus({
    this.phase = SceneLoadPhase.idle,
    this.fraction = 0,
    this.label = '',
    this.errors = const [],
  });

  final SceneLoadPhase phase;

  /// Progress of the whole load, 0..1.
  final double fraction;

  /// Human-readable stage label for the loading indicator.
  final String label;

  /// Resources that failed to load (loading continues without them).
  final List<SceneLoadError> errors;

  /// Whether the scene is ready to render.
  bool get isReady => phase == SceneLoadPhase.ready;

  /// Whether the load failed or finished with errors.
  bool get hasError => phase == SceneLoadPhase.error || errors.isNotEmpty;

  SceneLoadStatus copyWith({
    SceneLoadPhase? phase,
    double? fraction,
    String? label,
    List<SceneLoadError>? errors,
  }) => SceneLoadStatus(
    phase: phase ?? this.phase,
    fraction: fraction ?? this.fraction,
    label: label ?? this.label,
    errors: errors ?? this.errors,
  );
}
