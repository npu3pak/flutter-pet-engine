import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/model_scene.dart';
import '../models/project_meta.dart';
import '../models/scene_loader.dart';
import 'app_log.dart';

export '../models/project_meta.dart' show ResourceMeta;

/// Errors reported per-file during a project load.
class LoadError {
  final String fileName;
  final String message;
  LoadError(this.fileName, this.message);
}

class ProjectStore {
  final Directory root;
  String name;
  String? created; // ISO-8601 UTC
  String? lastModelId;

  /// Paths of textures (files in textures/) and sprites (files in sprites/).
  /// Re-scanned from disk on every access — imported/renamed resources are
  /// picked up without reopening the project.
  List<String> get textures => _listPng('textures');
  List<String> get sprites => _listPng('sprites');

  /// Loaded models keyed by file id (name without .json).
  final Map<String, ModelData> models = {};
  final List<LoadError> errors = [];

  /// Resource index from project.json (keyed by resource id).
  final Map<String, ResourceMeta> resources = {};

  ProjectStore(this.root, {required this.name});

  Directory get modelsDir => Directory(p.join(root.path, 'models'));

  List<String> _listPng(String sub) {
    final dir = Directory(p.join(root.path, sub));
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.toLowerCase().endsWith('.png'))
        .toList()
      ..sort();
  }

  /// Opens a clean project: requires `project.json` with `format: project_v1`.
  factory ProjectStore.open(String path) {
    final root = Directory(path);
    if (!root.existsSync()) {
      throw FileSystemException('Каталог не найден', path);
    }
    final metaFile = File(p.join(path, 'project.json'));
    if (!metaFile.existsSync()) {
      throw FileSystemException(
          'Не является проектом Scene Editor (нет project.json)', path);
    }
    final store = ProjectStore(root, name: p.basename(path));
    try {
      final m = jsonDecode(metaFile.readAsStringSync()) as Map<String, Object?>;
      if (m['format'] != projectFormatV1) {
        throw const FormatException('Неизвестный формат проекта');
      }
      final name = m['name'];
      if (name is String && name.trim().isNotEmpty) {
        store.name = name.trim();
      }
      store.created = m['created'] as String?;
      final settings = m['settings'];
      if (settings is Map) {
        final last = settings['lastModelId'];
        if (last is String) store.lastModelId = last;
      }
      final res = m['resources'];
      if (res is List) {
        for (final r in res) {
          final meta = ResourceMeta.fromJson(r);
          if (meta.id.isNotEmpty) store.resources[meta.id] = meta;
        }
      }
    } catch (e) {
      throw FileSystemException(
          'Не удалось прочитать project.json: $e', path);
    }
    store.reloadModels();
    return store;
  }

  /// Creates a project at [path] (may be an existing folder — a manual
  /// migration: legacy `chunks/*.json` files are copied into `models/` and
  /// rewritten to `model_v1`).
  factory ProjectStore.create(String path, {required String name}) {
    final root = Directory(path);
    root.createSync(recursive: true);
    final clean = name.trim();
    final store = ProjectStore(root, name: clean.isEmpty ? p.basename(path) : clean)
      ..created = DateTime.now().toUtc().toIso8601String();
    final chunksDir = Directory(p.join(path, 'chunks'));
    if (chunksDir.existsSync()) {
      store._createModelsDir();
      for (final f in chunksDir.listSync().whereType<File>()) {
        if (!f.path.toLowerCase().endsWith('.json')) continue;
        try {
          final id = p.basenameWithoutExtension(f.path);
          final model = loadModelData(f.readAsStringSync(), id: id);
          store.saveModel(model);
          logStage('store', 'migrated $id');
        } catch (e) {
          store.errors.add(LoadError(p.basename(f.path), 'Ошибка миграции: $e'));
        }
      }
    }
    store.saveMeta();
    store.reloadModels();
    return store;
  }

  /// Atomic write of project.json (`.json.tmp` → rename).
  void saveMeta() {
    final file = File(p.join(root.path, 'project.json'));
    file.parent.createSync(recursive: true);
    final json = <String, Object>{
      'format': projectFormatV1,
      'name': name,
      'created': ?created,
      if (resources.isNotEmpty)
        'resources': [for (final r in resources.values) r.toJson()],
      if (lastModelId != null)
        'settings': {'lastModelId': lastModelId},
    };
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    tmp.renameSync(file.path);
  }

  /// Re-reads models/*.json from disk (keeps current in-memory edits of the
  /// currently open model untouched — used after save/rename).
  void reloadModels() {
    models.clear();
    errors.clear();
    if (!modelsDir.existsSync()) return;
    for (final f in modelsDir.listSync().whereType<File>()) {
      if (!f.path.toLowerCase().endsWith('.json')) continue;
      final id = p.basenameWithoutExtension(f.path);
      final sw = Stopwatch()..start();
      try {
        final model = loadModelData(f.readAsStringSync(), id: id);
        models[id] = model;
        logStage(
          'store',
          'reload ${p.basename(f.path)} objects=${model.objects.length} '
              'groups=${model.groups.length}',
          ms: sw.elapsedMilliseconds,
        );
      } catch (e) {
        logStage(
          'store',
          'reload FAIL ${p.basename(f.path)}: $e',
          ms: sw.elapsedMilliseconds,
        );
        errors.add(LoadError(p.basename(f.path), 'Ошибка JSON: $e'));
      }
    }
    // Sort by id for a stable list.
    final sorted = models.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    models
      ..clear()
      ..addEntries(sorted);
  }

  /// Lists model ids in a stable order.
  List<String> modelIds() => models.keys.toList();

  ModelData? loadModel(String id) => models[id];

  /// Creates a new model in memory (saved with the save button).
  ModelData createModel(String id) {
    final data = ModelData(id: id, name: id);
    models[id] = data;
    return data;
  }

  /// Renames [from] to [to] on disk (file + id). Returns the renamed model.
  ModelData? renameModel(String from, String to) {
    final data = models.remove(from);
    if (data == null) return null;
    data.id = to;
    models[to] = data;
    final file = File(p.join(modelsDir.path, '$from.json'));
    if (file.existsSync()) file.renameSync(p.join(modelsDir.path, '$to.json'));
    return data;
  }

  /// Deletes [id] from disk and memory. Returns true if a file was removed.
  bool deleteModel(String id) {
    models.remove(id);
    final file = File(p.join(modelsDir.path, '$id.json'));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Atomic save: write to `<name>.json.tmp` then rename over the target.
  void saveModel(ModelData model) {
    _createModelsDir();
    final sw = Stopwatch()..start();
    final tmp = File(p.join(modelsDir.path, '${model.id}.json.tmp'));
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(model.toJson()),
      flush: true,
    );
    tmp.renameSync(p.join(modelsDir.path, '${model.id}.json'));
    model.dirty = false;
    logStage('store', 'saved ${model.id}', ms: sw.elapsedMilliseconds);
  }

  /// Checks a model id is usable as a new file name.
  String? validateModelId(String id) {
    if (id.trim().isEmpty) return 'Имя не может быть пустым';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(id)) {
      return 'Имя содержит запрещённые символы';
    }
    return null;
  }

  void _createModelsDir() {
    modelsDir.createSync(recursive: true);
  }
}
