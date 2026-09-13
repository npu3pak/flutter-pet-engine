import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/line_geometry.dart';
import '../geometry/scene_geometry.dart';
import '../materials/scene_material.dart';
import '../scene_controller.dart';
import '../scene_layer.dart';
import 'group_node.dart';
import 'primitives.dart';
import 'scene_node.dart';

/// What a gizmo edits.
enum GizmoMode {
  /// Three arrows: drag an axis to move along it.
  translate,

  /// Three rings: drag a ring to rotate around its axis.
  rotate,
}

/// A gizmo axis (the world X, Y or Z direction).
enum GizmoAxis { x, y, z }

/// The world direction of [axis].
vm.Vector3 gizmoAxisDirection(GizmoAxis axis) => switch (axis) {
  GizmoAxis.x => vm.Vector3(1, 0, 0),
  GizmoAxis.y => vm.Vector3(0, 1, 0),
  GizmoAxis.z => vm.Vector3(0, 0, 1),
};

/// The screen-space look and feel of a [GizmoNode]. Every size is in logical
/// pixels, so the gizmo keeps its size at any camera distance.
class GizmoStyle {
  const GizmoStyle({
    this.lineWidth = 3.0,
    this.length = 96.0,
    this.tipLength = 18.0,
    this.hitTolerance = 12.0,
    this.xColor = const Color(0xFFFF4136),
    this.yColor = const Color(0xFF5AD469),
    this.zColor = const Color(0xFF4A90D9),
    this.throughGeometry = true,
  });

  /// The shaft/ring line thickness in screen pixels (the default is 3 px).
  final double lineWidth;

  /// The arrow length (translate) or ring radius (rotate) in screen pixels.
  final double length;

  /// The arrow tip length in screen pixels.
  final double tipLength;

  /// How close a tap must be to a handle, in screen pixels.
  final double hitTolerance;

  final Color xColor;
  final Color yColor;
  final Color zColor;

  /// Whether the gizmo draws above everything (its own view).
  final bool throughGeometry;

  Color colorFor(GizmoAxis axis) => switch (axis) {
    GizmoAxis.x => xColor,
    GizmoAxis.y => yColor,
    GizmoAxis.z => zColor,
  };

  GizmoStyle copyWith({
    double? lineWidth,
    double? length,
    double? tipLength,
    double? hitTolerance,
    Color? xColor,
    Color? yColor,
    Color? zColor,
    bool? throughGeometry,
  }) => GizmoStyle(
    lineWidth: lineWidth ?? this.lineWidth,
    length: length ?? this.length,
    tipLength: tipLength ?? this.tipLength,
    hitTolerance: hitTolerance ?? this.hitTolerance,
    xColor: xColor ?? this.xColor,
    yColor: yColor ?? this.yColor,
    zColor: zColor ?? this.zColor,
    throughGeometry: throughGeometry ?? this.throughGeometry,
  );

  @override
  bool operator ==(Object other) =>
      other is GizmoStyle &&
      other.lineWidth == lineWidth &&
      other.length == length &&
      other.tipLength == tipLength &&
      other.hitTolerance == hitTolerance &&
      other.xColor == xColor &&
      other.yColor == yColor &&
      other.zColor == zColor &&
      other.throughGeometry == throughGeometry;

  @override
  int get hashCode => Object.hash(
    lineWidth,
    length,
    tipLength,
    hitTolerance,
    xColor,
    yColor,
    zColor,
    throughGeometry,
  );
}

/// A gizmo handle under the pointer: the gizmo plus the axis to drag.
class GizmoHit {
  const GizmoHit(this.gizmo, this.axis);

  final GizmoNode gizmo;
  final GizmoAxis axis;
}

/// A drag update produced by a [GizmoNode].
class GizmoDragEvent {
  const GizmoDragEvent({
    required this.axis,
    this.translation,
    this.rotation,
  });

  final GizmoAxis axis;

  /// The world-space translation delta (translate gizmos).
  final vm.Vector3? translation;

  /// The rotation angle in radians around [axis] (rotate gizmos).
  final double? rotation;
}

/// A screen-space translate/rotate gizmo.
///
/// The gizmo keeps a constant pixel size: the controller rescales it every
/// frame from the camera distance. It draws on the top layer, so it stays
/// visible through the scene, and [SceneController.hitGizmo] gives it
/// priority over every scene object regardless of depth.
///
/// Attach it with `SceneController.addGizmo`. Drags are driven by the
/// controller ([SceneController.beginGizmoDrag] and friends); the deltas
/// arrive through [onDrag], and an optional [target] node is transformed
/// directly.
class GizmoNode extends GroupNode {
  GizmoNode({
    super.id,
    super.name,
    required this.mode,
    required vm.Vector3 anchor,
    this.style = const GizmoStyle(),
    this.target,
    this.onDrag,
    this.onDragEnd,
  }) : _anchor = anchor.clone(),
       super(layer: style.throughGeometry ? SceneLayer.top : SceneLayer.base) {
    _buildVisuals();
  }

  /// Translate or rotate.
  GizmoMode mode;

  GizmoStyle style;

  /// The node transformed directly by drags, or null for callback-only use.
  SceneNode? target;

  /// Called on every drag update.
  void Function(GizmoDragEvent event)? onDrag;

  /// Called when the drag ends.
  void Function()? onDragEnd;

  vm.Vector3 _anchor;

  /// The world anchor of the gizmo.
  vm.Vector3 get anchor => _anchor;
  set anchor(vm.Vector3 value) {
    if (_anchor == value) return;
    _anchor = value.clone();
    _applyTransform();
    markChanged();
  }

  double _screenScale = 0.0;

  /// The current world length of one gizmo unit (arrow length / ring radius).
  double get screenScale => _screenScale;

  /// Sets the gizmo's world length for the current camera (the world size of
  /// one gizmo unit). The controller calls it every frame; tests and
  /// headless setups may call it explicitly.
  void applyScreenScale(double scale) {
    if ((scale - _screenScale).abs() < 1e-9) return;
    _screenScale = scale;
    _applyTransform();
  }

  /// Keeps the gizmo on its [target]'s world position (called by the
  /// controller each frame).
  @internal
  void followTarget() {
    final target = this.target;
    if (target == null) return;
    final position = target.globalTransform.getTranslation();
    if ((_anchor - position).length2 < 1e-12) return;
    _anchor = position.clone();
    _applyTransform();
  }

  void _applyTransform() {
    engine.transform =
        vm.Matrix4.translation(_anchor) *
        vm.Matrix4.diagonal3Values(_screenScale, _screenScale, _screenScale);
  }

  int get _layer =>
      style.throughGeometry ? SceneLayer.top : SceneLayer.base;

  void _buildVisuals() {
    removeAll();
    if (mode == GizmoMode.translate) {
      _buildTranslate();
    } else {
      _buildRotate();
    }
    _applyTransform();
  }

  void _buildTranslate() {
    final tipRatio = style.length <= 0
        ? 0.2
        : (style.tipLength / style.length).clamp(0.05, 0.5);
    final shaftEnd = 1.0 - tipRatio;
    for (final axis in GizmoAxis.values) {
      final dir = gizmoAxisDirection(axis);
      final color = style.colorFor(axis);
      final shaft = LineNode(
        id: '$id:${axis.name}:shaft',
        geometry: LineGeometry(
          [vm.Vector3.zero(), dir * shaftEnd],
          widthPx: style.lineWidth,
        ),
        color: color,
      )..layer = _layer;
      add(shaft);
      final tip = MeshNode(
        id: '$id:${axis.name}:tip',
        geometry: SceneGeometry.cone(
          radius: tipRatio * 0.35,
          height: tipRatio,
        ),
        material: SceneMaterial.unlit(color: color),
      )..layer = _layer;
      tip.transform =
          vm.Matrix4.translation(dir * (1 - tipRatio / 2)) *
          _tipRotation(axis);
      add(tip);
    }
  }

  void _buildRotate() {
    const segments = 64;
    for (final axis in GizmoAxis.values) {
      final points = <vm.Vector3>[];
      for (var i = 0; i <= segments; i++) {
        final t = 2 * math.pi * i / segments;
        final c = math.cos(t);
        final s = math.sin(t);
        points.add(switch (axis) {
          GizmoAxis.x => vm.Vector3(0, c, s),
          GizmoAxis.y => vm.Vector3(c, 0, s),
          GizmoAxis.z => vm.Vector3(c, s, 0),
        });
      }
      final segmentsList = <vm.Vector3>[];
      for (var i = 0; i < points.length - 1; i++) {
        segmentsList
          ..add(points[i])
          ..add(points[i + 1]);
      }
      final ring = LineNode(
        id: '$id:${axis.name}:ring',
        geometry: LineGeometry(segmentsList, widthPx: style.lineWidth),
        color: style.colorFor(axis),
      )..layer = _layer;
      add(ring);
    }
  }

  static vm.Matrix4 _tipRotation(GizmoAxis axis) => switch (axis) {
    GizmoAxis.y => vm.Matrix4.identity(),
    GizmoAxis.x => vm.Matrix4.rotationZ(-math.pi / 2),
    GizmoAxis.z => vm.Matrix4.rotationX(math.pi / 2),
  };

  /// The handle under [screenPoint], or null. Screen-space and
  /// depth-independent: a scene object in front of the gizmo never steals
  /// the tap.
  GizmoHit? hitTest(Offset screenPoint) {
    final controller = scene;
    if (controller == null || _screenScale <= 0) return null;
    final anchorScreen = controller.worldToScreen(_anchor);
    if (anchorScreen == null) return null;
    final tolerance = style.hitTolerance;
    GizmoAxis? best;
    var bestDistance = tolerance;
    for (final axis in GizmoAxis.values) {
      final distance = mode == GizmoMode.translate
          ? _translateHandleDistance(controller, screenPoint, anchorScreen, axis)
          : _rotateHandleDistance(controller, screenPoint, axis);
      if (distance != null && distance < bestDistance) {
        bestDistance = distance;
        best = axis;
      }
    }
    return best == null ? null : GizmoHit(this, best);
  }

  double? _translateHandleDistance(
    SceneController controller,
    Offset screenPoint,
    Offset anchorScreen,
    GizmoAxis axis,
  ) {
    final end = controller.worldToScreen(
      _anchor + gizmoAxisDirection(axis) * _screenScale,
    );
    if (end == null) return null;
    return _distanceToSegment(screenPoint, anchorScreen, end);
  }

  double? _rotateHandleDistance(
    SceneController controller,
    Offset screenPoint,
    GizmoAxis axis,
  ) {
    const segments = 48;
    Offset? previous;
    var best = double.infinity;
    for (var i = 0; i <= segments; i++) {
      final t = 2 * math.pi * i / segments;
      final c = math.cos(t);
      final s = math.sin(t);
      final point = switch (axis) {
        GizmoAxis.x => vm.Vector3(0, c, s),
        GizmoAxis.y => vm.Vector3(c, 0, s),
        GizmoAxis.z => vm.Vector3(c, s, 0),
      };
      final projected = controller.worldToScreen(
        _anchor + point * _screenScale,
      );
      if (projected != null && previous != null) {
        best = math.min(
          best,
          _distanceToSegment(screenPoint, previous, projected),
        );
      }
      previous = projected;
    }
    return best == double.infinity ? null : best;
  }

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (length2 < 1e-9) return (point - a).distance;
    final t = (((point - a).dx * ab.dx + (point - a).dy * ab.dy) / length2)
        .clamp(0.0, 1.0);
    return (point - (a + ab * t)).distance;
  }

  // ── drag ─────────────────────────────────────────────────────────────

  GizmoAxis? _dragAxis;
  vm.Vector3? _dragPlanePoint;
  vm.Vector3? _dragPlaneNormal;
  double _dragStartValue = 0;
  vm.Vector3? _rotCenter;
  vm.Vector3? _rotStartPoint;
  vm.Matrix4? _targetStartTransform;

  /// Whether a drag is in progress.
  bool get dragging => _dragAxis != null;

  /// Starts a drag of [axis] grabbed at [screenPoint].
  void beginDrag(GizmoAxis axis, Offset screenPoint) {
    final controller = scene;
    if (controller == null) return;
    _dragAxis = axis;
    _targetStartTransform = target?.transform.clone();
    final dir = gizmoAxisDirection(axis);
    if (mode == GizmoMode.translate) {
      _dragPlanePoint = _anchor.clone();
      final ray = controller.screenPointToRay(screenPoint);
      // The drag plane faces the actual view direction through the grab
      // point (the horizontal forward degenerates for a top-down camera).
      _dragPlaneNormal = ray.direction.clone();
      _dragStartValue =
          axisDragDelta(ray, _dragPlanePoint!, _dragPlaneNormal!, dir) ?? 0;
    } else {
      _rotCenter = _anchor.clone();
      _rotStartPoint = planeHit(
        controller.screenPointToRay(screenPoint),
        _rotCenter!,
        dir,
      );
    }
  }

  /// Advances the active drag to [screenPoint].
  void updateDrag(Offset screenPoint) {
    final controller = scene;
    final axis = _dragAxis;
    if (controller == null || axis == null) return;
    final dir = gizmoAxisDirection(axis);
    final ray = controller.screenPointToRay(screenPoint);
    if (mode == GizmoMode.translate) {
      final point = _dragPlanePoint;
      final normal = _dragPlaneNormal;
      if (point == null || normal == null) return;
      final current = axisDragDelta(ray, point, normal, dir);
      if (current == null) return;
      final translation = dir * (current - _dragStartValue);
      _applyTargetTranslation(translation);
      onDrag?.call(GizmoDragEvent(axis: axis, translation: translation));
    } else {
      final center = _rotCenter;
      final startPoint = _rotStartPoint;
      if (center == null || startPoint == null) return;
      final delta = rotationDragDelta(ray, center, dir, startPoint);
      if (delta == null) return;
      _applyTargetRotation(center, dir, delta);
      onDrag?.call(GizmoDragEvent(axis: axis, rotation: delta));
    }
  }

  /// Ends the active drag.
  void endDrag() {
    if (_dragAxis == null) return;
    _dragAxis = null;
    _dragPlanePoint = null;
    _dragPlaneNormal = null;
    _rotCenter = null;
    _rotStartPoint = null;
    _targetStartTransform = null;
    onDragEnd?.call();
  }

  void _applyTargetTranslation(vm.Vector3 delta) {
    final target = this.target;
    final start = _targetStartTransform;
    if (target == null || start == null) return;
    target.position = start.getTranslation() + delta;
  }

  void _applyTargetRotation(vm.Vector3 center, vm.Vector3 axis, double angle) {
    final target = this.target;
    final start = _targetStartTransform;
    if (target == null || start == null) return;
    final rotation = vm.Matrix4.compose(
      vm.Vector3.zero(),
      vm.Quaternion.axisAngle(axis.normalized(), angle),
      vm.Vector3(1, 1, 1),
    );
    final around =
        vm.Matrix4.translation(center) *
        rotation *
        vm.Matrix4.translation(-center);
    target.transform = around * start;
  }
}

/// The signed distance the ray hit moved along [axisDir] since the drag
/// start, projected on a plane through [planePoint] perpendicular to
/// [planeNormal]. Returns null when the ray is parallel to the plane.
///
/// The plane keeps the movement screen-proportional with a correct sign even
/// when the ray is nearly parallel to the axis (the closest-point method
/// swings there).
double? axisDragDelta(
  vm.Ray ray,
  vm.Vector3 planePoint,
  vm.Vector3 planeNormal,
  vm.Vector3 axisDir,
) {
  final denom = ray.direction.dot(planeNormal);
  if (denom.abs() < 1e-6) return null;
  final t = (planePoint - ray.origin).dot(planeNormal) / denom;
  final hit = ray.origin + ray.direction * t;
  return (hit - planePoint).dot(axisDir);
}

/// The ray's intersection with the plane through [point] perpendicular to
/// [normal], or null when the ray is parallel to the plane.
vm.Vector3? planeHit(vm.Ray ray, vm.Vector3 point, vm.Vector3 normal) {
  final denom = ray.direction.dot(normal);
  if (denom.abs() < 1e-6) return null;
  final t = (point - ray.origin).dot(normal) / denom;
  return ray.origin + ray.direction * t;
}

/// The signed angle from [from] to [to] around [axis] (radians), positive =
/// right-handed rotation about [axis].
double signedAngleAroundAxis(
  vm.Vector3 from,
  vm.Vector3 to,
  vm.Vector3 axis,
) {
  final u = from.normalized();
  final v = to.normalized();
  final cos = u.dot(v);
  final sin = u.cross(v).dot(axis);
  return math.atan2(sin, cos);
}

/// The signed angle (radians) the ray's hit has swept in the plane through
/// [center] perpendicular to [axisDir] since the grab-time [startPoint].
/// Returns null when the ray is parallel to the plane.
double? rotationDragDelta(
  vm.Ray ray,
  vm.Vector3 center,
  vm.Vector3 axisDir,
  vm.Vector3 startPoint,
) {
  final hit = planeHit(ray, center, axisDir);
  if (hit == null) return null;
  final from = startPoint - center;
  final to = hit - center;
  if (from.length < 1e-9 || to.length < 1e-9) return null;
  return signedAngleAroundAxis(from, to, axisDir);
}

/// A model grid: screen-pixel lines on a flat XZ plane.
class GridNode extends LineNode {
  GridNode({
    super.id,
    super.name,
    super.layer = SceneLayer.overlay,
    super.color = const Color(0xFF737380),
    required double width,
    required double depth,
    double cell = 1.0,
    double lineWidthPx = 1.0,
    vm.Vector3? center,
  }) : super(
         geometry: LineGeometry(
           gridSegments(
             width: width,
             depth: depth,
             cell: cell,
             center: center ?? vm.Vector3.zero(),
           ),
           widthPx: lineWidthPx,
         ),
       );
}

/// The endpoint pairs of a [width]×[depth] grid with [cell] spacing, centered
/// on [center] (in the XZ plane).
List<vm.Vector3> gridSegments({
  required double width,
  required double depth,
  double cell = 1.0,
  vm.Vector3? center,
}) {
  if (cell <= 0 || width <= 0 || depth <= 0) return const [];
  final origin = center ?? vm.Vector3.zero();
  final out = <vm.Vector3>[];
  final halfW = width / 2;
  final halfD = depth / 2;
  for (var x = -halfW; x <= halfW + 1e-9; x += cell) {
    out
      ..add(vm.Vector3(origin.x + x, origin.y, origin.z - halfD))
      ..add(vm.Vector3(origin.x + x, origin.y, origin.z + halfD));
  }
  for (var z = -halfD; z <= halfD + 1e-9; z += cell) {
    out
      ..add(vm.Vector3(origin.x - halfW, origin.y, origin.z + z))
      ..add(vm.Vector3(origin.x + halfW, origin.y, origin.z + z));
  }
  return out;
}
