import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'engine_material.dart';

/// Opaque handle to vertex/index data owned by pet_engine.
class EngineGeometry {
  EngineGeometry.wrap(this.raw);

  /// The underlying fork geometry. Engine-internal plumbing only.
  final Geometry raw;

  /// A unit box centered on the origin (the standard primitive for merged
  /// static geometry; the caller supplies the transform).
  static EngineGeometry cuboid(vm.Vector3 extents) =>
      EngineGeometry.wrap(CuboidGeometry(extents));

  /// A flat quad in the XZ plane (width along X, depth along Z).
  static EngineGeometry plane({double width = 1.0, double depth = 1.0}) =>
      EngineGeometry.wrap(PlaneGeometry(width: width, depth: depth));

  /// A flat ring (annulus) in the XZ plane — markers and target rings.
  static EngineGeometry ring({
    double innerRadius = 0.8,
    double outerRadius = 1.0,
    int segments = 32,
  }) =>
      EngineGeometry.wrap(RingGeometry(
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        segments: segments,
      ));
}

/// Opaque handle to a drawable mesh: geometry plus its shading material.
/// Multi-primitive meshes (e.g. a wall core plus its cutout skin) carry one
/// geometry/material pair per primitive.
class EngineMesh {
  EngineMesh(EngineGeometry geometry, EngineMaterial material)
      : raw = Mesh(geometry.raw, material.raw);

  EngineMesh.wrap(this.raw);

  /// Engine-internal plumbing only.
  final Mesh raw;

  factory EngineMesh.primitives(
    List<(EngineGeometry geometry, EngineMaterial material)> parts,
  ) {
    return EngineMesh.wrap(Mesh.primitives(
      primitives: [
        for (final (geometry, material) in parts)
          MeshPrimitive(geometry.raw, material.raw),
      ],
    ));
  }

  /// A shallow copy with [material] replacing the first primitive's material.
  /// Multi-primitive meshes keep their remaining primitives untouched.
  EngineMesh withFirstMaterial(EngineMaterial material) {
    final primitives = [
      for (final p in raw.primitives) MeshPrimitive(p.geometry, p.material),
    ];
    if (primitives.isNotEmpty) {
      primitives[0] = MeshPrimitive(primitives[0].geometry, material.raw);
    }
    return EngineMesh.wrap(Mesh.primitives(primitives: primitives));
  }

  /// The material of the first primitive, or null for an empty mesh.
  EngineMaterial? get material {
    final primitives = raw.primitives;
    if (primitives.isEmpty) return null;
    return EngineMaterial.wrap(primitives.first.material);
  }
}
