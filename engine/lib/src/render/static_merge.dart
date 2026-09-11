import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The result of [mergeStaticNodes]: the new merged nodes and the source
/// nodes they consumed.
class StaticMergeResult {
  const StaticMergeResult(this.merged, this.consumed);

  /// New one-mesh nodes (one per merged group).
  final List<Node> merged;

  /// Source nodes whose geometry was baked into [merged] — the caller must
  /// detach/forget them.
  final List<Node> consumed;
}

/// Merges single-primitive readable [nodes] into one mesh per group, baking
/// each node's local transform into the vertices (and reversing triangle
/// winding for negative-determinant transforms, matching the renderer's
/// per-node winding parity). Groups with fewer than two nodes stay as they
/// are. The group key defaults to the material identity; the level baker
/// passes a shape+material key for its `batch` mode.
///
/// Shared by `ModelRenderer`'s `mergeStatic` and the level baker — one
/// implementation of the merge invariant (global index rebasing + winding).
StaticMergeResult mergeStaticNodes(
  List<Node> nodes, {
  Object Function(Node node, Material material)? groupKey,
}) {
  final groups = <Object, List<Node>>{};
  for (final node in nodes) {
    final mesh = node.mesh;
    if (mesh == null || mesh.primitives.length != 1) continue;
    final primitive = mesh.primitives.first;
    if (!primitive.geometry.isReadable) continue;
    final key = groupKey?.call(node, primitive.material) ?? primitive.material;
    groups.putIfAbsent(key, () => []).add(node);
  }
  final merged = <Node>[];
  final consumed = <Node>[];
  for (final entry in groups.entries) {
    final group = entry.value;
    if (group.length < 2) continue;
    final builder = GeometryBuilder(deduplicate: false);
    for (final node in group) {
      appendNodeGeometry(builder, node);
    }
    if (builder.triangleCount == 0) continue;
    final material = group.first.mesh!.primitives.first.material;
    merged.add(
      Node(
        name: 'merged:${identityHashCode(entry.key)}',
        mesh: Mesh(builder.build(), material),
      )..shadowStatic = true,
    );
    consumed.addAll(group);
  }
  return StaticMergeResult(merged, consumed);
}

/// Appends [node]'s single-primitive geometry to [builder] with its local
/// transform baked into positions and normals. Triangle indices are rebased
/// on the builder's current vertex count (the global-index trap).
void appendNodeGeometry(GeometryBuilder builder, Node node) {
  final geometry = node.mesh!.primitives.first.geometry;
  final data = geometry.extractMeshData();
  final transform = node.localTransform;
  final s = transform.storage;
  // The renderer flips cull winding for negative-determinant transforms;
  // baking the transform into vertices drops that compensation, so the
  // triangle order is reversed here instead.
  final flip = transform.determinant() < 0;
  final positions = data.positions;
  final normals = data.normals;
  final texCoords = data.texCoords;
  final colors = data.colors;
  final base = builder.vertexCount;
  for (var i = 0; i < data.vertexCount; i++) {
    final x = positions[i * 3];
    final y = positions[i * 3 + 1];
    final z = positions[i * 3 + 2];
    if (normals != null) {
      final nx = normals[i * 3];
      final ny = normals[i * 3 + 1];
      final nz = normals[i * 3 + 2];
      final tx = s[0] * nx + s[4] * ny + s[8] * nz;
      final ty = s[1] * nx + s[5] * ny + s[9] * nz;
      final tz = s[2] * nx + s[6] * ny + s[10] * nz;
      final len = math.sqrt(tx * tx + ty * ty + tz * tz);
      builder.normal(len > 1e-12
          ? vm.Vector3(tx / len, ty / len, tz / len)
          : vm.Vector3(0, 0, 1));
    }
    if (texCoords != null) {
      builder.texCoord(vm.Vector2(texCoords[i * 2], texCoords[i * 2 + 1]));
    }
    if (colors != null) {
      builder.color(vm.Vector4(
          colors[i * 4], colors[i * 4 + 1], colors[i * 4 + 2], colors[i * 4 + 3]));
    } else {
      builder.color(vm.Vector4(1, 1, 1, 1));
    }
    builder.addVertex(vm.Vector3(
      s[0] * x + s[4] * y + s[8] * z + s[12],
      s[1] * x + s[5] * y + s[9] * z + s[13],
      s[2] * x + s[6] * y + s[10] * z + s[14],
    ));
  }
  final indices = data.indices;
  if (indices != null) {
    for (var t = 0; t + 2 < indices.length; t += 3) {
      final a = base + indices[t];
      var b = base + indices[t + 1];
      var c = base + indices[t + 2];
      if (flip) {
        final swap = b;
        b = c;
        c = swap;
      }
      builder.addTriangle(a, b, c);
    }
  } else {
    for (var t = 0; t + 2 < data.vertexCount; t += 3) {
      final a = base + t;
      var b = base + t + 1;
      var c = base + t + 2;
      if (flip) {
        final swap = b;
        b = c;
        c = swap;
      }
      builder.addTriangle(a, b, c);
    }
  }
}
