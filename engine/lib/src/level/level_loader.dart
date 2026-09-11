import '../engine/game_resource_manager.dart';
import 'construction_model.dart';
import 'level_baker.dart';
import 'level_resources.dart';

/// Stages of the level loader (подшаг 5.3): project → models → resources →
/// geometry → bake. Progress within a stage may pause — that is allowed.
enum LevelLoadStage { project, models, resources, geometry, bake }

extension LevelLoadStageLabel on LevelLoadStage {
  /// Human-readable stage name for the loading UI.
  String get label => switch (this) {
        LevelLoadStage.project => 'Проект',
        LevelLoadStage.models => 'Модели',
        LevelLoadStage.resources => 'Ресурсы',
        LevelLoadStage.geometry => 'Геометрия',
        LevelLoadStage.bake => 'Запекание',
      };
}

/// Kind of a [LevelLoadEvent].
enum LevelLoadEventKind { started, progress, finished }

/// One thing that could not be loaded: the file or key and the reason.
class LevelLoadError {
  const LevelLoadError(this.resource, this.reason);

  /// File path or resource key (e.g. `textures/wall.png`, `models/house.json`).
  final String resource;

  /// Why it could not be loaded.
  final String reason;

  @override
  String toString() => '$resource: $reason';
}

/// Outcome of a level load: the baked level (null when building failed
/// catastrophically), the error list and the elapsed time. A non-empty error
/// list does NOT mean [baked] is null — the level is shown with placeholders.
class LevelLoadResult {
  const LevelLoadResult({
    required this.baked,
    required this.errors,
    required this.elapsed,
  });

  final LevelBakeResult? baked;
  final List<LevelLoadError> errors;
  final Duration elapsed;

  bool get hasErrors => errors.isNotEmpty;
}

/// A loader event: started / progress (stage, fraction, label) / finished.
class LevelLoadEvent {
  const LevelLoadEvent._(
      this.kind, this.stage, this.fraction, this.label, this.result);

  const LevelLoadEvent.started()
      : this._(LevelLoadEventKind.started, null, 0, '', null);

  const LevelLoadEvent.progress(
      LevelLoadStage stage, double fraction, String label)
      : this._(LevelLoadEventKind.progress, stage, fraction, label, null);

  const LevelLoadEvent.finished(LevelLoadResult result)
      : this._(LevelLoadEventKind.finished, null, 1, '', result);

  final LevelLoadEventKind kind;

  /// Set for [LevelLoadEventKind.progress].
  final LevelLoadStage? stage;

  /// Stage-local progress, 0..1.
  final double fraction;

  /// Short stage label (the resource being loaded or the stage name).
  final String label;

  /// Set for [LevelLoadEventKind.finished].
  final LevelLoadResult? result;
}

/// An extra resource the game must have ready by the time the level is shown
/// (sky image, grass/weather atlases, fog textures). [load] must complete
/// when the resource is fully ready; a thrown error lands in the result's
/// error list with [label] as the resource name.
class LevelExtraResource {
  const LevelExtraResource(this.label, this.load);

  final String label;
  final Future<void> Function() load;
}

/// Loads a level by the five stages and reports progress/errors (подшаг 5.3).
///
/// The loader preloads the whole resource closure of [model] (textures,
/// sprites, glTF, referenced models) plus the game's [extraResources] BEFORE
/// baking, so by the time [load] completes every material is ready and the
/// baked geometry never shows gray placeholders. With [openProject] the
/// loader also drives the `project`/`models` stages through
/// [GameResourceManager.openProject]/[openModels]; otherwise the manager is
/// expected to be open already and those stages complete immediately.
class LevelLoader {
  LevelLoader({
    required this.resources,
    required this.model,
    this.openProject = false,
    this.extraResources = const [],
    this.onEvent,
    this.collectStats = false,
    this.baker,
    this.onMaterial,
  });

  final GameResourceManager resources;
  final ConstructionModel model;

  /// Optional custom baker (a game may pre-configure one; tests inject a
  /// GPU-free fake). Null — the loader creates its own over the resources.
  final LevelBaker? baker;

  /// Material recipe hook forwarded to the baker ([BakedMaterialHook]): the
  /// game applies its wet look/tinting to every unique material after the
  /// geometry pass.
  final BakedMaterialHook? onMaterial;

  /// When true, the loader opens the project and re-reads the models itself
  /// (the game creates a fresh [GameResourceManager] per level). When false,
  /// [resources] must already be open.
  final bool openProject;

  final List<LevelExtraResource> extraResources;

  /// Progress/result listener (nullable — the load still works).
  final void Function(LevelLoadEvent event)? onEvent;

  /// Collect bake statistics (a measurement pass; off by default).
  final bool collectStats;

  void _emit(LevelLoadEvent event) => onEvent?.call(event);

  /// Runs the five stages and returns the result. Never throws: a catastrophic
  /// failure finishes with `baked == null` and the reason in the error list.
  Future<LevelLoadResult> load() async {
    final sw = Stopwatch()..start();
    final errors = <LevelLoadError>[];
    _emit(const LevelLoadEvent.started());

    try {
      // ── 1. проект ─────────────────────────────────────────────────────
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.project, 0, 'Проект'));
      if (openProject) await resources.openProject();
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.project, 1, 'Проект'));

      // ── 2. модели ─────────────────────────────────────────────────────
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.models, 0, 'Модели'));
      if (openProject) await resources.openModels();
      for (final line in resources.loadErrors) {
        final sep = line.indexOf(': ');
        if (sep > 0) {
          errors.add(LevelLoadError(line.substring(0, sep),
              line.substring(sep + 2)));
        } else {
          errors.add(LevelLoadError('models', line));
        }
      }
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.models, 1, 'Модели'));

      // ── 3. ресурсы ────────────────────────────────────────────────────
      final closure =
          collectModelResources(model.data, modelCatalog: resources.model);
      for (final id in closure.missingModelIds) {
        errors.add(LevelLoadError('models/$id.json', 'модель не найдена'));
      }
      final textureKeys = <String>{...closure.textureKeys};
      final spriteKeys = <String>{...closure.spriteKeys};
      final gltfNames = <String>{...closure.gltfNames};
      final total = textureKeys.length +
          spriteKeys.length +
          gltfNames.length +
          extraResources.length;
      var done = 0;
      void step(String label) {
        done++;
        _emit(LevelLoadEvent.progress(
            LevelLoadStage.resources, total == 0 ? 1 : done / total, label));
      }

      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.resources, 0, 'Ресурсы'));
      for (final key in textureKeys) {
        final tex = await resources.textures.texture(key);
        if (tex == null) {
          errors.add(LevelLoadError(
              'textures/$key', 'не найдено или не удалось декодировать'));
        }
        step('textures/$key');
      }
      for (final key in spriteKeys) {
        final tex = await resources.textures.sprite(key);
        if (tex == null) {
          errors.add(LevelLoadError(
              'sprites/$key', 'не найдено или не удалось декодировать'));
        }
        step('sprites/$key');
      }
      for (final name in gltfNames) {
        final entry = resources.gltfEntry(name);
        if (entry == null) {
          errors.add(
              LevelLoadError('3d_models/$name', 'модель не найдена в каталоге'));
        } else {
          try {
            await resources.gltfAssets.load(entry);
            if (resources.gltfAssets.failed(name)) {
              errors.add(LevelLoadError('3d_models/$name', 'ошибка импорта'));
            }
          } catch (e) {
            errors.add(LevelLoadError('3d_models/$name', '$e'));
          }
        }
        step('3d_models/$name');
      }
      for (final resource in extraResources) {
        try {
          await resource.load();
        } catch (e) {
          errors.add(LevelLoadError(resource.label, '$e'));
        }
        step(resource.label);
      }
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.resources, 1, 'Ресурсы'));

      // ── 4–5. геометрия и запекание ────────────────────────────────────
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.geometry, 0, 'Геометрия'));
      final baker = this.baker ??
          LevelBaker(
            resources.textures,
            gltfAssets: resources.gltfAssets,
            modelCatalog: resources.model,
            gltfCatalog: resources.gltfEntry,
            gltfCatalogReady: () => resources.gltfCatalogReady,
          );
      var geometryReported = false;
      final baked = baker.bake(
        model,
        collectStats: collectStats,
        onMaterial: onMaterial,
        onGeometryBuilt: () {
          geometryReported = true;
          _emit(const LevelLoadEvent.progress(
              LevelLoadStage.geometry, 1, 'Геометрия'));
          _emit(const LevelLoadEvent.progress(
              LevelLoadStage.bake, 0, 'Запекание'));
        },
      );
      if (!geometryReported) {
        _emit(const LevelLoadEvent.progress(
            LevelLoadStage.geometry, 1, 'Геометрия'));
        _emit(const LevelLoadEvent.progress(
            LevelLoadStage.bake, 0, 'Запекание'));
      }
      _emit(const LevelLoadEvent.progress(
          LevelLoadStage.bake, 1, 'Запекание'));

      sw.stop();
      final result = LevelLoadResult(
        baked: baked,
        errors: List.unmodifiable(errors),
        elapsed: sw.elapsed,
      );
      _emit(LevelLoadEvent.finished(result));
      return result;
    } catch (e) {
      sw.stop();
      final result = LevelLoadResult(
        baked: null,
        errors: List.unmodifiable(
            [...errors, LevelLoadError('уровень', '$e')]),
        elapsed: sw.elapsed,
      );
      _emit(LevelLoadEvent.finished(result));
      return result;
    }
  }
}
