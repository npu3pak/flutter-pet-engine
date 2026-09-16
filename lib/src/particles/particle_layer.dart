import 'dart:async';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../render/billboard_batch.dart';
import '../render/engine_node.dart';
import '../render/sprite_atlas.dart';
import 'particle_config.dart';
import 'particle_placement.dart';

/// One world-space particle layer (rain, snow, wind draught) rendered as a
/// single instanced [BillboardBatch] over a [ParticleField].
///
/// The layer owns the atlas (composed from the config sprites' asset paths,
/// nearest sampling for crisp layers / linear for soft ones) and the batch
/// (facing mode, opaque alpha-test vs alpha/additive, blend order). Call
/// [build] once the assets are available (and again after changing the config
/// or field), then [update] every frame with the current time and focus cell.
///
/// Particles are world-anchored and their motion is a closed-form function of
/// [update]'s `time` ([placeParticles]), so the layer never follows the camera
/// and costs one draw call. The game maps its walkable cells through
/// [ParticleField.allowsCell] and may override the wind direction per floor
/// ([windDirection], e.g. the cave draught blowing toward the exit).
class ParticleLayer {
  ParticleLayer({
    required this.config,
    required this.field,
    this.enabled = true,
    this.intensity = 1.0,
    this.bundle,
  });

  ParticleConfig config;
  ParticleField field;

  /// Density multiplier (see [ParticleConfig.withIntensity]).
  double intensity;

  /// Whether the layer draws at all (hidden while false).
  bool enabled;

  /// Optional asset bundle for atlas loading (tests/dev); defaults to
  /// `rootBundle`.
  AssetBundle? bundle;

  /// Per-floor wind override (normalized inside [placeParticles]); null uses
  /// the config's direction.
  vm.Vector3? windDirection;

  Node? _parent;
  BillboardBatch? _batch;
  Map<String, int> _frames = const {};
  String _signature = '';
  int _generation = 0;
  bool _building = false;
  bool _disposed = false;
  final List<ParticleInstance> _scratch = [];

  /// The config with [intensity] applied.
  ParticleConfig get effectiveConfig => config.withIntensity(intensity);

  /// Whether the atlas and batch are ready to draw.
  bool get ready => _batch != null;

  /// Instances drawn last frame.
  int get instanceCount => _batch?.instanceCount ?? 0;

  /// The batch node, or null before [build] completes.
  Node? get node => _batch?.node;

  /// Attaches the layer's node under [parent] (safe before or after [build]).
  void attachTo(Node parent) {
    _parent = parent;
    final batchNode = _batch?.node;
    if (batchNode == null) return;
    final current = batchNode.parent;
    if (current == parent) return;
    if (current != null) current.remove(batchNode);
    parent.add(batchNode);
  }

  /// The engine-facade variant of [attachTo]: accepts an [EngineNode].
  void attachToNode(EngineNode parent) => attachTo(parent.raw);

  /// Composes the atlas and creates the batch. Idempotent while the config and
  /// field are unchanged; rebuilds when they change (call after edits).
  Future<void> build() async {
    if (_disposed) return;
    final signature = _signatureOf();
    if (signature == _signature && (_batch != null || _building)) return;
    _signature = signature;
    _generation++;
    final generation = _generation;
    _disposeBatch();
    _building = true;
    try {
      final paths = <String>[];
      for (final def in config.sprites) {
        final path = def.assetPath;
        if (path != null && !paths.contains(path)) paths.add(path);
      }
      if (paths.isEmpty) return;
      final sampling = config.crisp
          ? AtlasSampling.nearest
          : AtlasSampling.linear;
      final atlas = await buildSpriteAtlas(
        paths,
        bundle: bundle,
        sampling: sampling,
      );
      if (atlas == null || generation != _generation || _disposed) return;
      _createBatch(atlas);
    } finally {
      _building = false;
    }
  }

  /// Repacks the layer for the current frame. [focusRow]/[focusColumn] are the
  /// cell the density rings are centered on (the player's cell).
  void update({
    required double time,
    required int focusRow,
    required int focusColumn,
  }) {
    if (_disposed) return;
    final batch = _batch;
    if (batch == null) return;
    if (!enabled) {
      if (batch.instanceCount != 0) batch.commit(0);
      return;
    }
    placeParticles(
      field,
      effectiveConfig,
      focusRow: focusRow,
      focusColumn: focusColumn,
      time: time,
      windDirection: windDirection,
      out: _scratch,
    );
    if (_scratch.length > batch.capacity) {
      // Capacity covers the whole domain at the build-time intensity; a
      // raised intensity can outgrow it — rebuild with the new density.
      _generation++;
      _disposeBatch();
      unawaited(build());
      return;
    }
    final tint = config.color;
    var written = 0;
    for (final p in _scratch) {
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
        velocity: vm.Vector3(p.vx, p.vy, p.vz),
      );
      written++;
    }
    batch.commit(written);
  }

  void _createBatch(SpriteAtlas atlas) {
    final capacity = particleBatchCapacity(field, effectiveConfig);
    if (capacity == 0) return;

    final batch = BillboardBatch(
      capacity: capacity,
      atlas: atlas.texture,
      facing: config.kind == ParticleKind.rain
          ? BillboardFacing.velocityStretched
          : BillboardFacing.spherical,
      velocityStretch: config.velocityStretch,
      flipbookColumns: atlas.keys.length,
      flipbookRows: 1,
    );
    if (config.crisp) {
      batch
        ..opaque = true
        ..blendOrder = config.blendOrder;
    } else {
      batch
        ..blendOrder = config.blendOrder
        ..blendMode = config.additive
            ? SpriteBlendMode.additive
            : SpriteBlendMode.alpha;
    }
    final frames = spriteFrameMap([
      for (final def in config.sprites)
        if (def.assetPath != null) (key: def.spriteKey, path: def.assetPath!),
    ], atlas.keys);
    _frames = frames;
    _batch = batch;
    final parent = _parent;
    if (parent != null) parent.add(batch.node);
  }

  void _disposeBatch() {
    final batch = _batch;
    _batch = null;
    _frames = const {};
    batch?.dispose();
  }

  /// Detaches the node and releases the batch. The layer cannot be used after.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _disposeBatch();
    _scratch.clear();
  }

  String _signatureOf() {
    final sb = StringBuffer(
      '${config.kind.name}|${field.rows}x${field.columns}@${field.seed}|'
      '${config.maxPerCell}|${config.fullDensityRings}|${config.viewRadius}|'
      '${config.spawnChance}|${config.bottomY}-${config.topY}|'
      '${config.fallSpeedMin}-${config.fallSpeedMax}|'
      '${config.swayAmp}-${config.swayFreq}|'
      '${config.windDirection.x},${config.windDirection.z}'
      '${config.windSpeed}|${config.color.x},${config.color.y},'
      '${config.color.z}|${config.opacity}|${config.rotationSpin}|'
      '${config.velocityStretch}|${config.crisp}|${config.additive}|'
      '${config.blendOrder}',
    );
    for (final d in config.sprites) {
      sb.write(
        '|${d.spriteKey}:${d.weight}:${d.width}:${d.height}:'
        '${d.assetPath}',
      );
    }
    return sb.toString();
  }
}
