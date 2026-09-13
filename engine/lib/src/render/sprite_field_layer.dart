import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'billboard_batch.dart';
import 'engine_node.dart';
import 'sprite_atlas.dart';

/// How a sprite field's quads face the camera (mirrors the fork's modes).
enum SpriteFieldFacing {
  /// Fully camera-facing (snow, particles).
  spherical,

  /// Upright and screen-parallel — a shared yaw keeps every quad vertical and
  /// facing the player (grass, decor).
  screenParallel,

  /// Stretched along the per-instance velocity (rain streaks).
  velocityStretched,
}

/// One sprite of a field's flipbook atlas: the semantic [key] instances refer
/// to and the [assetPath] composed into the atlas.
class SpriteFieldSprite {
  const SpriteFieldSprite({required this.key, required this.assetPath});

  final String key;
  final String assetPath;
}

/// One world-anchored sprite of the current frame.
class SpriteFieldInstance {
  const SpriteFieldInstance({
    required this.spriteKey,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    this.rotation = 0.0,
    this.color,
    this.velocity,
  });

  final String spriteKey;
  final double x, y, z;
  final double width, height;
  final double rotation;

  /// Per-instance linear RGBA; null keeps the layer tint.
  final vm.Vector4? color;

  /// Per-instance velocity (used by [SpriteFieldFacing.velocityStretched]).
  final vm.Vector3? velocity;
}

/// The engine's generic instanced sprite field: a list of atlas sprites is
/// composed into a flipbook atlas and every instance draws in ONE
/// [BillboardBatch] — a whole floor's grass, leaves or particles cost a
/// single draw call. The owning game decides which instances exist; the layer
/// packs them.
///
/// The atlas is built by [prepare] (await it before the level is shown) and
/// SURVIVES [reset]: a floor rebuild recreates the batch from the cached
/// atlas without a GPU re-upload.
class SpriteFieldLayer {
  SpriteFieldLayer({
    required List<SpriteFieldSprite> sprites,
    required this.capacity,
    this.facing = SpriteFieldFacing.spherical,
    this.opaque = false,
    this.blendOrder = 0.0,
    this.velocityStretch = 0.0,
    this.linearSampling = false,
    this.flipbookBlend = false,
  }) : _sprites = List.unmodifiable(sprites);

  final List<SpriteFieldSprite> _sprites;

  /// Maximum number of sprites packed per frame.
  final int capacity;

  final SpriteFieldFacing facing;

  double _screenParallelYaw = 0.0;

  /// The shared yaw (radians) of [SpriteFieldFacing.screenParallel] instances.
  /// Applied to the live batch immediately, so the application can update it
  /// while the camera turns; repacking stays one instanced call.
  double get screenParallelYaw => _screenParallelYaw;
  set screenParallelYaw(double value) {
    if (_screenParallelYaw == value) return;
    _screenParallelYaw = value;
    _batch?.screenParallelYaw = value;
  }

  /// Opaque alpha-tested batch (depth buffer resolves ordering exactly).
  final bool opaque;

  /// Translucent-pass layering vs the decor billboards.
  final double blendOrder;

  /// Default velocity stretch (overridable per instance).
  final double velocityStretch;

  /// Soft sprites want linear sampling; crisp fields keep nearest.
  final bool linearSampling;

  /// Whether the atlas frames cross-fade (flipbook blending).
  final bool flipbookBlend;

  EngineNode? _parent;
  SpriteAtlas? _atlas;
  String _atlasSignature = '';
  Map<String, int> _frames = const {};
  BillboardBatch? _batch;
  bool _disposed = false;

  /// Whether the atlas is composed and the batch exists.
  bool get ready => _batch != null;

  /// Composes the atlas (idempotent) and creates the batch.
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
        sampling: linearSampling ? kAtlasLinearSampling : kAtlasNearestSampling,
      );
      if (_disposed || atlas == null) return;
      _atlas = atlas;
      _frames = spriteFrameMap(
        [for (final s in _sprites) (key: s.key, path: s.assetPath)],
        atlas.keys,
      );
    }
    _ensureBatch();
  }

  /// Repacks the layer for the current frame. [tint] multiplies every
  /// instance's color (the layer default when an instance carries none);
  /// [screenParallelYaw] overrides the stored yaw for this pack.
  void update(
    List<SpriteFieldInstance> instances, {
    vm.Vector4? tint,
    double? screenParallelYaw,
  }) {
    if (_disposed) return;
    if (screenParallelYaw != null) this.screenParallelYaw = screenParallelYaw;
    _ensureBatch();
    final batch = _batch;
    if (batch == null) return;
    batch.screenParallelYaw = _screenParallelYaw;
    final count =
        instances.length > batch.capacity ? batch.capacity : instances.length;
    var written = 0;
    for (var i = 0; i < count; i++) {
      final p = instances[i];
      final frame = _frames[p.spriteKey];
      if (frame == null) continue;
      final velocity = p.velocity;
      if (velocity != null) {
        batch.velocityStretch =
            velocityStretch > 0 ? velocityStretch : velocity.length;
      }
      batch.setInstance(
        written,
        center: vm.Vector3(p.x, p.y, p.z),
        width: p.width,
        height: p.height,
        rotation: p.rotation,
        color: p.color ?? tint,
        frame: frame.toDouble(),
        velocity: velocity,
      );
      written++;
    }
    batch.commit(written);
  }

  /// Attaches the batch under [parent] (safe before or after [prepare]).
  void attachTo(EngineNode parent) {
    _parent = parent;
    _batch?.attachTo(parent.raw);
  }

  /// Drops the batch (and its node) but keeps the composed atlas.
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
      facing: switch (facing) {
        SpriteFieldFacing.spherical => BillboardFacing.spherical,
        SpriteFieldFacing.screenParallel => BillboardFacing.screenParallel,
        SpriteFieldFacing.velocityStretched =>
          BillboardFacing.velocityStretched,
      },
      opaque: opaque,
      blendOrder: blendOrder,
      velocityStretch: velocityStretch,
      flipbookColumns: atlas.keys.length,
      flipbookRows: 1,
    )
      ..worldUp = vm.Vector3(0, 1, 0)
      ..flipbookBlend = flipbookBlend;
    _batch = batch;
    final parent = _parent;
    if (parent != null) batch.attachTo(parent.raw);
  }

  void _disposeBatch() {
    final batch = _batch;
    _batch = null;
    batch?.dispose();
  }
}
