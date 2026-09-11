import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'engine_material.dart';
import 'engine_mesh.dart';

/// Opaque handle to a node of the engine scene graph.
///
/// Games create nodes through [EngineNode] / the [EngineScene] add methods and
/// drive them through these members; the fork's node type stays behind the
/// facade.
class EngineNode {
  EngineNode.wrap(this.raw);

  /// Creates a detached node (attach it with [EngineScene.add] or [add]).
  factory EngineNode({String name = '', vm.Matrix4? transform}) =>
      EngineNode.wrap(Node(name: name, localTransform: transform));

  /// Creates a detached node carrying [mesh] (a convenience for the
  /// `Node(mesh: ..., localTransform: ...)` construction).
  factory EngineNode.withMesh({
    String name = '',
    EngineMesh? mesh,
    vm.Matrix4? transform,
  }) {
    final node = EngineNode.wrap(Node(name: name, localTransform: transform));
    if (mesh != null) node.mesh = mesh;
    return node;
  }

  /// The underlying fork node. Engine-internal plumbing only.
  final Node raw;

  String get name => raw.name;
  set name(String value) => raw.name = value;

  bool get visible => raw.visible;
  set visible(bool value) => raw.visible = value;

  vm.Matrix4 get transform => raw.localTransform;
  set transform(vm.Matrix4 value) => raw.localTransform = value;

  /// Marks this node's geometry as static shadow casters (see `Node.shadowStatic`).
  bool get shadowStatic => raw.shadowStatic;
  set shadowStatic(bool value) => raw.shadowStatic = value;

  /// Selection-outline color (linear RGBA), or null for none.
  vm.Vector4? get highlightColor => raw.highlightColor;
  set highlightColor(vm.Vector4? value) => raw.highlightColor = value;

  EngineNode? get parent {
    final p = raw.parent;
    return p == null ? null : EngineNode.wrap(p);
  }

  List<EngineNode> get children =>
      [for (final child in raw.children) EngineNode.wrap(child)];

  int get childCount => raw.children.length;

  void add(EngineNode child) => raw.add(child.raw);

  void remove(EngineNode child) => raw.remove(child.raw);

  void removeAll() => raw.removeAll();

  /// Detaches this node from its parent (no-op when it has none).
  void detach() {
    if (raw.parent != null) raw.parent!.remove(raw);
  }

  /// The mesh of this node, or null when it carries none.
  EngineMesh? get mesh {
    final value = raw.mesh;
    return value == null ? null : EngineMesh.wrap(value);
  }

  set mesh(EngineMesh? value) => raw.mesh = value?.raw;

  /// The first primitive's material, or null.
  EngineMaterial? get material {
    final value = raw.mesh;
    if (value == null || value.primitives.isEmpty) return null;
    return EngineMaterial.wrap(value.primitives.first.material);
  }

  /// Replaces the first primitive's material (multi-primitive meshes keep the
  /// remaining primitives). No-op when the node has no mesh.
  set material(EngineMaterial? value) {
    if (value == null) return;
    final mesh = raw.mesh;
    if (mesh == null || mesh.primitives.isEmpty) return;
    final primitives = [
      for (final p in mesh.primitives) MeshPrimitive(p.geometry, p.material),
    ];
    primitives[0] = MeshPrimitive(primitives[0].geometry, value.raw);
    raw.mesh = Mesh.primitives(primitives: primitives);
  }

  /// Attaches a point light at this node's origin.
  EnginePointLight addPointLight({
    vm.Vector3? color,
    double intensity = 1.0,
    double range = 0.0,
  }) {
    final component = PointLightComponent(PointLight(
      color: color,
      intensity: intensity,
      range: range,
    ));
    raw.addComponent(component);
    return EnginePointLight(component);
  }

  /// The node's point light, or null when it has none.
  EnginePointLight? get pointLight {
    final component = raw.getComponent<PointLightComponent>();
    return component == null ? null : EnginePointLight(component);
  }
}

/// Handle to a point light attached to an [EngineNode].
class EnginePointLight {
  EnginePointLight(this.raw);

  /// Engine-internal plumbing only.
  final PointLightComponent raw;

  double get intensity => raw.light.intensity;
  set intensity(double value) => raw.light.intensity = value;

  double get range => raw.light.range;
  set range(double value) => raw.light.range = value;

  vm.Vector3 get color => raw.light.color;
  set color(vm.Vector3 value) => raw.light.color = value;
}
