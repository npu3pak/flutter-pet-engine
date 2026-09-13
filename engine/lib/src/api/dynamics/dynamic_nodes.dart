import 'package:vector_math/vector_math.dart' as vm;

import '../nodes/scene_node.dart';
import '../scene_controller.dart';

/// Per-frame callback of a dynamic object.
typedef DynamicTick = void Function(DynamicObject object, double dt);

/// Lifecycle callback of a dynamic object.
typedef DynamicEvent = void Function(DynamicObject object);

/// Builds a fresh node for a pooled dynamic entry.
typedef SceneNodeBuilder = SceneNode Function();

/// The description of one object of a synchronized dynamic set.
class DynamicEntry {
  const DynamicEntry({
    required this.id,
    this.node,
    this.builder,
    this.position,
    this.rotationY = 0,
    this.lifetime,
    this.layer = 0,
    this.userData,
    this.onUpdate,
  });

  final String id;

  /// A ready node (one-shot addition).
  final SceneNode? node;

  /// A node factory (the pool reuses nodes between syncs).
  final SceneNodeBuilder? builder;

  final vm.Vector3? position;
  final double rotationY;
  final Duration? lifetime;
  final int layer;
  final Object? userData;
  final DynamicTick? onUpdate;
}

/// One live dynamic object: a node with an age, an optional lifetime and
/// callbacks.
class DynamicObject {
  DynamicObject._({
    required this.id,
    required this.node,
    required this.layer,
    required this.userData,
    required this.lifetime,
    required this.onUpdate,
    required this.onFinished,
    required this.onEnteredFrame,
    required this.position,
    required this.rotationY,
  });

  /// The unique id of the object within its [DynamicNodes].
  final String id;

  /// The node representing the object.
  final SceneNode node;

  /// The application layer tag (ordering is application-defined).
  final int layer;

  /// Application data attached to the object.
  Object? userData;

  /// The time to live, or null for an eternal object.
  Duration? lifetime;

  /// Whether the object is still alive.
  bool get alive => _alive;
  bool _alive = true;

  /// The object's age.
  Duration get ageSeconds => _age;
  Duration _age = Duration.zero;

  /// The remaining lifetime, or null for an eternal object.
  Duration? get remaining {
    final lifetime = this.lifetime;
    if (lifetime == null) return null;
    final left = lifetime - _age;
    return left.isNegative ? Duration.zero : left;
  }

  /// The remaining lifetime as 1 → 0 (1 for eternal objects).
  double get remainingFactor {
    final lifetime = this.lifetime;
    if (lifetime == null || lifetime.inMicroseconds == 0) return 1;
    return (remaining!.inMicroseconds / lifetime.inMicroseconds).clamp(
      0.0,
      1.0,
    );
  }

  vm.Vector3 position;
  double rotationY;

  final DynamicTick? onUpdate;
  final DynamicEvent? onFinished;
  final DynamicEvent? onEnteredFrame;

  bool _entered = false;

  /// Detaches and pools this object.
  void despawn() => _owner.despawn(this);

  late DynamicNodes _owner;
}

/// The dynamic-object registry of a [SceneController]: spawn/despawn with
/// lifetimes, and [sync] for sets that change every frame without recreating
/// the unchanged nodes.
class DynamicNodes {
  DynamicNodes(this._controller);

  final SceneController _controller;
  final Map<String, DynamicObject> _objects = {};
  final Map<Type, List<SceneNode>> _pool = {};
  final Map<String, Set<String>> _syncKeys = {};

  /// The live objects.
  Iterable<DynamicObject> get objects => _objects.values;

  /// The number of live objects.
  int get aliveCount => _objects.length;

  /// The object with [id], or null.
  DynamicObject? byId(String id) => _objects[id];

  /// Spawns an object: the [node] is added to the scene and tracked until its
  /// [lifetime] expires (or [despawn] is called).
  DynamicObject spawn({
    required String id,
    required SceneNode node,
    vm.Vector3? position,
    double rotationY = 0,
    Duration? lifetime,
    int layer = 0,
    Object? userData,
    DynamicTick? onUpdate,
    DynamicEvent? onFinished,
    DynamicEvent? onEnteredFrame,
  }) {
    if (_objects.containsKey(id)) {
      throw ArgumentError('Динамический объект "$id" уже существует.');
    }
    node.attachToHost(_controller);
    if (position != null) node.position = position;
    node.rotation = vm.Vector3(0, rotationY, 0);
    final object = DynamicObject._(
      id: id,
      node: node,
      layer: layer,
      userData: userData,
      lifetime: lifetime,
      onUpdate: onUpdate,
      onFinished: onFinished,
      onEnteredFrame: onEnteredFrame,
      position: position ?? node.position,
      rotationY: rotationY,
    ).._owner = this;
    _objects[id] = object;
    return object;
  }

  /// Detaches [object] and returns its node to the pool.
  void despawn(DynamicObject object) {
    if (!object._alive) return;
    object._alive = false;
    _objects.remove(object.id);
    object.node.detach();
    _poolOf(object.node.runtimeType).add(object.node);
    object.onFinished?.call(object);
  }

  /// Despawns every object (without firing `onFinished`, matching the v1
  /// `clear` semantics).
  void clear() {
    for (final object in List.of(_objects.values)) {
      object._alive = false;
      object.node.detach();
      _poolOf(object.node.runtimeType).add(object.node);
    }
    _objects.clear();
  }

  /// Synchronizes a set of dynamic objects without recreating unchanged
  /// nodes: existing ids update in place, missing ids are added (from the
  /// pool when possible) and vanished ids are despawned.
  void sync(String key, Iterable<DynamicEntry> entries) {
    final incoming = <String, DynamicEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final previous = _syncKeys[key] ?? const <String>{};
    for (final id in previous) {
      if (!incoming.containsKey(id)) {
        final object = _objects[id];
        if (object != null) despawn(object);
      }
    }
    _syncKeys[key] = incoming.keys.toSet();
    for (final entry in incoming.values) {
      final existing = _objects[entry.id];
      if (existing != null) {
        if (entry.position != null) existing.position = entry.position!;
        existing.rotationY = entry.rotationY;
        existing.userData = entry.userData;
        existing.node.position = existing.position;
        existing.node.rotation = vm.Vector3(0, existing.rotationY, 0);
        entry.onUpdate?.call(existing, 0);
        continue;
      }
      final node = _acquire(entry);
      node.attachToHost(_controller);
      if (entry.position != null) node.position = entry.position!;
      node.rotation = vm.Vector3(0, entry.rotationY, 0);
      final object = DynamicObject._(
        id: entry.id,
        node: node,
        layer: entry.layer,
        userData: entry.userData,
        lifetime: entry.lifetime,
        onUpdate: entry.onUpdate,
        onFinished: null,
        onEnteredFrame: null,
        position: entry.position ?? node.position,
        rotationY: entry.rotationY,
      ).._owner = this;
      _objects[entry.id] = object;
      entry.onUpdate?.call(object, 0);
    }
  }

  /// Advances every object: age, [DynamicEntry.onUpdate], lifetime expiry.
  void update(double dt) {
    for (final object in List.of(_objects.values)) {
      object._age += Duration(microseconds: (dt * 1000000).round());
      object.position = object.node.position;
      object.rotationY = object.node.rotation.y;
      object.onUpdate?.call(object, dt);
      object.node.position = object.position;
      object.node.rotation = vm.Vector3(0, object.rotationY, 0);
      if (!object._entered) {
        object._entered = true;
        object.onEnteredFrame?.call(object);
      }
      final lifetime = object.lifetime;
      if (lifetime != null && object._age >= lifetime) {
        despawn(object);
      }
    }
  }

  /// Drops the pool; live objects stay.
  void dispose() {
    _pool.clear();
  }

  SceneNode _acquire(DynamicEntry entry) {
    final ready = entry.node;
    if (ready != null) return ready;
    final builder = entry.builder;
    if (builder == null) {
      throw ArgumentError(
        'DynamicEntry "${entry.id}" needs either a node or a builder.',
      );
    }
    final built = builder();
    final pool = _poolOf(built.runtimeType);
    if (pool.isNotEmpty) {
      final reused = pool.removeLast();
      pool.add(built);
      return reused;
    }
    return built;
  }

  List<SceneNode> _poolOf(Type type) => _pool.putIfAbsent(type, () => []);
}
