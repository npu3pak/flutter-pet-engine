import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('gizmo math', () {
    test('axisDragDelta projects the hit movement on the axis', () {
      final ray = vm.Ray.originDirection(
        vm.Vector3(1, 0, 0),
        vm.Vector3(0, 0, 1),
      );
      final delta = axisDragDelta(
        ray,
        vm.Vector3(0, 0, 5),
        vm.Vector3(0, 0, 1),
        vm.Vector3(1, 0, 0),
      );
      expect(delta, closeTo(1, 1e-6));
    });

    test('axisDragDelta returns null for a parallel ray', () {
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, 0),
        vm.Vector3(0, 0, 1),
      );
      expect(
        axisDragDelta(
          ray,
          vm.Vector3.zero(),
          vm.Vector3(1, 0, 0),
          vm.Vector3(1, 0, 0),
        ),
        isNull,
      );
    });

    test('planeHit intersects the plane', () {
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, 0),
        vm.Vector3(0, 0, 1),
      );
      final hit = planeHit(ray, vm.Vector3(0, 0, 5), vm.Vector3(0, 0, 1))!;
      expect(hit.z, closeTo(5, 1e-6));
    });

    test('signedAngleAroundAxis follows the right-hand rule', () {
      final angle = signedAngleAroundAxis(
        vm.Vector3(1, 0, 0),
        vm.Vector3(0, 1, 0),
        vm.Vector3(0, 0, 1),
      );
      expect(angle, closeTo(math.pi / 2, 1e-6));
    });

    test('rotationDragDelta sweeps a quarter turn', () {
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 1, 5),
        vm.Vector3(0, 0, -1),
      );
      final delta = rotationDragDelta(
        ray,
        vm.Vector3.zero(),
        vm.Vector3(0, 0, 1),
        vm.Vector3(1, 0, 0),
      );
      expect(delta, closeTo(math.pi / 2, 1e-6));
    });
  });

  group('GizmoNode', () {
    test('translate builds three arrows on the top layer', () {
      final gizmo = GizmoNode(
        mode: GizmoMode.translate,
        anchor: vm.Vector3.zero(),
      );
      expect(gizmo.children, hasLength(6));
      expect(
        gizmo.children.every((child) => child.layer == SceneLayer.top),
        isTrue,
      );
      expect(gizmo.mode, GizmoMode.translate);
      gizmo.remove();
    });

    test('rotate builds three rings', () {
      final gizmo = GizmoNode(
        mode: GizmoMode.rotate,
        anchor: vm.Vector3(1, 2, 3),
      );
      expect(gizmo.children, hasLength(3));
      expect(gizmo.anchor, vm.Vector3(1, 2, 3));
      gizmo.remove();
    });
  });

  group('controller gizmos', () {
    test('hitGizmo finds the axis under the pointer, drag emits deltas', () {
      final controller = SceneController();
      controller.setViewport(const Size(400, 300), 1);
      final anchor = vm.Vector3(0, 0, 10);
      final gizmo = controller.addGizmo(
        GizmoNode(mode: GizmoMode.translate, anchor: anchor),
      );
      gizmo.applyScreenScale(2.0);

      final center = controller.worldToScreen(anchor)!;
      final xEnd = controller.worldToScreen(
        anchor + vm.Vector3(2, 0, 0),
      )!;
      final grab = Offset.lerp(center, xEnd, 0.6)!;
      final hit = controller.hitGizmo(grab);
      expect(hit, isNotNull);
      expect(hit!.axis, GizmoAxis.x);
      expect(hit.gizmo, same(gizmo));

      final events = <GizmoDragEvent>[];
      gizmo.onDrag = events.add;
      expect(controller.beginGizmoDrag(grab), isNotNull);
      controller.updateGizmoDrag(grab + const Offset(20, 0));
      controller.endGizmoDrag();

      expect(events, isNotEmpty);
      expect(events.last.axis, GizmoAxis.x);
      expect(events.last.translation!.x, greaterThan(0));
      controller.dispose();
    });

    test('hitGizmo returns null far from every handle', () {
      final controller = SceneController();
      controller.setViewport(const Size(400, 300), 1);
      final gizmo = controller.addGizmo(
        GizmoNode(mode: GizmoMode.rotate, anchor: vm.Vector3(0, 0, 10)),
      );
      gizmo.applyScreenScale(2.0);
      expect(controller.hitGizmo(const Offset(10, 10)), isNull);
      controller.dispose();
    });

    test('hidden gizmos never take the hit', () {
      final controller = SceneController();
      controller.setViewport(const Size(400, 300), 1);
      final anchor = vm.Vector3(0, 0, 10);
      // Скрытый гизмо вращения стоит первым в порядке обхода (reversed) и
      // раньше перехватывал клик по видимой оси переноса.
      final rotate = controller.addGizmo(
        GizmoNode(mode: GizmoMode.rotate, anchor: anchor),
      );
      final move = controller.addGizmo(
        GizmoNode(mode: GizmoMode.translate, anchor: anchor),
      );
      rotate.visible = false;
      rotate.applyScreenScale(2.0);
      move.applyScreenScale(2.0);

      final center = controller.worldToScreen(anchor)!;
      final xEnd = controller.worldToScreen(anchor + vm.Vector3(2, 0, 0))!;
      final grab = Offset.lerp(center, xEnd, 0.6)!;
      final hit = controller.hitGizmo(grab);
      expect(hit, isNotNull);
      expect(hit!.gizmo, same(move));

      rotate.visible = true;
      expect(controller.hitGizmo(grab), isNotNull);
      controller.dispose();
    });

    test('a target node follows a translate drag', () {
      final controller = SceneController();
      controller.setViewport(const Size(400, 300), 1);
      final anchor = vm.Vector3(0, 0, 10);
      final target = controller.add(BoxNode(id: 'box'));
      final gizmo = controller.addGizmo(
        GizmoNode(
          mode: GizmoMode.translate,
          anchor: anchor,
          target: target,
        ),
      );
      gizmo.applyScreenScale(2.0);

      final center = controller.worldToScreen(anchor)!;
      final grab = center + const Offset(10, 0);
      controller.beginGizmoDrag(grab);
      controller.updateGizmoDrag(grab + const Offset(30, 0));
      controller.endGizmoDrag();

      expect(target.position.x, greaterThan(0));
      controller.dispose();
    });
  });

  group('GridNode', () {
    test('grid segments cover the requested size', () {
      final grid = GridNode(width: 4, depth: 2, cell: 1);
      // 5 lines across X plus 3 across Z, two endpoints each.
      expect(grid.geometry.segmentCount, 8);
      expect(grid.widthPx, 1.0);
      expect(grid.layer, SceneLayer.overlay);
      grid.remove();
    });

    test('degenerate sizes produce an empty grid', () {
      expect(gridSegments(width: 0, depth: 2), isEmpty);
      expect(gridSegments(width: 2, depth: 2, cell: 0), isEmpty);
    });
  });
}
