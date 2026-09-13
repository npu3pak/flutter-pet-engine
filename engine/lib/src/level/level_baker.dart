import 'dart:convert';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model3d_entry.dart';
import '../models/model_scene.dart';
import '../render/engine_material.dart';
import '../render/static_merge.dart';
import '../scene/model_renderer.dart';
import '../services/gltf_asset_store.dart';
import '../services/texture_cache.dart';
import 'construction_model.dart';

/// The pure (GPU-free) bake plan of a construction model: which elements
/// merge, batch or stay separate, and the group key of each merge/batch
/// element. Testable without a video card; [LevelBaker.bake] executes it.
class LevelBakePlan {
  const LevelBakePlan({
    required this.modes,
    required this.groupKeys,
    required this.groupCounts,
  });

  /// Element id → its bake mode.
  final Map<String, BakeMode> modes;

  /// Merge/batch element id → its group key (elements with the same key
  /// share one baked mesh).
  final Map<String, String> groupKeys;

  /// Group key → element count.
  final Map<String, int> groupCounts;

  /// Groups of two or more elements become one mesh; a group of one stays a
  /// separate node.
  int _meshes(BakeMode mode) => groupKeys.entries
      .where((e) => modes[e.key] == mode)
      .map((e) => e.value)
      .toSet()
      .where((key) => (groupCounts[key] ?? 0) >= 2)
      .length;

  int get mergedMeshes => _meshes(BakeMode.merge);
  int get batchMeshes => _meshes(BakeMode.batch);

  /// Elements that end up as separate nodes: explicit [BakeMode.node] plus
  /// groups of one.
  int get separateNodes => modes.values
          .where((m) => m == BakeMode.node)
          .length +
      groupKeys.entries
          .where((e) => (groupCounts[e.value] ?? 0) < 2)
          .length;
}

/// Statistics of one [LevelBaker.bake] run — measurements for the perf
/// journal, never an optimization trigger by themselves.
class LevelBakeStats {
  const LevelBakeStats({
    required this.elements,
    required this.mergedMeshes,
    required this.batchMeshes,
    required this.separateNodes,
    required this.vertices,
    required this.triangles,
  });

  final int elements;
  final int mergedMeshes;
  final int batchMeshes;
  final int separateNodes;
  final int vertices;
  final int triangles;

  @override
  String toString() =>
      'elements=$elements merged=$mergedMeshes batch=$batchMeshes '
      'nodes=$separateNodes vertices=$vertices triangles=$triangles';
}

/// Called once per unique material of a baked level after the geometry pass,
/// before the merge — the game applies its material recipes here (the wet
/// look of rain biomes, tinting). [tags] are the element tags that resolved
/// to this material (empty when the element carries none), [sprite] is true
/// only when every contributing element is a billboard sprite.
///
/// Internal engine-material hook; the public `BakedMaterialHook` of the API
/// wraps it with `SceneMaterial`.
typedef LevelMaterialHook = void Function(
  EngineMaterial material, {
  required bool sprite,
  required Set<String> tags,
});

/// The baked level: a render root plus the separate nodes addressable by
/// element id ([BakeMode.node] and single-element groups). A multi-part
/// element (a model instance, a csg result) gets ONE wrapper node named
/// `obj:<id>` so the game can move/update the whole element.
class LevelBakeResult {
  const LevelBakeResult({
    required this.root,
    required this.nodes,
    required this.stats,
    required this.buildTime,
    this.billboards = const [],
  });

  final Node root;

  /// Element id → its separate node (a wrapper for multi-part elements).
  final Map<String, Node> nodes;

  final LevelBakeStats stats;
  final Duration buildTime;

  /// Billboard sprites of the baked level: top-level sprites carry a null
  /// chain (their node transform holds the anchor), sprites nested in model
  /// instances carry the instance chain without yaw.
  final List<(Node, vm.Matrix4?)> billboards;

  /// Reorients every baked billboard toward the camera with the given
  /// camera-local forward — call per frame. [GameScene.update] does it for
  /// engine-managed levels; a game owning its own scene calls it from its
  /// render loop.
  void reorientBillboards(double fx, double fz) {
    if (billboards.isEmpty) return;
    final yaw = screenParallelYaw(fx, fz);
    final mirrorYaw =
        vm.Matrix4.diagonal3Values(-1, 1, 1) * vm.Matrix4.rotationY(yaw);
    for (final (node, chain) in billboards) {
      if (chain != null) {
        node.localTransform = chain * mirrorYaw;
      } else {
        // The top-level sprite transform is T(anchor)·mirror·R(rotY): the
        // translation part is the anchor, the rest is replaced by the yaw.
        final anchor = node.localTransform.getTranslation();
        node.localTransform = vm.Matrix4.translation(anchor) * mirrorYaw;
      }
    }
  }
}

/// Turns a construction model into render content by the element's bake mode
/// (plan §3.10):
/// - [BakeMode.merge] — one shared static mesh per material;
/// - [BakeMode.batch] — one shared mesh per shape+material (CPU grouping;
///   true GPU instancing is phase 6);
/// - [BakeMode.node] — a separate node the game can move/update without a
///   content rebuild. Sprites, model and gltf instances are always node
///   mode ([bakeModeOf]).
///
/// The grouping decision is [plan] (pure, tested without a GPU); the geometry
/// and materials are `ModelRenderer`'s (no duplication), and the merge uses
/// the same helper as the renderer's `mergeStatic`. Merge/batch groups key on
/// the RESOLVED material of each part, so per-face materials and csg results
/// never merge unrelated geometry; the batch key adds the element shape.
class LevelBaker {
  final ModelRenderer _renderer;

  LevelBaker(
    TextureCache textures, {
    GltfAssetStore? gltfAssets,
    ModelData? Function(String id)? modelCatalog,
    Model3dEntry? Function(String name)? gltfCatalog,
    bool Function()? gltfCatalogReady,
    void Function(String modelId, String objId, List<double> bounds)?
        onGltfFootprint,
  }) : _renderer = ModelRenderer(
          textures,
          gltfAssets: gltfAssets,
          mergeStatic: false,
        ) {
    if (modelCatalog != null) _renderer.modelCatalog = modelCatalog;
    if (gltfCatalog != null) _renderer.gltfCatalog = gltfCatalog;
    if (gltfCatalogReady != null) _renderer.gltfCatalogReady = gltfCatalogReady;
    if (onGltfFootprint != null) _renderer.onGltfFootprint = onGltfFootprint;
  }

  /// Builds the pure bake plan: mode per element and merge/batch group keys.
  LevelBakePlan plan(ConstructionModel model) {
    final modes = <String, BakeMode>{};
    final groupKeys = <String, String>{};
    final counts = <String, int>{};
    for (final o in model.data.visibleObjects()) {
      final mode = bakeModeOf(o);
      modes[o.id] = mode;
      if (mode == BakeMode.node) continue;
      final key = mode == BakeMode.batch
          ? 'b|${_shapeKey(o)}|${_materialKey(o)}'
          : 'm|${_materialKey(o)}';
      groupKeys[o.id] = key;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return LevelBakePlan(
      modes: modes,
      groupKeys: groupKeys,
      groupCounts: counts,
    );
  }

  /// Bakes [model] into render content by the plan. Vertex/triangle
  /// statistics are measurement-only and collected only when [collectStats]
  /// is true (the counting pass reads every output mesh).
  ///
  /// [onGeometryBuilt] fires right after the geometry rebuild and before the
  /// merge pass — the level loader uses it to report the «геометрия» stage
  /// separately from «запекание». [onMaterial] fires for every unique
  /// material after the geometry pass (see [BakedMaterialHook]).
  LevelBakeResult bake(
    ConstructionModel model, {
    bool collectStats = false,
    void Function()? onGeometryBuilt,
    LevelMaterialHook? onMaterial,
  }) {
    final sw = Stopwatch()..start();
    final plan = this.plan(model);
    _renderer.rebuild(model.data);
    onGeometryBuilt?.call();

    // Snapshot the billboards before the nodes move under wrappers/merges:
    // the registry references the same node instances and stays valid.
    final billboards = _renderer.billboards;

    if (onMaterial != null) _emitMaterials(model, onMaterial);

    final mergeNodes = <Node>[];
    final batchNodes = <Node>[];
    final separate = <Node>[];
    for (final node in List<Node>.of(_renderer.root.children)) {
      final id = _renderer.elementOfNode[node];
      final mode =
          id == null ? BakeMode.node : (plan.modes[id] ?? BakeMode.node);
      switch (mode) {
        case BakeMode.merge:
          mergeNodes.add(node);
        case BakeMode.batch:
          batchNodes.add(node);
        case BakeMode.node:
          separate.add(node);
      }
    }

    Object groupKeyOf(Node node, Material material) {
      final id = _renderer.elementOfNode[node];
      if (id == null) return material;
      if (plan.modes[id] != BakeMode.batch) return material;
      final obj = model.byId(id);
      return (material, obj == null ? id : _shapeKey(obj));
    }

    final merged = mergeStaticNodes(mergeNodes, groupKey: groupKeyOf);
    final batched = mergeStaticNodes(batchNodes, groupKey: groupKeyOf);

    final root = Node(name: 'level:${model.id}');
    _renderer.root.removeAll();
    for (final node in merged.merged) {
      root.add(node);
    }
    for (final node in batched.merged) {
      root.add(node);
    }

    // Leftovers (groups of one) and node-mode parts: group by element id so
    // a multi-part element gets ONE addressable wrapper node.
    final consumed = {...merged.consumed, ...batched.consumed};
    final kept = <String, List<Node>>{};
    final unknown = <Node>[];
    for (final node in [...mergeNodes, ...batchNodes, ...separate]) {
      if (consumed.contains(node)) continue;
      final id = _renderer.elementOfNode[node];
      if (id == null) {
        unknown.add(node);
      } else {
        kept.putIfAbsent(id, () => []).add(node);
      }
    }
    final nodes = <String, Node>{};
    for (final entry in kept.entries) {
      final list = entry.value;
      if (list.length == 1) {
        root.add(list.first);
        nodes[entry.key] = list.first;
      } else {
        final wrapper = Node(name: '$objectNodePrefix${entry.key}');
        for (final node in list) {
          wrapper.add(node);
        }
        root.add(wrapper);
        nodes[entry.key] = wrapper;
      }
    }
    for (final node in unknown) {
      root.add(node);
    }

    // Vertex/triangle counts need a readable-mesh pass over every output
    // mesh (`extractMeshData`); they are measurement-only and opt-in so the
    // hot path stays clean (review note 3).
    var vertices = 0;
    var triangles = 0;
    if (collectStats) {
      for (final node in root.children) {
        final mesh = node.mesh;
        if (mesh == null) continue;
        for (final primitive in mesh.primitives) {
          final data = primitive.geometry.extractMeshData();
          vertices += data.vertexCount;
          triangles += (data.indices?.length ?? data.vertexCount) ~/ 3;
        }
      }
    }
    sw.stop();
    return LevelBakeResult(
      root: root,
      nodes: nodes,
      stats: LevelBakeStats(
        elements: model.elements.length,
        mergedMeshes: merged.merged.length,
        batchMeshes: batched.merged.length,
        separateNodes: nodes.length + unknown.length,
        vertices: vertices,
        triangles: triangles,
      ),
      buildTime: sw.elapsed,
      billboards: billboards,
    );
  }

  /// Calls [hook] once per unique material of the current rebuild, with the
  /// tags of the elements using it and whether it belongs to sprites only.
  void _emitMaterials(ConstructionModel model, LevelMaterialHook hook) {
    final tags = <Material, Set<String>>{};
    final sprites = <Material, bool>{};
    for (final node in _renderer.root.children) {
      final mesh = node.mesh;
      if (mesh == null) continue;
      final id = _renderer.elementOfNode[node];
      final obj = id == null ? null : model.byId(id);
      final tag = obj?.tag;
      final sprite = obj?.kind == 'sprite';
      for (final primitive in mesh.primitives) {
        final material = primitive.material;
        sprites.update(material, (v) => v && sprite, ifAbsent: () => sprite);
        if (tag != null) {
          tags.putIfAbsent(material, () => <String>{}).add(tag);
        }
      }
    }
    for (final material in sprites.keys) {
      hook(EngineMaterial.wrap(material),
          sprite: sprites[material] ?? false,
          tags: tags[material] ?? const <String>{});
    }
  }

  static String _materialKey(ModelObject obj) {
    final mat = obj.material;
    final faces = obj.faces;
    if (mat == null && faces.isEmpty) return 'none';
    return jsonEncode({
      'm': mat?.toJson(),
      'f': {for (final e in faces.entries) e.key: e.value.toJson()},
    });
  }

  static String _shapeKey(ModelObject obj) {
    final keys = obj.dims.keys.toList()..sort();
    final dims = [for (final k in keys) '$k=${obj.dims[k]}'].join(',');
    return '${obj.kind}:$dims';
  }
}
