import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../models/model3d_entry.dart';
import 'app_log.dart';
import 'texture_alpha.dart';

/// One glTF animation of a loaded resource, ready for a picker UI.
class GltfAnimInfo {
  /// Full glTF animation name (e.g. Sketchfab's
  /// `SKM_Cat|SKM_Cat|Cat_Walk`) — the stored selection value.
  final String fullName;

  /// Short display name: the text after the last `|`, or the whole name.
  final String shortName;

  final double duration;

  GltfAnimInfo({required this.fullName, required this.shortName, required this.duration});

  /// The text after the last `|` of a glTF animation name (or the whole
  /// name) — display form used by the model viewer and the editor panels.
  static String shortOf(String name) {
    final i = name.lastIndexOf('|');
    final tail = i >= 0 ? name.substring(i + 1).trim() : '';
    return tail.isEmpty ? name : tail;
  }
}

/// A glTF/GLB resource imported by the engine's runtime importer and cached
/// for editor use. [root] is a DETACHED node tree (never attached to a
/// scene); instances clone it per use site. The tree is already fitted:
/// its local frame sits on the floor (minY = 0 at the anchor's height) with
/// the footprint centered on X/Z — see [bounds].
class LoadedGltf {
  /// The imported, fitted root node (cache master; detach/never mounted).
  final Node root;

  /// Parsed animations of the model (shared descriptors — create clips on
  /// clones via [Node.createAnimationClip]).
  final List<Animation> animations;

  /// Display descriptors of [animations] (parallel list).
  final List<GltfAnimInfo> animInfos;

  /// The footprint the fitted content occupies in its own local frame —
  /// `[minX, minY, minZ, maxX, maxY, maxZ]` with minY = 0 and X/Z centered
  /// on the anchor. Null when the model reports no bounds (skinned meshes).
  final List<double>? bounds;

  LoadedGltf({
    required this.root,
    required this.animations,
    required this.animInfos,
    this.bounds,
  });
}

/// Runtime cache of the project's imported `3d_models/` resources for the 3D
/// editor: the engine imports each glTF/GLB once (per catalog name, per
/// project session) and every gltf instance in the scenes clones the cached
/// tree (geometry/materials stay shared). Loading is lazy — it only happens
/// when a scene containing a gltf instance is actually rendered.
///
/// A [ChangeNotifier]: the AppState listens and rebuilds the viewport when a
/// load finishes (the instance can then attach its real content) or fails.
class GltfAssetStore extends ChangeNotifier {
  final Map<String, LoadedGltf> _ready = {};
  final Map<String, Future<LoadedGltf>> _loading = {};
  final Set<String> _failed = {};

  /// Optional byte loader for environments without direct file access
  /// (bundled/network assets). When set, [Model3dEntry.sourcePath] is a
  /// source-relative path (`3d_models/<name>/scene.gltf`) and every read
  /// (the entry file and its resolveUri siblings) goes through this callback
  /// instead of dart:io. A null result means "missing file".
  Future<Uint8List?> Function(String path)? byteLoader;

  /// Per-catalog-name texture/URI overrides applied on import: key = the URI
  /// inside the glTF's folder (e.g. 'textures/MI_Cat_diffuse.png'), value =
  /// replacement bytes. Lets games recolor glTF resources (re-import the same
  /// model with a different diffuse) — see [GameResourceManager.overrideGltfTextures].
  final Map<String, Map<String, Uint8List>> _uriOverrides = {};

  GltfAssetStore({this.byteLoader});

  /// Whether a load for [name] is in flight.
  bool isLoading(String name) => _loading.containsKey(name);

  /// Whether the last load attempt of [name] failed (a corrupt/unreadable
  /// file). Cleared by [invalidateAll].
  bool failed(String name) => _failed.contains(name);

  /// The loaded resource for [name], or null while loading/failed/missing.
  LoadedGltf? ready(String name) => _ready[name];

  /// Imports [entry] (deduplicated per catalog name; failures are cached as
  /// [failed]). The returned future completes when the tree is ready; UI
  /// listeners are notified through the store.
  Future<LoadedGltf> load(Model3dEntry entry) {
    final name = entry.name;
    final cached = _ready[name];
    if (cached != null) return Future.value(cached);
    return _loading.putIfAbsent(name, () async {
      try {
        final gltf = await _import(entry);
        _ready[name] = gltf;
        logStage(
          'models',
          'gltf instance loaded ${entry.name} (${entry.kindLabel}) '
              'animations=${gltf.animations.length}'
              '${gltf.bounds == null ? '' : ' bounds=${gltf.bounds!.map((v) => v.toStringAsFixed(1)).join(' ')}'}',
        );
        return gltf;
      } catch (e) {
        _failed.add(name);
        logStage('models', 'gltf instance FAIL ${entry.name}: $e');
        rethrow;
      } finally {
        _loading.remove(name);
        notifyListeners();
      }
    });
  }

  /// Drops every cached/loading/failed resource (project switch or a catalog
  /// mutation — rename/delete/import changes what the instances reference).
  void invalidateAll() {
    _ready.clear();
    _failed.clear();
    _uriOverrides.clear();
    for (final f in _loading.values) {
      // The in-flight import finishes; its result is simply not cached.
      f.ignore();
    }
    _loading.clear();
    notifyListeners();
  }

  /// Drops the cached/failed resource of one catalog name (keeps the others
  /// intact); the next render re-imports it — used after a URI override or a
  /// file replacement of a single resource.
  void invalidateName(String name) {
    _ready.remove(name);
    _failed.remove(name);
    notifyListeners();
  }

  /// Sets (or clears, when [overrides] is null) the URI overrides of
  /// [name]'s next import. The store drops the cached import of [name] — the
  /// caller rebuilds the scene to re-import with the overrides.
  void setUriOverrides(String name, Map<String, Uint8List>? overrides) {
    if (overrides == null) {
      _uriOverrides.remove(name);
    } else {
      _uriOverrides[name] = overrides;
    }
    invalidateName(name);
  }

  /// The runtime importer's async import, mirroring the model viewer's load
  /// ([Node.fromGltfBytes] with a disk resolver / [Node.fromGlbBytes]).
  Future<LoadedGltf> _import(Model3dEntry entry) async {
    final loader = byteLoader;
    final overrides = _uriOverrides[entry.name];
    Future<Uint8List?> readBytes(String path) {
      final l = loader;
      if (l != null) return l(path);
      return File(path).existsSync()
          ? File(path).readAsBytes()
          : Future.value(null);
    }

    final Node node;
    if (!entry.isFolder) {
      final bytes = await readBytes(entry.sourcePath);
      if (bytes == null) {
        throw FileSystemException('Файл не найден', entry.sourcePath);
      }
      node = await Node.fromGlbBytes(bytes);
    } else {
      final path = entry.sourcePath;
      final dir = path.substring(0, path.lastIndexOf('/'));
      final gltf = await readBytes(path);
      if (gltf == null) {
        throw FileSystemException('Файл не найден', path);
      }
      node = await Node.fromGltfBytes(
        gltf,
        resolveUri: (uri) async {
          final o = overrides?[uri];
          if (o != null) return o;
          final b = await readBytes('$dir/$uri');
          return b ?? Uint8List(0);
        },
      );
      // Cut-out models routinely ship as `alphaMode: BLEND` with a
      // binary-alpha diffuse texture; the engine's per-object translucent
      // pass would show their hidden geometry through the body (legs through
      // the torso). Reclassify such materials to `mask`/`opaque` by the
      // actual texture alpha — best effort, never fails the import. See
      // texture_alpha.dart.
      try {
        await configureGltfBlendMaterials(
          node,
          gltfDoc: jsonDecode(utf8.decode(gltf)) as Map<String, Object?>,
          readImage: (uri) async {
            final o = overrides?[uri];
            if (o != null) return o;
            return readBytes('$dir/$uri');
          },
          label: entry.name,
        );
      } catch (e) {
        logStage('models', 'gltf alpha config skipped ${entry.name}: $e');
      }
    }
    final bounds = _fitToFloor(node);
    final animations = node.parsedAnimations;
    return LoadedGltf(
      root: node,
      animations: animations,
      animInfos: [
        for (final a in animations)
          GltfAnimInfo(
            fullName: a.name,
            shortName: GltfAnimInfo.shortOf(a.name),
            duration: a.endTime,
          ),
      ],
      bounds: bounds,
    );
  }

  /// Fits [root] into the editor instance frame: the content stands on the
  /// floor (its min Y lands on the instance anchor's height) and its
  /// footprint is centered on X/Z around the anchor. The shift is applied as
  /// an extra translation OUTSIDE the importer's handedness flip (in engine
  /// frame). Returns the resulting footprint `[minX, 0, minZ, maxX, maxY,
  /// maxZ]`, or null when the model reports no bounds (skinned meshes — the
  /// tree is left as imported and the anchor follows the glTF origin).
  List<double>? _fitToFloor(Node root) {
    final b = root.combinedWorldBounds;
    if (b == null) return null;
    final min = b.min, max = b.max;
    if ((max.x - min.x) < 1e-9 && (max.y - min.y) < 1e-9 && (max.z - min.z) < 1e-9) {
      return null;
    }
    final cx = (min.x + max.x) / 2;
    final cy = min.y;
    final cz = (min.z + max.z) / 2;
    // The node transform maps the imported (flipped) frame to the engine
    // frame: left-multiplying the translation shifts the content there.
    root.localTransform =
        vm.Matrix4.translation(vm.Vector3(-cx, -cy, -cz)) * root.localTransform;
    return [
      min.x - cx,
      0,
      min.z - cz,
      max.x - cx,
      max.y - cy,
      max.z - cz,
    ];
  }
}
