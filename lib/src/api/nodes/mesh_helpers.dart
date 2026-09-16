import 'package:flutter_scene/scene.dart' show Geometry;

import '../../render/engine_material.dart';
import '../../render/engine_mesh.dart';
import '../materials/scene_material.dart';

/// Internal bridges from scene geometry/material to the engine (render)
/// layer. Used by the node subclasses that own meshes (`MeshNode`,
/// `PolyhedronNode`, ...); NOT part of the public API — this file is not
/// exported by `pet_engine.dart`.

EngineGeometry nodeEngineGeometry(Geometry geometry) =>
    EngineGeometry.wrap(geometry);

EngineMaterial nodeEngineMaterial(SceneMaterial material) =>
    EngineMaterial.wrap(material.raw);

EngineMesh nodeEngineMesh(Geometry geometry, SceneMaterial material) =>
    EngineMesh(nodeEngineGeometry(geometry), nodeEngineMaterial(material));

/// One engine mesh from several geometry/material pairs (one draw item
/// each), used by the multi-part nodes.
EngineMesh nodeEngineMeshParts(List<(Geometry, SceneMaterial)> parts) =>
    EngineMesh.primitives([
      for (final (geometry, material) in parts)
        (nodeEngineGeometry(geometry), nodeEngineMaterial(material)),
    ]);
