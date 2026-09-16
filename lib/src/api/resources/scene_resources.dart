import 'dart:convert';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';

import '../../engine/game_resource_manager.dart';
import '../../engine/project_source.dart';
import '../../models/model3d_entry.dart';
import '../../models/model_scene.dart';
import '../../models/project_meta.dart';
import '../materials/scene_texture.dart';

/// Read-only view of a project's resources: models, texture/sprite catalogs,
/// the glTF catalog and decoded textures.
///
/// The session owns the caches; it belongs to the `SceneController` and is
/// not disposed separately. Writing models goes through `ProjectStore`.
class SceneResources {
  /// Wraps an opened resource manager. Plumbing for `SceneController`.
  @internal
  SceneResources(this.manager);

  /// The underlying v1 resource manager. Plumbing only.
  @internal
  final GameResourceManager manager;

  /// The project name from `project.json`.
  String get projectName => manager.name;

  /// Whether the project source accepts writes.
  bool get writable => manager.source.writable;

  /// The ids of the loaded models (`models/*.json`).
  List<String> get modelIds => manager.modelIds;

  /// A loaded model by id, or null.
  ModelData? model(String id) => manager.model(id);

  /// Every loaded model of the project.
  Iterable<ModelData> get models => manager.models.values;

  /// Texture keys (file stems without the extension).
  List<String> get textureKeys => manager.textureKeys;

  /// Sprite keys (file stems without the extension).
  List<String> get spriteKeys => manager.spriteKeys;

  /// Resources that failed to load.
  List<String> get loadErrors => manager.loadErrors;

  /// The `3d_models/` catalog entry by name, or null.
  Model3dEntry? gltfEntry(String name) => manager.gltfEntry(name);

  /// Every `3d_models/` catalog entry, sorted by name.
  List<Model3dEntry> get gltfEntries => manager.gltfEntries;

  /// Reads an arbitrary project file by root-relative path.
  Future<Uint8List?> readBytes(String relativePath) =>
      manager.resourceBytes(relativePath);

  /// Loads a texture from `textures/` by document key (with or without the
  /// `.png` extension), or null when it is missing.
  Future<SceneTexture?> texture(String key) async {
    final canonical = _canonicalKey(key);
    final raw = await manager.textures.texture(canonical);
    if (raw == null) return null;
    final size = manager.textures.textureSize(canonical);
    return SceneTexture.fromGpu(
      raw,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
    );
  }

  /// Loads a sprite from `sprites/` by document key.
  Future<SceneTexture?> sprite(String key) async {
    final canonical = _canonicalKey(key);
    final raw = await manager.textures.sprite(canonical);
    if (raw == null) return null;
    final size = manager.textures.spriteSize(canonical);
    return SceneTexture.fromGpu(
      raw,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
    );
  }

  /// The already-loaded texture, without starting a load.
  SceneTexture? peekTexture(String key) {
    final canonical = _canonicalKey(key);
    final raw = manager.textures.peekTexture(canonical);
    if (raw == null) return null;
    final size = manager.textures.textureSize(canonical);
    return SceneTexture.fromGpu(
      raw,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
    );
  }

  /// The already-loaded sprite, without starting a load.
  SceneTexture? peekSprite(String key) {
    final canonical = _canonicalKey(key);
    final raw = manager.textures.peekSprite(canonical);
    if (raw == null) return null;
    final size = manager.textures.spriteSize(canonical);
    return SceneTexture.fromGpu(
      raw,
      width: size?.$1 ?? 0,
      height: size?.$2 ?? 0,
    );
  }

  /// Replaces texture URIs inside a glTF resource (see `GameResourceManager`).
  void setGltfTextureOverride(String name, Map<String, Uint8List> overrides) =>
      manager.setGltfTextureOverride(name, overrides);

  /// Drops a glTF texture override.
  void clearGltfTextureOverride(String name) =>
      manager.clearGltfTextureOverride(name);

  /// Drops every cached texture and glTF import.
  void invalidate() => manager.invalidateResources();

  /// Drops the caches and re-reads `models/*.json`.
  Future<void> reload() async {
    manager.invalidateResources();
    await manager.reloadModels();
  }

  static String _canonicalKey(String key) =>
      key.contains('.') ? key : '$key.png';
}

/// Model-level write operations of a project: create, save, delete and
/// rename models. This is the canonical write path for the editor. It also
/// owns the `project.json` meta: the display name, the creation date, the
/// last opened model and the resource index (`resources[]`).
class ProjectStore {
  /// Wraps a resource session (or none, for a closed project). Plumbing.
  @internal
  ProjectStore(this._resources);

  final SceneResources? _resources;
  final Map<String, ResourceMeta> _resourcesIndex = {};
  String? _created;

  /// The last opened model id (the editor reopens it), or null.
  String? lastModelId;

  GameResourceManager get _manager {
    final resources = _resources;
    if (resources == null) {
      throw StateError(
        'Проект не открыт: сначала вызовите SceneController.open.',
      );
    }
    return resources.manager;
  }

  /// The display name of the project (`project.json` → `name`).
  String get name => _manager.name;

  /// The project's root folder when the source is a local directory, or null
  /// (bundled/network sources). The editor uses it for resource file I/O.
  Directory? get directory {
    final source = _manager.source;
    return source is DirectoryProjectSource ? source.root : null;
  }

  /// The creation timestamp (ISO-8601 UTC), or null.
  String? get created => _created;

  /// The resource index of `project.json`, keyed by resource id. Live:
  /// mutate the entries and call [saveMeta] to persist.
  Map<String, ResourceMeta> get resources => _resourcesIndex;

  /// Reads the `project.json` meta (creation date, last model, resource
  /// index). Called by `SceneController.open`; a malformed file is not fatal.
  Future<void> loadMeta() async {
    _created = null;
    lastModelId = null;
    _resourcesIndex.clear();
    final text = await _manager.source.readText('project.json');
    if (text == null) return;
    try {
      final m = jsonDecode(text) as Map<String, Object?>;
      _created = m['created'] as String?;
      final settings = m['settings'];
      if (settings is Map) {
        final last = settings['lastModelId'];
        if (last is String) lastModelId = last;
      }
      final list = m['resources'];
      if (list is List) {
        for (final r in list) {
          final meta = ResourceMeta.fromJson(r);
          if (meta.id.isNotEmpty) _resourcesIndex[meta.id] = meta;
        }
      }
    } catch (_) {
      // A malformed project.json must not break the opened session.
    }
  }

  /// Writes `project.json` (atomic on directory sources), preserving the
  /// current name, creation date and resource index. [lastModelId] updates
  /// the remembered model.
  Future<void> saveMeta({String? lastModelId}) async {
    if (lastModelId != null) this.lastModelId = lastModelId;
    _created ??= DateTime.now().toUtc().toIso8601String();
    final json = <String, Object?>{
      'format': projectFormatV1,
      'name': name,
      'created': _created,
      if (_resourcesIndex.isNotEmpty)
        'resources': [for (final r in _resourcesIndex.values) r.toJson()],
      if (this.lastModelId != null) 'settings': {'lastModelId': this.lastModelId},
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );
    final source = _manager.source;
    final mutable = source is MutableProjectSource
        ? source as MutableProjectSource
        : null;
    if (mutable != null) {
      await source.writeBytes('project.json.tmp', bytes);
      await mutable.renameBytes('project.json.tmp', 'project.json');
    } else {
      await source.writeBytes('project.json', bytes);
    }
  }

  /// The ids of the models in the project.
  List<String> get modelIds => _manager.modelIds;

  /// The loaded models keyed by id (the live catalog of the session).
  Map<String, ModelData> get models => _manager.models;

  /// Creates an empty model, registers it in the catalog and returns it.
  /// The model is not written to disk until [saveModel].
  ModelData createModel({String? id, String? name}) {
    final modelId = id ?? _nextId();
    if (_manager.models.containsKey(modelId)) {
      throw ArgumentError('Модель "$modelId" уже существует.');
    }
    final model = ModelData(id: modelId, name: name ?? modelId);
    _manager.models[modelId] = model;
    return model;
  }

  /// Writes [model] to `models/<id>.json`.
  Future<void> saveModel(ModelData model) async {
    await _manager.saveModel(model);
    _manager.models[model.id] = model;
  }

  /// Deletes `models/<id>.json` (when the source supports deletion).
  Future<void> deleteModel(String id) async {
    final source = _manager.source;
    if (source is MutableProjectSource) {
      await (source as MutableProjectSource).deleteBytes('models/$id.json');
    }
    _manager.models.remove(id);
  }

  /// Renames `models/<id>.json` to `<newId>` and updates the catalog.
  Future<void> renameModel(String id, String newId) async {
    if (id == newId) return;
    final model = _manager.models[id];
    if (model == null) {
      throw ArgumentError('Модель "$id" не найдена.');
    }
    if (_manager.models.containsKey(newId)) {
      throw ArgumentError('Модель "$newId" уже существует.');
    }
    final source = _manager.source;
    if (source is MutableProjectSource) {
      await (source as MutableProjectSource).renameBytes(
        'models/$id.json',
        'models/$newId.json',
      );
    } else {
      model.id = newId;
      await _manager.saveModel(model);
      await deleteModel(id);
    }
    model.id = newId;
    _manager.models.remove(id);
    _manager.models[newId] = model;
  }

  String _nextId() {
    var index = _manager.models.length + 1;
    while (_manager.models.containsKey('model_$index')) {
      index++;
    }
    return 'model_$index';
  }
}
