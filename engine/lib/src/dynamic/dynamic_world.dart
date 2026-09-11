import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';

/// Called every frame while a dynamic object is alive.
typedef DynamicObjectTick = void Function(DynamicObject object, double dt);

/// Lifecycle callback of a dynamic object (`onFinished`, `onEnteredFrame`).
typedef DynamicObjectEvent = void Function(DynamicObject object);

/// How a dynamic object's quad is oriented in the world.
enum DynamicFacing {
  /// Reoriented toward the camera every frame with the engine's
  /// screen-parallel billboard yaw (the same convention the model renderer
  /// uses for decor sprites). Needs the camera forward in [DynamicWorld.update].
  billboard,

  /// Keeps the authored [DynamicObject.rotationY].
  fixed,
}

/// The drawable of a dynamic object: one [Node] per object, reused through the
/// world's node pool. Games implement this for their own effects; the engine
/// ships [SpriteVisual] (a textured, camera-facing quad).
///
/// The world calls [updateNode] every frame after applying the object's
/// lifecycle, so the visual owns the node's material, visibility and
/// transform. Nodes are pooled by [poolKey]: nodes of the same key must be
/// interchangeable (a reused node is reset by [updateNode]).
abstract class DynamicVisual {
  /// Pool family key — nodes of the same key are reused across objects.
  String get poolKey;

  /// Builds the node for [object] (once per pooled node).
  Node createNode(DynamicObject object);

  /// Applies the object's current state to [node] (called every frame while
  /// the object is alive, and once on spawn).
  void updateNode(
    DynamicObject object,
    Node node,
    double dt, {
    double? billboardYaw,
  });

  /// Releases the node when the world is disposed (pooled nodes are kept
  /// alive between spawns, so this runs once per node, not per despawn).
  void disposeNode(Node node) {}
}

/// A textured vertical quad rendered as a lit PBR sprite — the engine's
/// default dynamic-object visual. Billboards face the camera via the shared
/// screen-parallel yaw; [DynamicFacing.fixed] quads keep their rotation.
class SpriteVisual extends DynamicVisual {
  SpriteVisual({this.texture, this.brightness = 1.0, this.doubleSided = true});

  /// The quad's texture; null renders a flat white quad (tinted by the
  /// object's tint/opacity).
  Texture2D? texture;

  /// Multiplier baked into the material's base color factor.
  double brightness;

  /// Whether the quad renders double-sided (sprite default).
  bool doubleSided;

  @override
  String get poolKey => 'sprite-pbr';

  @override
  Node createNode(DynamicObject object) {
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = texture
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..roughnessFactor = 1.0
      ..metallicFactor = 0.0
      ..alphaMode = AlphaMode.blend
      ..doubleSided = doubleSided;
    return Node(name: 'dynamic-sprite', mesh: Mesh(PlaneGeometry(), material));
  }

  @override
  void updateNode(
    DynamicObject object,
    Node node,
    double dt, {
    double? billboardYaw,
  }) {
    final material = node.mesh?.primitives.first.material;
    if (material is PhysicallyBasedMaterial) {
      material.baseColorTexture = texture;
      material.baseColorFactor = vm.Vector4(
        object.tint.x * brightness,
        object.tint.y * brightness,
        object.tint.z * brightness,
        object.opacity,
      );
    }
    node.visible = object.visible;
    node.localTransform = dynamicSpriteTransform(
      position: object.position,
      width: object.width,
      height: object.height,
      yaw: object.facing == DynamicFacing.billboard && billboardYaw != null
          ? billboardYaw
          : object.rotationY,
    );
  }
}

final _rotateXHalfPi = vm.Matrix4.rotationX(math.pi / 2);

/// The vertical-sprite transform: mirrored X, screen-parallel yaw, unit quad
/// scaled to [width]×[height] — the same composition as the engine's
/// [makeVerticalSprite], with the size applied as a local scale so pooled
/// nodes serve any object.
vm.Matrix4 dynamicSpriteTransform({
  required vm.Vector3 position,
  required double width,
  required double height,
  required double yaw,
}) {
  return vm.Matrix4.translation(position) *
      vm.Matrix4.diagonal3Values(-1, 1, 1) *
      vm.Matrix4.rotationY(yaw) *
      _rotateXHalfPi *
      vm.Matrix4.diagonal3Values(width, 1, height);
}

/// One live object of a [DynamicWorld]: a pooled node plus its lifetime,
/// transform, material knobs, events and game-owned payload.
///
/// The world owns the object: spawn through [DynamicWorld.spawn], end it
/// through [despawn] (or let [lifetime] expire). Reaching zero life fires
/// [onFinished] exactly once.
class DynamicObject {
  DynamicObject._({required this.id, required this.layer, required this.visual});

  /// Unique key inside its world (a second [DynamicWorld.spawn] with the same
  /// id throws while the first is alive).
  final String id;

  /// Grouping layer — the world keeps one root per layer and traverses them
  /// in ascending order. That order drives opaque draws; translucent
  /// materials are sorted by `Material.blendOrder` then depth, so order
  /// transparent effects through `blendOrder`, not the layer.
  final int layer;

  /// The object's drawable; may be swapped between spawns of the same world.
  DynamicVisual visual;

  /// Game-owned payload (target, enemy state, …).
  Object? userData;

  /// World position (mirrored world space, same frame as [dynamicSpriteTransform]).
  final vm.Vector3 position = vm.Vector3.zero();

  /// Yaw around Y (radians) used by [DynamicFacing.fixed] (and by billboards
  /// while the world has no camera forward).
  double rotationY = 0.0;

  /// Quad size in world units.
  double width = 1.0;
  double height = 1.0;

  /// Linear RGB tint and opacity of the sprite material.
  final vm.Vector3 tint = vm.Vector3(1.0, 1.0, 1.0);
  double opacity = 1.0;

  /// Optional selection-style outline color (linear RGBA) applied to the
  /// object's node each frame; null = none.
  vm.Vector4? highlightColor;

  bool visible = true;
  DynamicFacing facing = DynamicFacing.billboard;

  /// Optional auto-despawn after this much time; null lives until [despawn].
  Duration? lifetime;

  /// Time the object has been alive (seconds, accumulated by [DynamicWorld.update]).
  double ageSeconds = 0.0;

  DynamicObjectTick? onUpdate;
  DynamicObjectEvent? onFinished;
  DynamicObjectEvent? onEnteredFrame;

  bool _alive = true;
  bool _enteredFrame = false;
  Node? _node;
  DynamicWorld? _world;

  bool get alive => _alive;

  /// True once [DynamicWorld.update] saw the object in frame (needs the
  /// caller's `isInFrame` test).
  bool get enteredFrame => _enteredFrame;

  /// The pooled scene node while alive; null after despawn.
  Node? get node => _node;

  /// Time left before [lifetime] expires (null = no lifetime).
  Duration? get remaining {
    final life = lifetime;
    if (life == null) return null;
    final left = life - Duration(microseconds: (ageSeconds * 1e6).round());
    return left.isNegative ? Duration.zero : left;
  }

  /// Ends the object: fires [onFinished] once, detaches and pools its node,
  /// and frees the id for reuse. Safe to call more than once.
  void despawn() => _world?.despawn(this);
}

/// The runtime home of dynamic objects (enemies, items, effects): spawn with a
/// lifetime, tick every frame, auto-remove the finished ones — all without
/// touching the model content or triggering a scene rebuild.
///
/// Nodes are pooled by [DynamicVisual.poolKey], so repeated spawns of the same
/// visual family reuse the same scene nodes. Layers group objects under one
/// root each and are traversed in ascending order (opaque draw order); the
/// translucent pass sorts by `Material.blendOrder` then depth, so transparent
/// effects order through their material, not the layer. A game may own several
/// worlds; [GameScene] keeps one by default.
class DynamicWorld {
  DynamicWorld({Node? root}) : root = root ?? Node(name: 'dynamic-world');

  /// The world's scene root — attach it to a [Scene] to render the objects.
  final Node root;

  final List<DynamicObject> _objects = [];
  final Map<String, DynamicObject> _byId = {};
  final Map<int, Node> _layerRoots = {};
  final Map<String, List<_PooledNode>> _nodePools = {};
  final List<DynamicObject> _scratch = [];
  bool _disposed = false;

  /// Number of live objects.
  int get aliveCount => _objects.length;

  /// Live objects in spawn order.
  Iterable<DynamicObject> get objects => _objects;

  /// The live object with [id], or null.
  DynamicObject? byId(String id) => _byId[id];

  /// Whether a live object with [id] exists.
  bool contains(String id) => _byId.containsKey(id);

  /// Creates a live object and returns its handle. Throws when [id] is
  /// already alive or the world is disposed.
  DynamicObject spawn({
    required String id,
    required DynamicVisual visual,
    int layer = 0,
    vm.Vector3? position,
    double rotationY = 0.0,
    double width = 1.0,
    double height = 1.0,
    double opacity = 1.0,
    vm.Vector3? tint,
    bool visible = true,
    DynamicFacing facing = DynamicFacing.billboard,
    Duration? lifetime,
    Object? userData,
    DynamicObjectTick? onUpdate,
    DynamicObjectEvent? onFinished,
    DynamicObjectEvent? onEnteredFrame,
  }) {
    if (_disposed) throw StateError('DynamicWorld is disposed');
    if (_byId.containsKey(id)) {
      throw StateError('DynamicObject "$id" is already alive');
    }
    final object = DynamicObject._(id: id, layer: layer, visual: visual)
      ..rotationY = rotationY
      ..width = width
      ..height = height
      ..opacity = opacity
      ..visible = visible
      ..facing = facing
      ..lifetime = lifetime
      ..userData = userData
      ..onUpdate = onUpdate
      ..onFinished = onFinished
      ..onEnteredFrame = onEnteredFrame
      .._world = this;
    if (position != null) object.position.setFrom(position);
    if (tint != null) object.tint.setFrom(tint);

    final node = _acquireNode(object);
    object._node = node;
    _layerRoot(layer).add(node);
    _objects.add(object);
    _byId[id] = object;
    visual.updateNode(object, node, 0.0);
    node.highlightColor = object.highlightColor;
    return object;
  }

  /// Ends [object] if it belongs to this world and is alive; returns whether
  /// it was despawned by this call.
  bool despawn(DynamicObject object) {
    if (!identical(_byId[object.id], object)) return false;
    object._alive = false;
    final node = object._node;
    object._node = null;
    if (node != null) {
      final layerRoot = _layerRoots[object.layer];
      if (layerRoot != null && node.parent == layerRoot) layerRoot.remove(node);
      _nodePools.putIfAbsent(object.visual.poolKey, () => []).add(
        _PooledNode(object.visual, node),
      );
    }
    _byId.remove(object.id);
    _objects.remove(object);
    object.onFinished?.call(object);
    return true;
  }

  /// Removes every live object and pools its nodes. Does NOT fire
  /// `onFinished` — this is an explicit teardown, not a lifecycle end.
  void clear() {
    for (final object in _objects) {
      object._alive = false;
      final node = object._node;
      object._node = null;
      if (node != null) {
        final layerRoot = _layerRoots[object.layer];
        if (layerRoot != null && node.parent == layerRoot) layerRoot.remove(node);
        _nodePools.putIfAbsent(object.visual.poolKey, () => []).add(
          _PooledNode(object.visual, node),
        );
      }
    }
    _objects.clear();
    _byId.clear();
  }

  /// Per-frame tick: advances lifetimes, runs [DynamicObject.onUpdate],
  /// auto-despawns expired objects, fires `onEnteredFrame` (when [isInFrame]
  /// is supplied) and re-applies each visual's node state.
  ///
  /// [cameraForward] drives billboard orientation (the horizontal view
  /// direction); pass null to keep the objects' authored rotations.
  void update(
    double dt, {
    vm.Vector3? cameraForward,
    bool Function(DynamicObject object)? isInFrame,
  }) {
    if (_disposed) return;
    final billboardYaw = cameraForward == null
        ? null
        : screenParallelYaw(cameraForward.x, cameraForward.z);
    _scratch
      ..clear()
      ..addAll(_objects);
    for (final object in _scratch) {
      if (!object.alive) continue;
      object.ageSeconds += dt;
      object.onUpdate?.call(object, dt);
      if (!object.alive) continue;
      final lifetime = object.lifetime;
      if (lifetime != null &&
          object.ageSeconds * 1000.0 >= lifetime.inMicroseconds / 1000.0) {
        despawn(object);
        continue;
      }
      if (!object._enteredFrame && isInFrame != null && isInFrame(object)) {
        object._enteredFrame = true;
        object.onEnteredFrame?.call(object);
      }
      final node = object._node;
      if (node != null) {
        object.visual.updateNode(
          object,
          node,
          dt,
          billboardYaw: object.facing == DynamicFacing.billboard
              ? billboardYaw
              : null,
        );
        node.highlightColor = object.highlightColor;
      }
    }
  }

  /// Detaches the root, disposes every pooled and live node and frees the id
  /// map. The world cannot be used afterwards.
  void dispose() {
    if (_disposed) return;
    clear();
    for (final pool in _nodePools.values) {
      for (final entry in pool) {
        entry.visual.disposeNode(entry.node);
      }
    }
    _nodePools.clear();
    _layerRoots.clear();
    root.removeAll();
    if (root.parent != null) root.parent!.remove(root);
    _disposed = true;
  }

  Node _acquireNode(DynamicObject object) {
    final pool = _nodePools[object.visual.poolKey];
    if (pool != null && pool.isNotEmpty) return pool.removeLast().node;
    return object.visual.createNode(object);
  }

  Node _layerRoot(int layer) {
    final existing = _layerRoots[layer];
    if (existing != null) return existing;
    final node = Node(name: 'dynamic-layer-$layer');
    _layerRoots[layer] = node;
    _reorderLayerRoots();
    return node;
  }

  // Layer roots are re-added in ascending order so the render walk (child
  // order) draws lower layers first regardless of creation order.
  void _reorderLayerRoots() {
    final layers = _layerRoots.keys.toList()..sort();
    for (final layer in layers) {
      final node = _layerRoots[layer]!;
      if (node.parent == root) root.remove(node);
      root.add(node);
    }
  }
}

class _PooledNode {
  _PooledNode(this.visual, this.node);

  final DynamicVisual visual;
  final Node node;
}
