/// A 3D model entry in the project's `3d_models/` catalog.
///
/// Two storage layouts are supported (the glTF convention of Sketchfab
/// downloads and the engine's runtime importer):
///
/// 1. **glTF folder** — a subfolder containing `*.gltf` plus its sibling
///    `*.bin`/texture files (referenced by relative URI). The entry is the
///    first `*.gltf` file found directly inside the folder.
/// 2. **GLB file** — a single self-contained `*.glb` beside nothing else.
///
/// The catalog is discovered purely from disk (no `project.json` index):
/// the model is self-contained in its folder/file, so an index entry would
/// only duplicate what the file system already stores.
class Model3dEntry {
  /// Catalog name of the model — the folder name (glTF) or the file stem
  /// (GLB). Unique within the catalog, valid as a file/folder name.
  final String name;

  /// True for a glTF folder entry, false for a single `.glb` file.
  final bool isFolder;

  /// Absolute path of the entry file: the `.gltf` for folders, the `.glb`
  /// for file entries. The viewer loads the model from here.
  final String sourcePath;

  /// Total size on disk of the model (sum over the folder contents for
  /// glTF folders, the file size for GLB), in bytes.
  final int sizeBytes;

  const Model3dEntry({
    required this.name,
    required this.isFolder,
    required this.sourcePath,
    required this.sizeBytes,
  });

  /// Storage kind label for tiles/panels («glTF» / «GLB»).
  String get kindLabel => isFolder ? 'glTF' : 'GLB';

  /// File name of the entry file (for tooltips).
  String get entryFileName {
    final sep = sourcePath.lastIndexOf('/');
    return sep >= 0 ? sourcePath.substring(sep + 1) : sourcePath;
  }

  /// Human-readable size («2.4 МБ» / «820 КБ»).
  String get sizeLabel {
    const kb = 1024.0, mb = kb * 1024;
    if (sizeBytes >= mb) {
      return '${(sizeBytes / mb).toStringAsFixed(1)} МБ';
    }
    if (sizeBytes >= kb) {
      return '${(sizeBytes / kb).round()} КБ';
    }
    return '$sizeBytes Б';
  }
}
