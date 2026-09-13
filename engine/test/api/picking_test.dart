import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

SceneController _controller() {
  final controller = SceneController();
  controller.setViewport(const Size(200, 100), 1);
  return controller;
}

void main() {
  group('screenPointToRay', () {
    test('center ray points forward', () {
      final controller = _controller();
      final ray = controller.screenPointToRay(const Offset(100, 50));
      expect(ray.origin.x, closeTo(0, 1e-6));
      expect(ray.direction.x, closeTo(0, 1e-6));
      expect(ray.direction.z, closeTo(1, 1e-6));
      controller.dispose();
    });

    test('right ray turns to the right', () {
      final controller = _controller();
      final ray = controller.screenPointToRay(const Offset(200, 50));
      expect(ray.direction.x, greaterThan(0));
      expect(ray.direction.z, greaterThan(0));
      controller.dispose();
    });

    test('center ray follows the camera forward at any orientation', () {
      final controller = _controller();
      final fly = FlyCameraController();
      controller.camera = fly;
      fly.yaw = 1.9;
      fly.pitch = 0.33;
      final ray = controller.screenPointToRay(const Offset(100, 50));
      final forward = fly.forward;
      expect(ray.direction.x, closeTo(forward.x, 1e-9));
      expect(ray.direction.y, closeTo(forward.y, 1e-9));
      expect(ray.direction.z, closeTo(forward.z, 1e-9));
      controller.dispose();
    });

    test('ray through a projected point passes through it', () {
      final controller = _controller();
      final fly = FlyCameraController();
      controller.camera = fly;
      fly.eye = vm.Vector3(3.2, 4.1, 5.3);
      fly.yaw = 2.1;
      fly.pitch = 0.37;
      final target = vm.Vector3(0.4, 0.8, -0.6);
      final screen = controller.worldToScreen(target);
      expect(screen, isNotNull);
      final ray = controller.screenPointToRay(screen!);
      final toTarget = target - ray.origin;
      final along = toTarget.dot(ray.direction);
      expect(along, greaterThan(0), reason: 'точка должна быть перед камерой');
      final offAxis = (toTarget - ray.direction * along).length;
      expect(offAxis, lessThan(1e-6));
      controller.dispose();
    });

    test('screen-space raycast hits a box from a rotated camera', () {
      final controller = _controller();
      final fly = FlyCameraController();
      controller.camera = fly;
      fly.eye = vm.Vector3(4, 3, 4);
      fly.lookAt(vm.Vector3.zero());
      final box = controller.add(BoxNode(id: 'box', size: vm.Vector3(1, 1, 1)));
      final hit = controller.raycast(const Offset(100, 50));
      expect(hit?.node, same(box));
      controller.dispose();
    });
  });

  group('worldToScreen', () {
    test('projects a point in front of the camera', () {
      final controller = _controller();
      final screen = controller.worldToScreen(vm.Vector3(0, 0, 10));
      expect(screen, isNotNull);
      expect(screen!.dx, closeTo(100, 1e-6));
      expect(screen.dy, closeTo(50, 1e-6));
      controller.dispose();
    });

    test('returns null behind the camera', () {
      final controller = _controller();
      expect(controller.worldToScreen(vm.Vector3(0, 0, -10)), isNull);
      controller.dispose();
    });

    test('screenRect covers projected bounds', () {
      final controller = _controller();
      final rect = controller.screenRect(
        vm.Aabb3.minMax(vm.Vector3(-1, -1, 4), vm.Vector3(1, 1, 6)),
      );
      expect(rect, isNotNull);
      expect(rect!.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.center.dx, closeTo(100, 0.5));
      controller.dispose();
    });
  });

  group('raycast', () {
    test('hits a box and reports the nearest surface', () {
      final controller = _controller();
      final box = controller.add(BoxNode(id: 'box', size: vm.Vector3(2, 2, 2)));
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, 5),
        vm.Vector3(0, 0, -1),
      );
      final hit = controller.raycastRay(ray);
      expect(hit, isNotNull);
      expect(hit!.node, same(box));
      expect(hit.distance, closeTo(4, 1e-4));
      expect(hit.worldPoint.z, closeTo(1, 1e-4));
      expect(hit.worldNormal!.z, closeTo(1, 1e-4));
      controller.dispose();
    });

    test('respects visibility, skip ids and where filters', () {
      final controller = _controller();
      final box = controller.add(BoxNode(id: 'box', size: vm.Vector3(2, 2, 2)));
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, 5),
        vm.Vector3(0, 0, -1),
      );

      box.visible = false;
      expect(controller.raycastRay(ray), isNull);
      expect(
        controller.raycastRay(
          ray,
          options: const RaycastOptions(includeInvisible: true),
        ),
        isNotNull,
      );

      box.visible = true;
      expect(
        controller.raycastRay(
          ray,
          options: const RaycastOptions(skipNodeIds: {'box'}),
        ),
        isNull,
      );
      expect(
        controller.raycastRay(
          ray,
          options: RaycastOptions(where: (node) => node.id == 'other'),
        ),
        isNull,
      );
      controller.dispose();
    });

    test('returns all hits nearest first', () {
      final controller = _controller();
      controller.add(BoxNode(id: 'near', size: vm.Vector3(2, 2, 2)));
      final far = controller.add(BoxNode(id: 'far', size: vm.Vector3(2, 2, 2)));
      far.position = vm.Vector3(0, 0, -5);
      final ray = vm.Ray.originDirection(
        vm.Vector3(0, 0, 5),
        vm.Vector3(0, 0, -1),
      );
      final hits = controller.raycastAll(ray);
      expect(hits.length, 2);
      expect(hits.first.node.id, 'near');
      expect(hits.last.node.id, 'far');
      controller.dispose();
    });

    test('screen-space raycast hits through the camera', () {
      final controller = _controller();
      final box = controller.add(BoxNode(id: 'box', size: vm.Vector3(2, 2, 2)));
      final hit = controller.raycast(const Offset(100, 50));
      expect(hit?.node, same(box));
      controller.dispose();
    });

    test('nearestNode picks the closest projected node', () {
      final controller = _controller();
      final left = controller.add(
        BoxNode(id: 'left', size: vm.Vector3(1, 1, 1))
          ..position = vm.Vector3(-2, 0, 10),
      );
      controller.add(
        BoxNode(id: 'right', size: vm.Vector3(1, 1, 1))
          ..position = vm.Vector3(2, 0, 10),
      );
      final center = controller.worldToScreen(vm.Vector3(-2, 0, 10))!;
      expect(controller.nearestNode(center), same(left));
      controller.dispose();
    });
  });

  group('document object picking', () {
    ModelData model() =>
        ModelData(id: 'm', name: 'M', size: ModelSize(w: 4, l: 4, h: 3));

    ModelObject box({
      String id = 'obj_1',
      double x = 1,
      double z = 2,
      double w = 2,
      double h = 1,
      double d = 2,
    }) => ModelObject(
      id: id,
      name: 'box',
      kind: 'cuboid',
      x: x,
      y: 0,
      z: z,
      dims: {'w': w, 'h': h, 'd': d},
    );

    test('hits a document cuboid and reports its face', () {
      final controller = _controller();
      controller.loadModelData(model());
      final node = controller.addObject(box());

      final top = controller.raycastRay(
        vm.Ray.originDirection(
          vm.Vector3(0.5, 5, 0.5),
          vm.Vector3(0, -1, 0),
        ),
      );
      expect(top, isNotNull);
      expect(top!.node, same(node));
      expect(top.face?.key, '+y');
      expect(top.worldPoint.y, closeTo(1, 1e-4));

      final side = controller.raycastRay(
        vm.Ray.originDirection(
          vm.Vector3(0.5, 0.5, 5),
          vm.Vector3(0, 0, -1),
        ),
      );
      expect(side?.node, same(node));
      expect(side!.face?.key, '+z');
      controller.dispose();
    });

    test('face ref carries the document material', () {
      final controller = _controller();
      controller.loadModelData(model());
      final object = box();
      final material = ModelMaterial(type: MaterialType.color);
      object.faces['+y'] = material;
      controller.addObject(object);

      final hit = controller.raycastRay(
        vm.Ray.originDirection(
          vm.Vector3(0.5, 5, 0.5),
          vm.Vector3(0, -1, 0),
        ),
      );
      expect(hit?.face?.material, same(material));
      controller.dispose();
    });

    test('document nodes take part in skip, where and nearest filters', () {
      final controller = _controller();
      controller.loadModelData(model());
      final node = controller.addObject(box());
      final ray = vm.Ray.originDirection(
        vm.Vector3(0.5, 5, 0.5),
        vm.Vector3(0, -1, 0),
      );

      expect(
        controller.raycastRay(ray, options: const RaycastOptions(skipNodeIds: {'obj_1'})),
        isNull,
      );
      expect(
        controller.raycastRay(ray, options: RaycastOptions(where: (n) => n.id == 'other')),
        isNull,
      );

      final screen = controller.worldToScreen(node.worldPosition)!;
      expect(controller.nearestNode(screen), same(node));
      expect(controller.byId('obj_1'), same(node));
      expect(controller.objectNode('obj_1'), same(node));
      expect(controller.nodesOfType<ModelNode>(), contains(node));
      controller.dispose();
    });

    test('moved objects update the cached pick geometry', () {
      final controller = _controller();
      controller.loadModelData(model());
      final node = controller.addObject(box(w: 1, d: 1));

      expect(
        controller.raycastRay(
          vm.Ray.originDirection(vm.Vector3(0.5, 5, 0.5), vm.Vector3(0, -1, 0)),
        ),
        isNotNull,
      );
      node.setPlacement(x: 2);
      expect(
        controller.raycastRay(
          vm.Ray.originDirection(vm.Vector3(0.5, 5, 0.5), vm.Vector3(0, -1, 0)),
        ),
        isNull,
      );
      expect(
        controller.raycastRay(
          vm.Ray.originDirection(
            vm.Vector3(-0.5, 5, 0.5),
            vm.Vector3(0, -1, 0),
          ),
        ),
        isNotNull,
      );
      controller.dispose();
    });

    test('cylinder exposes side and cap faces', () {
      final controller = _controller();
      controller.loadModelData(model());
      controller.addObject(
        ModelObject(
          id: 'cyl',
          name: 'cyl',
          kind: 'cylinder',
          x: 1,
          y: 0,
          z: 2,
          dims: {'bottomR': 0.5, 'topR': 0.5, 'h': 1, 'segments': 16},
        ),
      );

      final top = controller.raycastRay(
        vm.Ray.originDirection(vm.Vector3(0.5, 5, 0.5), vm.Vector3(0, -1, 0)),
      );
      expect(top?.face?.key, '+y');

      final side = controller.raycastRay(
        vm.Ray.originDirection(vm.Vector3(0.5, 0.5, 5), vm.Vector3(0, 0, -1)),
      );
      expect(side?.face?.key, 'side');
      expect(side!.worldPoint.z, closeTo(1.0, 1e-3));
      controller.dispose();
    });

    test('rounded cuboid keeps planar and round face keys', () {
      final controller = _controller();
      controller.loadModelData(model());
      controller.addObject(
        ModelObject(
          id: 'round',
          name: 'round',
          kind: 'cuboid',
          x: 1,
          y: 0,
          z: 2,
          dims: {'w': 2, 'h': 1, 'd': 2, 'roundR': 0.2, 'roundSegments': 3},
        ),
      );
      final hit = controller.raycastRay(
        vm.Ray.originDirection(vm.Vector3(0.5, 5, 0.5), vm.Vector3(0, -1, 0)),
      );
      expect(hit?.face?.key, '+y');
      controller.dispose();
    });

    test('csg result picks as a whole object and hides its operands', () {
      final controller = _controller();
      final data = model();
      final a = box(id: 'a', w: 1, d: 1);
      final b = box(id: 'b', w: 1, d: 1);
      final csg = ModelObject(
        id: 'csg_1',
        name: 'csg',
        kind: 'csg',
        op: csgOpUnion,
        operands: ['a', 'b'],
      );
      data.objects.addAll([a, b, csg]);
      controller.loadModelData(data);

      final ray = vm.Ray.originDirection(
        vm.Vector3(0.5, 5, 0.5),
        vm.Vector3(0, -1, 0),
      );
      final hits = controller.raycastAll(ray);
      expect(hits, hasLength(1));
      expect(hits.single.node.id, 'csg_1');
      expect(hits.single.face, isNull);
      controller.dispose();
    });

    test('model and gltf instances pick through their footprint box', () {
      final controller = _controller();
      final data = model();
      data.objects.add(
        ModelObject(
          id: 'inst',
          name: 'inst',
          kind: modelRefKind,
          x: 1,
          y: 0,
          z: 2,
          refModelId: 'src',
          refSize: ModelSize(w: 2, l: 2, h: 2),
        ),
      );
      data.objects.add(
        ModelObject(
          id: 'gltf',
          name: 'gltf',
          kind: gltfRefKind,
          x: 1,
          y: 0,
          z: 2,
          gltfName: 'cat',
          gltfBounds: const [0, 0, 0, 1, 1, 1],
        ),
      );
      controller.loadModelData(data);

      final ray = vm.Ray.originDirection(
        vm.Vector3(0.5, 5, 0.5),
        vm.Vector3(0, -1, 0),
      );
      final hits = controller.raycastAll(ray);
      expect(hits.map((h) => h.node.id).toSet(), {'inst', 'gltf'});
      controller.dispose();
    });

    test('a model instance picks where its content is anchored', () {
      final controller = _controller();
      final data = model();
      // Anchor (0.5, 0, 0.5); a 3×2 footprint spans x −1..2, z −0.5..1.5.
      data.objects.add(
        ModelObject(
          id: 'inst',
          name: 'inst',
          kind: modelRefKind,
          x: 1,
          y: 0,
          z: 2,
          refModelId: 'src',
          refSize: ModelSize(w: 3, l: 2, h: 2),
        ),
      );
      controller.loadModelData(data);

      bool hitsInstance(double x, double z) {
        final hits = controller.raycastAll(
          vm.Ray.originDirection(
            vm.Vector3(x, 5, z),
            vm.Vector3(0, -1, 0),
          ),
        );
        return hits.any((hit) => hit.node.id == 'inst');
      }

      // Inside the anchor-centered footprint (the old offset proxy missed).
      expect(hitsInstance(-0.5, 0.75), isTrue);
      // Outside it, but inside the old offset proxy (which must not hit).
      expect(hitsInstance(2.5, 0.75), isFalse);
      controller.dispose();
    });

    test('a billboard sprite picks with its live camera yaw', () {
      final controller = _controller();
      final data = model();
      data.objects.add(
        ModelObject(
          id: 'curtain',
          name: 'curtain',
          kind: 'sprite',
          x: 1,
          y: 0,
          z: 2,
          rotY: 90, // authored yaw differs from the live billboard yaw
          dims: const {'w': 2, 'h': 2},
        ),
      );
      controller.loadModelData(data);

      // The anchor is world (0.5, 0, 0.5); the default camera faces +Z, so
      // the live billboard quad lies in the XY plane at z = 0.5.
      final ray = vm.Ray.originDirection(
        vm.Vector3(0.5, 1, -5),
        vm.Vector3(0, 0, 1),
      );
      final hits = controller.raycastAll(ray);
      expect(hits.map((hit) => hit.node.id), contains('curtain'));
      controller.dispose();
    });

    test('picking respects the render side (invisible faces are skipped)', () {
      final controller = _controller();
      final data = model();
      data.objects.add(
        ModelObject(
          id: 'ceiling',
          name: 'ceiling',
          kind: 'plane',
          x: 1,
          y: 2,
          z: 2,
          dims: const {'w': 4, 'd': 4},
          material: ModelMaterial(
            type: MaterialType.color,
            side: 'inner',
          ),
        ),
      );
      data.objects.add(box(id: 'below', x: 1, z: 2));
      controller.loadModelData(data);

      final ray = vm.Ray.originDirection(
        vm.Vector3(0.5, 6, 0.5),
        vm.Vector3(0, -1, 0),
      );
      final hits = controller.raycastAll(ray);
      expect(hits.map((hit) => hit.node.id), isNot(contains('ceiling')));
      expect(hits.map((hit) => hit.node.id), contains('below'));

      // Disabling the culling keeps the old double-sided behavior.
      final all = controller.raycastAll(
        ray,
        options: const RaycastOptions(respectCulling: false),
      );
      expect(all.map((hit) => hit.node.id), contains('ceiling'));
      controller.dispose();
    });

    test('unloadModel drops document nodes', () {
      final controller = _controller();
      controller.loadModelData(model());
      controller.addObject(box());
      controller.unloadModel();
      expect(controller.byId('obj_1'), isNull);
      expect(controller.nodesOfType<ModelNode>(), isEmpty);
      controller.dispose();
    });
  });
}
