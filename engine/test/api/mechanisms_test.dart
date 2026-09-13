import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('ParticleNode', () {
    test('holds config, field and focus', () {
      final node = ParticleNode(
        config: ParticleConfig(kind: ParticleKind.rain, sprites: const []),
        field: ParticleField(rows: 4, columns: 4),
      );
      expect(node.enabled, isTrue);
      expect(node.intensity, 1.0);
      expect(node.focus, isNull);
      expect(node.ready, isFalse);

      node.focus = vm.Vector3(1, 0, 2);
      node.intensity = 2;
      node.enabled = false;
      expect(node.focus!.x, 1);
      expect(node.intensity, 2);
      expect(node.enabled, isFalse);
      node.dispose();
    });

    test('windDirection falls back to the config', () {
      final config = ParticleConfig(
        kind: ParticleKind.wind,
        sprites: const [],
        windDirection: vm.Vector3(1, 0, 0),
      );
      final node = ParticleNode(
        config: config,
        field: ParticleField(rows: 2, columns: 2),
      );
      expect(node.windDirection!.x, 1);
      node.windDirection = vm.Vector3(0, 0, 1);
      expect(node.windDirection!.z, 1);
      node.dispose();
    });

    test(
      'prepare without sprites stays not ready and frameTick is safe',
      () async {
        final node = ParticleNode(
          config: ParticleConfig(kind: ParticleKind.snow, sprites: const []),
          field: ParticleField(rows: 2, columns: 2),
        );
        await node.prepare();
        expect(node.ready, isFalse);
        node.frameTick(const Duration(seconds: 1), 0.016);
        node.dispose();
      },
    );
  });

  group('SpriteFieldNode', () {
    test('prepare with no sprites is a no-op and update is safe', () async {
      final node = SpriteFieldNode(sprites: const [], capacity: 16);
      expect(node.ready, isFalse);
      await node.prepare();
      expect(node.ready, isFalse);
      node.update(const []);
      node.reset();
      node.dispose();
    });

    test('screenParallelYaw flows through to the layer', () {
      final node = SpriteFieldNode(sprites: const [], capacity: 16);
      expect(node.screenParallelYaw, 0.0);
      node.screenParallelYaw = 0.75;
      expect(node.screenParallelYaw, 0.75);
      // Repack keeps the stored yaw.
      node.update(const []);
      expect(node.screenParallelYaw, 0.75);
      node.dispose();
    });
  });

  group('GroundFogNode', () {
    test('prepare with no sprites is a no-op and update is safe', () async {
      final node = GroundFogNode(sprites: const [], capacity: 8);
      await node.prepare();
      expect(node.ready, isFalse);
      node.update(const []);
      node.reset();
      node.dispose();
    });
  });

  group('BillboardBatchNode', () {
    test('stores the batch parameters lazily', () {
      final node = BillboardBatchNode(
        capacity: 32,
        facing: BillboardFacing.screenParallel,
        blendMode: SpriteBlendMode.alpha,
        blendOrder: 3,
      );
      expect(node.capacity, 32);
      expect(node.facing, BillboardFacing.screenParallel);
      expect(node.blendMode, SpriteBlendMode.alpha);
      expect(node.blendOrder, 3);
      expect(node.instanceCount, 0);
      node.dispose();
    });
  });

  group('LevelNode', () {
    test('wraps a baked result and looks elements up', () {
      final root = Node(name: 'level-root');
      final element = Node(name: 'obj:house');
      final result = LevelBakeResult(
        root: root,
        nodes: {'house': element},
        stats: const LevelBakeStats(
          elements: 1,
          mergedMeshes: 0,
          batchMeshes: 0,
          separateNodes: 1,
          vertices: 0,
          triangles: 0,
        ),
        buildTime: Duration.zero,
      );
      final node = LevelNode(id: 'level', result: result);
      expect(node.result, same(result));

      final wrapped = node.nodeFor('house');
      expect(wrapped, isNotNull);
      expect(wrapped!.engine.raw, same(element));
      expect(node.nodeFor('missing'), isNull);

      node.syncToEngine();
      expect(node.engine.raw.children, contains(root));
      node.dispose();
    });
  });
}
