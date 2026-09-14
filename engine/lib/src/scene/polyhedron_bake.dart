import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import 'csg.dart';
import 'polyhedron.dart';

/// Result of converting a primitive/csg object into a polyhedron mesh.
class PolyBakeResult {
  final PolyMesh mesh;

  /// Per-face materials of the produced mesh (copied from the source face
  /// keys). The object's default material stays on the object.
  final Map<String, ModelMaterial> faces;

  /// True when the source geometry already carried its rotation (csg results
  /// and rounded cuboids are authored in model space): the editor must reset
  /// the object's rotation after applying the mesh, the position stays.
  final bool rotationBaked;

  const PolyBakeResult(
    this.mesh,
    this.faces, {
    this.rotationBaked = false,
  });
}

/// Converts [obj]'s kind into an equivalent polyhedron mesh (local frame):
/// flat and rounded cuboids, trapezoids, cylinders/cones, planes, sprites
/// and csg results. Returns null for kinds without own geometry (model/gltf
/// refs, unknown kinds).
///
/// The conversion is visual-lossless: rendering the result through the
/// polyhedron path reproduces the source exactly (including the mirrored-X
/// world convention). Model-space sources (csg, rounded cuboid) come back
/// with [PolyBakeResult.rotationBaked]; the caller then keeps the object
/// position and zeroes the rotation.
///
/// ```dart
/// final bake = bakePolyhedron(model, object);
/// if (bake == null) return; // у вида нет своей геометрии
/// object
///   ..kind = polyhedronKind
///   ..mesh = bake.mesh
///   ..faces = bake.faces
///   ..dims.clear();
/// if (bake.rotationBaked) object
///   ..rotX = 0
///   ..rotY = 0
///   ..rotZ = 0;
/// ```
PolyBakeResult? bakePolyhedron(ModelData model, ModelObject obj) {
  switch (obj.kind) {
    case 'cuboid':
      if (isRoundedCuboid(obj)) {
        return _fromModelSpacePolys(csgLeafPolys(obj), obj);
      }
      return _bakeCuboid(obj);
    case 'trapezoid':
      return _bakeTrapezoid(obj);
    case 'cylinder':
      return _bakeCylinder(obj);
    case 'plane':
      return _bakePlane(obj);
    case 'sprite':
      return _bakeSprite(obj);
    case csgKind:
      return _fromModelSpacePolys(csgEvaluate(obj, model), obj);
    default:
      return null;
  }
}

PolyBakeResult _bakeCuboid(ModelObject obj) {
  final mesh = PolyMesh.box(
    w: obj.dim('w', 1),
    h: obj.dim('h', 1),
    d: obj.dim('d', 1),
  );
  final mats = <String, ModelMaterial>{};
  for (final face in mesh.faces) {
    final m = obj.faces[face.key];
    if (m != null) mats[face.key] = ModelMaterial.copy(m);
  }
  return PolyBakeResult(mesh, mats);
}

PolyBakeResult _bakeTrapezoid(ModelObject obj) {
  final bw = obj.dim('bottomW', 1), bd = obj.dim('bottomD', 1);
  final tw = obj.dim('topW', 0.5), td = obj.dim('topD', 0.5);
  final h = obj.dim('h', 0.5);
  final bhx = bw / 2, bhz = bd / 2, thx = tw / 2, thz = td / 2;
  final v = [
    vm.Vector3(-bhx, 0, -bhz),
    vm.Vector3(bhx, 0, -bhz),
    vm.Vector3(bhx, 0, bhz),
    vm.Vector3(-bhx, 0, bhz),
    vm.Vector3(-thx, h, -thz),
    vm.Vector3(thx, h, -thz),
    vm.Vector3(thx, h, thz),
    vm.Vector3(-thx, h, thz),
  ];
  final loops = <String, List<int>>{
    '-y': [0, 1, 2, 3],
    '+y': [4, 5, 6, 7],
    '-z': [0, 1, 5, 4],
    '+x': [1, 2, 6, 5],
    '+z': [2, 3, 7, 6],
    '-x': [3, 0, 4, 7],
  };
  return _direct(obj, v, loops);
}

PolyBakeResult _bakeCylinder(ModelObject obj) {
  final bottomR = obj.dim('bottomR', 0.25);
  final topR = obj.dim('topR', bottomR);
  final h = obj.dim('h', 1);
  final segments = obj.dim('segments', 16).clamp(3, 64).toInt();
  final vertices = <vm.Vector3>[];
  final bottom = <int>[];
  final top = <int>[];
  if (bottomR <= 0) {
    bottom.add(vertices.length);
    vertices.add(vm.Vector3(0, 0, 0));
  } else {
    for (var s = 0; s < segments; s++) {
      bottom.add(vertices.length);
      vertices.add(vm.Vector3(
        bottomR * math.cos(2 * math.pi * s / segments),
        0,
        bottomR * math.sin(2 * math.pi * s / segments),
      ));
    }
  }
  if (topR <= 0) {
    top.add(vertices.length);
    vertices.add(vm.Vector3(0, h, 0));
  } else {
    for (var s = 0; s < segments; s++) {
      top.add(vertices.length);
      vertices.add(vm.Vector3(
        topR * math.cos(2 * math.pi * s / segments),
        h,
        topR * math.sin(2 * math.pi * s / segments),
      ));
    }
  }
  final faces = <PolyFace>[];
  final mats = <String, ModelMaterial>{};
  // An apex ring holds a single shared vertex; the other holds `segments`.
  int at(List<int> ring, int i) => ring.length == 1 ? ring[0] : ring[i];
  for (var s = 0; s < segments; s++) {
    final s1 = (s + 1) % segments;
    final b0 = at(bottom, s), b1 = at(bottom, s1);
    final t0 = at(top, s), t1 = at(top, s1);
    final loop = b0 == b1
        ? [b0, t0, t1]
        : (t0 == t1 ? [b0, t0, b1] : [b0, t0, t1, b1]);
    final key = 'side_$s';
    faces.add(PolyFace(key: key, outer: PolyLoop(vertices: loop)));
    final m = obj.faces['side'];
    if (m != null) mats[key] = ModelMaterial.copy(m);
  }
  if (bottomR > 0) {
    faces.add(PolyFace(
      key: '-y',
      outer: PolyLoop(vertices: [
        for (var s = 0; s < segments; s++) bottom[s],
      ]),
    ));
    final m = obj.faces['-y'];
    if (m != null) mats['-y'] = ModelMaterial.copy(m);
  }
  if (topR > 0) {
    faces.add(PolyFace(
      key: '+y',
      outer: PolyLoop(
        vertices: [
          for (var s = segments - 1; s >= 0; s--) top[s],
        ],
      ),
    ));
    final m = obj.faces['+y'];
    if (m != null) mats['+y'] = ModelMaterial.copy(m);
  }
  _orientOutward(vertices, faces);
  return PolyBakeResult(PolyMesh(vertices: vertices, faces: faces), mats);
}

PolyBakeResult _bakePlane(ModelObject obj) {  final w = obj.dim('w', 1), d = obj.dim('d', 1);
  final vertical = obj.flag('vertical');
  final key = vertical ? '+z' : '+y';
  final v = vertical
      ? [
          vm.Vector3(-w / 2, 0, 0),
          vm.Vector3(w / 2, 0, 0),
          vm.Vector3(w / 2, d, 0),
          vm.Vector3(-w / 2, d, 0),
        ]
      : [
          vm.Vector3(-w / 2, 0, d / 2),
          vm.Vector3(w / 2, 0, d / 2),
          vm.Vector3(w / 2, 0, -d / 2),
          vm.Vector3(-w / 2, 0, -d / 2),
        ];
  return _direct(obj, v, {
    key: [0, 1, 2, 3],
  });
}

PolyBakeResult _bakeSprite(ModelObject obj) {
  final w = obj.dim('w', 1), h = obj.dim('h', 1);
  final v = [
    vm.Vector3(-w / 2, 0, 0),
    vm.Vector3(w / 2, 0, 0),
    vm.Vector3(w / 2, h, 0),
    vm.Vector3(-w / 2, h, 0),
  ];
  return _direct(obj, v, {
    '*': [0, 1, 2, 3],
  });
}

/// A direct-frame conversion: loops reuse the primitive's own local frame
/// and the object keeps its rotation. Non-convex inputs never get here —
/// the converter's primitives are convex, so the outward orientation is
/// normalized against the vertex centroid (some `faceCorners` orders follow
/// the renderer's strip winding, not the Newell-outward convention).
PolyBakeResult _direct(
  ModelObject obj,
  List<vm.Vector3> vertices,
  Map<String, List<int>> loops,
) {
  final faces = <PolyFace>[];
  final mats = <String, ModelMaterial>{};
  for (final e in loops.entries) {
    faces.add(PolyFace(key: e.key, outer: PolyLoop(vertices: e.value)));
    final m = obj.faces[e.key];
    if (m != null) mats[e.key] = ModelMaterial.copy(m);
  }
  _orientOutward(vertices, faces);
  return PolyBakeResult(PolyMesh(vertices: vertices, faces: faces), mats);
}

/// Flips loops so their Newell normal points away from the solid's vertex
/// centroid (convex primitives only).
void _orientOutward(List<vm.Vector3> vertices, List<PolyFace> faces) {
  if (faces.length < 2) return;
  var centroid = vm.Vector3.zero();
  for (final v in vertices) {
    centroid += v;
  }
  centroid /= vertices.length.toDouble();
  final mesh = PolyMesh(vertices: vertices, faces: faces);
  for (final face in faces) {
    final n = polyFaceNormal(mesh, face);
    if (n.length2 < 1e-18) continue;
    var center = vm.Vector3.zero();
    for (final i in face.outer.vertices) {
      center += mesh.vertices[i];
    }
    center /= face.outer.vertices.length.toDouble();
    if (n.dot(center - centroid) < 0) {
      final reversed = List<int>.of(face.outer.vertices.reversed);
      face.outer.vertices.setAll(0, reversed);
    }
  }
}

/// A model-space source (csg result / rounded cuboid): vertices are
/// re-expressed in the object's local frame with the world X-mirror baked
/// (matching the renderer), and the baked rotation makes the caller zero
/// `rotX/Y/Z`.
PolyBakeResult _fromModelSpacePolys(List<CsgPoly> polys, ModelObject obj) {
  final a = vm.Vector3(obj.x, obj.y, obj.z);
  final totals = <String, int>{};
  for (final p in polys) {
    totals[p.surface.faceKey] = (totals[p.surface.faceKey] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final byPosition = <String, int>{};
  final vertices = <vm.Vector3>[];
  final faces = <PolyFace>[];
  final mats = <String, ModelMaterial>{};
  for (final p in polys) {
    if (p.vertices.length < 3) continue;
    final src = p.surface.faceKey;
    final i = seen[src] ?? 0;
    seen[src] = i + 1;
    final key = (totals[src] ?? 1) > 1 ? '${src}_$i' : src;
    final loop = <int>[];
    for (final raw in p.vertices) {
      // Model → local (mirror X baked into the vertex, like the renderer's
      // world emission), then the loop is reversed to restore the outward
      // CCW winding of the polyhedron convention.
      final local = vm.Vector3(-(raw.x - a.x), raw.y - a.y, raw.z - a.z);
      final id = '${round6(local.x)},${round6(local.y)},${round6(local.z)}';
      final index = byPosition.putIfAbsent(id, () {
        vertices.add(local);
        return vertices.length - 1;
      });
      loop.add(index);
    }
    while (loop.length > 1 && loop.first == loop.last) {
      loop.removeLast();
    }
    if (loop.length < 3) continue;
    faces.add(PolyFace(
      key: key,
      outer: PolyLoop(vertices: loop.reversed.toList()),
    ));
    final m = obj.faces[src];
    if (m != null) mats[key] = ModelMaterial.copy(m);
  }
  return PolyBakeResult(
    PolyMesh(vertices: vertices, faces: faces),
    mats,
    rotationBaked: true,
  );
}
