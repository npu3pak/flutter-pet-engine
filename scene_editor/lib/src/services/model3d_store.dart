import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'project_files.dart';
import 'resource_store.dart' show ResourceStore;
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// The result of an import: [error] (null on success) and the imported
/// catalog [name].
typedef ImportResult = ({String? error, String? name});

/// The «Модели» resource catalog of a project: `3d_models/` (glTF folders
/// and GLB files, see [Model3dEntry]).
///
/// The catalog is disk-derived like `textures/`/`sprites/` — no
/// `project.json` index. Imported models are copied verbatim (folder with
/// `.gltf` + siblings for glTF, a single `.glb` for GLB), so relative
/// `.bin`/texture references and any `license.txt` stay intact.
class Model3dStore extends ChangeNotifier {
  /// Catalog folder name inside the project. Note: distinct from `models/`
  /// which holds the editor's own `model_v1` JSON scenes.
  static const catalogDirName = '3d_models';

  final ProjectStore project;
  List<Model3dEntry> _items = [];
  bool _scanned = false;

  Model3dStore(this.project);

  /// Catalog entries sorted by name. Empty until [reload] succeeds.
  List<Model3dEntry> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// True once a [reload] has finished (used by UIs to tell «no models
  /// imported yet» from «not scanned yet»).
  bool get scanned => _scanned;

  Directory get dir => Directory(p.join(project.directory!.path, catalogDirName));

  /// Absolute path of [name]'s storage: the folder for glTF entries, the
  /// `*.glb` file for file entries.
  String storagePath(String name) {
    final e = entry(name);
    if (e != null && !e.isFolder) return p.join(dir.path, '$name.glb');
    return p.join(dir.path, name);
  }

  Model3dEntry? entry(String name) {
    for (final e in _items) {
      if (e.name == name) return e;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Scanning
  // -------------------------------------------------------------------------

  /// Re-scans `3d_models/` from disk and notifies listeners.
  Future<void> reload() async {
    _items = _scan(dir);
    _scanned = true;
    notifyListeners();
  }

  List<Model3dEntry> _scan(Directory root) {
    final result = <Model3dEntry>[];
    if (!root.existsSync()) return result;
    for (final e in root.listSync(followLinks: false)) {
      if (e is Directory) {
        final gltf = _firstGltf(e);
        if (gltf == null) continue;
        result.add(
          Model3dEntry(
            name: p.basename(e.path),
            isFolder: true,
            sourcePath: gltf.path,
            sizeBytes: _dirSizeSync(e),
          ),
        );
      } else if (e is File && _isGlb(e)) {
        result.add(
          Model3dEntry(
            name: p.basenameWithoutExtension(e.path),
            isFolder: false,
            sourcePath: e.path,
            sizeBytes: e.lengthSync(),
          ),
        );
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static bool _isGlb(File f) => p.extension(f.path).toLowerCase() == '.glb';

  /// The first `*.gltf` file directly inside [dir], or null.
  File? _firstGltf(Directory dir) {
    File? found;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File) continue;
      if (p.extension(e.path).toLowerCase() != '.gltf') continue;
      if (found == null ||
          p.basename(e.path).compareTo(p.basename(found.path)) < 0) {
        found = e;
      }
    }
    return found;
  }

  static int _dirSizeSync(Directory dir) {
    var total = 0;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is Directory) {
        total += _dirSizeSync(e);
      } else if (e is File) {
        total += e.lengthSync();
      }
    }
    return total;
  }

  // -------------------------------------------------------------------------
  // Import
  // -------------------------------------------------------------------------

  /// Imports a single picked file: a `.gltf` is imported together with its
  /// whole containing folder (Sketchfab layout — `.bin`/textures/license
  /// siblings), a `.glb` as a single file.
  Future<ImportResult> importFile(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.glb') {
      return _importCopyFile(path);
    }
    if (ext == '.gltf') {
      return _importGltfFolder(Directory(p.dirname(path)));
    }
    return (error: 'Поддерживаются только .gltf и .glb', name: null);
  }

  /// Imports a picked directory: the folder (which must directly contain a
  /// `*.gltf`) is copied into the catalog under its own name.
  Future<ImportResult> importDirectory(String path) async {
    final source = Directory(path);
    if (!source.existsSync()) {
      return (error: 'Каталог не найден: $path', name: null);
    }
    if (_firstGltf(source) == null) {
      return (
        error: 'В каталоге нет .gltf — выберите папку модели',
        name: null,
      );
    }
    return _importFolder(source);
  }

  Future<ImportResult> _importCopyFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return (error: 'Файл не найден: $path', name: null);
    }
    final base = p.basenameWithoutExtension(path);
    final name = _nextFreeName(base);
    final target = File(p.join(dir.path, '$name.glb'));
    try {
      await target.parent.create(recursive: true);
      await file.copy(target.path);
    } catch (e) {
      return (error: 'Не удалось скопировать модель: $e', name: null);
    }
    await _afterMutation('imported $name (GLB)');
    return (error: null, name: name);
  }

  Future<ImportResult> _importGltfFolder(Directory folder) async {
    if (!folder.existsSync()) {
      return (error: 'Папка модели не найдена', name: null);
    }
    if (_firstGltf(folder) == null) {
      return (error: 'В папке нет .gltf', name: null);
    }
    return _importFolder(folder);
  }

  Future<ImportResult> _importFolder(Directory folder) async {
    final base = p.basename(folder.path);
    final name = _nextFreeName(base);
    final target = p.join(dir.path, name);
    final error = await copyDirectory(folder.path, target);
    if (error != null) {
      // Clean up a partially copied folder.
      final created = Directory(target);
      if (created.existsSync()) created.deleteSync(recursive: true);
      return (error: error, name: null);
    }
    await _afterMutation('imported $name (glTF folder)');
    return (error: null, name: name);
  }

  /// Finds `<base>` (or `<base>_2`, …) that doesn't clash with an existing
  /// catalog entry.
  String _nextFreeName(String base) {
    final existing = _items.map((i) => i.name).toSet();
    var candidate = base;
    var n = 2;
    while (existing.contains(candidate)) {
      candidate = '${base}_$n';
      n++;
    }
    return candidate;
  }

  // -------------------------------------------------------------------------
  // Rename / delete / export
  // -------------------------------------------------------------------------

  /// Renames a catalog entry on disk (folder for glTF, file for GLB).
  /// Returns an error message, or null on success.
  String? rename(String from, String to) {
    final e = entry(from);
    if (e == null) return 'Модель «$from» не найдена';
    final cleaned = to.trim();
    if (cleaned.isEmpty) return 'Имя не может быть пустым';
    if (cleaned == from) return null;
    final err = validateName(cleaned);
    if (err != null) return err;
    if (_items.any((i) => i.name == cleaned)) {
      return 'Модель с таким именем уже есть';
    }
    final oldPath = storagePath(from);
    final newPath = e.isFolder
        ? p.join(dir.path, cleaned)
        : p.join(dir.path, '$cleaned.glb');
    if (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) {
      return 'Модель с таким именем уже есть';
    }
    try {
      if (e.isFolder) {
        Directory(oldPath).renameSync(newPath);
      } else {
        File(oldPath).renameSync(newPath);
      }
    } catch (e) {
      return 'Не удалось переименовать: $e';
    }
    _afterMutation('renamed $from -> $cleaned');
    return null;
  }

  /// Deletes a catalog entry recursively. Returns an error message, or
  /// null on success.
  String? delete(String name) {
    final e = entry(name);
    if (e == null) return 'Модель «$name» не найдена';
    final path = storagePath(name);
    try {
      if (e.isFolder) {
        Directory(path).deleteSync(recursive: true);
      } else {
        File(path).deleteSync();
      }
    } catch (e) {
      return 'Не удалось удалить: $e';
    }
    _afterMutation('deleted $name');
    return null;
  }

  /// Exports (copies) the model into [destDir] preserving its storage
  /// layout. Returns an error message, or null on success.
  Future<String?> export(String name, String destDir) async {
    final e = entry(name);
    if (e == null) return 'Модель «$name» не найдена';
    final error = await copyDirectory(storagePath(name), destDir);
    return error;
  }

  /// A model name must be a valid file/folder name and must not end with
  /// the reserved `_original` suffix (which belongs to image backups).
  String? validateName(String name) {
    if (name.trim().isEmpty) return 'Имя не может быть пустым';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      return 'Имя содержит запрещённые символы';
    }
    if (name.endsWith(ResourceStore.originalSuffix)) {
      return 'Суффикс «${ResourceStore.originalSuffix}» зарезервирован';
    }
    return null;
  }

  Future<void> _afterMutation(String message) async {
    logStage('store', message);
    await reload();
  }
}
