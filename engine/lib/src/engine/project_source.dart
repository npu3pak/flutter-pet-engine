import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;

/// A container of a project folder: `project.json`, `models/*.json`,
/// `textures/*.png`, `sprites/*.png` and `3d_models/…` — addressed by
/// ROOT-RELATIVE slash paths regardless of the physical backing.
///
/// The engine reads every byte through this abstraction: a game can load a
/// project from a local folder (desktop development), from a bundled asset
/// (mobile apps) or, later, from the network — without touching the renderer.
abstract class ProjectSource {
  /// Human-readable description (path / asset prefix) for logs and UI.
  String get label;

  /// Reads one file; null when the file does not exist.
  Future<Uint8List?> readBytes(String relPath);

  /// All FILES under [relDir], recursively, as root-relative slash paths in
  /// sorted order; empty when the directory does not exist.
  Future<List<String>> listFiles(String relDir);

  /// Writes/overwrites one file (parent folders created). Read-only sources
  /// throw [UnsupportedError].
  Future<void> writeBytes(String relPath, Uint8List bytes);

  /// True when [writeBytes] is supported.
  bool get writable;

  /// Reads [relPath] and decodes it as UTF-8 text (null when missing).
  Future<String?> readText(String relPath) async {
    final bytes = await readBytes(relPath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Writes [text] as UTF-8 (see [writeBytes]).
  Future<void> writeText(String relPath, String text) =>
      writeBytes(relPath, Uint8List.fromList(utf8.encode(text)));
}

/// Optional capability of a writable [ProjectSource]: deleting and renaming
/// files. Kept separate so custom sources stay source-compatible.
abstract interface class MutableProjectSource {
  /// Deletes one file (no-op when it does not exist).
  Future<void> deleteBytes(String relPath);

  /// Renames a file inside the source.
  Future<void> renameBytes(String from, String to);
}

/// Local-folder backing: every path resolves under [root].
class DirectoryProjectSource extends ProjectSource
    implements MutableProjectSource {
  final Directory root;

  DirectoryProjectSource(this.root);

  @override
  String get label => root.path;

  @override
  bool get writable => true;

  String _abs(String rel) => p.join(root.path, rel);

  @override
  Future<Uint8List?> readBytes(String relPath) async {
    final f = File(_abs(relPath));
    return f.existsSync() ? f.readAsBytes() : null;
  }

  @override
  Future<List<String>> listFiles(String relDir) async {
    final dir = Directory(_abs(relDir));
    if (!dir.existsSync()) return const [];
    final out = <String>[];
    final relBase = relDir.isEmpty ? '' : '$relDir/';
    void walk(Directory d, String relPrefix) {
      for (final e in d.listSync(followLinks: false)) {
        if (e is File) {
          out.add('$relBase$relPrefix${p.basename(e.path)}');
        } else if (e is Directory) {
          walk(e, '$relPrefix${p.basename(e.path)}/');
        }
      }
    }

    walk(dir, '');
    out.sort();
    return out;
  }

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) async {
    final f = File(_abs(relPath));
    f.parent.createSync(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteBytes(String relPath) async {
    final f = File(_abs(relPath));
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<void> renameBytes(String from, String to) async {
    final source = File(_abs(from));
    final target = File(_abs(to));
    target.parent.createSync(recursive: true);
    if (source.existsSync()) {
      await source.rename(target.path);
    }
  }
}

/// Asset-bundle backing: files staged under a fixed asset prefix (a
/// `manifest.json` inside the prefix lists every staged file). Read-only.
///
/// Flutter asset directory entries are not recursive, so a flattened bundle
/// lays the files out with slashes encoded as `__` and keeps a
/// `manifest.json` of the original root-relative paths.
class BundleProjectSource extends ProjectSource {
  /// Asset key prefix of the staged project root (e.g.
  /// `'assets/pet_project/'`). The manifest lives at
  /// `[assetPrefix]manifest.json`.
  final String assetPrefix;

  /// Files staged under the root, root-relative (from the manifest); null
  /// until [manifest] completes.
  Future<List<String>>? _manifest;

  BundleProjectSource(this.assetPrefix);

  /// Asset key of a root-relative path (slashes encoded as `__`).
  static String assetKeyOf(String relPath) =>
      relPath.replaceAll('/', '__');

  @override
  String get label => assetPrefix;

  @override
  bool get writable => false;

  Future<List<String>> _manifestFiles() async {
    final loader = _manifest ??= _loadManifest();
    return loader;
  }

  Future<List<String>> _loadManifest() async {
    final key = '$assetPrefix${'manifest.json'}';
    final data = await rootBundle.load(key);
    final list = (jsonDecode(utf8.decode(data.buffer.asUint8List())) as List)
        .cast<String>();
    list.sort();
    return list;
  }

  @override
  Future<Uint8List?> readBytes(String relPath) async {
    try {
      final data =
          await rootBundle.load('$assetPrefix${assetKeyOf(relPath)}');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<String>> listFiles(String relDir) async {
    final files = await _manifestFiles();
    final prefix = relDir.isEmpty ? '' : '$relDir/';
    return [
      for (final f in files)
        if (f.startsWith(prefix) && (relDir.isEmpty || f.length > prefix.length)) f,
    ];
  }

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) =>
      throw UnsupportedError('BundleProjectSource is read-only');
}

/// Asset-bundle backing for a project stored as PLAIN Flutter assets: the
/// original folder layout (`project.json`, `models/…`, `textures/…`,
/// `sprites/…`, `3d_models/…`) is declared directory-by-directory in the
/// application's pubspec, so files keep their root-relative paths — unlike
/// the flattened [BundleProjectSource]. Read-only.
class AssetProjectSource extends ProjectSource {
  /// Asset key prefix of the project root (e.g. `'assets/Pet/'`), with a
  /// trailing slash.
  final String assetPrefix;

  AssetProjectSource(this.assetPrefix);

  /// All asset keys of the application, cached per instance.
  Future<List<String>>? _assets;

  @override
  String get label => assetPrefix;

  @override
  bool get writable => false;

  Future<List<String>> _allAssets() => _assets ??= _loadAssets();

  Future<List<String>> _loadAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets();
  }

  @override
  Future<Uint8List?> readBytes(String relPath) async {
    try {
      final data = await rootBundle.load('$assetPrefix$relPath');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<String>> listFiles(String relDir) async {
    final prefix = relDir.isEmpty ? assetPrefix : '$assetPrefix$relDir/';
    final assets = await _allAssets();
    final files = [
      for (final key in assets)
        if (key.startsWith(prefix) && key.length > prefix.length)
          key.substring(assetPrefix.length),
    ];
    files.sort();
    return files;
  }

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) =>
      throw UnsupportedError('AssetProjectSource is read-only');
}
