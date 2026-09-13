import 'dart:convert';
import 'dart:typed_data';

import '../models/model3d_entry.dart';
import '../models/model_scene.dart';
import '../models/scene_loader.dart';
import '../services/gltf_asset_store.dart';
import '../services/texture_cache.dart';
import 'gltf_catalog.dart';
import 'project_source.dart';

/// Opens a project from any [ProjectSource] and owns its runtime-facing
/// resources: the model catalog (`models/*.json`), the texture/sprite caches
/// and the `3d_models/` glTF catalog + asset store. Everything the 3D layer
/// ([ModelRenderer]) needs resolves through this manager.
///
/// Byte access goes through the source, so the same code serves desktop
/// (folder), mobile (bundled assets) and, later, network projects.
class GameResourceManager {
  final ProjectSource source;

  /// Display name from `project.json` (`name`), falling back to the source
  /// label.
  late String name;

  /// Models keyed by file id (name without `.json`), sorted by id.
  final Map<String, ModelData> models = {};

  /// Per-file load errors (parse failures) — non-fatal, listed for the UI.
  final List<String> loadErrors = [];

  /// Texture/sprite cache bound to the source.
  late final TextureCache textures;

  /// Imported `3d_models/` assets bound to the source.
  late final GltfAssetStore gltfAssets;

  /// The discovered `3d_models/` catalog keyed by catalog name.
  final Map<String, Model3dEntry> _gltfCatalog = {};

  /// File names of `textures/` and `sprites/` (PNG only, sorted).
  List<String> textureKeys = const [];
  List<String> spriteKeys = const [];

  /// True once [open] finished the glTF catalog scan.
  bool get gltfCatalogReady => _gltfCatalogScanned;
  bool _gltfCatalogScanned = false;

  GameResourceManager(this.source)
      : name = 'project' {
    final read = source.readBytes;
    textures = TextureCache(
      texturesDir: 'textures',
      spritesDir: 'sprites',
      byteLoader: read,
    );
    gltfAssets = GltfAssetStore(byteLoader: read);
  }

  /// Loads `project.json`, every `models/*.json`, the resource keys and the
  /// glTF catalog. Call once before rendering scenes.
  Future<void> open() async {
    await openProject();
    await openModels();
  }

  /// Stage «проект» of the level loader: reads `project.json` (display name),
  /// the `textures/`/`sprites/` keys and scans the `3d_models/` catalog.
  Future<void> openProject() async {
    loadErrors.clear();
    _gltfCatalog.clear();
    _gltfCatalogScanned = false;

    final metaText = await source.readText('project.json');
    name = _projectName(metaText) ?? source.label;
    textureKeys = await _pngNames('textures');
    spriteKeys = await _pngNames('sprites');
    _gltfCatalog
      ..clear()
      ..addAll(await const GltfCatalogScanner().scan(source));
    _gltfCatalogScanned = true;
  }

  /// Stage «модели» of the level loader: re-reads every `models/*.json`.
  Future<void> openModels() async {
    models.clear();
    await _reloadModels();
  }

  Future<void> _reloadModels() async {
    final files = await source.listFiles('models');
    for (final f in files) {
      if (!f.toLowerCase().endsWith('.json')) continue;
      final id = _stem(f);
      try {
        final text = await source.readText(f);
        if (text == null) continue;
        models[id] = loadModelData(text, id: id);
      } catch (e) {
        loadErrors.add('$f: $e');
      }
    }
  }

  /// Re-reads `models/*.json` from the source (keeps in-memory edits of the
  /// currently open models untouched).
  Future<void> reloadModels() => _reloadModels();

  /// Sorted model ids.
  List<String> get modelIds => models.keys.toList();

  /// A loaded model by id, or null.
  ModelData? model(String id) => models[id];

  /// The `3d_models/` entry by catalog name, or null (deleted/unknown).
  Model3dEntry? gltfEntry(String name) => _gltfCatalog[name];

  /// Every `3d_models/` entry, sorted by name (the editor's catalog panel).
  List<Model3dEntry> get gltfEntries =>
      _gltfCatalog.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Writes [model] back to `models/<id>.json` (read-only sources throw).
  Future<void> saveModel(ModelData model) async {
    final json = const JsonEncoder.withIndent('  ').convert(model.toJson());
    await source.writeBytes('models/${model.id}.json',
        Uint8List.fromList(utf8.encode(json)));
    model.dirty = false;
  }

  /// Drops every cached texture/glTF import — call after replacing resource
  /// files underneath the source (dynamic downloads etc.).
  void invalidateResources() {
    textures.invalidate();
    gltfAssets.invalidateAll();
  }

  /// Re-colors a glTF resource of the catalog: [overrides] maps URIs inside
  /// the model's folder (e.g. `'textures/MI_Cat_diffuse.png'`) to replacement
  /// bytes. The cached import of [name] is dropped — the next scene rebuild
  /// re-imports the resource with the overrides.
  void setGltfTextureOverride(
          String name, Map<String, Uint8List> overrides) =>
      gltfAssets.setUriOverrides(name, overrides);

  /// Clears the texture overrides of [name] (re-imports the original file).
  void clearGltfTextureOverride(String name) =>
      gltfAssets.setUriOverrides(name, null);

  /// Reads a resource file's bytes through the source (null when missing).
  Future<Uint8List?> resourceBytes(String relPath) =>
      source.readBytes(relPath);

  /// Releases the glTF store (a [ChangeNotifier]).
  void dispose() => gltfAssets.dispose();

  String? _projectName(String? text) {
    if (text == null) return null;
    try {
      final m = jsonDecode(text) as Map<String, Object?>;
      final n = m['name'];
      return n is String && n.trim().isNotEmpty ? n.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _pngNames(String dir) async {
    final files = await source.listFiles(dir);
    return [
      for (final f in files)
        if (f.toLowerCase().endsWith('.png')) _stem(f),
    ];
  }

  static String _stem(String relPath) {
    final slash = relPath.lastIndexOf('/');
    final base = slash >= 0 ? relPath.substring(slash + 1) : relPath;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
