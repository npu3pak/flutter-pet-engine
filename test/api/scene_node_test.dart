import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _FakeHost implements SceneNodeHost {
  final attached = <SceneNode>[];
  final detached = <SceneNode>[];
  final changed = <SceneNode>[];
  final disposed = <SceneNode>[];

  @override
  void onNodeAttached(SceneNode node) => attached.add(node);

  @override
  void onNodeDetached(SceneNode node) => detached.add(node);

  @override
  void onNodeChanged(SceneNode node) => changed.add(node);

  @override
  void onNodeDisposed(SceneNode node) => disposed.add(node);
}

class _MaterialProbe extends BoxNode {
  _MaterialProbe({super.material});

  SceneMaterial effective() => effectiveMaterial(material);
}

void main() {
  group('SceneNode identity and state', () {
    test('generates unique ids and accepts explicit ones', () {
      final a = GroupNode();
      final b = GroupNode();
      final c = GroupNode(id: 'custom');
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
      expect(c.id, 'custom');
      a.dispose();
      b.dispose();
      c.dispose();
    });

    test('name, layer, visibility, opacity and highlight notify', () {
      final host = _FakeHost();
      final node = GroupNode(id: 'n')..attachToHost(host);
      host.changed.clear();

      node.name = 'lamp';
      expect(node.name, 'lamp');
      node.layer = SceneLayer.overlay;
      expect(node.layer, SceneLayer.overlay);
      node.visible = false;
      expect(node.visible, isFalse);
      node.opacity = 0.4;
      expect(node.opacity, 0.4);
      node.highlightColor = vm.Vector4(1, 0, 0, 1);
      expect(node.highlightColor, isNotNull);

      expect(host.changed.length, greaterThanOrEqualTo(5));
      node.remove();
    });

    test('opacity clamps to 0..1', () {
      final node = GroupNode();
      node.opacity = 2;
      expect(node.opacity, 1);
      node.opacity = -1;
      expect(node.opacity, 0);
      node.dispose();
    });
  });

  group('SceneNode attach and hierarchy', () {
    test('attach and detach flip inScene and notify the host', () {
      final host = _FakeHost();
      final node = GroupNode(id: 'g');
      expect(node.inScene, isFalse);

      node.attachToHost(host);
      expect(node.inScene, isTrue);
      expect(host.attached, [node]);

      node.detachFromHost();
      expect(node.inScene, isFalse);
      expect(host.detached, [node]);
      node.dispose();
    });

    test('group children attach with the parent subtree', () {
      final host = _FakeHost();
      final group = GroupNode(id: 'root');
      final child = GroupNode(id: 'child');
      final grandchild = GroupNode(id: 'grandchild');
      child.add(grandchild);
      group.add(child);

      expect(group.children, [child]);
      expect(child.parent, group);
      expect(grandchild.parent, child);

      group.attachToHost(host);
      expect(group.inScene, isTrue);
      expect(child.inScene, isTrue);
      expect(grandchild.inScene, isTrue);
      expect(
        host.attached.map((n) => n.id),
        containsAll(['root', 'child', 'grandchild']),
      );

      group.remove(child);
      expect(child.parent, isNull);
      expect(child.inScene, isFalse);
      expect(grandchild.inScene, isFalse);

      group.remove();
    });

    test('adding a child to an attached group attaches the child', () {
      final host = _FakeHost();
      final group = GroupNode(id: 'root')..attachToHost(host);
      final child = GroupNode(id: 'child')..attachToHost(host);
      expect(child.inScene, isTrue);

      group.add(child);
      expect(child.parent, group);
      expect(child.inScene, isTrue);
      expect(host.detached, contains(child));

      group.removeAll();
      expect(group.children, isEmpty);
      expect(child.inScene, isFalse);
      group.remove();
    });

    test('detach keeps the node alive', () {
      final host = _FakeHost();
      final group = GroupNode(id: 'root');
      final child = GroupNode(id: 'child');
      group.add(child);
      group.attachToHost(host);

      child.detach();
      expect(child.inScene, isFalse);
      expect(child.isDisposed, isFalse);
      expect(group.children, isEmpty);

      group.add(child);
      expect(child.inScene, isTrue);
      group.remove();
    });

    test('remove detaches and disposes', () {
      final host = _FakeHost();
      final node = GroupNode(id: 'n')..attachToHost(host);
      node.remove();
      expect(node.isDisposed, isTrue);
      expect(node.inScene, isFalse);
      expect(host.disposed, [node]);
    });
  });

  group('SceneNode transform', () {
    test('position, rotation and scale round-trip', () {
      final node = GroupNode();
      node.position = vm.Vector3(1, 2, 3);
      node.rotation = vm.Vector3(0.3, -0.7, 0.15);
      node.scale = vm.Vector3(2, 3, 4);

      expect(node.position.x, closeTo(1, 1e-5));
      expect(node.position.y, closeTo(2, 1e-5));
      expect(node.position.z, closeTo(3, 1e-5));
      expect(node.rotation.x, closeTo(0.3, 1e-5));
      expect(node.rotation.y, closeTo(-0.7, 1e-5));
      expect(node.rotation.z, closeTo(0.15, 1e-5));
      expect(node.scale.x, closeTo(2, 1e-5));
      expect(node.scale.y, closeTo(3, 1e-5));
      expect(node.scale.z, closeTo(4, 1e-5));
      node.dispose();
    });

    test('transform setter decomposes into TRS', () {
      final node = GroupNode();
      node.transform =
          vm.Matrix4.translation(vm.Vector3(5, 0, -2)) *
          vm.Matrix4.rotationY(1.2) *
          vm.Matrix4.diagonal3Values(2, 2, 2);

      expect(node.position.x, closeTo(5, 1e-5));
      expect(node.position.z, closeTo(-2, 1e-5));
      expect(node.rotation.y, closeTo(1.2, 1e-5));
      expect(node.scale.x, closeTo(2, 1e-5));
      node.dispose();
    });

    test('globalTransform walks the parent chain', () {
      final parent = GroupNode()..position = vm.Vector3(10, 0, 0);
      final child = GroupNode()..position = vm.Vector3(0, 1, 0);
      parent.add(child);
      final world = child.globalTransform.getTranslation();
      expect(world.x, closeTo(10, 1e-5));
      expect(world.y, closeTo(1, 1e-5));
      parent.remove();
    });
  });

  group('SceneNode bounds', () {
    test('box bounds follow position and size', () {
      final box = BoxNode(size: vm.Vector3(2, 2, 2));
      box.position = vm.Vector3(1, 0, 0);
      final bounds = box.worldBounds!;
      expect(bounds.min.x, closeTo(0, 1e-5));
      expect(bounds.max.x, closeTo(2, 1e-5));
      expect(bounds.min.y, closeTo(-1, 1e-5));
      box.remove();
    });

    test('group bounds union children', () {
      final group = GroupNode();
      final a = BoxNode(size: vm.Vector3(2, 2, 2))
        ..position = vm.Vector3(-2, 0, 0);
      final b = BoxNode(size: vm.Vector3(2, 2, 2))
        ..position = vm.Vector3(2, 0, 0);
      group.add(a);
      group.add(b);
      final bounds = group.worldBounds!;
      expect(bounds.min.x, closeTo(-3, 1e-5));
      expect(bounds.max.x, closeTo(3, 1e-5));
      group.remove();
    });

    test('ring and line bounds are computed from geometry', () {
      final ring = RingNode(radius: 1, thickness: 0.2);
      final ringBounds = ring.worldBounds!;
      expect(ringBounds.max.x, closeTo(1, 1e-5));
      ring.remove();

      final line = LineNode(
        geometry: LineGeometry([
          vm.Vector3.zero(),
          vm.Vector3(0, 3, 0),
        ], width: 0.1),
      );
      final lineBounds = line.worldBounds!;
      expect(lineBounds.max.y, closeTo(3.05, 1e-5));
      line.remove();
    });
  });

  group('SceneNode material', () {
    test('material changes notify listeners and the host', () {
      final host = _FakeHost();
      final node = GroupNode(id: 'n')..attachToHost(host);
      final material = SceneMaterial.pbr(color: const Color(0xFFFF0000));
      node.material = material;
      expect(node.material, same(material));
      host.changed.clear();

      material.color = const Color(0xFF00FF00);
      expect(host.changed, contains(node));
      node.remove();
    });

    test('box and plane carry default materials', () {
      final box = BoxNode();
      expect(box.material.isPbr, isTrue);
      box.remove();
      final plane = PlaneNode(width: 1, depth: 1);
      expect(plane.material.isPbr, isTrue);
      plane.remove();
    });

    test('opacity renders through a per-node material copy', () {
      final base = SceneMaterial.unlit(color: const Color(0x80FF0000));
      final node = _MaterialProbe(material: base);
      expect(node.effective(), same(base));

      node.opacity = 0.5;
      final dimmed = node.effective();
      expect(dimmed, isNot(same(base)));
      expect(dimmed.color.a, closeTo(base.color.a * 0.5, 1e-4));
      expect(dimmed.alphaMode, SceneAlphaMode.blend);
      expect(base.alphaMode, SceneAlphaMode.opaque);
      expect(node.effective(), same(dimmed));

      final other = _MaterialProbe(material: base);
      expect(other.effective(), same(base));

      base.color = const Color(0x80FF00FF);
      expect(node.effective(), isNot(same(dimmed)));

      node.opacity = 1;
      expect(node.effective(), same(base));
      node.remove();
      other.remove();
      base.dispose();
    });
  });

  group('LineNode width', () {
    test('width lives on the geometry and updates bounds', () {
      final geometry = LineGeometry([
        vm.Vector3.zero(),
        vm.Vector3(0, 3, 0),
      ], width: 0.1);
      expect(geometry.localBounds!.max.y, closeTo(3.05, 1e-5));

      final node = LineNode(geometry: geometry);
      expect(node.width, 0.1);
      node.width = 0.5;
      expect(geometry.width, 0.5);
      expect(geometry.localBounds!.max.y, closeTo(3.25, 1e-5));

      final explicit = LineNode(geometry: geometry, width: 0.2);
      expect(explicit.width, 0.2);
      expect(geometry.width, 0.2);
      node.remove();
      explicit.remove();
    });
  });
}
