import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _MemorySource extends ProjectSource implements MutableProjectSource {
  _MemorySource(this.files);

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

/// A tiny chair-like source model (3×3 grid, one small box in the centre).
ModelData _sourceModel() => ModelData(
  id: 'model_1',
  name: 'Кресло',
  size: ModelSize(w: 3, l: 3, h: 3),
  objects: [
    ModelObject(
      id: 'seat',
      name: 'seat',
      kind: 'cuboid',
      x: 1,
      y: 0,
      z: 1,
      dims: const {'w': 1, 'h': 1.2, 'd': 1},
      material: ModelMaterial(type: MaterialType.color, color: const [180, 140, 90]),
    ),
  ],
);

/// The Pet room pieces around the north window: wall with a csg hole, the
/// window plane, two curtains and a model-instance chair.
ModelData _roomModel() => ModelData(
  id: 'model_2',
  name: 'Комната',
  size: ModelSize(w: 5, l: 5, h: 3),
  objects: [
    ModelObject(
      id: 'wall',
      name: 'Стена Север',
      kind: 'cuboid',
      x: 2,
      y: 0,
      z: -0.4,
      dims: const {'w': 5, 'h': 2.2, 'd': 0.2},
      material: ModelMaterial(type: MaterialType.texture, key: 'wallpaper.png'),
    ),
    ModelObject(
      id: 'hole',
      name: 'hole',
      kind: 'cuboid',
      x: 2,
      y: 0.5,
      z: -0.75,
      dims: const {'w': 1.25, 'h': 1.25, 'd': 1},
    ),
    ModelObject(
      id: 'wall_csg',
      name: 'Вычитание',
      kind: 'csg',
      op: csgOpDifference,
      operands: const ['wall', 'hole'],
      material: ModelMaterial(type: MaterialType.texture, key: 'wallpaper_blue.png'),
    ),
    ModelObject(
      id: 'window',
      name: 'Окно Север',
      kind: 'plane',
      x: 2,
      y: 0.425,
      z: -0.25,
      rotY: 180,
      dims: const {'w': 1.45, 'd': 1.45, 'vertical': 1},
      material: ModelMaterial(
        type: MaterialType.sprite,
        side: 'both',
        key: 'window.png',
      ),
    ),
    for (final (id, x) in const [('curtain_l', 1.136), ('curtain_r', 2.864)])
      ModelObject(
        id: id,
        name: id,
        kind: 'cuboid',
        x: x,
        y: 0.03,
        z: -0.213,
        dims: const {'w': 0.65, 'h': 2.2, 'd': 0.05},
        material: ModelMaterial(
          type: MaterialType.texture,
          key: 'curtain.png',
        ),
      ),
    ModelObject(
      id: 'chair',
      name: 'Кресло',
      kind: modelRefKind,
      x: 0.5,
      y: 0,
      z: 0.5,
      rotY: 325,
      refModelId: 'model_1',
      refSize: ModelSize(w: 3, l: 3, h: 3),
      scale: 0.6,
    ),
  ],
);

Future<SceneController> _openRoom() async {
  final controller = SceneController();
  await controller.open(
    _MemorySource({
      'project.json': Uint8List.fromList(
        utf8.encode('{"format":"project_v1","name":"Test"}'),
      ),
      'models/model_1.json': Uint8List.fromList(
        utf8.encode(jsonEncode(_sourceModel().toJson())),
      ),
      'models/model_2.json': Uint8List.fromList(
        utf8.encode(jsonEncode(_roomModel().toJson())),
      ),
    }),
  );
  await controller.loadModel('model_2');
  return controller;
}

vm.Ray _rayTo(vm.Vector3 target) {
  final origin = vm.Vector3(0, 1.2, 0);
  return vm.Ray.originDirection(
    origin,
    (target - origin).normalized(),
  );
}

void main() {
  group('Pet room picking', () {
    test('a ray through the old proxy gap misses the chair content', () async {
      final controller = await _openRoom();
      // Inside the old full-grid proxy (x 0.6..2.4, y 0..1.8, z −2.4..−0.6)
      // but above the seat content: the exact parts must not claim it.
      final hit = controller.raycastRay(_rayTo(vm.Vector3(0.75, 1.6, -1.0)));
      expect(hit?.node.id, isNot('chair'));
      controller.dispose();
    });

    test('clicking the left curtain picks the curtain', () async {
      final controller = await _openRoom();
      // Model (1.136, −0.213) → world (0.864, −2.213).
      final hit = controller.raycastRay(_rayTo(vm.Vector3(0.864, 1.1, -2.213)));
      expect(hit?.node.id, 'curtain_l');
      controller.dispose();
    });

    test('clicking the window divider picks the window sprite', () async {
      final controller = await _openRoom();
      final hit = controller.raycastRay(_rayTo(vm.Vector3(0, 1.1, -2.25)));
      expect(hit?.node.id, 'window');
      controller.dispose();
    });

    test('clicking the wall near the chair picks the wall', () async {
      final controller = await _openRoom();
      // Behind the chair (world x 1.5, z −1.5): the old full-grid proxy
      // intercepted this ray.
      final hit = controller.raycastRay(_rayTo(vm.Vector3(1.5, 1.0, -2.4)));
      expect(hit?.node.id, 'wall_csg');
      controller.dispose();
    });

    test('clicking the chair picks the chair', () async {
      final controller = await _openRoom();
      final hit = controller.raycastRay(_rayTo(vm.Vector3(1.5, 0.4, -1.5)));
      expect(hit?.node.id, 'chair');
      controller.dispose();
    });
  });
}
