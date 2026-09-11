import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'dynamic_world.dart';

/// A flat glowing ring on the floor — the engine's ready-made target marker
/// visual. The ring keeps its authored [color] and applies the object's
/// opacity per frame, so a game fades the marker by driving
/// `DynamicObject.opacity` (no custom [DynamicVisual] needed).
class RingVisual extends DynamicVisual {
  RingVisual({
    vm.Vector4? color,
    vm.Vector4? emissive,
    this.innerRadius = 0.14,
    this.outerRadius = 0.2,
    this.segments = 32,
    this.doubleSided = true,
    this.roughness = 1.0,
    this.metallic = 0.0,
  })  : color = color ?? vm.Vector4(1.0, 0.78, 0.25, 1.0),
        emissive = emissive ?? vm.Vector4(0.9, 0.55, 0.1, 1.0);

  /// Linear RGBA ring color.
  final vm.Vector4 color;

  /// Linear RGBA emissive tint (keeps the ring visible in dark scenes).
  final vm.Vector4 emissive;

  final double innerRadius;
  final double outerRadius;
  final int segments;
  final bool doubleSided;
  final double roughness;
  final double metallic;

  @override
  String get poolKey => 'engine-ring';

  @override
  Node createNode(DynamicObject object) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..emissiveFactor = emissive
      ..roughnessFactor = roughness
      ..metallicFactor = metallic
      ..doubleSided = doubleSided
      ..alphaMode = AlphaMode.blend;
    return Node(
      name: 'engine-ring',
      mesh: Mesh(
        RingGeometry(
          innerRadius: innerRadius,
          outerRadius: outerRadius,
          segments: segments,
        ),
        material,
      ),
    );
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
      material.baseColorFactor =
          vm.Vector4(color.x, color.y, color.z, object.opacity);
    }
    node.visible = object.visible;
    node.localTransform = vm.Matrix4.translation(object.position);
  }
}
