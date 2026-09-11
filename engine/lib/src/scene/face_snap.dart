import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import 'model_renderer.dart';

/// Face-snap math for the «Перенести к грани» / «Параллельно грани» tools and
/// the level layer's `BuildOps`: a face's model-local outward normal and
/// center (rotation-aware), and the Euler angles that align an object with a
/// face. All pure — unit-tested without a GPU.
///
/// Conventions (matching the renderer):
/// - model-local coordinates; the object's rotation Rz·Rx·Ry applies around
///   its anchor (obj.x, obj.y, obj.z);
/// - «листовые» объекты (plane, sprite) are aligned with their local +Z
///   toward the face normal (their surface becomes parallel to the face);
/// - «объёмные» объекты (cuboid, trapezoid, cylinder) lie ON the face:
///   their local +Y aligns with the face normal.

/// Object-local → model-local corner mapping (the object's rotation applies
/// around the anchor; sprite billboards use the yaw instead of rotX/rotZ).
/// [local] is the corner's offset from the object origin (the anchor).
vm.Vector3 _cornerChunkLocal(
  ModelObject obj,
  vm.Vector3 local,
  double billboardYaw,
) {
  final rot = obj.kind == 'sprite'
      ? vm.Matrix4.diagonal3Values(-1, 1, 1) * vm.Matrix4.rotationY(billboardYaw)
      : objectRotation(obj);
  final r = rot.transform3(local);
  return vm.Vector3(obj.x + r.x, obj.y + r.y, obj.z + r.z);
}

/// The four model-local corners of a flat face (cuboid/trapezoid/plane/
/// sprite) or null for the cylinder side (curved — handled analytically).
/// Corners keep the faceCorners winding (BL, BR, TR, TL).
List<vm.Vector3>? flatFaceCorners(
  ModelObject obj,
  String faceKey,
  double billboardYaw,
) {
  if (obj.kind == 'cylinder') return null;
  final corners = faceCorners(obj, faceKey);
  if (corners.isEmpty) return null;
  return [for (final c in corners) _cornerChunkLocal(obj, c, billboardYaw)];
}

/// The outward unit normal of the face in model-local space (null when the
/// face can't be resolved). [clickLocal] is the model-local click point —
/// required for the cylinder side and the curved 'round' zones of a rounded
/// cuboid, whose normal depends on the click angle.
vm.Vector3? faceNormalAt(
  ModelObject obj,
  String faceKey, {
  vm.Vector3? clickLocal,
  required double billboardYaw,
}) {
  final anchor = vm.Vector3(obj.x, obj.y, obj.z);
  if (obj.kind == 'cylinder') {
    final bottomR = obj.dim('bottomR', 0.25);
    final topR = obj.dim('topR', bottomR);
    final h = math.max(obj.dim('h', 1), 1e-9);
    final rot = objectRotation(obj);
    // A rotation matrix's inverse is its transpose (exact).
    final inv = rot.transposed();
    if (faceKey == 'side') {
      final click = clickLocal;
      if (click == null) return null;
      // The click arrives in the RENDERED frame (mirrored x — the renderer
      // adds local offsets directly to the negated anchor, see the AGENTS.md
      // camera quirk), so the object-frame offset negates the x component —
      // otherwise the angle θ would point at the mirrored (opposite) side.
      final local = inv.transform3(
        vm.Vector3(
          -(click.x - anchor.x),
          click.y - anchor.y,
          click.z - anchor.z,
        ),
      );
      final theta = math.atan2(local.z, local.x);
      // Side surface tangent cross: (−cosθ, (topR−bottomR)/h, −sinθ) —
      // points inward; the anchor test flips it outward (the dot with the
      // surface offset is always negative, so the flip is exact).
      var n = vm.Vector3(-math.cos(theta), (topR - bottomR) / h, -math.sin(theta));
      if (n.dot(local) < 0) n = n * -1;
      return rot.transform3(n).normalized();
    }
    // Caps: the disc normal rotates with the object.
    return rot
        .transform3(vm.Vector3(0, faceKey == '+y' ? 1 : -1, 0))
        .normalized();
  }
  if (isRoundedCuboid(obj) && faceKey == roundFaceKey) {
    final click = clickLocal;
    if (click == null) return null;
    final local = roundBoxLocalNormal(obj, click);
    if (local == null) return null;
    return objectRotation(obj).transform3(local).normalized();
  }
  final corners = flatFaceCorners(obj, faceKey, billboardYaw);
  if (corners == null) return null;
  final center = _quadCenter(corners);
  var n = (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized();
  if (obj.kind == 'sprite') {
    // The billboard renders through a −X mirror (diag(−1,1,1)), which flips
    // the quad's winding: the cross above is the BACK side. The outward
    // normal is the VISIBLE side, which faces the camera (toward the
    // player) — its negative.
    n = n * -1;
  }
  // Orient outward: away from the object anchor (robust for the trapezoid
  // slopes, whose quads are wound inward). Faces through the anchor keep
  // the winding sign.
  if (n.dot(center - anchor) < 0) return n * -1;
  return n;
}

/// The model-local point the object's anchor moves to when it snaps to the
/// face: the quad/disc center for flat faces and caps, and for the cylinder
/// side the surface point at the click angle and MID-HEIGHT, radius
/// (bottomR+topR)/2. The pure model frame — the editor mirrors it through
/// [faceCenterAt].
vm.Vector3? faceCenterLocal(
  ModelObject obj,
  String faceKey, {
  vm.Vector3? clickLocal,
  required double billboardYaw,
}) {
  final anchor = vm.Vector3(obj.x, obj.y, obj.z);
  vm.Vector3 center;
  if (obj.kind == 'cylinder') {
    final bottomR = obj.dim('bottomR', 0.25);
    final topR = obj.dim('topR', bottomR);
    final h = math.max(obj.dim('h', 1), 1e-9);
    final rot = objectRotation(obj);
    final inv = rot.transposed();
    if (faceKey == 'side') {
      final click = clickLocal;
      if (click == null) return null;
      // Same object-frame angle as the normal (mirrored x — see above).
      final local = inv.transform3(
        vm.Vector3(
          -(click.x - anchor.x),
          click.y - anchor.y,
          click.z - anchor.z,
        ),
      );
      final theta = math.atan2(local.z, local.x);
      final rm = (bottomR + topR) / 2;
      final mid =
          vm.Vector3(rm * math.cos(theta), h / 2, rm * math.sin(theta));
      center = anchor + rot.transform3(mid);
    } else {
      // Caps: the disc center rotates with the object.
      center =
          anchor + rot.transform3(vm.Vector3(0, faceKey == '+y' ? h : 0, 0));
    }
  } else if (isRoundedCuboid(obj) && faceKey == roundFaceKey) {
    // Curved zones: the anchor lands on the clicked surface point itself.
    final click = clickLocal;
    if (click == null) return null;
    center = click;
  } else {
    final corners = flatFaceCorners(obj, faceKey, billboardYaw);
    if (corners == null) return null;
    center = _quadCenter(corners);
  }
  return center;
}

/// The model-local point the object's anchor moves to — the face center in
/// the RENDERED (visual) frame: the quad/disc center for flat faces and
/// caps, and for the cylinder side the surface point at the click angle and
/// MID-HEIGHT (the painting outline bounds the side by its two rings — its
/// center is the middle ring), radius (bottomR+topR)/2.
///
/// The editor renders model-local geometry mirrored in X through the anchor
/// (`chunkWorld(anchor) + local` — the cellWorld quirk, see the AGENTS.md
/// camera quirk): the VISUAL position of a face is `anchor − offset`, while
/// the model's face is at `anchor + offset`. The returned center is the
/// VISUAL one (`x' = 2·obj.x − x`), so an object placed there lands on the
/// face the user actually clicked — otherwise it would render on the
/// OPPOSITE face («прикрепился к противоположной грани»).
vm.Vector3? faceCenterAt(
  ModelObject obj,
  String faceKey, {
  vm.Vector3? clickLocal,
  required double billboardYaw,
}) {
  final center =
      faceCenterLocal(obj, faceKey, clickLocal: clickLocal, billboardYaw: billboardYaw);
  if (center == null) return null;
  // Model frame → rendered (visual) frame: mirror X through the anchor.
  return vm.Vector3(2 * obj.x - center.x, center.y, center.z);
}

/// The object-frame outward surface normal of a rounded cuboid at the
/// model-space point [click] (on its surface), or null when [obj] is not a
/// rounded cuboid. Analytic: the normal of the fully-rounded box at a
/// surface point is the direction from the INNER box (inset by r) toward
/// the point — exact on the planar faces, fillet rows and corner octants.
vm.Vector3? roundBoxLocalNormal(ModelObject obj, vm.Vector3 click) {
  final w = obj.dim('w', 1);
  final h = obj.dim('h', 1);
  final d = obj.dim('d', 1);
  final r = cuboidRoundRadiusOf(obj);
  if (r <= 0) return null;
  final inv = objectRotation(obj).transposed();
  final p = inv.transform3(click - vm.Vector3(obj.x, obj.y, obj.z));
  double clampTo(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
  final q = vm.Vector3(
    clampTo(p.x, -w / 2 + r, w / 2 - r),
    clampTo(p.y, r, h - r),
    clampTo(p.z, -d / 2 + r, d / 2 - r),
  );
  final diff = p - q;
  if (diff.length < 1e-9) return null;
  return diff.normalized();
}

vm.Vector3 _quadCenter(List<vm.Vector3> c) =>
    (c[0] + c[1] + c[2] + c[3]) / 4;

/// Euler angles (degrees, Rz·Rx·Ry — the renderer's order) that orient the
/// object so its primary axis is parallel to [normal]:
/// - plane/sprite: local +Z → the face normal, local +Y → the face's «up»
///   (world +Y projected onto the face plane);
/// - solids: local +Y → the face normal, local +Z → the face's «up».
///
/// Degenerate cases: a horizontal face (normal ≈ ±Y) leaves the yaw (rotY)
/// untouched; a gimbal (primary axis ending along world ±Z) tilts about X
/// and keeps rotY.
(double, double, double) parallelToFaceAngles(ModelObject obj, vm.Vector3 normal) {
  final n = normal.normalized();
  final sheet = obj.kind == 'plane' || obj.kind == 'sprite';
  // Face «up»: the projection of world +Y onto the face plane.
  final u = vm.Vector3(0, 1, 0) - n * vm.Vector3(0, 1, 0).dot(n);
  if (u.length < 1e-6) {
    // Horizontal face: the primary axis is already aligned; the spin about
    // it is free — keep the current yaw.
    final down = n.y < 0;
    if (sheet) {
      // +Z → +Y needs rotX = −90; → −Y needs rotX = +90.
      return (down ? 90.0 : -90.0, obj.rotY, 0.0);
    }
    // +Y → +Y needs rotX = 0; → −Y needs rotX = 180.
    return (down ? 180.0 : 0.0, obj.rotY, 0.0);
  }
  final up = u.normalized();
  // Right-handed target basis: X' = Y'×Z'.
  final (xp, yp, zp) = sheet
      ? (up.cross(n), up, n)
      : (n.cross(up), n, up);
  final rx = math.asin(yp.z.clamp(-1.0, 1.0));
  if ((rx - math.pi / 2).abs() < 1e-6 || (rx + math.pi / 2).abs() < 1e-6) {
    // Gimbal: the primary axis ends up along world ±Z — tilt about X and
    // keep the yaw.
    return (rx * 180 / math.pi, obj.rotY, 0.0);
  }
  final rz = math.atan2(-yp.x, yp.y);
  final ry = math.atan2(-xp.z, zp.z);
  return (rx * 180 / math.pi, ry * 180 / math.pi, rz * 180 / math.pi);
}
