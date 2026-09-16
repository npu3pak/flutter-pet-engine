import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'billboard_batch.dart';
import 'engine_node.dart';
import 'sprite_atlas.dart';

/// One sprite of a ground-fog layer's flipbook atlas: the semantic [key] the
/// game's fog instances refer to and the [assetPath] the engine composes into
/// the atlas. A missing asset simply drops that sprite from the atlas.
class GroundFogSprite {
  const GroundFogSprite({required this.key, required this.assetPath});

  final String key;
  final String assetPath;
}

/// One world-anchored fog cloud of the current frame: where it sits, how big
/// it is and how opaque it is. The game's placement logic (`placeGroundFog`)
/// produces these; the layer only packs them into its batch.
class FogInstance {
  const FogInstance({
    required this.spriteKey,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  final String spriteKey;
  final double x, y, z;
  final double width, height;
  final double rotation;
  final double opacity;
}

/// The engine's creeping ground-fog layer (механизм): soft cloud billboards
/// composited at runtime into a flipbook atlas and drawn as ONE instanced
/// [BillboardBatch] — a floor's mist costs a single draw call. Each cloud is
/// tinted through its per-instance color (the atlas sprites are white, so
/// `color × opacity` shows through).
///
/// The layer owns no placement rules: the game decides which clouds exist
/// ([FogInstance]s) and how they drift; the layer packs them. The atlas is
/// built by [prepare] (the level loader awaits it before showing the level)
/// and SURVIVES [reset] — a floor rebuild must not re-upload textures, and
/// the batch is recreated synchronously from the cached atlas on the next
/// [update].
class GroundFogLayer {
  GroundFogLayer({
    required List<GroundFogSprite> sprites,
    required this.capacity,
    this.blendOrder = 0.0,
    this.linearSampling = true,
  }) : _sprites = List.unmodifiable(sprites);

  final List<GroundFogSprite> _sprites;

  /// Maximum number of clouds packed per frame.
  final int capacity;

  /// Translucent-pass layering vs the decor billboards the clouds intersect
  /// (positive = in front of everything, negative = behind; 0 = depth sort).
  final double blendOrder;

  /// Soft clouds want linear sampling; crisp fields may opt into nearest.
  final bool linearSampling;

  Node? _parent;
  SpriteAtlas? _atlas;
  String _atlasSignature = '';
  Map<String, int> _frames = const {};
  BillboardBatch? _batch;
  bool _disposed = false;

  /// The batch node, or null before the atlas is ready.
  Node? get node => _batch?.node;

  /// Whether the atlas is composed and the batch exists.
  bool get ready => _batch != null;

  /// Composes the atlas (idempotent) and creates the batch. Await it before
  /// the level is shown (a level-loader extra resource) so the first frame
  /// already carries the mist.
  Future<void> prepare() async {
    if (_disposed || _sprites.isEmpty) return;
    final signature = _sprites.map((s) => s.assetPath).join('|');
    if (signature != _atlasSignature) {
      _atlasSignature = signature;
      _atlas = null;
      _frames = const {};
      _disposeBatch();
      final atlas = await buildSpriteAtlas(
        [for (final s in _sprites) s.assetPath],
        sampling: linearSampling ? AtlasSampling.linear : AtlasSampling.nearest,
      );
      if (_disposed || atlas == null) return;
      _atlas = atlas;
      _frames = spriteFrameMap([
        for (final s in _sprites) (key: s.key, path: s.assetPath),
      ], atlas.keys);
    }
    _ensureBatch();
  }

  /// Repacks the layer for the current frame. [tint] is the biome fog color
  /// (linear); each instance contributes its own opacity. Instances beyond
  /// the capacity are dropped.
  void update(List<FogInstance> instances, {required vm.Vector3 tint}) {
    if (_disposed) return;
    _ensureBatch();
    final batch = _batch;
    if (batch == null) return;
    final count = instances.length > batch.capacity
        ? batch.capacity
        : instances.length;
    var written = 0;
    for (var i = 0; i < count; i++) {
      final p = instances[i];
      final frame = _frames[p.spriteKey];
      if (frame == null) continue;
      batch.setInstance(
        written,
        center: vm.Vector3(p.x, p.y, p.z),
        width: p.width,
        height: p.height,
        rotation: p.rotation,
        color: vm.Vector4(tint.x, tint.y, tint.z, p.opacity),
        frame: frame.toDouble(),
      );
      written++;
    }
    batch.commit(written);
  }

  /// Attaches the batch under [parent] (safe before or after [prepare]).
  void attachTo(Node parent) {
    _parent = parent;
    final batch = _batch;
    if (batch == null) return;
    final current = batch.node.parent;
    if (current == parent) return;
    if (current != null) current.remove(batch.node);
    parent.add(batch.node);
  }

  /// The engine-facade variant of [attachTo]: accepts an [EngineNode].
  void attachToNode(EngineNode parent) => attachTo(parent.raw);

  /// Drops the batch (and its node) but keeps the composed atlas — the next
  /// [update] recreates the batch from the cache without a GPU re-upload.
  void reset() => _disposeBatch();

  /// Detaches and releases the atlas. The layer cannot be used after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeBatch();
    _atlas = null;
    _frames = const {};
  }

  void _ensureBatch() {
    if (_disposed || _batch != null || _atlas == null) return;
    if (capacity <= 0 || _sprites.isEmpty) return;
    final atlas = _atlas!;
    if (atlas.keys.isEmpty) return;
    final batch = BillboardBatch(
      capacity: capacity,
      atlas: atlas.texture,
      blendOrder: blendOrder,
      flipbookColumns: atlas.keys.length,
      flipbookRows: 1,
    )..worldUp = vm.Vector3(0, 1, 0);
    _batch = batch;
    final parent = _parent;
    if (parent != null) parent.add(batch.node);
  }

  void _disposeBatch() {
    final batch = _batch;
    _batch = null;
    batch?.dispose();
  }
}
