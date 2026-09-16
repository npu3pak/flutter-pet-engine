import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pet_engine/pet_engine.dart';

import '../models/resource_item.dart';
import '../processing/background_remover.dart';
import '../processing/image_ops.dart';

/// How a scale operation treats the aspect ratio.
enum ResourceScaleMode {
  /// Exact target size (aspect ratio is distorted).
  stretch,

  /// Fits inside the target box, keeping the aspect (no cropping).
  contain,

  /// Fills the target box completely, center-cropping the excess.
  cover,
}

/// State + file operations for the project's resources (textures/ + sprites/).
class ResourceStore extends ChangeNotifier {
  static const originalSuffix = '_original';
  static const scalePresets = [1024, 512, 256, 128, 64];

  static const _imageExtensions = {'.png', '.jpg', '.jpeg', '.webp'};

  final ProjectStore project;
  final List<ResourceItem> _items = [];
  ResourceItem? _selected;

  /// Fired on any mutation (import/rename/family/delete/apply/save) — the
  /// app uses it to invalidate the resource caches so the 3D editor picks up
  /// changed resources.
  void Function()? onMutation;

  /// Cached auto-detected background colour per item (invalidated on edit).
  final Map<ResourceItem, RgbColor> _detectedBg = {};

  ResourceStore(this.project);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<ResourceItem> get items => List.unmodifiable(_items);

  ResourceItem? get selected => _selected;

  int get selectedCount => _items.where((i) => i.selectedForExport).length;

  String familyDir(String family) => p.join(
    project.directory!.path,
    family == 'sprite' ? 'sprites' : 'textures',
  );

  static bool _isImageFile(File f) =>
      _imageExtensions.contains(p.extension(f.path).toLowerCase());

  static bool _isOriginalFile(String fileName) =>
      p.basenameWithoutExtension(fileName).endsWith(originalSuffix);

  /// Identity used to pair `<name>.png` with `<name>_original.png`.
  static String _identity(String fileName) {
    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    if (stem.endsWith(originalSuffix)) {
      return '${stem.substring(0, stem.length - originalSuffix.length)}$ext';
    }
    return fileName;
  }

  // -------------------------------------------------------------------------
  // Loading (scans textures/ and sprites/ of the project)
  // -------------------------------------------------------------------------

  Future<void> reload() async {
    if (_disposed) return;
    _selected = null;
    _items.clear();
    _detectedBg.clear();
    for (final family in ['texture', 'sprite']) {
      final dir = Directory(familyDir(family));
      if (!dir.existsSync()) continue;
      List<File> entries;
      try {
        entries = await dir
            .list(followLinks: false)
            .where((e) => e is File)
            .cast<File>()
            .where(_isImageFile)
            .toList();
      } catch (_) {
        continue; // The folder may have been removed mid-scan.
      }

      final groups = <String, List<File>>{};
      for (final f in entries) {
        groups.putIfAbsent(_identity(p.basename(f.path)), () => []).add(f);
      }
      for (final group in groups.values) {
        final regular = group
            .where((f) => !_isOriginalFile(p.basename(f.path)))
            .toList();
        final originals = group
            .where((f) => _isOriginalFile(p.basename(f.path)))
            .toList();

        File working;
        File? backup;
        String name;
        if (regular.isNotEmpty) {
          working = regular.first;
          backup = originals.isNotEmpty ? originals.first : null;
          name = p.basenameWithoutExtension(working.path);
        } else {
          working = originals.first;
          backup = null;
          name = p.basenameWithoutExtension(working.path);
        }

        try {
          final workingBytes = await working.readAsBytes();
          final originalBytes = backup != null
              ? await backup.readAsBytes()
              : workingBytes;
          final workingImg = decodeImage(workingBytes);
          final originalImg = decodeImage(originalBytes);
          final meta = project.resources[name];
          _items.add(
            ResourceItem(
              sourcePath: working.path,
              name: name,
              family: family,
              history: [
                ResourceSnapshot(
                  originalBytes,
                  originalImg.width,
                  originalImg.height,
                ),
                ResourceSnapshot(
                  workingBytes,
                  workingImg.width,
                  workingImg.height,
                ),
              ],
              hasDiskOriginal: backup != null,
            )..tolerancePercent = meta?.tolerance ?? 30,
          );
        } catch (_) {
          // Broken image files are skipped.
        }
      }
    }
    _items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_disposed) return;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  void select(ResourceItem item) {
    _selected = item;
    notifyListeners();
  }

  /// Clears the selected item (e.g. when a «Модели» tile is chosen instead).
  void clearSelected() {
    if (_selected == null) return;
    _selected = null;
    notifyListeners();
  }

  void toggleExport(ResourceItem item) {
    item.selectedForExport = !item.selectedForExport;
    notifyListeners();
  }

  /// Marks every item (or just one [family], if given) for export.
  void selectAll({String? family}) {
    for (final i in _items) {
      if (family == null || i.family == family) {
        i.selectedForExport = true;
      }
    }
    notifyListeners();
  }

  void clearSelection({String? family}) {
    for (final i in _items) {
      if (family == null || i.family == family) {
        i.selectedForExport = false;
      }
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Import
  // -------------------------------------------------------------------------

  /// Decodes [path] and writes it into the project as `<name>.png` in
  /// [family]'s folder. Returns the resource name or null on failure.
  Future<String?> importFile(String path, {required String family}) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final img = decodeImage(bytes);
    final png = encodePng(img);
    final base = p.basenameWithoutExtension(path);
    final name = _nextFreeName(base, family);
    final target = File(p.join(familyDir(family), '$name.png'));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(png, flush: true);
    project.resources[name] = ResourceMeta(id: name, family: family);
    await project.saveMeta();
    await reload();
    onMutation?.call();
    return name;
  }

  /// Finds `<base>.png` (or `<base>_2.png`, …) that doesn't clash with an
  /// existing resource anywhere in the project.
  String _nextFreeName(String base, String family) {
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
  // Editing
  // -------------------------------------------------------------------------

  /// Detect the background colour of [item]'s current snapshot (cached).
  RgbColor detectBackground(ResourceItem item) {
    return _detectedBg.putIfAbsent(
      item,
      () => detectBackgroundFromBytes(item.snapshot.bytes),
    );
  }

  /// Compute a live preview of background removal without committing.
  Uint8List previewRemoval({
    required ResourceItem item,
    required double tolerance,
  }) {
    return removeBackgroundFromBytes(
      bytes: item.snapshot.bytes,
      bg: detectBackground(item),
      tolerance: tolerance,
    );
  }

  /// Commit a background removal on [item] (defaults to the selection).
  Future<void> applyRemoval({
    ResourceItem? item,
    required double tolerance,
  }) async {
    final it = item ?? _selected;
    if (it == null) return;
    it.tolerancePercent = tolerance;
    await _saveTolerance(it);
    final out = previewRemoval(item: it, tolerance: tolerance);
    _commit(it, out);
  }

  /// Scale [item] to the [width]×[height] target with nearest-neighbour
  /// interpolation. [mode] picks the aspect behaviour:
  /// [ResourceScaleMode.stretch] — exact target (distorted);
  /// [ResourceScaleMode.contain] — fits inside the box, no crop;
  /// [ResourceScaleMode.cover] — fills the box, center-cropped.
  void applyScale({
    ResourceItem? item,
    required int width,
    required int height,
    ResourceScaleMode mode = ResourceScaleMode.stretch,
  }) {
    final it = item ?? _selected;
    if (it == null || width <= 0 || height <= 0) return;
    final Uint8List out = switch (mode) {
      ResourceScaleMode.stretch => resizeNearestFromBytes(
        bytes: it.snapshot.bytes,
        width: width,
        height: height,
      ),
      ResourceScaleMode.contain => resizeContainFromBytes(
        bytes: it.snapshot.bytes,
        maxWidth: width,
        maxHeight: height,
      ),
      ResourceScaleMode.cover => resizeCoverFromBytes(
        bytes: it.snapshot.bytes,
        width: width,
        height: height,
      ),
    };
    _commit(it, out);
  }

  /// Translate [item]'s visible content as a rigid block until its [target]
  /// edge touches the matching canvas edge (or it is centered on both axes).
  void applyAlign({ResourceItem? item, required AlignTarget target}) {
    final it = item ?? _selected;
    if (it == null) return;
    final out = alignFromBytes(it.snapshot.bytes, target);
    if (identical(out, it.snapshot.bytes)) return;
    _commit(it, out);
  }

  /// Trim [item]'s empty borders and re-add [left]/[top]/[right]/[bottom]
  /// transparent pixels around the visible content (see [trimAndPadFromBytes]).
  void applyTrimMargins({
    ResourceItem? item,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final it = item ?? _selected;
    if (it == null) return;
    final out = trimAndPadFromBytes(
      bytes: it.snapshot.bytes,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    if (identical(out, it.snapshot.bytes)) return;
    _commit(it, out);
  }

  Future<void> _saveTolerance(ResourceItem item) async {
    final meta =
        project.resources[item.name] ??
        ResourceMeta(id: item.name, family: item.family);
    meta.tolerance = item.tolerancePercent;
    project.resources[item.name] = meta;
    await project.saveMeta();
  }

  void _commit(ResourceItem item, Uint8List bytes) {
    final img = decodeImage(bytes);
    item.pushSnapshot(ResourceSnapshot(bytes, img.width, img.height));
    _detectedBg.remove(item);
    onMutation?.call();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Name / family
  // -------------------------------------------------------------------------

  /// Renames the resource on disk (working file + `_original` backup) and in
  /// the index. Returns an error message, or null on success.
  Future<String?> rename(ResourceItem item, String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'Имя не может быть пустым';
    if (cleaned == item.name) return null;
    final err = validateName(cleaned);
    if (err != null) return err;
    if (_items.any((i) => i != item && i.name == cleaned)) {
      return 'Ресурс с таким именем уже есть';
    }
    final dir = familyDir(item.family);
    final oldWorking = File(p.join(dir, '${item.name}.png'));
    final oldOriginal = File(p.join(dir, '${item.name}$originalSuffix.png'));
    final newWorking = File(p.join(dir, '$cleaned.png'));
    final newOriginal = File(p.join(dir, '$cleaned$originalSuffix.png'));
    if (oldWorking.existsSync() && !newWorking.existsSync()) {
      oldWorking.renameSync(newWorking.path);
    }
    if (oldOriginal.existsSync() && !newOriginal.existsSync()) {
      oldOriginal.renameSync(newOriginal.path);
    }
    final meta = project.resources.remove(item.name);
    item.name = cleaned;
    item.sourcePath = newWorking.path;
    if (meta != null) {
      meta.id = cleaned;
      project.resources[cleaned] = meta;
      await project.saveMeta();
    }
    onMutation?.call();
    notifyListeners();
    return null;
  }

  /// Moves the resource between textures/ and sprites/ (family change).
  Future<void> setFamily(ResourceItem item, String family) async {
    if (item.family == family) return;
    final oldDir = familyDir(item.family);
    final newDir = familyDir(family);
    final oldWorking = File(p.join(oldDir, '${item.name}.png'));
    final oldOriginal = File(p.join(oldDir, '${item.name}$originalSuffix.png'));
    final newWorking = File(p.join(newDir, '${item.name}.png'));
    final newOriginal = File(p.join(newDir, '${item.name}$originalSuffix.png'));
    Directory(newDir).createSync(recursive: true);
    if (oldWorking.existsSync() && !newWorking.existsSync()) {
      oldWorking.renameSync(newWorking.path);
    }
    if (oldOriginal.existsSync() && !newOriginal.existsSync()) {
      oldOriginal.renameSync(newOriginal.path);
    }
    item.family = family;
    item.sourcePath = newWorking.path;
    final meta =
        project.resources[item.name] ??
        ResourceMeta(id: item.name, family: family);
    meta.family = family;
    project.resources[item.name] = meta;
    await project.saveMeta();
    onMutation?.call();
    notifyListeners();
  }

  /// Deletes the resource (working file + `_original` + index entry).
  Future<void> delete(ResourceItem item) => _delete([item]);

  /// Deletes every item flagged for export. Returns the number deleted.
  Future<int> deleteSelected() async {
    final selected = _items.where((i) => i.selectedForExport).toList();
    await _delete(selected);
    return selected.length;
  }

  Future<void> _delete(List<ResourceItem> items) async {
    if (items.isEmpty) return;
    for (final item in items) {
      final dir = familyDir(item.family);
      final working = File(p.join(dir, '${item.name}.png'));
      final original = File(p.join(dir, '${item.name}$originalSuffix.png'));
      if (working.existsSync()) working.deleteSync();
      if (original.existsSync()) original.deleteSync();
      project.resources.remove(item.name);
      _items.remove(item);
      _detectedBg.remove(item);
      if (_selected == item) _selected = null;
    }
    await project.saveMeta();
    onMutation?.call();
    notifyListeners();
  }

  /// A resource name must be a valid file name, unique project-wide, and
  /// must not end with the reserved `_original` suffix.
  String? validateName(String name) {
    if (name.trim().isEmpty) return 'Имя не может быть пустым';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      return 'Имя содержит запрещённые символы';
    }
    if (name.endsWith(originalSuffix)) {
      return 'Суффикс «$originalSuffix» зарезервирован';
    }
    return null;
  }

  void rollback(ResourceItem item, int index) {
    item.rollbackTo(index);
    _detectedBg.remove(item);
    onMutation?.call();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Save / export
  // -------------------------------------------------------------------------

  /// Write [item]'s current snapshot back into the project folder.
  /// On the first in-place overwrite the untouched original is persisted as
  /// `<name>_original.png` so it survives app restarts.
  Future<String?> saveItem(ResourceItem item) async {
    final dir = familyDir(item.family);
    try {
      final source = File(item.sourcePath);
      final target = File(p.join(dir, '${item.name}.png'));

      final sameFile = await _sameFile(source, target);
      if (sameFile && !item.hasDiskOriginal) {
        final backup = File(p.join(dir, '${item.name}$originalSuffix.png'));
        if (!await backup.exists()) {
          await backup.writeAsBytes(item.original.bytes, flush: true);
          item.hasDiskOriginal = true;
        }
      }

      await target.writeAsBytes(item.snapshot.bytes, flush: true);
      item.sourcePath = target.path;
      item.isModified = false;
      onMutation?.call();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Не удалось сохранить «${item.name}»: $e';
    }
  }

  Future<String?> saveAll() async {
    String? lastError;
    for (final item in _items) {
      if (!item.isModified) continue;
      final error = await saveItem(item);
      if (error != null) lastError = error;
    }
    return lastError;
  }

  /// Write the current snapshot of every selected item into [destDir].
  Future<String?> exportSelected(String destDir) async {
    final dest = Directory(destDir);
    final selected = _items.where((i) => i.selectedForExport).toList();
    if (selected.isEmpty) return 'Ничего не выбрано для экспорта';

    try {
      await dest.create(recursive: true);
      for (final item in selected) {
        await File(p.join(destDir, '${item.name}.png'))
            .writeAsBytes(item.snapshot.bytes, flush: true);
      }
      return 'Экспортировано ${selected.length} — $destDir';
    } catch (e) {
      return 'Не удалось экспортировать: $e';
    }
  }

  Future<String?> pickExportDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Куда экспортировать выбранные изображения',
    );
    if (path == null) return null;
    return exportSelected(path);
  }

  Future<bool> _sameFile(File a, File b) async {
    try {
      final ra = await a.resolveSymbolicLinks();
      final rb = await b.resolveSymbolicLinks();
      return ra == rb;
    } catch (_) {
      return a.path == b.path;
    }
  }
}
