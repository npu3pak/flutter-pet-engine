import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../engine_compat/coords.dart';
import '../models/model_scene.dart';
import '../scene/csg.dart';
import '../scene/model_renderer.dart'
    show
        faceCorners,
        gltfFootprintBox,
        modelRefFootprintBox,
        objectRotation,
        objectScale,
        sideFor,
        sourceAnchor,
        spriteBillboardMatrix,
        spriteBillboardRotation;
import '../scene/polyhedron_geometry.dart';
import 'geometry/geometry_builder.dart';
import 'geometry/scene_geometry.dart';
import 'nodes/scene_node.dart' show PickPart;

/// Builds the CPU pick parts of a document object in the WORLD (render)
/// frame — the same placement the renderer bakes into its nodes, so the
/// parts line up with the visible content.
///
/// Flat-faced primitives (cuboid, trapezoid, plane, sprite) and the cylinder
/// yield one part per document face key; rounded cuboids keep their six
/// planar keys plus the shared `round` surface; a csg result is one
/// whole-object part (its face provenance is not a document face); model and
/// gltf instances are picked through their footprint proxy boxes. Pure CPU —
/// used by `SceneController.raycast` and testable without a device.
///
/// [billboardYaw] is the live screen-parallel yaw of billboard sprites (the
/// renderer reorients them every frame); null keeps the authored [rotY].
///
/// [modelOf] resolves a referenced model by id (the resource session): with
/// it a model instance is picked through the world AABB of its ACTUAL
/// resolved content instead of the whole source grid, so the proxy box never
/// sticks through nearby walls. Without a resolver (or a missing source) the
/// cached footprint box is used.
List<PickPart> buildObjectPickParts(
  ModelData model,
  ModelObject object, {
  double? billboardYaw,
  ModelData? Function(String id)? modelOf,
}) {
  switch (object.kind) {
    case 'cuboid':
      if (object.dim('roundR', 0) > 0) {
        return _roundedParts(model, object);
      }
      return _flatParts(object, _objectWorld(model, object));
    case 'trapezoid':
    case 'plane':
    case 'sprite':
      return _flatParts(
        object,
        _objectWorld(model, object, billboardYaw: billboardYaw),
      );
    case 'cylinder':
      return _cylinderParts(model, object);
    case polyhedronKind:
      return _polyhedronParts(model, object);
    case 'csg':
      return _csgParts(model, object);
    case modelRefKind:
      final target = modelOf?.call(object.refModelId);
      if (target == null) {
        return _proxyParts(
          modelRefFootprintBox(object),
          _modelRefChain(model, object),
        );
      }
      return _collectContentParts(
        target,
        _modelRefChain(model, object),
        {target.id},
        billboardYaw: billboardYaw,
        modelOf: modelOf!,
      );
    case gltfRefKind:
      return _proxyParts(
        gltfFootprintBox(object),
        _modelRefChain(model, object),
      );
    default:
      return const [];
  }
}

/// The exact pick parts of a resolved model instance: every visible object
/// of [src] under the instance chain [m], mirroring the renderer's nested
/// emission (`_buildNestedScene` / `_buildNestedCsg`). Primitives use their
/// per-face parts, csg/rounded results their evaluated polygons, nested
/// instances recurse (missing sources fall back to the footprint box) and
/// billboard sprites carry the live yaw. [guard] breaks reference cycles.
List<PickPart> _collectContentParts(
  ModelData src,
  vm.Matrix4 m,
  Set<String> guard, {
  double? billboardYaw,
  required ModelData? Function(String id) modelOf,
}) {
  final out = <PickPart>[];
  for (final obj in src.visibleObjects()) {
    if (obj.isCsg) {
      final polys = csgEvaluate(obj, src);
      if (polys.isEmpty) continue;
      final geometry = _worldPolyMesh(src, polys);
      if (geometry != null) {
        out.add(
          PickPart(
            _inWorld(geometry, m),
            side: sideFor(obj, '*'),
          ),
        );
      }
      continue;
    }
    if (obj.kind == 'cuboid' && obj.dim('roundR', 0) > 0) {
      for (final part in _groupedWorldParts(src, obj, csgLeafPolys(obj))) {
        out.add(
          PickPart(
            _inWorld(part.geometry, m),
            faceKey: part.faceKey,
            side: part.side,
          ),
        );
      }
      continue;
    }
    final anchor = sourceAnchor(src.size.w, src.size.l, obj);
    final scale = vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
    if (obj.isModelRef) {
      final chain = m * vm.Matrix4.translation(anchor) * objectRotation(obj) * scale;
      final inner = modelOf(obj.refModelId);
      if (inner == null) {
        out.addAll(
          _proxyParts(modelRefFootprintBox(obj), chain),
        );
      } else if (guard.add(inner.id)) {
        out.addAll(
          _collectContentParts(
            inner,
            chain,
            guard,
            billboardYaw: billboardYaw,
            modelOf: modelOf,
          ),
        );
        guard.remove(inner.id);
      }
      continue;
    }
    if (obj.isGltfRef) {
      final chain = m * vm.Matrix4.translation(anchor) * objectRotation(obj) * scale;
      out.addAll(_proxyParts(gltfFootprintBox(obj), chain));
      continue;
    }
    if (obj.kind == 'sprite') {
      final yaw = billboardYaw ?? obj.rotY * math.pi / 180;
      final world =
          m * vm.Matrix4.translation(anchor) * spriteBillboardRotation(yaw);
      out.addAll(_flatParts(obj, world));
      continue;
    }
    final world = m *
        vm.Matrix4.translation(anchor) *
        objectRotation(obj) *
        objectScale(obj);
    switch (obj.kind) {
      case 'cylinder':
        out.addAll(_cylinderParts(src, obj, world: world));
      case 'cuboid':
      case 'trapezoid':
      case 'plane':
        out.addAll(_flatParts(obj, world));
      case polyhedronKind:
        out.addAll(_polyhedronParts(src, obj, world: world));
    }
  }
  return out;
}


/// The world transform mapping a model/gltf instance's own frame into the
/// container world: anchor (mirrored chunkWorld) · rotation · uniform scale.
vm.Matrix4 _modelRefChain(ModelData model, ModelObject object) {
  final w = chunkWorld(object.x, object.z, model.size.w, model.size.l);
  return vm.Matrix4.translation(vm.Vector3(w.x, object.y, w.z)) *
      objectRotation(object) *
      vm.Matrix4.diagonal3Values(object.scale, object.scale, object.scale);
}

/// The object's own world placement for primitive kinds: anchor · rotation
/// (sprite additionally carries the billboard X-mirror and its yaw — the
/// live screen-parallel yaw when the caller supplies it).
vm.Matrix4 _objectWorld(
  ModelData model,
  ModelObject object, {
  double? billboardYaw,
}) {
  final w = chunkWorld(object.x, object.z, model.size.w, model.size.l);
  final anchor = vm.Vector3(w.x, object.y, w.z);
  if (object.kind == 'sprite') {
    final yaw = billboardYaw ?? object.rotY * math.pi / 180;
    return spriteBillboardMatrix(anchor, yaw);
  }
  return vm.Matrix4.translation(anchor) *
      objectRotation(object) *
      objectScale(object);
}

/// One quad part per flat face (`faceCorners` covers cuboid, trapezoid,
/// plane and sprite), baked into the world frame. The part carries the
/// renderer's side and winding flip so picking can skip invisible faces.
List<PickPart> _flatParts(ModelObject object, vm.Matrix4 world) {
  final parts = <PickPart>[];
  // Billboards are two-sided by design: culling them would make a sprite
  // disappear from behind.
  final side = object.kind == 'sprite' ? 'double' : null;
  for (final key in facesOf(object)) {
    final corners = faceCorners(object, key);
    if (corners.length < 3) continue;
    final geometry = GeometryBuilder();
    geometry.addQuad(
      a: world.transform3(corners[0].clone()),
      b: world.transform3(corners[1].clone()),
      c: world.transform3(corners[2].clone()),
      d: world.transform3(corners[3].clone()),
    );
    parts.add(
      PickPart(
        geometry.build(),
        faceKey: key,
        side: side ?? sideFor(object, key),
      ),
    );
  }
  return parts;
}

/// Per-face pick parts of a polyhedron: one ear-clipped geometry per face
/// (holes included), carrying its face key and side. [world] overrides the
/// top-level placement (nested instance content) and already includes the
/// per-axis scale.
List<PickPart> _polyhedronParts(
  ModelData model,
  ModelObject object, {
  vm.Matrix4? world,
}) {
  final mesh = object.mesh;
  if (mesh == null) return const [];
  final placement = world ?? _objectWorld(model, object);
  final parts = <PickPart>[];
  for (final face in mesh.faces) {
    final geometry = buildPolyFaceGeometry(object, mesh, face);
    if (geometry == null) continue;
    parts.add(
      PickPart(
        _inWorld(geometry, placement),
        faceKey: face.key,
        side: sideFor(object, face.key),
      ),
    );
  }
  return parts;
}

/// Cylinder parts: the wrapped side plus the caps (each its own face key).
/// [world] overrides the top-level placement (nested instance content).
List<PickPart> _cylinderParts(
  ModelData model,
  ModelObject object, {
  vm.Matrix4? world,
}) {
  final bottomR = object.dim('bottomR', 0.25);
  final topR = object.dim('topR', bottomR);
  final h = object.dim('h', 1);
  final segments = object.dim('segments', 16).clamp(3, 64).toInt();
  final placement = world ?? _objectWorld(model, object);
  final parts = <PickPart>[];
  if (bottomR > 0 || topR > 0) {
    parts.add(
      PickPart(
        _inWorld(_cylinderSide(bottomR, topR, h, segments), placement),
        faceKey: 'side',
        side: sideFor(object, 'side'),
      ),
    );
  }
  if (bottomR > 0) {
    parts.add(
      PickPart(
        _inWorld(_disc(bottomR, segments, h, up: false), placement),
        faceKey: '-y',
        side: sideFor(object, '-y'),
      ),
    );
  }
  if (topR > 0) {
    parts.add(
      PickPart(
        _inWorld(_disc(topR, segments, h, up: true), placement),
        faceKey: '+y',
        side: sideFor(object, '+y'),
      ),
    );
  }
  return parts;
}

/// Bakes [world] into [geometry] (positions and normals).
SceneGeometry _inWorld(SceneGeometry geometry, vm.Matrix4 world) {
  final b = GeometryBuilder();
  b.addGeometry(geometry, world);
  return b.build();
}

/// The cylinder side as a quad strip with the base at y = 0 (the renderer's
/// centered strip plus its h/2 offset, baked). The quads are wound so the
/// authored normal points outward, matching [sideFor]'s `outer` side.
SceneGeometry _cylinderSide(
  double bottomR,
  double topR,
  double h,
  int segments,
) {
  final b = GeometryBuilder();
  for (var s = 0; s < segments; s++) {
    final t0 = 2 * math.pi * s / segments;
    final t1 = 2 * math.pi * (s + 1) / segments;
    final b0 = vm.Vector3(bottomR * math.cos(t0), 0, bottomR * math.sin(t0));
    final b1 = vm.Vector3(bottomR * math.cos(t1), 0, bottomR * math.sin(t1));
    final t1v = vm.Vector3(topR * math.cos(t1), h, topR * math.sin(t1));
    final t0v = vm.Vector3(topR * math.cos(t0), h, topR * math.sin(t0));
    b.addQuad(a: b0, b: t0v, c: t1v, d: b1);
  }
  return b.build();
}

/// One cap disc at y = 0 (bottom) or y = h (top).
SceneGeometry _disc(double radius, int segments, double h, {required bool up}) {
  final b = GeometryBuilder();
  final y = up ? h : 0.0;
  b.setNormal(vm.Vector3(0, up ? 1 : -1, 0));
  final center = b.addVertex(vm.Vector3(0, y, 0));
  final base = b.vertexCount;
  for (var s = 0; s <= segments; s++) {
    final t = 2 * math.pi * s / segments;
    b.addVertex(vm.Vector3(radius * math.cos(t), y, radius * math.sin(t)));
  }
  for (var s = 0; s < segments; s++) {
    b.addTriangle(center, base + s, base + s + 1);
  }
  return b.build();
}

/// A rounded cuboid: the six planar faces keep their keys, every curved
/// facet shares the `round` key — exactly the renderer's grouping.
List<PickPart> _roundedParts(ModelData model, ModelObject object) {
  final polys = csgLeafPolys(object);
  return _groupedWorldParts(model, object, polys);
}

/// A csg result: one whole-object part (the renderer registers its nodes
/// without a face key).
List<PickPart> _csgParts(ModelData model, ModelObject object) {
  final polys = csgEvaluate(object, model);
  if (polys.isEmpty) return const [];
  final geometry = _worldPolyMesh(model, polys);
  if (geometry == null) return const [];
  return [PickPart(geometry, side: sideFor(object, '*'))];
}

/// Groups model-space CSG polygons by face key and bakes each group into a
/// world-space part (X mirrored about the grid center, like the renderer).
List<PickPart> _groupedWorldParts(
  ModelData model,
  ModelObject object,
  List<CsgPoly> polys,
) {
  final groups = <String, List<CsgPoly>>{};
  for (final p in polys) {
    groups.putIfAbsent(p.surface.faceKey, () => []).add(p);
  }
  final parts = <PickPart>[];
  for (final entry in groups.entries) {
    final geometry = _worldPolyMesh(model, entry.value);
    if (geometry == null) continue;
    parts.add(
      PickPart(
        geometry,
        faceKey: entry.key,
        side: sideFor(object, entry.key),
      ),
    );
  }
  return parts;
}

/// Triangulates a group of model-space polygons into world-space geometry
/// (the same mirror the renderer bakes into its meshes).
SceneGeometry? _worldPolyMesh(ModelData model, List<CsgPoly> polys) {
  final originX = (model.size.w - 1) / 2;
  final originZ = (model.size.l - 1) / 2;
  final b = GeometryBuilder();
  var base = 0;
  var vertices = 0;
  for (final p in polys) {
    final n = p.normal;
    b.setNormal(vm.Vector3(-n.x, n.y, n.z));
    for (final v in p.vertices) {
      b.addVertex(vm.Vector3(originX - v.x, v.y, v.z - originZ));
    }
    final m = p.vertices.length;
    for (var i = 1; i + 1 < m; i++) {
      b.addTriangle(base, base + i, base + i + 1);
    }
    base += m;
    vertices += m;
  }
  if (vertices < 3) return null;
  return b.build();
}

/// A model/gltf instance's footprint proxy box under the instance chain.
List<PickPart> _proxyParts(ModelObject proxy, vm.Matrix4 chain) {
  final world = chain * vm.Matrix4.translation(
    vm.Vector3(proxy.x, proxy.y, proxy.z),
  );
  final parts = <PickPart>[];
  for (final key in facesOf(proxy)) {
    final corners = faceCorners(proxy, key);
    if (corners.length < 3) continue;
    final b = GeometryBuilder();
    b.addQuad(
      a: world.transform3(corners[0].clone()),
      b: world.transform3(corners[1].clone()),
      c: world.transform3(corners[2].clone()),
      d: world.transform3(corners[3].clone()),
    );
    parts.add(
      PickPart(
        b.build(),
        faceKey: key,
        side: sideFor(proxy, key),
      ),
    );
  }
  return parts;
}
