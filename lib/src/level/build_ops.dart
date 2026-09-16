import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import '../scene/face_snap.dart';
import '../scene/model_renderer.dart' show objectRotation;

/// The exact + convenient operation set of the level layer: everything the
/// in-game builder and the editor need to place and snap primitives without
/// hand-rolling coordinate math.
///
/// Two levels, one implementation: the exact operations ([objectBounds],
/// [objectCenter], [translateObject], [setSizeAlong]) are public and complete;
/// the convenient ones ([snapToFace], [alignTo], [fillGap], [cover], [inset],
/// [outset], [stretchTo]) are thin compositions of them. All operations work
/// in model-local coordinates and resolve immediately — no live dependency
/// graph.
///
/// The mirrored-X convention is sacred: positions here are model-local; the
/// world mirror happens only in the renderer (`cellWorld`/`chunkWorld`).

/// Axis selector for the axis-aligned convenient operations.
enum LevelAxis { x, y, z }

/// Model-local AABB of [obj] with its rotation applied (the local box's eight
/// corners rotated around the anchor). Sprites use the billboard frame.
(vm.Vector3 min, vm.Vector3 max) objectBounds(ModelObject obj) {
  final (minX, minY, minZ) = obj.minCorner();
  final (maxX, maxY, maxZ) = obj.maxCorner();
  final anchor = vm.Vector3(obj.x, obj.y, obj.z);
  final rot = objectRotation(obj);
  var lo = vm.Vector3(
    double.infinity,
    double.infinity,
    double.infinity,
  );
  var hi = vm.Vector3(
    double.negativeInfinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final px in [minX, maxX]) {
    for (final py in [minY, maxY]) {
      for (final pz in [minZ, maxZ]) {
        final p = anchor + rot.transform3(vm.Vector3(px, py, pz) - anchor);
        lo = vm.Vector3(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z));
        hi = vm.Vector3(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z));
      }
    }
  }
  return (lo, hi);
}

/// The center of [obj]'s rotation-aware AABB.
vm.Vector3 objectCenter(ModelObject obj) {
  final (lo, hi) = objectBounds(obj);
  return (lo + hi) / 2;
}

/// The size of [obj]'s rotation-aware AABB.
vm.Vector3 objectSize(ModelObject obj) {
  final (lo, hi) = objectBounds(obj);
  return hi - lo;
}

/// Moves [obj] by [delta] (model-local).
ModelObject translateObject(ModelObject obj, vm.Vector3 delta) {
  obj.x += delta.x;
  obj.y += delta.y;
  obj.z += delta.z;
  return obj;
}

/// Sets the object's size along [axis] (bounds-based; the center stays).
/// Supported for cuboid (full), trapezoid/cylinder/plane/sprite (best
/// effort — the matching dims are set).
ModelObject setSizeAlong(ModelObject obj, LevelAxis axis, double size) {
  final s = math.max(size, 0.0);
  switch (obj.kind) {
    case 'cuboid':
      switch (axis) {
        case LevelAxis.x:
          obj.setDim('w', s);
        case LevelAxis.y:
          obj.setDim('h', s);
        case LevelAxis.z:
          obj.setDim('d', s);
      }
    case 'trapezoid':
      switch (axis) {
        case LevelAxis.x:
          obj.setDim('bottomW', s);
          obj.setDim('topW', s);
        case LevelAxis.y:
          obj.setDim('h', s);
        case LevelAxis.z:
          obj.setDim('bottomD', s);
          obj.setDim('topD', s);
      }
    case 'cylinder':
      switch (axis) {
        case LevelAxis.x:
        case LevelAxis.z:
          obj.setDim('bottomR', s / 2);
          obj.setDim('topR', s / 2);
        case LevelAxis.y:
          obj.setDim('h', s);
      }
    case 'plane':
      switch (axis) {
        case LevelAxis.x:
          obj.setDim('w', s);
        case LevelAxis.y:
          if (obj.flag('vertical')) obj.setDim('d', s);
        case LevelAxis.z:
          if (!obj.flag('vertical')) obj.setDim('d', s);
      }
    case 'sprite':
      switch (axis) {
        case LevelAxis.x:
          obj.setDim('w', s);
        case LevelAxis.y:
          obj.setDim('h', s);
        case LevelAxis.z:
          break;
      }
  }
  return obj;
}

double _axisOf(vm.Vector3 v, LevelAxis axis) => switch (axis) {
      LevelAxis.x => v.x,
      LevelAxis.y => v.y,
      LevelAxis.z => v.z,
    };

void _shiftAxis(ModelObject obj, LevelAxis axis, double delta) {
  switch (axis) {
    case LevelAxis.x:
      obj.x += delta;
    case LevelAxis.y:
      obj.y += delta;
    case LevelAxis.z:
      obj.z += delta;
  }
}

/// Moves [element] so its anchor lands on the center of [target]'s [faceKey]
/// face in the RENDERED frame ([faceCenterAt]), offset by [gap] along the
/// face's outward normal. The anchor mapping mirrors x (chunkWorld) while
/// the face geometry adds its local offset unmirrored, so the pure model
/// frame would render on the OPPOSITE face whenever the center is offset
/// from the anchor in x (cylinder/cone sides, rotated faces); [faceCenterAt]
/// is the visual position the editor uses for clicks. The gap follows the
/// rendered outward normal, which is the model normal with x negated.
ModelObject snapToFace(
  ModelObject element,
  ModelObject target,
  String faceKey, {
  double gap = 0,
  double billboardYaw = 0,
  vm.Vector3? clickLocal,
}) {
  final normal = faceNormalAt(target, faceKey,
      billboardYaw: billboardYaw, clickLocal: clickLocal);
  final center = faceCenterAt(target, faceKey,
      billboardYaw: billboardYaw, clickLocal: clickLocal);
  if (normal == null || center == null) return element;
  element.x = center.x - normal.x * gap;
  element.y = center.y + normal.y * gap;
  element.z = center.z + normal.z * gap;
  return element;
}

/// Orients [element] so its primary axis is parallel to [target]'s [faceKey]
/// face (the editor's «Параллельно грани»).
ModelObject parallelToFace(
  ModelObject element,
  ModelObject target,
  String faceKey, {
  double billboardYaw = 0,
  vm.Vector3? clickLocal,
}) {
  final normal = faceNormalAt(target, faceKey,
      billboardYaw: billboardYaw, clickLocal: clickLocal);
  if (normal == null) return element;
  final (rx, ry, rz) = parallelToFaceAngles(element, normal);
  element.rotX = rx;
  element.rotY = ry;
  element.rotZ = rz;
  return element;
}

/// Aligns [element]'s AABB center with [target]'s along [axis].
ModelObject alignTo(ModelObject element, ModelObject target, LevelAxis axis) {
  final want = _axisOf(objectCenter(target), axis);
  final have = _axisOf(objectCenter(element), axis);
  _shiftAxis(element, axis, want - have);
  return element;
}

/// Resizes and moves [element] to fill the gap between [a] and [b] along
/// [axis]: it spans from the nearer faces of the two. Does nothing when the
/// objects overlap or the gap is empty.
ModelObject fillGap(
  ModelObject element,
  ModelObject a,
  ModelObject b,
  LevelAxis axis,
) {
  final (aLo, aHi) = objectBounds(a);
  final (bLo, bHi) = objectBounds(b);
  final gapLo = math.min(_axisOf(aHi, axis), _axisOf(bHi, axis));
  final gapHi = math.max(_axisOf(aLo, axis), _axisOf(bLo, axis));
  if (gapHi <= gapLo) return element;
  setSizeAlong(element, axis, gapHi - gapLo);
  final want = (gapLo + gapHi) / 2;
  final have = _axisOf(objectCenter(element), axis);
  _shiftAxis(element, axis, want - have);
  return element;
}

/// Resizes and moves [element] to cover [target]'s footprint (x/z), with its
/// base sitting on [target]'s top face.
ModelObject cover(ModelObject element, ModelObject target) {
  final (lo, hi) = objectBounds(target);
  setSizeAlong(element, LevelAxis.x, hi.x - lo.x);
  setSizeAlong(element, LevelAxis.z, hi.z - lo.z);
  element.x = (lo.x + hi.x) / 2;
  element.z = (lo.z + hi.z) / 2;
  element.y = hi.y;
  return element;
}

/// Shrinks [element]'s footprint by [amount] on every side (clamped at zero).
ModelObject inset(ModelObject element, double amount) {
  final (lo, hi) = objectBounds(element);
  setSizeAlong(element, LevelAxis.x, math.max(hi.x - lo.x - 2 * amount, 0));
  setSizeAlong(element, LevelAxis.z, math.max(hi.z - lo.z - 2 * amount, 0));
  return element;
}

/// Grows [element]'s footprint by [amount] on every side.
ModelObject outset(ModelObject element, double amount) {
  final (lo, hi) = objectBounds(element);
  setSizeAlong(element, LevelAxis.x, hi.x - lo.x + 2 * amount);
  setSizeAlong(element, LevelAxis.z, hi.z - lo.z + 2 * amount);
  return element;
}

/// Stretches [element] along [axis] until its far face reaches [target]'s
/// near face (the direction is chosen by the current centers).
ModelObject stretchTo(
  ModelObject element,
  ModelObject target,
  LevelAxis axis,
) {
  final (eLo, eHi) = objectBounds(element);
  final (tLo, tHi) = objectBounds(target);
  final eCenter = _axisOf((eLo + eHi) / 2, axis);
  final tCenter = _axisOf((tLo + tHi) / 2, axis);
  final double newLo, newHi;
  if (eCenter <= tCenter) {
    newLo = _axisOf(eLo, axis);
    newHi = _axisOf(tLo, axis);
  } else {
    newLo = _axisOf(tHi, axis);
    newHi = _axisOf(eHi, axis);
  }
  if (newHi <= newLo) return element;
  setSizeAlong(element, axis, newHi - newLo);
  final want = (newLo + newHi) / 2;
  final have = _axisOf(objectCenter(element), axis);
  _shiftAxis(element, axis, want - have);
  return element;
}
