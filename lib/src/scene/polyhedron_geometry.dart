import 'package:vector_math/vector_math.dart' as vm;

import '../api/geometry/geometry_builder.dart';
import '../api/geometry/scene_geometry.dart';
import '../models/model_scene.dart';
import 'model_renderer.dart' show quadFlipFor, sideFor;
import 'polyhedron.dart';

/// Builds the render/pick geometry of ONE polyhedron face: ear-clipped
/// triangles with flat outward normals and texture coordinates.
///
/// UVs: explicit loop UVs win (they are final texture coordinates — the
/// material's stretch/rotation/flip settings are not applied); otherwise the
/// face is projected onto its plane and [uvMaterial]'s `stretch`/`tile`
/// semantics apply exactly like the flat primitive faces. A null
/// [uvMaterial] keeps normalized 0..1 planar UVs (the runtime node path).
///
/// [flip] reverses the triangle order (the engine's front-face convention:
/// the flat quads need it for `outer` sides).
SceneGeometry? buildPolyFaceGeometryRaw({
  required PolyMesh mesh,
  required PolyFace face,
  required bool flip,
  ModelMaterial? uvMaterial,
}) {
  final triangles = triangulatePolyFace(mesh, face);
  if (triangles.isEmpty) return null;
  final normal = polyFaceNormal(mesh, face);
  if (normal.length2 < 1e-18) return null;
  final unit = normal.normalized();
  final (u, v) = polyFaceBasis(unit);

  // Explicit UV lookup: the first loop that carries them defines the UV of
  // each vertex (loop UV arrays are parallel to their vertex arrays).
  final explicit = <int, vm.Vector2>{};
  for (final loop in [face.outer, ...face.holes]) {
    if (!loop.hasUvs) continue;
    for (var i = 0; i < loop.vertices.length; i++) {
      explicit.putIfAbsent(loop.vertices[i], () => loop.uvs[i]);
    }
  }
  final useExplicit = triangles.every(
    (t) =>
        explicit.containsKey(t.$1) &&
        explicit.containsKey(t.$2) &&
        explicit.containsKey(t.$3),
  );

  // The planar frame of the whole face (outer + holes) for relative UVs.
  var uMin = double.infinity, uMax = -double.infinity;
  var vMin = double.infinity, vMax = -double.infinity;
  for (final loop in [face.outer, ...face.holes]) {
    for (final i in loop.vertices) {
      final p = mesh.vertices[i];
      final pu = p.dot(u), pv = p.dot(v);
      if (pu < uMin) uMin = pu;
      if (pu > uMax) uMax = pu;
      if (pv < vMin) vMin = pv;
      if (pv > vMax) vMax = pv;
    }
  }
  final mat = uvMaterial;
  final ts = mat == null || mat.tileScale <= 0 ? 1.0 : mat.tileScale;
  final tsu = mat == null || mat.tileScaleU <= 0 ? ts : mat.tileScaleU;
  final tsv = mat == null || mat.tileScaleV <= 0 ? ts : mat.tileScaleV;
  final tiled = mat != null && mat.stretch == 'tile';
  final uExtent = uMax - uMin;
  final vExtent = vMax - vMin;

  (double, double) uvAt(int index) {
    if (useExplicit) {
      final uv = explicit[index]!;
      return (uv.x, uv.y);
    }
    final p = mesh.vertices[index];
    var du = uExtent <= 1e-12 ? 0.0 : (p.dot(u) - uMin) / uExtent;
    var dv = vExtent <= 1e-12 ? 0.0 : (p.dot(v) - vMin) / vExtent;
    if (tiled) {
      du *= uExtent / tsu;
      dv *= vExtent / tsv;
    }
    return mat == null ? (du, dv) : _transformUv(mat, du, dv);
  }

  final builder = GeometryBuilder();
  builder.setNormal(unit);
  for (final t in triangles) {
    final (a, b, c) = t;
    final indices = <int>[];
    for (final i in [a, b, c]) {
      final (uu, vv) = uvAt(i);
      builder.setTexCoord(uu, vv);
      indices.add(builder.addVertex(mesh.vertices[i].clone()));
    }
    if (flip) {
      builder.addTriangle(indices[0], indices[2], indices[1]);
    } else {
      builder.addTriangle(indices[0], indices[1], indices[2]);
    }
  }
  return builder.build();
}

/// The document path of [buildPolyFaceGeometryRaw]: the object's default
/// material drives planar UVs and the face side drives the winding flip.
SceneGeometry? buildPolyFaceGeometry(
  ModelObject obj,
  PolyMesh mesh,
  PolyFace face,
) =>
    buildPolyFaceGeometryRaw(
      mesh: mesh,
      face: face,
      uvMaterial: obj.material,
      flip: quadFlipFor(sideFor(obj, face.key)),
    );

/// Rotation (about the face center) + flips — the `_UvSpec.transform`
/// semantics of the flat parts.
(double, double) _transformUv(ModelMaterial mat, double u, double v) {
  const c = 0.5;
  var nu = u - c, nv = v - c;
  final (ru, rv) = switch (mat.uvDir % 360) {
    90 => (nv, -nu),
    180 => (-nu, -nv),
    270 => (-nv, nu),
    _ => (nu, nv),
  };
  nu = ru + c;
  nv = rv + c;
  if (mat.flipX) nu = 1 - nu;
  if (mat.flipY) nv = 1 - nv;
  return (nu, nv);
}
