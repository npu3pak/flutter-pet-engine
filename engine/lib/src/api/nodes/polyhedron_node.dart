import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../scene/polyhedron.dart';
import '../../scene/polyhedron_geometry.dart';
import '../geometry/scene_geometry.dart';
import '../materials/scene_material.dart';
import 'mesh_helpers.dart';
import 'scene_node.dart';

/// A runtime node with an arbitrary [PolyMesh]: indexed vertices, flat faces
/// (holes allowed), optional explicit UVs and per-face materials.
///
/// The node renders through the same geometry builder as the document
/// `polyhedron` kind, so a mesh imported by a converter looks identical
/// whether it is placed as a document object or as a live node. Casting a
/// ray gives one hit per face (`SceneHit.face!.key` is the face key), and
/// the per-axis [scale] inherited from [SceneNode] stretches the mesh.
///
/// ```dart
/// final wall = PolyhedronNode(
///   name: 'Стена',
///   mesh: PolyMesh.box(w: 2, h: 3, d: 0.2),
///   material: SceneMaterial.pbr(color: const Color(0xFF8A8F99)),
///   faceMaterials: {
///     '+y': SceneMaterial.pbr(color: const Color(0xFF60BA70)),
///   },
/// );
/// wall.position = vm.Vector3(4, 0, 2);
/// controller.add(wall);
/// ```
class PolyhedronNode extends SceneNode {
  PolyhedronNode({
    super.id,
    super.name,
    super.layer,
    required PolyMesh mesh,
    SceneMaterial? material,
    Map<String, SceneMaterial>? faceMaterials,
  })  : _mesh = mesh.copy(),
        _defaultMaterial = material ?? SceneMaterial.pbr(),
        _faceMaterials = Map.of(faceMaterials ?? const {}) {
    _defaultMaterial.addListener(_onMaterialChanged);
    for (final m in _faceMaterials.values) {
      m.addListener(_onMaterialChanged);
    }
  }

  PolyMesh _mesh;
  SceneMaterial _defaultMaterial;
  final Map<String, SceneMaterial> _faceMaterials;
  List<(String, SceneGeometry)>? _parts;
  List<Object>? _syncedSignature;

  /// The mesh (a copy of the constructed value; assign to replace it).
  PolyMesh get mesh => _mesh;
  set mesh(PolyMesh value) {
    if (identical(_mesh, value)) return;
    _mesh = value;
    _parts = null;
    markChanged();
  }

  /// The material of faces without an override; assigning replaces it.
  @override
  SceneMaterial get material => _defaultMaterial;
  @override
  set material(SceneMaterial value) {
    if (identical(_defaultMaterial, value)) return;
    _defaultMaterial.removeListener(_onMaterialChanged);
    _defaultMaterial = value;
    value.addListener(_onMaterialChanged);
    markChanged();
  }

  /// Per-face material overrides (keyed by [PolyFace.key]).
  Map<String, SceneMaterial> get faceMaterials =>
      Map.unmodifiable(_faceMaterials);

  /// The material of one face: its override or the default [material].
  SceneMaterial faceMaterial(String faceKey) =>
      _faceMaterials[faceKey] ?? _defaultMaterial;

  /// Sets ([material]) or clears (null) the material override of one face.
  void setFaceMaterial(String faceKey, SceneMaterial? material) {
    final old = _faceMaterials.remove(faceKey);
    old?.removeListener(_onMaterialChanged);
    if (material != null) {
      _faceMaterials[faceKey] = material;
      material.addListener(_onMaterialChanged);
    }
    markChanged();
  }

  void _onMaterialChanged() {
    invalidateEffectiveMaterials();
    markChanged();
  }

  /// The per-face geometries, cached until the mesh changes. Invalid or
  /// degenerate faces are skipped.
  List<(String, SceneGeometry)> get _builtParts => _parts ??= [
        for (final face in _mesh.faces)
          if (buildPolyFaceGeometryRaw(
            mesh: _mesh,
            face: face,
            flip: true,
          ) case final geometry?)
            (face.key, geometry),
      ];

  @override
  Iterable<SceneGeometry> get pickGeometries => [
        for (final (_, geometry) in _builtParts) geometry,
      ];

  @override
  Iterable<PickPart> get pickParts => [
        for (final (key, geometry) in _builtParts)
          PickPart(
            geometry,
            faceKey: key,
            side: faceMaterial(key).doubleSided ? 'double' : 'outer',
          ),
      ];

  @override
  @protected
  vm.Aabb3? get localBounds {
    final bounds = _mesh.vertexBounds;
    return bounds == null ? null : vm.Aabb3.minMax(bounds.$1, bounds.$2);
  }

  /// The face contours (outer loops and holes) — no triangulation diagonals.
  @override
  List<vm.Vector3> wireframeSegments({
    double? creaseAngleDegrees,
    bool all = true,
  }) {
    final out = <vm.Vector3>[];
    for (final face in _mesh.faces) {
      for (final loop in [face.outer, ...face.holes]) {
        final count = loop.vertices.length;
        if (count < 2) continue;
        for (var i = 0; i < count; i++) {
          out
            ..add(_mesh.vertices[loop.vertices[i]])
            ..add(_mesh.vertices[loop.vertices[(i + 1) % count]]);
        }
      }
    }
    return out;
  }

  @override
  void syncToEngine() {
    final parts = _builtParts;
    final signature = [
      for (final (key, geometry) in parts) ...[
        geometry,
        effectiveMaterial(faceMaterial(key)),
      ],
    ];
    if (listEquals(signature, _syncedSignature)) return;
    _syncedSignature = signature;
    if (parts.isEmpty) {
      engine.mesh = null;
      return;
    }
    engine.mesh = nodeEngineMeshParts([
      for (final (key, geometry) in parts)
        (geometry.raw, effectiveMaterial(faceMaterial(key))),
    ]);
  }

  @override
  void dispose() {
    _defaultMaterial.removeListener(_onMaterialChanged);
    for (final m in _faceMaterials.values) {
      m.removeListener(_onMaterialChanged);
    }
    super.dispose();
  }
}
