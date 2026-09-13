import 'dart:typed_data';

/// An immutable snapshot of an image (PNG bytes + pixel dimensions).
class ResourceSnapshot {
  const ResourceSnapshot(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// One resource image in the project (`textures/` or `sprites/`).
///
/// `history[0]` is always the original; later entries are committed edits
/// (an undo stack). The original is additionally persisted to disk as
/// `<name>_original.png` on the first in-place save (see [ResourceStore]).
class ResourceItem {
  ResourceItem({
    required this.sourcePath,
    required this.name,
    required this.family,
    required List<ResourceSnapshot> history,
    required this.hasDiskOriginal,
  }) : _history = history; // ignore: prefer_initializing_formals

  /// Path of the working file in the project folder.
  String sourcePath;

  /// Editable name (file name without extension, unique within the project).
  String name;

  /// 'texture' (textures/) or 'sprite' (sprites/) — the folder the file lives in.
  String family;

  /// Whether `<name>_original.png` already exists on disk.
  bool hasDiskOriginal;

  bool selectedForExport = false;

  /// True when the current snapshot differs from the original.
  bool isModified = false;

  /// Last-used background removal tolerance (percentage), per image.
  double tolerancePercent = 30;

  static const maxHistory = 25;

  final List<ResourceSnapshot> _history;

  List<ResourceSnapshot> get history => List.unmodifiable(_history);

  ResourceSnapshot get snapshot => _history.last;

  ResourceSnapshot get original => _history.first;

  int get width => snapshot.width;

  int get height => snapshot.height;

  String get stem {
    final slash = sourcePath.lastIndexOf('/');
    final dot = sourcePath.lastIndexOf('.');
    final start = slash < 0 ? 0 : slash + 1;
    final end = dot <= start ? sourcePath.length : dot;
    return sourcePath.substring(start, end);
  }

  /// Commit an edit onto the undo stack (discarding any entries after the
  /// current one and capping the total size).
  void pushSnapshot(ResourceSnapshot s) {
    _history.add(s);
    if (_history.length > maxHistory) {
      _history.removeRange(1, _history.length - maxHistory);
    }
    isModified = _history.length > 1;
  }

  /// Roll the working state back to history entry [index].
  void rollbackTo(int index) {
    final target = index.clamp(0, _history.length - 1);
    if (target >= _history.length) return;
    _history.removeRange(target + 1, _history.length);
    isModified = target != 0;
  }
}
