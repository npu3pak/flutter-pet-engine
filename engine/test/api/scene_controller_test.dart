import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _MemorySource extends ProjectSource implements MutableProjectSource {
  _MemorySource([Map<String, Uint8List>? files]) : files = files ?? {};

  final Map<String, Uint8List> files;

  @override
  String get label => 'memory';

  @override
  bool get writable => true;

  @override
  Future<Uint8List?> readBytes(String relPath) async => files[relPath];

  @override
  Future<List<String>> listFiles(String relDir) async => [
    for (final key in files.keys)
      if (key.startsWith('$relDir/')) key,
  ];

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) async {
    files[relPath] = bytes;
  }

  @override
  Future<void> deleteBytes(String relPath) async {
    files.remove(relPath);
  }

  @override
  Future<void> renameBytes(String from, String to) async {
    final bytes = files.remove(from);
    if (bytes != null) files[to] = bytes;
  }
}

_MemorySource _projectSource() => _MemorySource({
  'project.json': Uint8List.fromList(
    utf8.encode('{"format":"project_v1","name":"Test"}'),
  ),
  'models/model_1.json': Uint8List.fromList(
    utf8.encode('{"format":"model_v1"}'),
  ),
  'models/model_2.json': Uint8List.fromList(
    utf8.encode('{"format":"model_v1"}'),
  ),
});

void main() {
  group('SceneController nodes', () {
    test('add, lookup, type filtering and removal', () {
      final controller = SceneController();
      final box = controller.add(BoxNode(id: 'box'));
      final sprite = controller.add(SpriteNode(id: 'sprite'));

      expect(controller.nodes, containsAll([box, sprite]));
      expect(controller.byId('box'), same(box));
      expect(box.scene, same(controller));
      expect(controller.nodesOfType<BoxNode>(), [box]);
      expect(controller.nodesOfType<SpriteNode>(), [sprite]);

      controller.remove(box);
      expect(controller.byId('box'), isNull);
      expect(controller.nodes, isNot(contains(box)));
      expect(box.isDisposed, isTrue);

      controller.dispose();
    });

    test('children are not roots and are tracked by id', () {
      final controller = SceneController();
      final group = controller.add(GroupNode(id: 'group'));
      final child = BoxNode(id: 'child');
      group.add(child);

      expect(controller.nodes, contains(group));
      expect(controller.nodes, isNot(contains(child)));
      expect(controller.byId('child'), same(child));
      expect(child.inScene, isTrue);

      controller.dispose();
      expect(group.isDisposed, isTrue);
      expect(child.isDisposed, isTrue);
    });

    test('unlinkChild tolerates an already detached engine node', () {
      final controller = SceneController();
      final group = controller.add(GroupNode(id: 'group'));
      final child = BoxNode(id: 'child');
      group.add(child);

      // Simulate a desynced engine mirror (the old subtree-detach bug): the
      // API tree still lists the child, its engine node is already detached.
      child.engine.detach();

      expect(() => group.removeAll(), returnsNormally);
      expect(group.children, isEmpty);
      expect(controller.byId('child'), isNull);
      controller.dispose();
    });

    test('cameraNode is attached to the controller', () {
      final controller = SceneController();
      expect(controller.cameraNode.inScene, isTrue);
      expect(controller.nodes, contains(controller.cameraNode));
      controller.dispose();
    });

    test('update after dispose is a no-op', () {
      final controller = SceneController();
      controller.add(BoxNode(id: 'box'));
      controller.dispose();
      expect(() => controller.update(0.016), returnsNormally);
    });

    test('frame listeners receive elapsed and delta', () {
      final controller = SceneController();
      final elapsed = <Duration>[];
      final deltas = <double>[];
      controller.addFrameListener((e, dt) {
        elapsed.add(e);
        deltas.add(dt);
      });
      controller.update(0.5);
      controller.update(0.25);
      expect(elapsed, const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 750),
      ]);
      expect(deltas, [0.5, 0.25]);
      controller.dispose();
    });
  });

  group('SceneController session', () {
    test('open reads the project and its models', () async {
      final controller = SceneController();
      await controller.open(_projectSource());

      expect(controller.status.isReady, isTrue);
      expect(controller.status.hasError, isFalse);
      final resources = controller.resources!;
      expect(resources.projectName, 'Test');
      expect(resources.writable, isTrue);
      expect(resources.modelIds, ['model_1', 'model_2']);
      expect(resources.model('model_1'), isNotNull);
      controller.dispose();
    });

    test('loadModel loads a catalog model and bumps the revision', () async {
      final controller = SceneController();
      await controller.open(_projectSource());
      final revision = controller.revision;

      expect(await controller.loadModel('model_1'), isTrue);
      expect(controller.modelId, 'model_1');
      expect(controller.model, isNotNull);
      expect(controller.revision, greaterThan(revision));

      expect(await controller.loadModel('missing'), isFalse);
      controller.unloadModel();
      expect(controller.model, isNull);
      expect(controller.modelId, isNull);
      controller.dispose();
    });

    test('failed open reports an error status', () async {
      final controller = SceneController();
      await controller.open(_ThrowingSource());
      expect(controller.status.hasError, isTrue);
      expect(controller.status.errors, isNotEmpty);
      controller.dispose();
    });

    test('reopen replaces the session', () async {
      final controller = SceneController();
      await controller.open(_projectSource());
      await controller.open(
        _MemorySource({
          'project.json': Uint8List.fromList(
            utf8.encode('{"format":"project_v1","name":"Other"}'),
          ),
        }),
      );
      expect(controller.resources!.projectName, 'Other');
      expect(controller.resources!.modelIds, isEmpty);
      controller.dispose();
    });
  });

  group('ProjectStore', () {
    test('create, save, rename and delete models', () async {
      final controller = SceneController();
      await controller.open(_projectSource());
      final store = controller.project;

      final created = store.createModel(id: 'model_3', name: 'Новая');
      expect(store.modelIds, contains('model_3'));
      expect(created.id, 'model_3');

      await store.saveModel(created);
      expect(controller.resources!.model('model_3'), isNotNull);

      await store.renameModel('model_3', 'model_4');
      expect(store.modelIds, contains('model_4'));
      expect(store.modelIds, isNot(contains('model_3')));
      expect(controller.resources!.model('model_4'), isNotNull);

      await store.deleteModel('model_4');
      expect(store.modelIds, isNot(contains('model_4')));
      controller.dispose();
    });

    test('the glTF catalog lists every 3d_models entry sorted', () async {
      final controller = SceneController();
      await controller.open(
        _MemorySource({
          'project.json': Uint8List.fromList(
            utf8.encode('{"format":"project_v1","name":"Test"}'),
          ),
          '3d_models/cat/scene.gltf': Uint8List.fromList(utf8.encode('{}')),
          '3d_models/rock.glb': Uint8List.fromList(const [1, 2, 3]),
        }),
      );
      final entries = controller.resources!.gltfEntries;
      expect(entries.map((e) => e.name), ['cat', 'rock']);
      expect(controller.resources!.gltfEntry('cat')!.isFolder, isTrue);
      expect(controller.resources!.gltfEntry('rock')!.isFolder, isFalse);
      controller.dispose();
    });
  });

  group('SceneController camera and billboards', () {
    test(
      'camera setter applies the matrix and disposes the old controller',
      () {
        final controller = SceneController();
        final matrixCamera = MatrixCameraController()
          ..matrix = vm.Matrix4.translation(vm.Vector3(1, 2, 3));
        controller.camera = matrixCamera;
        expect(controller.camera, same(matrixCamera));
        expect(controller.cameraNode.position.x, closeTo(1, 1e-5));
        expect(controller.cameraNode.position.y, closeTo(2, 1e-5));
        controller.dispose();
      },
    );

    test('billboards reorient to the camera each frame', () {
      final controller = SceneController();
      final sprite = controller.add(SpriteNode(billboard: true));
      final before = sprite.yaw;
      controller.camera = MatrixCameraController()
        ..matrix = vm.Matrix4.rotationY(0.7);
      controller.update(0.016);
      expect(sprite.yaw, isNot(before));
      controller.dispose();
    });
  });
}

class _ThrowingSource extends ProjectSource {
  @override
  String get label => 'broken';

  @override
  bool get writable => false;

  @override
  Future<Uint8List?> readBytes(String relPath) async => null;

  @override
  Future<List<String>> listFiles(String relDir) async {
    throw StateError('broken source');
  }

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) async {
    throw UnsupportedError('read-only');
  }
}
