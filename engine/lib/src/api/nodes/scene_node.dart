import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../render/engine_node.dart';
import '../geometry/scene_geometry.dart';
import '../geometry/wireframe.dart';
import '../materials/scene_material.dart';
import '../scene_controller.dart';
import '../scene_layer.dart';

/// One pickable piece of a node: CPU geometry plus the document face key the
/// piece belongs to (null for whole-object pieces). Plumbing for the
/// controller's CPU raycast.
class PickPart {
  const PickPart(
    this.geometry, {
    this.faceKey,
    this.side = 'double',
  });

  /// The piece's CPU geometry, in the same frame the node's transform maps.
  final SceneGeometry geometry;

  /// The document face key of the piece, or null for whole-object pieces.
  final String? faceKey;

  /// The render side of the piece: `outer`, `inner` or `double`/`both`.
  /// Culling-aware picking skips hits on the invisible side.
  final String side;
}

/// Internal attachment seam: the object a node is currently attached to
/// (implemented by `SceneController`). Applications never implement it.
abstract interface class SceneNodeHost {
  /// Called when [node] (or a whole subtree) entered the host.
  void onNodeAttached(SceneNode node);

  /// Called when [node] (or a whole subtree) left the host.
  void onNodeDetached(SceneNode node);

  /// Called when [node]'s state changed and the render side must refresh.
  void onNodeChanged(SceneNode node);

  /// Called when [node] was disposed.
  void onNodeDisposed(SceneNode node);
}

/// Base class of the live scene graph: identity, hierarchy, transform,
/// visibility and material.
///
/// A node is a live object: changing its parameters reflects in the scene as
/// soon as the render side syncs the node. Attaching and detaching is driven
/// by the host ([SceneNodeHost], the future `SceneController`); applications
/// add nodes with `SceneController.add` and remove them with [remove].
abstract class SceneNode extends ChangeNotifier {
  SceneNode({String? id, String name = '', int layer = SceneLayer.base})
    : this._(id ?? _nextId(), layer, EngineNode(name: name));

  /// Wraps an existing engine node (baked level pieces, runtime imports).
  /// Plumbing.
  @internal
  SceneNode.wrap(EngineNode engine, {String? id, int layer = SceneLayer.base})
    : this._(id ?? _nextId(), layer, engine);

  SceneNode._(this.id, this._layer, this.engine) {
    engine.raw.layers = _layer;
    _material.addListener(_onMaterialChanged);
  }

  static int _idCounter = 0;

  static String _nextId() => 'node_${++_idCounter}';

  /// Stable identifier of the node.
  final String id;

  /// The internal fork node wrapper. Plumbing only.
  @internal
  final EngineNode engine;

  /// The display name (empty by default).
  String get name => engine.name;
  set name(String value) {
    if (engine.name == value) return;
    engine.name = value;
    _changed();
  }

  int _layer;

  /// The layer bit mask of the node (see [SceneLayer]).
  int get layer => _layer;
  set layer(int value) {
    if (_layer == value) return;
    _layer = value;
    engine.raw.layers = value;
    _changed();
  }

  SceneNodeHost? _host;

  /// The object this node is attached to, or null.
  @internal
  SceneNodeHost? get host => _host;

  /// The controller this node is attached to, or null.
  SceneController? get scene {
    final host = _host;
    return host is SceneController ? host : null;
  }

  /// Whether the node is currently part of a scene.
  bool get inScene => _host != null;

  SceneNode? _parent;
  final List<SceneNode> _children = [];

  /// The parent node, or null for a root.
  SceneNode? get parent => _parent;

  /// The child nodes.
  List<SceneNode> get children => List.unmodifiable(_children);

  /// Whether this node (and its geometry) is drawn.
  bool get visible => engine.visible;
  set visible(bool value) {
    if (engine.visible == value) return;
    engine.visible = value;
    _changed();
  }

  double _opacity = 1.0;

  /// The node opacity, 0..1. 1 is fully opaque.
  double get opacity => _opacity;
  set opacity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_opacity == clamped) return;
    _opacity = clamped;
    invalidateEffectiveMaterials();
    _changed();
  }

  /// Selection-outline color (linear RGBA), or null for none.
  vm.Vector4? get highlightColor => engine.highlightColor;
  set highlightColor(vm.Vector4? value) {
    if (engine.highlightColor == value) return;
    engine.highlightColor = value;
    _changed();
  }

  WireframeStyle? _wireframe;

  /// The node's wireframe overlay, or null when it is off. The controller
  /// renders it as screen-pixel edge lines; the scene-wide style from
  /// `SceneController.setWireframe` applies to nodes without their own.
  WireframeStyle? get wireframe => _wireframe;
  set wireframe(WireframeStyle? value) {
    if (_wireframe == value) return;
    _wireframe = value;
    _changed();
  }

  /// Whether the node wants a wireframe overlay, including per-face sources
  /// (`ModelNode.setFaceWireframe`). Plumbing for the controller.
  @internal
  bool get hasWireframe => _wireframe != null;

  /// The wireframe edge segments in the node's local frame. Plumbing for the
  /// controller; document nodes override it with their evaluated content.
  /// [all] asks for every edge (the node or the whole scene enabled the
  /// overlay); otherwise only explicitly selected faces are included.
  @internal
  List<vm.Vector3> wireframeSegments({
    double? creaseAngleDegrees,
    bool all = true,
  }) {
    final out = <vm.Vector3>[];
    for (final geometry in pickGeometries) {
      appendWireframeEdges(
        out,
        geometry,
        creaseAngleDegrees: creaseAngleDegrees,
      );
    }
    return dedupeWireframeSegments(out);
  }

  // ── transform ────────────────────────────────────────────────────────

  /// The local transform relative to the parent.
  vm.Matrix4 get transform => engine.transform;
  set transform(vm.Matrix4 value) {
    engine.transform = value;
    _changed();
  }

  /// The local position (a copy; assign it back to move the node).
  vm.Vector3 get position => transform.getTranslation();

  set position(vm.Vector3 value) {
    final matrix = transform.clone()..setTranslation(value);
    transform = matrix;
  }

  /// The local rotation as XYZ Euler angles in radians (a copy).
  vm.Vector3 get rotation => _rotationOf(transform);

  set rotation(vm.Vector3 value) {
    final matrix = transform;
    final translation = matrix.getTranslation();
    final scale = this.scale;
    final rotation =
        vm.Matrix4.rotationZ(value.z) *
        vm.Matrix4.rotationY(value.y) *
        vm.Matrix4.rotationX(value.x);
    rotation.setColumn(0, rotation.getColumn(0) * scale.x);
    rotation.setColumn(1, rotation.getColumn(1) * scale.y);
    rotation.setColumn(2, rotation.getColumn(2) * scale.z);
    rotation.setTranslation(translation);
    transform = rotation;
  }

  /// The local scale (a copy).
  vm.Vector3 get scale {
    final matrix = transform;
    final sx = matrix.getColumn(0).length;
    final sy = matrix.getColumn(1).length;
    final sz = matrix.getColumn(2).length;
    return matrix.determinant() < 0
        ? vm.Vector3(-sx, sy, sz)
        : vm.Vector3(sx, sy, sz);
  }

  set scale(vm.Vector3 value) {
    final matrix = transform;
    final translation = matrix.getTranslation();
    final c0 = matrix.getColumn(0);
    final c1 = matrix.getColumn(1);
    final c2 = matrix.getColumn(2);
    if (c0.length2 > 1e-18) c0.normalize();
    if (c1.length2 > 1e-18) c1.normalize();
    if (c2.length2 > 1e-18) c2.normalize();
    final result = vm.Matrix4.identity()
      ..setColumn(0, c0 * value.x)
      ..setColumn(1, c1 * value.y)
      ..setColumn(2, c2 * value.z);
    result.setTranslation(translation);
    transform = result;
  }

  /// The node's transform in world space (walks the parent chain).
  vm.Matrix4 get globalTransform {
    final parent = _parent;
    return parent == null ? transform : parent.globalTransform * transform;
  }

  /// The local-space bounds, when the node can compute them.
  @protected
  vm.Aabb3? get localBounds => null;

  /// The world-space bounds, or null when they cannot be computed.
  vm.Aabb3? get worldBounds => _boundsInWorld(localBounds);

  vm.Aabb3? _boundsInWorld(vm.Aabb3? local) {
    if (local == null) return null;
    final matrix = globalTransform;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var i = 0; i < 8; i++) {
      final corner = vm.Vector3(
        (i & 1) == 0 ? local.min.x : local.max.x,
        (i & 2) == 0 ? local.min.y : local.max.y,
        (i & 4) == 0 ? local.min.z : local.max.z,
      );
      matrix.transform3(corner);
      if (corner.x < minX) minX = corner.x;
      if (corner.y < minY) minY = corner.y;
      if (corner.z < minZ) minZ = corner.z;
      if (corner.x > maxX) maxX = corner.x;
      if (corner.y > maxY) maxY = corner.y;
      if (corner.z > maxZ) maxZ = corner.z;
    }
    return vm.Aabb3.minMax(
      vm.Vector3(minX, minY, minZ),
      vm.Vector3(maxX, maxY, maxZ),
    );
  }

  // ── material ─────────────────────────────────────────────────────────

  SceneMaterial _material = SceneMaterial.pbr();

  /// The node's material.
  SceneMaterial get material => _material;
  set material(SceneMaterial value) {
    if (identical(_material, value)) return;
    _material.removeListener(_onMaterialChanged);
    invalidateEffectiveMaterials();
    _material = value;
    _material.addListener(_onMaterialChanged);
    _changed();
  }

  final Map<SceneMaterial, SceneMaterial> _effectiveMaterials = {};

  /// The material to render with: [base] when the node is opaque, otherwise a
  /// per-node copy whose color alpha is multiplied by [opacity] (with blending
  /// forced on), so sharing one material between nodes keeps their opacities
  /// independent. Plumbing for node subclasses.
  @protected
  SceneMaterial effectiveMaterial(SceneMaterial base) {
    if (_opacity >= 1.0) return base;
    final existing = _effectiveMaterials[base];
    if (existing != null) return existing;
    final copy = base.copy()
      ..color = base.color.withValues(alpha: base.color.a * _opacity);
    if (copy.alphaMode == SceneAlphaMode.opaque) {
      copy.alphaMode = SceneAlphaMode.blend;
    }
    _effectiveMaterials[base] = copy;
    return copy;
  }

  /// Drops the cached per-node material copies. Plumbing for subclasses that
  /// change or listen to their own materials.
  @protected
  void invalidateEffectiveMaterials() {
    if (_effectiveMaterials.isEmpty) return;
    for (final material in _effectiveMaterials.values) {
      material.dispose();
    }
    _effectiveMaterials.clear();
  }

  void _onMaterialChanged() {
    invalidateEffectiveMaterials();
    _host?.onNodeChanged(this);
    notifyListeners();
  }

  // ── lifecycle ────────────────────────────────────────────────────────

  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// Attaches this node (and its subtree) to [host]. Plumbing for
  /// `SceneController`.
  @internal
  void attachToHost(SceneNodeHost host) {
    if (identical(_host, host)) return;
    if (_host != null) detachFromHost();
    _attachSubtree(host);
  }

  /// Detaches this node (and its subtree) from its host.
  @internal
  void detachFromHost() {
    if (_host == null) return;
    _detachSubtree();
  }

  void _attachSubtree(SceneNodeHost host) {
    _host = host;
    host.onNodeAttached(this);
    for (final child in _children) {
      child._attachSubtree(host);
    }
    notifyListeners();
  }

  void _detachSubtree() {
    final host = _host;
    if (host == null) return;
    for (final child in _children) {
      child._detachSubtree();
    }
    _host = null;
    host.onNodeDetached(this);
    notifyListeners();
  }

  /// Adds [child] to this node's children. Plumbing for [GroupNode].
  @internal
  void linkChild(SceneNode child) {
    if (identical(child, this)) {
      throw ArgumentError('A node cannot be its own child.');
    }
    if (child._parent != null) {
      child._parent!._children.remove(child);
    } else if (child.inScene) {
      child.detachFromHost();
    }
    child._parent = this;
    _children.add(child);
    engine.add(child.engine);
    final host = _host;
    if (host != null && !child.inScene) {
      child._attachSubtree(host);
    }
    _host?.onNodeChanged(this);
    notifyListeners();
  }

  /// Removes [child] from this node's children. Plumbing for [GroupNode].
  @internal
  void unlinkChild(SceneNode child) {
    if (!_children.remove(child)) return;
    engine.remove(child.engine);
    child._parent = null;
    child._detachSubtree();
    _host?.onNodeChanged(this);
    notifyListeners();
  }

  /// Detaches the node from its parent and host; the node stays alive.
  void detach() {
    final parent = _parent;
    if (parent != null) {
      parent.unlinkChild(this);
    } else {
      detachFromHost();
    }
  }

  /// Detaches and disposes the node.
  void remove() {
    dispose();
  }

  /// The node's geometries for CPU picking. Plumbing for the controller.
  @internal
  Iterable<SceneGeometry> get pickGeometries => const [];

  /// The node's pickable pieces: geometry plus the document face key the
  /// piece belongs to (null for whole-object pieces). Plumbing.
  @internal
  Iterable<PickPart> get pickParts =>
      [for (final geometry in pickGeometries) PickPart(geometry)];

  /// Per-frame callback for mechanism nodes (weather, fields). Plumbing.
  @internal
  void frameTick(Duration elapsed, double dt) {}

  /// Builds or refreshes the internal fork mesh. Called by the render side
  /// when the node is attached to a real scene; headless tests never call it.
  @internal
  void syncToEngine() {}

  void _changed() {
    _host?.onNodeChanged(this);
    notifyListeners();
  }

  /// Notifies the host and listeners that the node's parameters changed.
  /// Plumbing for subclasses.
  @protected
  void markChanged() => _changed();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final child in List.of(_children)) {
      child.dispose();
    }
    final host = _host;
    detach();
    _material.removeListener(_onMaterialChanged);
    invalidateEffectiveMaterials();
    host?.onNodeDisposed(this);
    super.dispose();
  }

  /// Extracts XYZ Euler angles (radians) from a transform with the engine's
  /// `Rz·Ry·Rx` order.
  static vm.Vector3 _rotationOf(vm.Matrix4 matrix) {
    final c0 = matrix.getColumn(0);
    final c1 = matrix.getColumn(1);
    final c2 = matrix.getColumn(2);
    if (c0.length2 > 1e-18) c0.normalize();
    if (c1.length2 > 1e-18) c1.normalize();
    if (c2.length2 > 1e-18) c2.normalize();
    if (matrix.determinant() < 0) c0.negate();
    final sy = -c0.z.clamp(-1.0, 1.0);
    final ry = math.asin(sy);
    if (sy.abs() < 0.99999) {
      return vm.Vector3(math.atan2(c1.z, c2.z), ry, math.atan2(c0.y, c0.x));
    }
    return vm.Vector3(math.atan2(-c2.y, c1.y), ry, 0.0);
  }
}
