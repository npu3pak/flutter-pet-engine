// Private fields behind public getters/setters cannot use initializing
// formals in named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../../level/level_baker.dart';
import '../../particles/particle_config.dart';
import '../../particles/particle_layer.dart';
import '../../particles/particle_placement.dart';
import '../../render/billboard_batch.dart' as v1;
import '../../render/engine_node.dart';
import '../../render/ground_fog_layer.dart';
import '../../render/sprite_field_layer.dart';
import '../materials/scene_texture.dart';
import 'group_node.dart';
import 'scene_node.dart';

/// How a [BillboardBatchNode]'s quads face the camera.
enum BillboardFacing {
  spherical,
  axisLocked,
  velocityStretched,
  screenParallel,
}

/// The blend mode of a [BillboardBatchNode].
enum SpriteBlendMode { opaque, alpha, additive }

/// A weather/particle source: the engine repacks it every frame around
/// [focus] (the player's point).
class ParticleNode extends SceneNode {
  ParticleNode({
    super.id,
    super.name,
    super.layer,
    required this.config,
    required this.field,
    this.intensity = 1,
    this.enabled = true,
  });

  /// The particle appearance and motion configuration.
  ParticleConfig config;

  /// The walkable-cell grid the particles are placed over.
  ParticleField field;

  /// The density multiplier.
  double intensity;

  /// Whether the source is drawn.
  bool enabled;

  /// The point the density rings are centered on (usually the player).
  vm.Vector3? focus;

  vm.Vector3? _windDirection;

  /// The wind override; null uses the configuration's direction.
  vm.Vector3? get windDirection => _windDirection ?? config.windDirection;

  set windDirection(vm.Vector3? value) {
    _windDirection = value;
    markChanged();
  }

  ParticleLayer? _layer;

  /// Whether the atlas and batch are ready.
  bool get ready => _layer?.ready ?? false;

  /// Composes the sprite atlas and creates the batch; call after the assets
  /// are available (and again after changing [config] or [field]).
  Future<void> prepare() async {
    final layer = _ensureLayer();
    await layer.build();
  }

  ParticleLayer _ensureLayer() {
    final existing = _layer;
    if (existing != null) return existing;
    final layer = ParticleLayer(
      config: config,
      field: field,
      enabled: enabled,
      intensity: intensity,
    );
    _layer = layer;
    return layer;
  }

  @override
  void syncToEngine() {
    _ensureLayer().attachToNode(engine);
  }

  @override
  void frameTick(Duration elapsed, double dt) {
    if (!enabled) return;
    final focus = this.focus;
    final layer = _layer;
    if (focus == null || layer == null || !layer.ready) return;
    layer.enabled = true;
    layer.intensity = intensity;
    layer.windDirection = _windDirection;
    final row = (focus.z - field.origin.z).round();
    final column = (field.origin.x - focus.x).round();
    layer.update(
      time: elapsed.inMicroseconds / 1000000.0,
      focusRow: row,
      focusColumn: column,
    );
  }

  @override
  void dispose() {
    _layer?.dispose();
    _layer = null;
    super.dispose();
  }
}

/// A generic instanced sprite field (grass, leaves, decor): the application
/// packs the visible instances every frame, the node draws them in one call.
class SpriteFieldNode extends SceneNode {
  SpriteFieldNode({
    super.id,
    super.name,
    super.layer,
    required List<SpriteFieldSprite> sprites,
    required int capacity,
    SpriteFieldFacing facing = SpriteFieldFacing.screenParallel,
    bool opaque = false,
  }) : _layer = SpriteFieldLayer(
         sprites: sprites,
         capacity: capacity,
         facing: facing,
         opaque: opaque,
       );

  final SpriteFieldLayer _layer;

  /// The shared yaw (radians) of [SpriteFieldFacing.screenParallel] instances:
  /// the whole field turns uniformly, exactly like `SpriteNode.billboard`
  /// nodes driven by `SceneController.reorientBillboards`. The application
  /// writes it when the camera turns; the repack stays one instanced call.
  double get screenParallelYaw => _layer.screenParallelYaw;
  set screenParallelYaw(double value) => _layer.screenParallelYaw = value;

  /// Whether the atlas and batch are ready.
  bool get ready => _layer.ready;

  /// Composes the atlas before the first frame.
  Future<void> prepare() => _layer.prepare();

  /// Packs the current frame's [instances].
  void update(List<SpriteFieldInstance> instances) => _layer.update(instances);

  /// Drops the batch but keeps the atlas.
  void reset() => _layer.reset();

  @override
  void syncToEngine() => _layer.attachTo(engine);

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}

/// The creeping ground-fog layer: the application packs the visible clouds
/// every frame, the node draws them in one call.
class GroundFogNode extends SceneNode {
  GroundFogNode({
    super.id,
    super.name,
    super.layer,
    required List<GroundFogSprite> sprites,
    required int capacity,
    int blendOrder = 0,
  }) : _layer = GroundFogLayer(
         sprites: sprites,
         capacity: capacity,
         blendOrder: blendOrder.toDouble(),
       );

  final GroundFogLayer _layer;

  /// Whether the atlas and batch are ready.
  bool get ready => _layer.ready;

  /// Composes the atlas before the first frame.
  Future<void> prepare() => _layer.prepare();

  /// Packs the current frame's [instances], tinted by [tint].
  void update(List<FogInstance> instances, {Color? tint}) {
    final color = tint ?? const Color(0xFFFFFFFF);
    _layer.update(
      instances,
      tint: vm.Vector3(
        math.pow(color.r, 2.2).toDouble(),
        math.pow(color.g, 2.2).toDouble(),
        math.pow(color.b, 2.2).toDouble(),
      ),
    );
  }

  /// Drops the batch but keeps the atlas.
  void reset() => _layer.reset();

  @override
  void syncToEngine() => _layer.attachToNode(engine);

  @override
  void dispose() {
    _layer.dispose();
    super.dispose();
  }
}

/// A pooled instanced billboard batch: the application writes instances with
/// [setInstance] and calls [commit] once per frame.
class BillboardBatchNode extends SceneNode {
  BillboardBatchNode({
    super.id,
    super.name,
    super.layer,
    required this.capacity,
    SceneTexture? atlas,
    BillboardFacing facing = BillboardFacing.spherical,
    SpriteBlendMode blendMode = SpriteBlendMode.opaque,
    int blendOrder = 0,
    int flipbookColumns = 1,
    int flipbookRows = 1,
  }) : _atlas = atlas,
       _facing = facing,
       _blendMode = blendMode,
       _blendOrder = blendOrder,
       _flipbookColumns = flipbookColumns,
       _flipbookRows = flipbookRows {
    _atlas?.addListener(_onAtlasChanged);
  }

  /// The maximum number of instances per frame.
  final int capacity;

  SceneTexture? _atlas;

  /// The atlas texture; changing it applies to the live batch. A lazily
  /// uploaded texture is picked up as soon as its GPU image is ready.
  SceneTexture? get atlas => _atlas;
  set atlas(SceneTexture? value) {
    if (identical(_atlas, value)) return;
    _atlas?.removeListener(_onAtlasChanged);
    _atlas = value;
    _atlas?.addListener(_onAtlasChanged);
    _batch?.atlas = value?.raw;
    markChanged();
  }

  void _onAtlasChanged() {
    _batch?.atlas = _atlas?.raw;
    markChanged();
  }

  BillboardFacing _facing;

  /// How the quads face the camera; changing it applies to the live batch.
  BillboardFacing get facing => _facing;
  set facing(BillboardFacing value) {
    if (_facing == value) return;
    _facing = value;
    _batch?.facing = _fsFacing(value);
    markChanged();
  }

  SpriteBlendMode _blendMode;

  /// The blend mode (opaque is alpha-tested, depth-sorted by the buffer).
  SpriteBlendMode get blendMode => _blendMode;
  set blendMode(SpriteBlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    _batch
      ?..blendMode = value == SpriteBlendMode.additive
          ? fs.SpriteBlendMode.additive
          : fs.SpriteBlendMode.alpha
      ..opaque = value == SpriteBlendMode.opaque;
    markChanged();
  }

  int _blendOrder;

  /// Translucent-pass ordering.
  int get blendOrder => _blendOrder;
  set blendOrder(int value) {
    if (_blendOrder == value) return;
    _blendOrder = value;
    _batch?.blendOrder = value.toDouble();
    markChanged();
  }

  int _flipbookColumns;

  /// The atlas grid columns (`setInstance(frame:)` indexes the grid).
  int get flipbookColumns => _flipbookColumns;
  set flipbookColumns(int value) {
    if (_flipbookColumns == value) return;
    _flipbookColumns = value;
    _batch?.flipbookColumns = value;
    markChanged();
  }

  int _flipbookRows;

  /// The atlas grid rows.
  int get flipbookRows => _flipbookRows;
  set flipbookRows(int value) {
    if (_flipbookRows == value) return;
    _flipbookRows = value;
    _batch?.flipbookRows = value;
    markChanged();
  }

  v1.BillboardBatch? _batch;
  int _cursor = 0;

  /// The number of instances committed last frame.
  int get instanceCount => _batch?.instanceCount ?? 0;

  /// Writes one instance; call [commit] when done.
  void setInstance({
    required vm.Vector3 center,
    required double width,
    required double height,
    double rotation = 0,
    int frame = 0,
    vm.Vector3? velocity,
    Color? color,
  }) {
    final batch = _ensureBatch();
    if (batch == null || _cursor >= batch.capacity) return;
    batch.setInstance(
      _cursor++,
      center: center,
      width: width,
      height: height,
      rotation: rotation,
      frame: frame.toDouble(),
      velocity: velocity,
      color: color == null ? null : _linear(color),
    );
  }

  /// Publishes the instances written since the previous commit.
  void commit() {
    _batch?.commit(_cursor);
    _cursor = 0;
  }

  @override
  void syncToEngine() {
    final batch = _ensureBatch();
    if (batch != null && batch.node.parent == null) {
      engine.raw.add(batch.node);
    }
  }

  v1.BillboardBatch? _ensureBatch() {
    final existing = _batch;
    if (existing != null) return existing;
    final batch = v1.BillboardBatch(
      capacity: capacity,
      atlas: _atlas?.raw,
      facing: _fsFacing(_facing),
      blendMode: _blendMode == SpriteBlendMode.additive
          ? fs.SpriteBlendMode.additive
          : fs.SpriteBlendMode.alpha,
      opaque: _blendMode == SpriteBlendMode.opaque,
      blendOrder: _blendOrder.toDouble(),
      flipbookColumns: _flipbookColumns,
      flipbookRows: _flipbookRows,
    );
    _batch = batch;
    return batch;
  }

  @override
  void dispose() {
    _atlas?.removeListener(_onAtlasChanged);
    _batch?.dispose();
    _batch = null;
    super.dispose();
  }
}

/// A baked level mounted as a node: the whole level content plus the element
/// lookup for moving separate pieces.
class LevelNode extends GroupNode {
  LevelNode({super.id, super.name, super.layer, required this.result});

  /// The baked level result.
  final LevelBakeResult result;

  /// The separate node of a construction element, or null.
  SceneNode? nodeFor(String elementId) {
    final node = result.nodes[elementId];
    if (node == null) return null;
    return _BakedNode(EngineNode.wrap(node), id: elementId);
  }

  @override
  void syncToEngine() {
    if (result.root.parent == null) {
      engine.raw.add(result.root);
    }
  }
}

/// A read-only view of a baked level piece (owned by the level result).
class _BakedNode extends SceneNode {
  _BakedNode(super.engine, {super.id}) : super.wrap();
}

vm.Vector4 _linear(Color color) => vm.Vector4(
  math.pow(color.r, 2.2).toDouble(),
  math.pow(color.g, 2.2).toDouble(),
  math.pow(color.b, 2.2).toDouble(),
  color.a,
);

fs.BillboardFacing _fsFacing(BillboardFacing facing) => switch (facing) {
  BillboardFacing.spherical => fs.BillboardFacing.spherical,
  BillboardFacing.axisLocked => fs.BillboardFacing.axisLocked,
  BillboardFacing.velocityStretched => fs.BillboardFacing.velocityStretched,
  BillboardFacing.screenParallel => fs.BillboardFacing.screenParallel,
};
