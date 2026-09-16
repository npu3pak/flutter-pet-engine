import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('DynamicNodes', () {
    test('spawn attaches the node and tracks its age', () {
      final controller = SceneController();
      final node = RingNode();
      final object = controller.dynamics.spawn(
        id: 'target',
        node: node,
        position: vm.Vector3(1, 0, 2),
      );
      expect(object.alive, isTrue);
      expect(node.inScene, isTrue);
      expect(controller.dynamics.aliveCount, 1);
      expect(node.position.x, closeTo(1, 1e-5));

      controller.dynamics.update(0.5);
      expect(object.ageSeconds, const Duration(milliseconds: 500));
      expect(object.remaining, isNull);
      expect(object.remainingFactor, 1);
      controller.dispose();
    });

    test('lifetime expiry despawns and fires onFinished', () {
      final controller = SceneController();
      final finished = <String>[];
      controller.dynamics.spawn(
        id: 'spark',
        node: RingNode(),
        lifetime: const Duration(milliseconds: 100),
        onFinished: (object) => finished.add(object.id),
      );
      controller.dynamics.update(0.05);
      expect(controller.dynamics.aliveCount, 1);
      controller.dynamics.update(0.06);
      expect(controller.dynamics.aliveCount, 0);
      expect(finished, ['spark']);
      controller.dispose();
    });

    test('duplicate ids are rejected', () {
      final controller = SceneController();
      controller.dynamics.spawn(id: 'a', node: RingNode());
      expect(
        () => controller.dynamics.spawn(id: 'a', node: RingNode()),
        throwsArgumentError,
      );
      controller.dispose();
    });

    test('clear despawns without firing onFinished', () {
      final controller = SceneController();
      var finished = 0;
      controller.dynamics.spawn(
        id: 'a',
        node: RingNode(),
        onFinished: (_) => finished++,
      );
      controller.dynamics.clear();
      expect(controller.dynamics.aliveCount, 0);
      expect(finished, 0);
      controller.dispose();
    });

    test('sync reuses pooled nodes and updates entries', () {
      final controller = SceneController();
      var built = 0;
      SceneNode builder() {
        built++;
        return RingNode();
      }

      controller.dynamics.sync('enemies', [
        DynamicEntry(
          id: 'enemy:1',
          builder: builder,
          position: vm.Vector3(1, 0, 0),
        ),
        DynamicEntry(
          id: 'enemy:2',
          builder: builder,
          position: vm.Vector3(2, 0, 0),
        ),
      ]);
      expect(built, 2);
      expect(controller.dynamics.aliveCount, 2);

      controller.dynamics.sync('enemies', [
        DynamicEntry(
          id: 'enemy:1',
          builder: builder,
          position: vm.Vector3(5, 0, 0),
        ),
      ]);
      expect(controller.dynamics.aliveCount, 1);
      expect(built, 2);
      final object = controller.dynamics.byId('enemy:1')!;
      expect(object.node.position.x, closeTo(5, 1e-5));

      controller.dynamics.sync('enemies', [
        DynamicEntry(
          id: 'enemy:3',
          builder: builder,
          position: vm.Vector3(7, 0, 0),
        ),
      ]);
      expect(built, 3);
      expect(controller.dynamics.aliveCount, 1);
      controller.dispose();
    });

    test('onUpdate receives the object each frame', () {
      final controller = SceneController();
      final ticks = <double>[];
      controller.dynamics.spawn(
        id: 'mover',
        node: RingNode(),
        onUpdate: (object, dt) => ticks.add(dt),
      );
      controller.dynamics.update(0.1);
      controller.dynamics.update(0.2);
      expect(ticks, [0.1, 0.2]);
      controller.dispose();
    });
  });

  group('SkyboxNode', () {
    test('layers are ordered and removable', () {
      final sky = SkyboxNode(backgroundColor: const Color(0xFF102030));
      final gradient = SkyboxColorLayer(
        topColor: const Color(0xFF87CEEB),
        bottomColor: const Color(0xFFFFFFFF),
      );
      final stars = SkyboxStarsLayer(count: 100);
      sky.addLayer(gradient);
      sky.addLayer(stars);
      expect(sky.layers, [gradient, stars]);
      expect(sky.backgroundColor, const Color(0xFF102030));
      sky.removeLayer(gradient);
      expect(sky.layers, [stars]);
      sky.dispose();
    });

    test('controller exposes the active skybox', () {
      final controller = SceneController();
      expect(controller.skybox, isNull);
      final sky = controller.add(SkyboxNode());
      expect(controller.skybox, same(sky));
      controller.dispose();
    });
  });
}
