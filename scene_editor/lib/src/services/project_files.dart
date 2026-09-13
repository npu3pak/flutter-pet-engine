import 'dart:io';

import 'package:path/path.dart' as p;

/// Pure file helpers for the iPad project browser (Documents-based):
/// scanning project folders and copying folders into the sandbox.

/// Lists the subfolders of [rootDir] that contain a `project.json`
/// (sorted by name, folders first like the Files app).
Future<List<String>> scanProjects(String rootDir) async {
  final root = Directory(rootDir);
  if (!await root.exists()) return const [];
  final result = <String>[];
  await for (final e in root.list(followLinks: false)) {
    if (e is! Directory) continue;
    if (await File(p.join(e.path, 'project.json')).exists()) {
      result.add(e.path);
    }
  }
  result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

/// Recursively copies [src] into [dst] (creating it). Returns an error
/// message, or null on success.
Future<String?> copyDirectory(String src, String dst) async {
  final source = Directory(src);
  if (!await source.exists()) return 'Каталог не найден: $src';
  try {
    await _copyRecursive(source, Directory(dst));
    return null;
  } catch (e) {
    return 'Не удалось скопировать: $e';
  }
}

Future<void> _copyRecursive(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  await for (final e in src.list(followLinks: false)) {
    final target = p.join(dst.path, p.basename(e.path));
    if (e is Directory) {
      await _copyRecursive(e, Directory(target));
    } else if (e is File) {
      await File(target).writeAsBytes(await e.readAsBytes(), flush: true);
    }
  }
}
