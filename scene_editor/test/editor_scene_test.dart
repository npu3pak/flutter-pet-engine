import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_engine/pet_engine.dart';
import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// True when the point set contains (x, y, z) within [eps] per component —
/// matrix transforms carry ~1e-17 floating-point residue, so exact record
/// equality is fragile.
bool _hasPoint(
  Iterable<(double, double, double)> pts,
  double x,
  double y,
  double z, {
  double eps = 1e-6,
}) =>
    pts.any((p) =>
        (p.$1 - x).abs() < eps &&
        (p.$2 - y).abs() < eps &&
        (p.$3 - z).abs() < eps);

ModelData _model({int w = 4, int l = 4, int h = 3}) =>
    ModelData(id: 'm', name: 'M', size: ModelSize(w: w, l: l, h: h));

ModelObject _cuboid({
  String id = 'obj_1',
  double x = 1,
  double y = 0,
  double z = 2,
  double w = 2,
  double h = 1,
  double d = 2,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      dims: {'w': w, 'h': h, 'd': d},
    );

/// A headless [SceneViewport] backend: the viewport logic runs (size,
/// tick, input), no GPU is touched.
class _FakeBackend extends SceneViewportBackend {
  @override
  Widget build(BuildContext context, SceneViewportContext viewport) =>
      const SizedBox.expand();

  @override
  Future<Uint8List> capture(
    SceneViewportContext viewport, {
    double? pixelRatio,
  }) async =>
      Uint8List(0);
}

/// Mounts a headless viewport of [size] so the controller learns its
/// viewport geometry (`screenPointToRay` / `worldToScreen`).
Future<void> _pumpViewport(
  WidgetTester tester,
  SceneController controller, {
  Size size = const Size(200, 200),
}) async {
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 1),
      child: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: SceneViewport(
            controller: controller,
            backend: _FakeBackend(),
            autoTick: false,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('axisDragDelta', () {
    test('signed delta follows the mouse direction', () {
      // Plane through the origin, normal = camera forward (looking +Z from
      // the −Z side, straight down the Z axis).
      final planePoint = vm.Vector3.zero();
      final planeNormal = vm.Vector3(0, 0, 1);
      final axisDir = vm.Vector3(-1, 0, 0); // the gizmo X handle (world −X)

      // Ray from the left side toward the right → hit on the +X side.
      final leftRay = vm.Ray.originDirection(
        vm.Vector3(-1, 0, -5),
        vm.Vector3(1, 0, 1),
      );
      final leftD =
          axisDragDelta(leftRay, planePoint, planeNormal, axisDir);
      // Ray from the right side → hit on the −X side.
      final rightRay = vm.Ray.originDirection(
        vm.Vector3(1, 0, -5),
        vm.Vector3(-1, 0, 1),
      );
      final rightD =
          axisDragDelta(rightRay, planePoint, planeNormal, axisDir);

      expect(leftD, isNotNull);
      expect(rightD, isNotNull);
      // The two rays hit the plane on opposite sides of the anchor.
      expect(leftD! * rightD!, lessThan(0));
    });

    test('movement along the axis direction is proportional to ray offset', () {
      final planePoint = vm.Vector3(0, 0, 0);
      final planeNormal = vm.Vector3(0, 0, 1);
      final axisDir = vm.Vector3(0, 1, 0);

      // A ray hitting the plane 1 unit above the anchor (origin (0,−1,−1),
      // direction (0,2,1) crosses z=0 at t=1 → hit (0,1,0)).
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, -1, -1),
        vm.Vector3(0, 2, 1),
      );
      final d =
          axisDragDelta(ray, planePoint, planeNormal, axisDir);
      expect(d, closeTo(1.0, 1e-6));
    });

    test('ray parallel to the plane returns null', () {
      // Direction perpendicular to the plane normal → never intersects.
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, -5),
        vm.Vector3(1, 0, 0),
      );
      final d = axisDragDelta(
        ray,
        vm.Vector3.zero(),
        vm.Vector3(0, 0, 1),
        vm.Vector3(1, 0, 0),
      );
      expect(d, isNull);
    });

    test('x axis maps to model +x (world −x)', () {
      final planePoint = vm.Vector3.zero();
      final planeNormal = vm.Vector3(0, 0, 1);
      // Hit on the world +x side of the anchor (crosses z=0 at t=1 → (1,0,0)).
      final ray = vm.Ray.originDirection(
        vm.Vector3(2, 0, -1),
        vm.Vector3(-1, 0, 1),
      );
      final d = axisDragDelta(
        ray,
        planePoint,
        planeNormal,
        vm.Vector3(-1, 0, 0), // gizmo X handle direction
      );
      // Object model x increases when moving toward world −x, so a hit on
      // the +x side yields a NEGATIVE delta (moves −model x).
      expect(d, isNotNull);
      expect(d, lessThan(0));
    });
  });

  group('rotation drag math', () {
    test('signedAngleAroundAxis is right-handed about the axis', () {
      // +Z → +X around +Y is a positive (right-handed) rotation.
      final y = signedAngleAroundAxis(
        vm.Vector3(0, 0, 1),
        vm.Vector3(1, 0, 0),
        vm.Vector3(0, 1, 0),
      );
      expect(y, closeTo(math.pi / 2, 1e-6));
      // ...and the reverse sweep is negative.
      expect(
        signedAngleAroundAxis(
          vm.Vector3(1, 0, 0),
          vm.Vector3(0, 0, 1),
          vm.Vector3(0, 1, 0),
        ),
        closeTo(-math.pi / 2, 1e-6),
      );
      // +Y → +Z around +X: positive about +X.
      expect(
        signedAngleAroundAxis(
          vm.Vector3(0, 1, 0),
          vm.Vector3(0, 0, 1),
          vm.Vector3(1, 0, 0),
        ),
        closeTo(math.pi / 2, 1e-6),
      );
      // +Y → +X around +Z: NEGATIVE about +Z (right-handed: +X → +Y is +).
      expect(
        signedAngleAroundAxis(
          vm.Vector3(0, 1, 0),
          vm.Vector3(1, 0, 0),
          vm.Vector3(0, 0, 1),
        ),
        closeTo(-math.pi / 2, 1e-6),
      );
    });

    test('rotationDragDelta sweeps the ring like the mouse', () {
      // Y ring: plane through the origin ⊥ +Y. Grab at +Z, drag to +X.
      final center = vm.Vector3(0, 1, 0);
      final axis = vm.Vector3(0, 1, 0);
      final start = center + vm.Vector3(0, 0, 1);
      // Ray crossing the plane (y=1) at t=1 → hit (1, 1, 0).
      final ray = vm.Ray.originDirection(
        vm.Vector3(2, 2, 0),
        vm.Vector3(-1, -1, 0),
      );
      final delta = rotationDragDelta(ray, center, axis, start);
      // +Z → +X around +Y: +90°.
      expect(delta, closeTo(math.pi / 2, 1e-6));
      // The same sweep in the opposite direction is negative.
      final back = rotationDragDelta(
        vm.Ray.originDirection(vm.Vector3(-2, 2, 0), vm.Vector3(1, -1, 0)),
        center,
        axis,
        start,
      );
      expect(back, closeTo(-math.pi / 2, 1e-6));
    });

    test('rotationDragDelta returns null for a parallel ray', () {
      // Ray along the axis never crosses the ring plane.
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, -5, 0),
        vm.Vector3(0, 1, 0),
      );
      final delta = rotationDragDelta(
        ray,
        vm.Vector3.zero(),
        vm.Vector3(0, 1, 0),
        vm.Vector3(1, 0, 0),
      );
      expect(delta, isNull);
    });

    test('the engine gizmo axes are world X/Y/Z', () {
      expect(gizmoAxisDirection(GizmoAxis.x), vm.Vector3(1, 0, 0));
      expect(gizmoAxisDirection(GizmoAxis.y), vm.Vector3(0, 1, 0));
      expect(gizmoAxisDirection(GizmoAxis.z), vm.Vector3(0, 0, 1));
    });
  });

  group('gridLinePoints', () {
    test('grid is centered on the model origin', () {
      final pts = gridLinePoints(3, 3);
      final xs = pts.map((p) => p.$1).toSet();
      final zs = pts.map((p) => p.$3).toSet();
      expect(xs, {-1.5, -0.5, 0.5, 1.5});
      expect(zs, {-1.5, -0.5, 0.5, 1.5});
      // Lines run across the full extent.
      expect(pts, contains((-1.5, 0.0, -1.5)));
      expect(pts, contains((1.5, 0.0, 1.5)));
    });

    test('even sizes put the grid on integers', () {
      final pts = gridLinePoints(4, 2);
      final xs = pts.map((p) => p.$1).toSet();
      expect(xs, {-2.0, -1.0, 0.0, 1.0, 2.0});
    });
  });

  group('objectEdgeSegments', () {
    test('cuboid has 12 edges with correct world corners', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 1,
        y: 0,
        z: 2,
        dims: {'w': 2, 'h': 1, 'd': 4},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      expect(segs, hasLength(12));
      // Bottom-front-left corner: model (0, 0, 0) -> world (−2, 0, 0)
      // (anchor world x = −(1−0) = −1, offset −1).
      expect(segs[0].$1, (-2.0, 0.0, 0.0));
      // Top-back-right corner of the bottom edge set: world x negated.
      final xs = segs.expand((e) => [e.$1.$1, e.$2.$1]).toSet();
      expect(xs, {-2.0, 0.0});
      final ys = segs.expand((e) => [e.$1.$2, e.$2.$2]).toSet();
      expect(ys, {0.0, 1.0});
    });

    test('cuboid rotY=90 rotates the edges', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        rotY: 90,
        dims: {'w': 2, 'h': 1, 'd': 4},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      final pts = segs.expand((e) => [e.$1, e.$2]).toSet();
      // Chunk corner (1,0,2): local offset (1,2) rotated 90° in the world →
      // (2,0,−1) (anchor at origin).
      expect(pts, contains((2.0, 0.0, -1.0)));
      // The unrotated world position of that corner is gone.
      expect(pts, isNot(contains((1.0, 0.0, 2.0))));
    });

    test('cuboid rotZ=90 lies on its side (top → −X)', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        rotZ: 90,
        dims: {'w': 1, 'h': 1, 'd': 1},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      final pts = segs.expand((e) => [e.$1, e.$2]).toList();
      // Corner (0.5, 1, 0.5): Rz(90) → x' = −y = −1, y' = x = 0.5.
      expect(_hasPoint(pts, -1, 0.5, 0.5), isTrue);
      // Corner (0.5, 0, 0.5): Rz(90) → (0, 0.5, 0.5) — the base stands up.
      expect(_hasPoint(pts, 0, 0.5, 0.5), isTrue);
    });

    test('cuboid rotX=90 tips toward +Z', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        rotX: 90,
        dims: {'w': 1, 'h': 1, 'd': 1},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      final pts = segs.expand((e) => [e.$1, e.$2]).toList();
      // Corner (0.5, 1, 0.5): Rx(90) → y' = −z = −0.5, z' = y = 1.
      expect(_hasPoint(pts, 0.5, -0.5, 1), isTrue);
      // The rotated object no longer reaches y = 1 anywhere.
      expect(
        segs.expand((e) => [e.$1.$2, e.$2.$2]),
        isNot(contains(1.0)),
      );
    });

    test('rotX/rotZ compose with rotY (Rz·Rx·Ry)', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        rotX: 90,
        rotZ: 90,
        dims: {'w': 1, 'h': 1, 'd': 1},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      final pts = segs.expand((e) => [e.$1, e.$2]).toList();
      // Top corner (0.5, 1, 0.5): Rx(90) → (0.5, −0.5, 1); Rz(90) →
      // x' = −y = 0.5, y' = x = 0.5 → (0.5, 0.5, 1).
      expect(_hasPoint(pts, 0.5, 0.5, 1), isTrue);
      // Base corner (0.5, 0, 0.5): Rx(90) → (0.5, −0.5, 0); Rz(90) →
      // (0.5, 0.5, 0) — the base stays in the y = 0.5 plane.
      expect(_hasPoint(pts, 0.5, 0.5, 0), isTrue);
    });

    test('trapezoid has 12 edges incl. sloped verticals', () {
      final obj = ModelObject(
        id: 't',
        name: 't',
        kind: 'trapezoid',
        x: 2.5,
        y: 2,
        z: 1.5,
        dims: {'bottomW': 4, 'bottomD': 4, 'topW': 1, 'topD': 1, 'h': 1},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      expect(segs, hasLength(12));
      // Top corners: y = 2 + 1 = 3.
      final topY = segs.expand((e) => [e.$1.$2, e.$2.$2]).where((y) => y > 2.5);
      expect(topY.toSet(), {3.0});
    });

    test('cylinder has two rings plus two verticals', () {
      final obj = ModelObject(
        id: 'y',
        name: 'y',
        kind: 'cylinder',
        x: 0,
        y: 0,
        z: 0,
        dims: {'bottomR': 1, 'topR': 0.5, 'h': 2},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: 0);
      // 16 + 16 ring segments + 2 verticals.
      expect(segs, hasLength(34));
      // Verticals connect bottom y=0 to top y=2.
      final verticals = segs.where((e) =>
          e.$1.$2 == 0 && e.$2.$2 == 2 || e.$1.$2 == 2 && e.$2.$2 == 0);
      expect(verticals, hasLength(2));
    });

    test('sprite has 4 edges', () {
      final obj = ModelObject(
        id: 's',
        name: 's',
        kind: 'sprite',
        x: 0,
        y: 0,
        z: 0,
        dims: {'w': 1, 'h': 2},
      );
      final segs = objectEdgeSegments(obj, billboardYaw: math.pi);
      expect(segs, hasLength(4));
    });

    test('sprite outline always follows the billboard yaw (no flag needed)', () {
      final obj = ModelObject(
        id: 's',
        name: 's',
        kind: 'sprite',
        x: 0,
        y: 0,
        z: 0,
        dims: {'w': 1, 'h': 2},
      );
      // rotationY(π/2) turns the +Z quad edge-on: every outline point gets
      // world x = 0.
      final segs = objectEdgeSegments(obj, billboardYaw: math.pi / 2);
      for (final (a, b) in segs) {
        expect(a.$1, closeTo(0, 1e-9));
        expect(b.$1, closeTo(0, 1e-9));
      }
    });
  });

  group('chunkWorld (bottom-left cell center origin)', () {
    test('origin is the bottom-left cell center, world footprint centered', () {
      // Odd 5×5: (w−1)/2 = 2 — the corner cell center sits at world (2, −2).
      expect(chunkWorld(0, 0, 5, 5), vm.Vector3(2, 0, -2));
      // Even 4×4: (w−1)/2 = 1.5.
      expect(chunkWorld(0, 0, 4, 4), vm.Vector3(1.5, 0, -1.5));
      // The model center maps to world (0,0,0) for any size.
      expect(chunkWorld(2, 2, 5, 5), vm.Vector3.zero());
      expect(chunkWorld(1.5, 1.5, 4, 4), vm.Vector3.zero());
      // Chunk edges: x ∈ [−0.5, w−0.5] → world x ∈ [−w/2, w/2] (same
      // footprint as the old center-origin system).
      expect(chunkWorld(-0.5, -0.5, 5, 5).x, closeTo(2.5, 1e-9));
      expect(chunkWorld(4.5, 4.5, 5, 5).x, closeTo(-2.5, 1e-9));
      expect(chunkWorld(3.5, 3.5, 4, 4).x, closeTo(-2.0, 1e-9));
    });
  });

  group('objectEdgeSegments model origin', () {
    test('outline shifts with the model origin (odd 5×5)', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 0,
        y: 0,
        z: 0,
        dims: {'w': 1, 'h': 1, 'd': 1},
      );
      final segs = objectEdgeSegments(
        obj,
        billboardYaw: 0,
        originX: 2,
        originZ: 2,
      );
      // The outline corners must land exactly where chunkWorld puts the
      // cell-center-anchored cuboid in a 5×5 model.
      final corners = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      // Half of the cube spans the first cell: corners at model x ∈ {−0.5,
      // 0.5}, z ∈ {−0.5, 0.5} → world x = −(x − 2), z = z − 2.
      for (final (lx, lz) in [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]) {
        final wx = -(lx - 2);
        final wz = lz - 2;
        expect(corners, contains((wx, 0, wz)));
        expect(corners, contains((wx, 1, wz)));
      }
      // Sanity: chunkWorld agrees for the bottom-left cell center.
      final c = chunkWorld(0, 0, 5, 5);
      expect(c.x, closeTo(2, 1e-9));
      expect(c.z, closeTo(-2, 1e-9));
    });

    test('outline matches chunkWorld on an even 4×4 model', () {
      final obj = ModelObject(
        id: 'c',
        name: 'c',
        kind: 'cuboid',
        x: 1,
        y: 0,
        z: 1,
        dims: {'w': 1, 'h': 1, 'd': 1},
      );
      final segs = objectEdgeSegments(
        obj,
        billboardYaw: 0,
        originX: 1.5,
        originZ: 1.5,
      );
      final corners = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      // x=1 → world −(1−1.5) = 0.5; corners at ±0.5 around it: x ∈ {0, 1},
      // z ∈ {−1, 0} (chunkWorld z = lz − 1.5).
      expect(corners, contains((1.0, 0, -1.0)));
      expect(corners, contains((0.0, 0, 0.0)));
      expect(corners, contains((0.0, 1, -1.0)));
      expect(corners, contains((1.0, 1, 0.0)));
    });
  });

  group('billboard reorientation', () {
    test('screenParallelYaw turns the quad toward the camera', () {
      // Camera looking +X → the +Z quad rotates 90° to face it.
      expect(screenParallelYaw(1, 0), closeTo(math.pi / 2, 1e-9));
      // Default pose (looking −Z) → no rotation.
      expect(screenParallelYaw(0, -1), closeTo(0, 1e-9));
      // Looking −X → 270°.
      expect(screenParallelYaw(-1, 0), closeTo(3 * math.pi / 2, 1e-9));
      // Looking +Z → 180°.
      expect(screenParallelYaw(0, 1), closeTo(math.pi, 1e-9));
    });

    test('the billboard transform faces the camera from every side', () {
      // The game-convention transform (mirror · rotationY(yaw)) applied to
      // the quad's +Z normal must point TOWARD the camera (−f), so the
      // sprite front never culls away, and the u axis tracks the camera
      // right (texture never mirrors).
      for (final (fx, fz) in [
        (1.0, 0.0),
        (0.0, -1.0),
        (-1.0, 0.0),
        (0.0, 1.0),
        (0.70710678, 0.70710678),
      ]) {
        final yaw = screenParallelYaw(fx, fz);
        final t = vm.Matrix4.diagonal3Values(-1, 1, 1) *
            vm.Matrix4.rotationY(yaw);
        final n = t.transform3(vm.Vector3(0, 0, 1)).normalized();
        expect(n.x, closeTo(-fx, 1e-6), reason: '($fx, $fz)');
        expect(n.z, closeTo(-fz, 1e-6), reason: '($fx, $fz)');
        // u axis == camera's screen-right: for forward f = (sin θ, 0, cos θ),
        // screen-right = (cos θ, 0, −sin θ) = (fz, 0, −fx).
        final u = t.transform3(vm.Vector3(1, 0, 0)).normalized();
        expect(u.x, closeTo(fz, 1e-6), reason: 'u ($fx, $fz)');
        expect(u.z, closeTo(-fx, 1e-6), reason: 'u ($fx, $fz)');
      }
    });

    test('the sprite quad winding faces the camera (flip: true base)', () {
      // The sprite geometry is wound with flip: true (like the cuboid/plane
      // 'outer' faces and the game's PlaneGeometry billboards). After the
      // billboard mirror the triangle cross points TOWARD the camera, so the
      // blend material's back-face culling never hides the textured quad.
      // An unflipped base would end up pointing AWAY — the regression where
      // the sprite stayed gray (its textured material was culled).
      final sprite = ModelObject(
        id: 's',
        name: 's',
        kind: 'sprite',
        dims: {'w': 1, 'h': 2},
      );
      for (final (fx, fz) in [
        (1.0, 0.0),
        (0.0, -1.0),
        (-1.0, 0.0),
        (0.0, 1.0),
        (0.70710678, 0.70710678),
      ]) {
        final yaw = screenParallelYaw(fx, fz);
        final t = vm.Matrix4.diagonal3Values(-1, 1, 1) *
            vm.Matrix4.rotationY(yaw);
        final c = faceCorners(sprite, '*');
        // _quadPart(flip: true) → triangles (0,2,1) and (0,3,2); the first
        // triangle's cross is the quad's facing.
        final w0 = t.transform3(c[0]);
        final w1 = t.transform3(c[2]);
        final w2 = t.transform3(c[1]);
        final n = (w1 - w0).cross(w2 - w0).normalized();
        expect(n.x, closeTo(-fx, 1e-6), reason: '($fx, $fz)');
        expect(n.z, closeTo(-fz, 1e-6), reason: '($fx, $fz)');
        expect(n.y.abs(), lessThan(1e-6), reason: 'y ($fx, $fz)');
      }
    });
  });

  group('faceEdgeSegments', () {
    test('cuboid face is a 4-edge rectangle at the right world spot', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'cuboid',
            x: 1,
            y: 0,
            z: 1,
            dims: {'w': 2, 'h': 1, 'd': 4},
          ),
        ],
      );
      final segs = faceEdgeSegments(model, 'obj_1:+x', 2, 2, billboardYaw: 0);
      expect(segs, hasLength(4));
      final pts = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      // '+x' face corners are object-local (x = w/2 = 1, z = ±d/2 = ±2);
      // world = anchor (−(1−2), −1) + offset: x = 1 + 1 = 2, z = −1 ± 2.
      expect(pts, contains((2.0, 0, 1.0)));
      expect(pts, contains((2.0, 0, -3.0)));
      expect(pts, contains((2.0, 1, 1.0)));
      expect(pts, contains((2.0, 1, -3.0)));
    });

    test('cylinder side gets two rings, caps one ring each', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'cylinder',
            x: 0,
            y: 0,
            z: 0,
            dims: {'bottomR': 0.5, 'topR': 0.5, 'h': 2},
          ),
        ],
      );
      // Side: bottom + top rings (16 segments each).
      expect(faceEdgeSegments(model, 'obj_1:side', 0, 0, billboardYaw: 0),
          hasLength(32));
      expect(faceEdgeSegments(model, 'obj_1:+y', 0, 0, billboardYaw: 0),
          hasLength(16));
      expect(faceEdgeSegments(model, 'obj_1:-y', 0, 0, billboardYaw: 0),
          hasLength(16));
      // Side ring y-levels: 0 (bottom) and 2 (top).
      final side = faceEdgeSegments(model, 'obj_1:side', 0, 0, billboardYaw: 0);
      final ys = {for (final (a, b) in side) ...[a.$2, b.$2]};
      expect(ys, {0.0, 2.0});
    });

    test('offsets keep the outline at the object cell, not at 0', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'trapezoid',
            x: 3,
            y: 0,
            z: 2,
            dims: {'bottomW': 2, 'bottomD': 2, 'topW': 1, 'topD': 1, 'h': 1},
          ),
          ModelObject(
            id: 'obj_2',
            name: 's',
            kind: 'sprite',
            x: 1,
            y: 0,
            z: 1,
            dims: {'w': 1, 'h': 2},
          ),
        ],
      );
      final t = faceEdgeSegments(model, 'obj_1:+x', 0, 0, billboardYaw: 0);
      final tPts = <(double, double, double)>{
        for (final (a, b) in t) ...[a, b],
      };
      // '+x' sloped face: world anchor x = −(3−0) = −3 + offset 1 → −2;
      // bottom z ∈ 2±1, top x = −3 + 0.5, z ∈ 2±0.5.
      expect(tPts, contains((-2.0, 0, 1.0)));
      expect(tPts, contains((-2.0, 0, 3.0)));
      expect(tPts, contains((-2.5, 1, 1.5)));
      expect(tPts, contains((-2.5, 1, 2.5)));

      // Sprite quad at (1, 0, 1), w=1 h=2: corners world x = −(1±0.5),
      // z = 1 (the quad is in the XY plane).
      final sp = faceEdgeSegments(model, 'obj_2:*', 0, 0, billboardYaw: 0);
      final spPts = <(double, double, double)>{
        for (final (a, b) in sp) ...[a, b],
      };
      expect(spPts, contains((-0.5, 0, 1.0)));
      expect(spPts, contains((-1.5, 0, 1.0)));
      expect(spPts, contains((-0.5, 2, 1.0)));
      expect(spPts, contains((-1.5, 2, 1.0)));
    });

    test('rotated +z face outline is NOT mirrored (rotY=90)', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'cuboid',
            x: 0,
            y: 0,
            z: 0,
            rotY: 90,
            dims: {'w': 1, 'h': 1, 'd': 1},
          ),
        ],
      );
      // rotY=90: the +z face (local z = +0.5) lands at model x = +0.5.
      // A mirrored outline would put it at x = −0.5.
      final segs = faceEdgeSegments(model, 'obj_1:+z', 0, 0, billboardYaw: 0);
      final pts = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      for (final p in pts) {
        expect(p.$1, closeTo(0.5, 1e-9), reason: 'mirrored outline: $p');
      }
    });

    test('sprite outline mirrors like the billboard render', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 's',
            kind: 'sprite',
            x: 0,
            y: 0,
            z: 0,
            dims: {'w': 1, 'h': 2},
          ),
        ],
      );
      // The sprite renders as anchor · diag(−1,1,1) · rotY(yaw): the corner
      // (0.5, 0, 0) at yaw = π/4 lands at (−0.354, −0.354), not (+0.354, −0.354).
      final cs = math.cos(math.pi / 4);
      final segs =
          faceEdgeSegments(model, 'obj_1:*', 0, 0, billboardYaw: math.pi / 4);
      bool has(double x, double y, double z) => segs.any((e) =>
          (e.$1.$1 - x).abs() < 1e-6 &&
          (e.$1.$2 - y).abs() < 1e-6 &&
          (e.$1.$3 - z).abs() < 1e-6);
      // The render's diag(−1,1,1)·rotY(yaw): the corner (0.5, 0, 0) lands at
      // (−0.5·cs, −0.5·sn), the corner (−0.5, 0, 0) at (+0.5·cs, +0.5·sn).
      expect(has(-0.5 * cs, 0, -0.5 * cs), isTrue);
      expect(has(0.5 * cs, 0, 0.5 * cs), isTrue);
      expect(has(-0.5 * cs, 2, -0.5 * cs), isTrue);
      expect(has(0.5 * cs, 2, 0.5 * cs), isTrue);
      // The un-mirrored corner (0.5·cs, −0.5·sn) must be absent.
      expect(has(0.5 * cs, 0, -0.5 * cs), isFalse);
    });

    test('outline lifts with the object height', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'cuboid',
            x: 0,
            y: 3,
            z: 0,
            dims: {'w': 1, 'h': 2, 'd': 1},
          ),
        ],
      );
      final segs = faceEdgeSegments(model, 'obj_1:+x', 0, 0, billboardYaw: 0);
      final ys = {for (final (a, b) in segs) ...[a.$2, b.$2]};
      // The face spans the object's own height (3..5), not the floor.
      expect(ys, {3.0, 5.0});
    });

    test('missing object or unknown face returns no edges', () {
      final model = ModelData(id: 'c', name: 'c');
      expect(faceEdgeSegments(model, 'nope:+x', 0, 0, billboardYaw: 0), isEmpty);
      expect(faceEdgeSegments(model, 'bad', 0, 0, billboardYaw: 0), isEmpty);
    });

    test('rotated cuboid: the outline follows rotY', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'cuboid',
            x: 0,
            y: 0,
            z: 0,
            rotY: 90,
            dims: {'w': 1, 'h': 1, 'd': 1},
          ),
        ],
      );
      // rotY 90°: the model +x face ends up facing model +z. Its outline
      // must land there, not on the unrotated side.
      final segs = faceEdgeSegments(model, 'obj_1:+x', 0, 0, billboardYaw: 0);
      final pts = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      // Unrotated the +x face sits at model x = 0.5; rotated 90° the plane
      // is model z = −0.5 (world z = −0.5) with x ∈ {±0.5}.
      expect(pts, contains((-0.5, 0, -0.5)));
      expect(pts, contains((0.5, 0, -0.5)));
      expect(pts, contains((-0.5, 1, -0.5)));
      expect(pts, contains((0.5, 1, -0.5)));
    });

    test('trapezoid side outline is the sloped silhouette', () {
      final model = ModelData(
        id: 'c',
        name: 'c',
        objects: [
          ModelObject(
            id: 'obj_1',
            name: 'o',
            kind: 'trapezoid',
            x: 0,
            y: 0,
            z: 0,
            dims: {'bottomW': 2, 'bottomD': 2, 'topW': 1, 'topD': 1, 'h': 1},
          ),
        ],
      );
      // '+x' sloped face: bottom edge x = bw/2 = 1 → world +1, z ∈ {−1, 1};
      // top edge x = tw/2 = 0.5 → world +0.5 (inset), z ∈ {−0.5, 0.5}.
      final segs = faceEdgeSegments(model, 'obj_1:+x', 0, 0, billboardYaw: 0);
      final pts = <(double, double, double)>{
        for (final (a, b) in segs) ...[a, b],
      };
      expect(pts, contains((1.0, 0, -1.0)));
      expect(pts, contains((1.0, 0, 1.0)));
      expect(pts, contains((0.5, 1, -0.5)));
      expect(pts, contains((0.5, 1, 0.5)));
    });
  });

  group('selection and gizmo anchoring', () {
    test('setSelection / syncSelectionIds mirror the AppState selection', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 5, l: 5);
      model.objects.addAll([
        _cuboid(id: 'a', x: 0, y: 0, z: 0, w: 1, h: 1, d: 1),
        _cuboid(id: 'b', x: 2, y: 0, z: 2, w: 1, h: 1, d: 1),
      ]);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.setSelection('b');
      expect(editor.selectedObjectId, 'b');
      expect(editor.selectedIds, {'b'});
      editor.syncSelectionIds({'a', 'b'});
      expect(
        editor.selectedObjects(model).map((o) => o.id).toList(),
        ['a', 'b'],
      );
      editor.dispose();
      controller.dispose();
    });

    test('groupAnchor of a single object is its world anchor', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 5, l: 5);
      final obj = _cuboid(id: 'a', x: 0, y: 2, z: 0, w: 1, h: 1, d: 1);
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.setSelection(obj.id);
      final a = editor.groupAnchor(model);
      // chunkWorld(0, 0, 5, 5) = (2, 0, −2) — the anchor keeps its height.
      expect(a.x, closeTo(2, 1e-9));
      expect(a.y, closeTo(2, 1e-9));
      expect(a.z, closeTo(-2, 1e-9));
      editor.dispose();
      controller.dispose();
    });

    test('groupAnchor of a multi-selection is the union AABB center', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 5, l: 5);
      model.objects.addAll([
        _cuboid(id: 'a', x: 0, y: 0, z: 0, w: 1, h: 1, d: 1),
        _cuboid(id: 'b', x: 2, y: 0, z: 2, w: 1, h: 1, d: 1),
      ]);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.syncSelectionIds({'a', 'b'});
      final anchor = editor.groupAnchor(model);
      // Union AABB in model space: (−0.5,0,−0.5)..(2.5,1,2.5) →
      // center (1, 0.5, 1) → world (chunkWorld(1,1,5,5)) = (1, 0.5, −1).
      expect(anchor.x, closeTo(1, 1e-9));
      expect(anchor.y, closeTo(0.5, 1e-9));
      expect(anchor.z, closeTo(-1, 1e-9));
      editor.dispose();
      controller.dispose();
    });

    test('groupAnchor expands a csg result to its leaves', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 5, l: 5);
      model.objects.addAll([
        _cuboid(id: 'a', x: 0, y: 0, z: 0, w: 1, h: 1, d: 1),
        _cuboid(id: 'b', x: 2, y: 0, z: 2, w: 1, h: 1, d: 1),
        ModelObject(
          id: 'csg_1',
          name: 'csg',
          kind: csgKind,
          op: csgOpUnion,
          operands: ['a', 'b'],
        ),
      ]);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.setSelection('csg_1');
      // The selected object is the result node itself…
      expect(editor.selectedObjects(model).single.id, 'csg_1');
      // …but the anchor expands to the operands' union box.
      final anchor = editor.groupAnchor(model);
      expect(anchor.x, closeTo(1, 1e-9));
      expect(anchor.y, closeTo(0.5, 1e-9));
      expect(anchor.z, closeTo(-1, 1e-9));
      editor.dispose();
      controller.dispose();
    });

    test('rotationActive follows the rotate mode and the selection kind', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 5, l: 5);
      model.objects.addAll([
        _cuboid(id: 'a', x: 0, y: 0, z: 0, w: 1, h: 1, d: 1),
        ModelObject(
          id: 's',
          name: 's',
          kind: 'sprite',
          x: 2,
          y: 0,
          z: 2,
          dims: {'w': 1, 'h': 1},
        ),
      ]);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.setRotateMode(true);
      expect(editor.rotationActive, isFalse); // nothing selected
      editor.setSelection('a');
      expect(editor.rotationActive, isTrue);
      editor.setSelection('s');
      expect(editor.rotationActive, isFalse); // billboards do not rotate
      editor.dispose();
      controller.dispose();
    });
  });

  group('engine gizmo drag (headless screen drag)', () {
    testWidgets('moves the object along the axis and snaps to the step',
        (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 4, l: 4);
      final obj = _cuboid(w: 1, h: 1, d: 1); // anchor world (0.5, 0, 0.5)
      final startX = obj.x;
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      // Looking straight down; yaw = π makes screen-right = world −X, so the
      // engine's world +X handle points screen-left.
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(obj.id);
      editor.rebuildOverlays();
      // Headless: the controller has no render camera, so the per-frame
      // scale update is absent; set the engine gizmo's world scale manually.
      const scale = 1.0;
      editor.moveGizmo.applyScreenScale(scale);
      expect(editor.moveGizmo.visible, isTrue);
      final outlineBefore = editor.selectionOverlay.children.single;

      final anchor = editor.groupAnchor(model);
      final handle = controller.worldToScreen(
        anchor + gizmoAxisDirection(GizmoAxis.x) * scale,
      )!;
      final dragTo = handle + const Offset(40, 0);

      // Free drag: the world +X handle is screen-left, so dragging right
      // moves the object along model +x (world −X).
      editor.gizmoSnap = 0;
      expect(controller.beginGizmoDrag(handle), isNotNull);
      editor.beginGizmoDrag();
      controller.updateGizmoDrag(dragTo);
      controller.endGizmoDrag();
      editor.endGizmoDrag();
      expect(obj.x, greaterThan(startX));
      expect(
        editor.selectionOverlay.children.single,
        same(outlineBefore),
        reason: 'перенос сдвигает контур, не пересобирая его',
      );

      // Snap: the position rounds to the nearest multiple of the step.
      obj.x = 0.37;
      editor.rebuildOverlays();
      editor.gizmoSnap = 1;
      expect(controller.beginGizmoDrag(handle), isNotNull);
      editor.beginGizmoDrag();
      controller.updateGizmoDrag(dragTo);
      controller.endGizmoDrag();
      editor.endGizmoDrag();
      expect(obj.x, isNot(closeTo(0.37, 1e-9)));
      expect((obj.x - obj.x.roundToDouble()).abs(), lessThan(1e-9));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('moving a model instance does not rebuild the scene', (
      tester,
    ) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      final inst = ModelObject(
        id: 'inst',
        name: 'inst',
        kind: modelRefKind,
        x: 1,
        y: 0,
        z: 2,
        refModelId: 'src',
        refSize: ModelSize(w: 2, l: 2, h: 2),
      );
      model.objects.add(inst);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(inst.id);
      editor.rebuildOverlays();
      editor.moveGizmo.applyScreenScale(1.0);
      final anchor = editor.groupAnchor(model);
      final handle = controller.worldToScreen(
        anchor + gizmoAxisDirection(GizmoAxis.x),
      )!;

      final startX = inst.x;
      final rebuildsBefore = controller.rebuildCount;
      editor.gizmoSnap = 0;
      expect(controller.beginGizmoDrag(handle), isNotNull);
      editor.beginGizmoDrag();
      controller.updateGizmoDrag(handle + const Offset(40, 0));
      controller.endGizmoDrag();
      editor.endGizmoDrag();

      expect(inst.x, greaterThan(startX), reason: 'вставка должна сдвинуться');
      expect(
        controller.rebuildCount,
        rebuildsBefore,
        reason: 'перенос вставки идёт трансформами, без пересборки сцены',
      );

      // Полная пересборка (например, конец драга в AppState) счётчик растит.
      controller.rebuild();
      expect(controller.rebuildCount, rebuildsBefore + 1);

      editor.dispose();
      controller.dispose();
    });

    testWidgets('rotating a model instance does not rebuild the scene', (
      tester,
    ) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      final inst = ModelObject(
        id: 'inst',
        name: 'inst',
        kind: modelRefKind,
        x: 1,
        y: 0,
        z: 2,
        refModelId: 'src',
        refSize: ModelSize(w: 2, l: 2, h: 2),
      );
      model.objects.add(inst);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setRotateMode(true);
      editor.setSelection(inst.id);
      editor.rebuildOverlays();
      editor.rotateGizmo.applyScreenScale(1.0);
      expect(editor.rotateGizmo.visible, isTrue);

      // Top-down view: the Y ring lies in the horizontal plane. The grip is
      // the projected world +X offset; dragging to world +Z is a quarter turn.
      final anchor = editor.groupAnchor(model);
      final grip = controller.worldToScreen(anchor + vm.Vector3(1, 0, 0))!;
      final quarter = controller.worldToScreen(anchor + vm.Vector3(0, 0, 1))!;
      expect(controller.beginGizmoDrag(grip), isNotNull);

      final rebuildsBefore = controller.rebuildCount;
      final startRotY = inst.rotY;
      editor.gizmoSnapDeg = 0;
      editor.beginRotateDrag();
      controller.updateGizmoDrag(quarter);
      controller.endGizmoDrag();
      editor.endGizmoDrag();

      final turned = (inst.rotY - startRotY).abs();
      expect(
        turned == 270 ? 90 : turned,
        closeTo(90, 1e-3),
        reason: 'вставка должна повернуться на четверть оборота',
      );
      expect(
        controller.rebuildCount,
        rebuildsBefore,
        reason: 'поворот вставки идёт трансформами, без пересборки сцены',
      );

      editor.dispose();
      controller.dispose();
    });

    testWidgets('overlay caches survive rebuilds and follow the cursor', (
      tester,
    ) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      final obj = _cuboid();
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(obj.id);
      editor.rebuildOverlays();
      final overlayNodes = editor.overlays.children.toList();

      // A second rebuild reuses the very same grid/frame/cursor nodes.
      editor.rebuildOverlays();
      expect(editor.overlays.children.toList(), overlayNodes);
      final outline = editor.selectionOverlay.children.single;

      // Cursor/selection syncs are transform-only: the cached outline node
      // stays, and no new grid/frame/cursor nodes appear.
      editor.cursor = vm.Vector3(1, 0, 1);
      editor.cellCursor = true;
      editor.syncUiState();
      expect(
        editor.overlays.children.toList(),
        containsAll(overlayNodes),
        reason: 'синк курсора не пересобирает сетку/рамку',
      );
      expect(editor.selectionOverlay.children.single, same(outline));

      // Hiding the brush removes only its cell highlight.
      editor.cellCursor = false;
      editor.syncUiState();
      expect(
        editor.overlays.children.toList(),
        overlayNodes,
        reason: 'клетка кисти убирается из слоя',
      );

      editor.dispose();
      controller.dispose();
    });
  });

  group('picking (headless raycast)', () {
    testWidgets('pick returns the object id and the face key', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      model.objects.add(_cuboid());
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);
      const size = Size(200, 200);

      final screen = controller.worldToScreen(vm.Vector3(0.5, 0.5, 0.5))!;
      final pick = editor.pick(screen, size);
      expect(pick, isNotNull);
      expect(pick!.$1, 'obj_1');
      expect(pick.$2, '+y');

      final face = editor.pickFace(screen, size);
      expect(face, isNotNull);
      expect(face!.$1, 'obj_1');
      expect(face.$2, '+y');
      expect(face.$3.y, closeTo(1, 1e-4));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('pick works from a rotated camera (side view)', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      model.objects.add(_cuboid());
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      // Смотрим на куб с world −X строго горизонтально: луч входит в грань
      // −x (world x = −0.5) в её центре.
      editor.eye = vm.Vector3(-4, 0.5, 0.5);
      editor.fly.lookAt(vm.Vector3(0.5, 0.5, 0.5));
      await _pumpViewport(tester, controller);
      const size = Size(200, 200);

      final screen = controller.worldToScreen(vm.Vector3(0.5, 0.5, 0.5))!;
      final face = editor.pickFace(screen, size);
      expect(face, isNotNull);
      expect(face!.$1, 'obj_1');
      expect(face.$2, '-x');
      expect(face.$3.x, closeTo(-0.5, 1e-3));
      expect(face.$3.y, closeTo(0.5, 1e-3));
      expect(face.$3.z, closeTo(0.5, 1e-3));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('skipObjectIds passes the selected object through to the face '
        'behind', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      // The near box swallows the ray; skipping it must reach the far one.
      model.objects.add(_cuboid(id: 'near', y: 2, w: 2, h: 1, d: 2));
      model.objects.add(_cuboid(id: 'far', y: 0, w: 2, h: 1, d: 2));
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 6, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);
      const size = Size(200, 200);

      final screen = controller.worldToScreen(vm.Vector3(0.5, 1.5, 0.5))!;
      final near = editor.pick(screen, size);
      expect(near!.$1, 'near');
      expect(near.$2, '+y');

      final through = editor.pickFace(screen, size, skipObjectIds: {'near'});
      expect(through, isNotNull);
      expect(through!.$1, 'far');
      expect(through.$2, '+y');

      // Skipping everything under the cursor yields no pick.
      expect(
        editor.pickFace(screen, size, skipObjectIds: {'near', 'far'}),
        isNull,
      );

      editor.dispose();
      controller.dispose();
    });

    testWidgets('texture mode skips model instances (not editable content)',
        (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      model.objects.add(ModelObject(
        id: 'inst',
        name: 'inst',
        kind: modelRefKind,
        x: 1,
        y: 0,
        z: 2,
        refModelId: 'src',
        refSize: ModelSize(w: 2, l: 2, h: 2),
      ));
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);
      const size = Size(200, 200);

      final screen = controller.worldToScreen(vm.Vector3(0.5, 1, 0.5))!;
      expect(editor.pick(screen, size)!.$1, 'inst');

      editor.textureMode = true;
      expect(editor.pick(screen, size), isNull);
      expect(editor.pickFace(screen, size), isNull);

      editor.textureMode = false;
      expect(editor.pick(screen, size)!.$1, 'inst');

      editor.dispose();
      controller.dispose();
    });

    testWidgets('a miss returns null', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model();
      model.objects.add(_cuboid(w: 1, h: 1, d: 1));
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0.5, 5, 0.5);
      editor.yaw = math.pi;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);
      const size = Size(200, 200);

      expect(editor.pick(const Offset(2, 2), size), isNull);
      expect(editor.pickFace(const Offset(2, 2), size), isNull);

      editor.dispose();
      controller.dispose();
    });
  });

  group('многогранник: контуры, якоря и сетка', () {
    ModelObject poly({
      String id = 'p',
      double x = 0,
      double y = 0,
      double z = 0,
      double scaleY = 1,
      PolyMesh? mesh,
    }) =>
        ModelObject(
          id: id,
          name: id,
          kind: polyhedronKind,
          x: x,
          y: y,
          z: z,
          scaleY: scaleY,
          mesh: mesh ?? PolyMesh.box(w: 2, h: 1, d: 2),
        );

    test('objectEdgeSegments обводит контуры всех граней', () {
      final obj = poly();
      final edges = objectEdgeSegments(obj, billboardYaw: 0.5);
      // 6 граней × 4 ребра (каждое ребро принадлежит двум граням).
      expect(edges, hasLength(24));
      final points = [for (final e in edges) ...[e.$1, e.$2]];
      expect(_hasPoint(points, -1, 0, -1), isTrue);
      expect(_hasPoint(points, 1, 1, 1), isTrue);
    });

    test('per-axis масштаб растягивает контуры по осям', () {
      final obj = poly(scaleY: 2);
      final edges = objectEdgeSegments(obj, billboardYaw: 0);
      final points = [for (final e in edges) ...[e.$1, e.$2]];
      expect(_hasPoint(points, -1, 2, -1), isTrue);
      expect(_hasPoint(points, -1, 1, -1), isFalse);
    });

    test('faceEdgeSegments грани с отверстием обходит оба контура', () {
      final model = _model(w: 6, l: 6);
      final slab = poly(
        id: 's',
        mesh: PolyMesh(
          vertices: [
            vm.Vector3(-1, 0, -1),
            vm.Vector3(1, 0, -1),
            vm.Vector3(1, 0, 1),
            vm.Vector3(-1, 0, 1),
            vm.Vector3(-0.5, 0, -0.5),
            vm.Vector3(0.5, 0, -0.5),
            vm.Vector3(0.5, 0, 0.5),
            vm.Vector3(-0.5, 0, 0.5),
          ],
          faces: [
            PolyFace(
              key: '+y',
              outer: PolyLoop(vertices: [0, 1, 2, 3]),
              holes: [PolyLoop(vertices: [4, 5, 6, 7])],
            ),
          ],
        ),
      );
      model.objects.add(slab);
      final edges = faceEdgeSegments(
        model,
        's:+y',
        (model.size.w - 1) / 2,
        (model.size.l - 1) / 2,
        billboardYaw: 0,
      );
      expect(edges, hasLength(8));
    });

    test('polySelectionAnchor — центроид выбранных вершин в мире', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 6, l: 6);
      final obj = poly(x: 2, z: 3);
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.syncPolyEdit(PolyEditMode.vertices, {0, 1}, 0, null);
      final anchor = editor.polySelectionAnchor(controller.model!, obj)!;
      final expected = objectWorldMatrix(model, obj)
          .transform3(vm.Vector3(0, 0, -1));
      expect(anchor.x, closeTo(expected.x, 1e-9));
      expect(anchor.y, closeTo(expected.y, 1e-9));
      expect(anchor.z, closeTo(expected.z, 1e-9));
      // В режиме «объект» якорь не используется (null).
      editor.syncPolyEdit(PolyEditMode.object, const {}, null, null);
      expect(editor.polySelectionAnchor(controller.model!, obj), isNull);
      editor.dispose();
      controller.dispose();
    });

    test('polySelectionAnchor учитывает масштаб по осям', () {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 6, l: 6);
      final obj = poly(scaleY: 3);
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      // Вершина 4 куба (−1, 1, −1) при scaleY = 3 → мировой y = 3.
      editor.syncPolyEdit(PolyEditMode.vertices, {4}, 4, null);
      final anchor = editor.polySelectionAnchor(controller.model!, obj)!;
      final expected = objectWorldMatrix(model, obj)
          .transform3(vm.Vector3(-1, 1, -1));
      expect(anchor.y, closeTo(expected.y, 1e-9));
      editor.dispose();
      controller.dispose();
    });

    test('adaptiveGridCell: легаси единица, крупные карты удваиваются', () {
      expect(adaptiveGridCell(3, 3), 1);
      expect(adaptiveGridCell(64, 64), 1);
      expect(adaptiveGridCell(65, 40), 2);
      expect(adaptiveGridCell(4576, 2816), 128);
    });

    testWidgets('гизмо двигает выбранные вершины многогранника', (
      tester,
    ) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 6, l: 6);
      final obj = poly();
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0, 6, 0.01);
      editor.yaw = 0;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(obj.id);
      editor.syncPolyEdit(PolyEditMode.vertices, {4}, 4, null);
      editor.rebuildOverlays();
      editor.moveGizmo.applyScreenScale(1.0);
      final anchor = editor.polySelectionAnchor(controller.model!, obj)!;
      final handle = controller.worldToScreen(
        anchor + gizmoAxisDirection(GizmoAxis.x),
      )!;
      final before = obj.mesh!.vertices[4].clone();
      final other = obj.mesh!.vertices[0].clone();
      final matrix = objectWorldMatrix(model, obj);
      final worldBefore = matrix.transform3(before.clone());

      editor.gizmoSnap = 0;
      expect(controller.beginGizmoDrag(handle), isNotNull);
      editor.beginGizmoDrag();
      controller.updateGizmoDrag(handle + const Offset(40, 0));
      controller.endGizmoDrag();
      editor.endGizmoDrag();

      expect(obj.mesh!.vertices[4].x, isNot(closeTo(before.x, 1e-6)));
      expect(obj.mesh!.vertices[0].x, closeTo(other.x, 1e-9),
          reason: 'невыбранные вершины не двигаются');
      expect(editor.gizmoDragging, isFalse);
      // Красная ось: положительный драг гизмо даёт положительное смещение
      // вершины в МИРЕ (локальная рамка не зеркалит X).
      final worldAfter = matrix.transform3(obj.mesh!.vertices[4].clone());
      final worldDelta = worldAfter - worldBefore;
      expect(worldDelta.x, greaterThan(0));
      expect(worldDelta.y.abs(), lessThan(1e-6));
      expect(worldDelta.z.abs(), lessThan(1e-6));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('перенос вершины вдоль X верен у повёрнутого и растянутого '
        'объекта', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 8, l: 8);
      final obj = ModelObject(
        id: 'p',
        name: 'p',
        kind: polyhedronKind,
        x: 1,
        y: 0,
        z: 2,
        rotY: 30,
        scaleX: 2,
        scaleY: 1.5,
        mesh: PolyMesh.box(w: 2, h: 2, d: 2),
      );
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0, 7, 0.01);
      editor.yaw = 0;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(obj.id);
      editor.syncPolyEdit(PolyEditMode.vertices, {4}, 4, null);
      editor.rebuildOverlays();
      editor.moveGizmo.applyScreenScale(1.0);
      final anchor = editor.polySelectionAnchor(controller.model!, obj)!;
      final handle = controller.worldToScreen(
        anchor + gizmoAxisDirection(GizmoAxis.x),
      )!;
      final matrix = objectWorldMatrix(model, obj);
      final worldBefore =
          matrix.transform3(obj.mesh!.vertices[4].clone());

      editor.gizmoSnap = 0;
      expect(controller.beginGizmoDrag(handle), isNotNull);
      editor.beginGizmoDrag();
      controller.updateGizmoDrag(handle + const Offset(40, 0));
      controller.endGizmoDrag();
      editor.endGizmoDrag();

      final worldAfter =
          matrix.transform3(obj.mesh!.vertices[4].clone());
      final worldDelta = worldAfter - worldBefore;
      expect(worldDelta.x, greaterThan(0));
      expect(worldDelta.y.abs(), lessThan(1e-6));
      expect(worldDelta.z.abs(), lessThan(1e-6));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('поворот вершин вокруг красной оси не инвертирован', (
      tester,
    ) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 6, l: 6);
      final obj = poly();
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0, 6, 0.01);
      editor.yaw = 0;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      editor.setSelection(obj.id);
      // Верхние четыре вершины куба; пивот — их центроид (0, 1, 0).
      editor.syncPolyEdit(PolyEditMode.vertices, {4, 5, 6, 7}, 4, null);
      editor.rebuildOverlays();
      editor.moveGizmo.applyScreenScale(1.0);
      editor.beginRotateDrag();
      // Мировой поворот вокруг +X на +90°: (y,z) → (−z,y).
      editor.rotateGizmo.onDrag?.call(
        const GizmoDragEvent(axis: GizmoAxis.x, rotation: math.pi / 2),
      );
      editor.endGizmoDrag();

      // Вершина 4 (−1, 1, −1) относительно пивота → (−1, 2, 0).
      final v4 = obj.mesh!.vertices[4];
      expect(v4.x, closeTo(-1, 1e-6));
      expect(v4.y, closeTo(2, 1e-6));
      expect(v4.z, closeTo(0, 1e-6));

      editor.dispose();
      controller.dispose();
    });

    testWidgets('pickPolyVertex выбирает ближайшую вершину', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 6, l: 6);
      final obj = poly();
      model.objects.add(obj);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      controller.camera = editor.fly;
      editor.eye = vm.Vector3(0, 6, 0.01);
      editor.yaw = 0;
      editor.pitch = math.pi / 2;
      await _pumpViewport(tester, controller);

      final matrix = objectWorldMatrix(model, obj);
      final screen = controller.worldToScreen(
        matrix.transform3(obj.mesh!.vertices[4].clone()),
      )!;
      expect(editor.pickPolyVertex(obj, screen), 4);
      expect(
        editor.pickPolyVertex(obj, screen + const Offset(80, 80)),
        isNull,
      );

      editor.dispose();
      controller.dispose();
    });
    testWidgets('сетка земли: 1 px и переключаемая видимость', (tester) async {
      final controller = SceneController(mergeStatic: false);
      final model = _model(w: 64, l: 64, h: 8);
      controller.loadModelData(model);
      final editor = EditorScene(controller);
      editor.rebuildOverlays();

      GridNode grid() => editor.overlays.children.whereType<GridNode>().single;
      expect(grid().widthPx, 1.0, reason: 'линия сетки — 1 px');
      expect(grid().visible, isTrue);

      editor.setGridVisible(false);
      expect(grid().visible, isFalse);

      editor.setGridVisible(true);
      expect(grid().visible, isTrue);

      // Пересборка сетки (смена габаритов) сохраняет скрытое состояние.
      editor.setGridVisible(false);
      model.size.w = 128;
      editor.rebuild(model);
      expect(grid().visible, isFalse);

      editor.dispose();
      controller.dispose();
    });
  });
}
