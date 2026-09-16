/// The stage of a scene or level load. Shared by `SceneController.status`
/// and the level loader events.
enum SceneLoadPhase {
  idle,
  project,
  models,
  resources,
  geometry,
  bake,
  ready,
  error,
}

/// Human-readable stage name for the loading UI.
extension SceneLoadPhaseLabel on SceneLoadPhase {
  String get label => switch (this) {
    SceneLoadPhase.idle => 'Ожидание',
    SceneLoadPhase.project => 'Проект',
    SceneLoadPhase.models => 'Модели',
    SceneLoadPhase.resources => 'Ресурсы',
    SceneLoadPhase.geometry => 'Геометрия',
    SceneLoadPhase.bake => 'Запекание',
    SceneLoadPhase.ready => 'Готово',
    SceneLoadPhase.error => 'Ошибка',
  };
}

/// One resource that failed to load: what and why.
class SceneLoadError {
  const SceneLoadError({required this.resource, required this.reason});

  /// File path or resource key (e.g. `textures/wall.png`, `models/house.json`).
  final String resource;

  /// Why it could not be loaded.
  final String reason;

  @override
  String toString() => '$resource: $reason';
}
