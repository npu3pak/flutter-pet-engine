import '../models/model3d_entry.dart';
import 'project_source.dart';

/// Discovers the `3d_models/` catalog of a project from any [ProjectSource]:
///
/// 1. **glTF folder** — a folder containing a top-level `*.gltf` (entry name
///    = folder name, the glTF file may be any of its top-level files);
/// 2. **GLB file** — a single top-level `3d_models/<name>.glb`.
///
/// The result is keyed by catalog name (sorted for a stable order). The
/// entries' [Model3dEntry.sourcePath] is root-relative ('3d_models/…') and is
/// resolved by the byte loader of the source.
class GltfCatalogScanner {
  const GltfCatalogScanner();

  Future<Map<String, Model3dEntry>> scan(ProjectSource source) async {
    final out = <String, Model3dEntry>{};
    final all = await source.listFiles('3d_models');
    final top = <String>[];
    final folders = <String>{};
    final folderGltf = <String, String>{};
    for (final f in all) {
      final rel = f.startsWith('3d_models/') ? f.substring('3d_models/'.length) : f;
      if (rel.isEmpty) continue;
      final slash = rel.indexOf('/');
      if (slash < 0) {
        top.add(rel);
      } else {
        final folder = rel.substring(0, slash);
        folders.add(folder);
        final rest = rel.substring(slash + 1);
        if (!rest.contains('/') && _isGltf(rest)) {
          folderGltf.putIfAbsent(folder, () => f);
        }
      }
    }
    final glbNames = top.where(_isGlb).toList()..sort();
    for (final glb in glbNames) {
      final name = glb.substring(0, glb.length - 4);
      out[name] = Model3dEntry(
        name: name,
        isFolder: false,
        sourcePath: '3d_models/$glb',
        sizeBytes: 0,
      );
    }
    final folderNames = folders.toList()..sort();
    for (final name in folderNames) {
      final gltf = folderGltf[name];
      if (gltf == null) continue; // no top-level .gltf inside — not an entry
      out[name] = Model3dEntry(
        name: name,
        isFolder: true,
        sourcePath: gltf,
        sizeBytes: 0,
      );
    }
    return out;
  }

  static bool _isGltf(String name) => name.toLowerCase().endsWith('.gltf');
  static bool _isGlb(String name) => name.toLowerCase().endsWith('.glb');
}
