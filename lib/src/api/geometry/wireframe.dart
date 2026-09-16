import 'dart:ui' show Color;

import 'package:vector_math/vector_math.dart' as vm;

import 'scene_geometry.dart';

/// The look of a wireframe overlay: a per-node or whole-scene edge rendering
/// with a constant screen-pixel stroke.
class WireframeStyle {
  const WireframeStyle({
    this.thickness = 1.0,
    this.color = const Color(0xFFFFFFFF),
    this.throughGeometry = true,
    this.creaseAngle,
  });

  /// The stroke thickness in screen pixels, independent of the camera
  /// distance. The default is 1 px.
  final double thickness;

  /// The stroke color.
  final Color color;

  /// Whether the wireframe draws above everything (its own render view, so it
  /// stays visible through other geometry) or on the normal scene layer.
  final bool throughGeometry;

  /// The crease angle in degrees used to drop coplanar triangulation edges;
  /// null keeps every unique edge (the helpers default to 1°).
  final double? creaseAngle;

  WireframeStyle copyWith({
    double? thickness,
    Color? color,
    bool? throughGeometry,
    double? creaseAngle,
  }) => WireframeStyle(
    thickness: thickness ?? this.thickness,
    color: color ?? this.color,
    throughGeometry: throughGeometry ?? this.throughGeometry,
    creaseAngle: creaseAngle ?? this.creaseAngle,
  );

  @override
  bool operator ==(Object other) =>
      other is WireframeStyle &&
      other.thickness == thickness &&
      other.color == color &&
      other.throughGeometry == throughGeometry &&
      other.creaseAngle == creaseAngle;

  @override
  int get hashCode =>
      Object.hash(thickness, color, throughGeometry, creaseAngle);
}

/// Appends the edge segments of [geometry] to [out] as endpoint pairs.
///
/// [creaseAngleDegrees] drops the shared edges of nearly coplanar triangles
/// (the triangulation diagonals of flat faces); the default is 1°.
void appendWireframeEdges(
  List<vm.Vector3> out,
  SceneGeometry geometry, {
  double? creaseAngleDegrees,
}) {
  final data = geometry.data.extractEdges(
    creaseAngleDegrees: creaseAngleDegrees ?? 1.0,
  );
  final positions = data.positions;
  for (var i = 0; i + 5 < positions.length; i += 6) {
    out.add(vm.Vector3(positions[i], positions[i + 1], positions[i + 2]));
    out.add(vm.Vector3(positions[i + 3], positions[i + 4], positions[i + 5]));
  }
}

/// Removes duplicate segments (the same endpoint pair in either order), so
/// the shared edges of adjacent flat faces draw once. Endpoints are
/// quantized to 0.1 mm to catch the per-face vertex copies.
List<vm.Vector3> dedupeWireframeSegments(List<vm.Vector3> segments) {
  final seen = <String>{};
  final out = <vm.Vector3>[];
  String key(vm.Vector3 point) =>
      '${(point.x * 10000).round()}:'
      '${(point.y * 10000).round()}:'
      '${(point.z * 10000).round()}';
  for (var i = 0; i + 1 < segments.length; i += 2) {
    final a = key(segments[i]);
    final b = key(segments[i + 1]);
    final pair = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
    if (!seen.add(pair)) continue;
    out.add(segments[i]);
    out.add(segments[i + 1]);
  }
  return out;
}
