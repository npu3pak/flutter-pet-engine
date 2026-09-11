import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _StubVisual extends DynamicVisual {
  _StubVisual(this.poolKey);

  @override
  final String poolKey;

  int created = 0;
  int disposed = 0;
  final List<double?> yaws = [];

  @override
  Node createNode(DynamicObject object) {
    created++;
    return Node(name: 'stub:$poolKey');
  }

  @override
  void updateNode(
    DynamicObject object,
    Node node,
    double dt, {
    double? billboardYaw,
  }) {
    yaws.add(billboardYaw);
  }

  @override
  void disposeNode(Node node) => disposed++;
}

void main() {
  group('DynamicWorld.spawn', () {
    test('creates a live object with a node on its layer root', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      final object = world.spawn(
        id: 'a',
        visual: visual,
        layer: 3,
        position: vm.Vector3(1, 2, 3),
      );

      expect(object.alive, isTrue);
      expect(world.aliveCount, 1);
      expect(world.contains('a'), isTrue);
      expect(world.byId('a'), same(object));
      expect(object.node, isNotNull);
      expect(object.node!.parent, isNotNull);
      expect(object.node!.parent!.name, 'dynamic-layer-3');
      expect(world.root.children, contains(object.node!.parent));
      expect(visual.created, 1);
    });

    test('copies the spawn parameters onto the object', () {
      final world = DynamicWorld();
      final object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        rotationY: 1.5,
        width: 2,
        height: 3,
        opacity: 0.5,
        tint: vm.Vector3(0.1, 0.2, 0.3),
        visible: false,
        facing: DynamicFacing.fixed,
        lifetime: const Duration(seconds: 2),
        userData: 'payload',
      );

      expect(object.rotationY, 1.5);
      expect(object.width, 2);
      expect(object.height, 3);
      expect(object.opacity, 0.5);
      expect(object.tint, vm.Vector3(0.1, 0.2, 0.3));
      expect(object.visible, isFalse);
      expect(object.facing, DynamicFacing.fixed);
      expect(object.lifetime, const Duration(seconds: 2));
      expect(object.userData, 'payload');
    });

    test('throws on a duplicate live id and allows reuse after despawn', () {
      final world = DynamicWorld();
      final first = world.spawn(id: 'a', visual: _StubVisual('sprite'));
      expect(
        () => world.spawn(id: 'a', visual: _StubVisual('sprite')),
        throwsStateError,
      );
      first.despawn();
      final second = world.spawn(id: 'a', visual: _StubVisual('sprite'));
      expect(second.alive, isTrue);
    });

    test('throws after dispose', () {
      final world = DynamicWorld()..dispose();
      expect(
        () => world.spawn(id: 'a', visual: _StubVisual('sprite')),
        throwsStateError,
      );
    });
  });

  group('lifecycle', () {
    test('lifetime expiry despawns and fires onFinished once', () {
      final world = DynamicWorld();
      var finished = 0;
      final object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        lifetime: const Duration(milliseconds: 100),
        onFinished: (_) => finished++,
      );

      world.update(0.05);
      expect(object.alive, isTrue);
      expect(finished, 0);

      world.update(0.06);
      expect(object.alive, isFalse);
      expect(finished, 1);
      expect(world.aliveCount, 0);
      expect(world.contains('a'), isFalse);
      expect(object.node, isNull);

      world.update(1.0);
      expect(finished, 1);
    });

    test('manual despawn is idempotent and fires onFinished once', () {
      final world = DynamicWorld();
      var finished = 0;
      final object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        onFinished: (_) => finished++,
      );

      object.despawn();
      object.despawn();
      world.despawn(object);

      expect(finished, 1);
      expect(world.aliveCount, 0);
      expect(object.alive, isFalse);
      expect(object.node, isNull);
    });

    test('remaining counts down from the lifetime', () {
      final world = DynamicWorld();
      final object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        lifetime: const Duration(seconds: 1),
      );
      world.update(0.25);
      expect(object.remaining!.inMilliseconds, 750);
      object.lifetime = null;
      expect(object.remaining, isNull);
    });

    test('clear removes every object without firing onFinished', () {
      final world = DynamicWorld();
      var finished = 0;
      final first = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        onFinished: (_) => finished++,
      );
      world.spawn(
        id: 'b',
        visual: _StubVisual('sprite'),
        onFinished: (_) => finished++,
      );

      world.clear();

      expect(world.aliveCount, 0);
      expect(world.contains('a'), isFalse);
      expect(finished, 0);
      expect(first.alive, isFalse);
      expect(first.node, isNull);
    });
  });

  group('node pool', () {
    test('reuses nodes of the same pool key across spawns', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      final first = world.spawn(id: 'a', visual: visual);
      final firstNode = first.node;
      first.despawn();
      final second = world.spawn(id: 'b', visual: visual);

      expect(visual.created, 1);
      expect(second.node, same(firstNode));
    });

    test('does not reuse nodes while the previous object is alive', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      world.spawn(id: 'a', visual: visual);
      world.spawn(id: 'b', visual: visual);
      expect(visual.created, 2);
    });

    test('keeps separate pools per pool key', () {
      final world = DynamicWorld();
      final sprites = _StubVisual('sprite');
      final quads = _StubVisual('quad');
      world.spawn(id: 'a', visual: sprites).despawn();
      world.spawn(id: 'b', visual: quads).despawn();
      world.spawn(id: 'c', visual: sprites);
      world.spawn(id: 'd', visual: quads);

      expect(sprites.created, 1);
      expect(quads.created, 1);
    });

    test('dispose disposes pooled and live nodes', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      world.spawn(id: 'a', visual: visual);
      world.spawn(id: 'b', visual: visual).despawn();

      world.dispose();

      expect(visual.disposed, 2);
      expect(world.root.children, isEmpty);
    });
  });

  group('layers', () {
    test('renders layers in ascending order regardless of creation order', () {
      final world = DynamicWorld();
      world.spawn(id: 'late', visual: _StubVisual('sprite'), layer: 5);
      world.spawn(id: 'early', visual: _StubVisual('sprite'), layer: 1);

      expect(
        world.root.children.map((n) => n.name).toList(),
        ['dynamic-layer-1', 'dynamic-layer-5'],
      );
    });

    test('each layer has its own root', () {
      final world = DynamicWorld();
      final a = world.spawn(id: 'a', visual: _StubVisual('sprite'), layer: 0);
      final b = world.spawn(id: 'b', visual: _StubVisual('sprite'), layer: 1);
      expect(a.node!.parent, isNot(same(b.node!.parent)));
    });
  });

  group('update', () {
    test('ticks onUpdate with the delta and can despawn from it', () {
      final world = DynamicWorld();
      final deltas = <double>[];
      late DynamicObject object;
      object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        onUpdate: (o, dt) {
          deltas.add(dt);
          if (deltas.length == 2) o.despawn();
        },
      );

      world.update(0.1);
      world.update(0.2);
      expect(deltas, [0.1, 0.2]);
      expect(object.alive, isFalse);
      expect(world.aliveCount, 0);

      world.update(0.3);
      expect(deltas, [0.1, 0.2]);
    });

    test('passes the billboard yaw for camera-facing objects only', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      final billboard = world.spawn(id: 'b', visual: visual);
      final fixed = world.spawn(
        id: 'f',
        visual: visual,
        facing: DynamicFacing.fixed,
        rotationY: 0.25,
      );
      visual.yaws.clear();

      final forward = vm.Vector3(1, 0, 0);
      world.update(1 / 60, cameraForward: forward);

      final expected = screenParallelYaw(forward.x, forward.z);
      expect(visual.yaws, [expected, null]);
      expect(billboard.facing, DynamicFacing.billboard);
      expect(fixed.rotationY, 0.25);
    });

    test('keeps authored rotation when no camera forward is supplied', () {
      final world = DynamicWorld();
      final visual = _StubVisual('sprite');
      world.spawn(id: 'a', visual: visual);
      visual.yaws.clear();

      world.update(1 / 60);

      expect(visual.yaws, [null]);
    });

    test('applies the object highlight to its node', () {
      final world = DynamicWorld();
      final object = world.spawn(id: 'a', visual: _StubVisual('sprite'));
      expect(object.node!.highlightColor, isNull);

      object.highlightColor = vm.Vector4(1, 0.8, 0, 1);
      world.update(1 / 60);
      expect(object.node!.highlightColor, vm.Vector4(1, 0.8, 0, 1));

      object.highlightColor = null;
      world.update(1 / 60);
      expect(object.node!.highlightColor, isNull);
    });

    test('fires onEnteredFrame once when the predicate turns true', () {
      final world = DynamicWorld();
      var entered = 0;
      final object = world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        onEnteredFrame: (_) => entered++,
      );

      world.update(0.1, isInFrame: (_) => false);
      expect(entered, 0);
      expect(object.enteredFrame, isFalse);

      world.update(0.1, isInFrame: (_) => true);
      expect(entered, 1);
      expect(object.enteredFrame, isTrue);

      world.update(0.1, isInFrame: (_) => true);
      expect(entered, 1);
    });

    test('does not fire onEnteredFrame without a predicate', () {
      final world = DynamicWorld();
      var entered = 0;
      world.spawn(
        id: 'a',
        visual: _StubVisual('sprite'),
        onEnteredFrame: (_) => entered++,
      );
      world.update(0.1);
      expect(entered, 0);
    });
  });

  group('dynamicSpriteTransform', () {
    test('mirrors X, scales the unit quad and translates', () {
      final m = dynamicSpriteTransform(
        position: vm.Vector3(4, 5, 6),
        width: 2,
        height: 3,
        yaw: 0,
      );
      expect(m.getTranslation(), vm.Vector3(4, 5, 6));
      expect(m.storage[0], -2); // mirrored X × width
      expect(m.storage[5], closeTo(0, 1e-12)); // rotX(π/2) top
      expect(m.storage[9], closeTo(-3, 1e-12)); // depth × height maps to -Y
    });
  });
}
