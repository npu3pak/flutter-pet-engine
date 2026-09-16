import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

ModelData _model() =>
    ModelData(id: 'm', name: 'M', size: ModelSize(w: 4, l: 4, h: 3));

ModelObject _box({String id = 'obj_1'}) => ModelObject(
  id: id,
  name: 'box',
  kind: 'cuboid',
  x: 1,
  y: 0,
  z: 2,
  dims: {'w': 2, 'h': 1, 'd': 2},
);

void main() {
  group('SceneController document', () {
    test('addObject requires a loaded document', () {
      final controller = SceneController();
      expect(() => controller.addObject(_box()), throwsStateError);
      controller.dispose();
    });

    test('add, find and remove objects', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final revision = controller.revision;

      final node = controller.addObject(_box());
      expect(node.kind, 'cuboid');
      expect(controller.model!.objects, hasLength(1));
      expect(controller.revision, greaterThan(revision));
      expect(controller.objectNode('obj_1'), isNotNull);

      controller.removeObject(node.object);
      expect(controller.model!.objects, isEmpty);
      expect(controller.objectNode('obj_1'), isNull);
      controller.dispose();
    });

    test('metas, lights and groups mutate the document', () {
      final controller = SceneController();
      controller.loadModelData(_model());

      final meta = ModelMeta(id: 'meta_1', kind: metaKindMarker, name: '');
      controller.addMeta(meta);
      expect(controller.model!.metas, [meta]);
      controller.removeMeta(meta);
      expect(controller.model!.metas, isEmpty);

      final light = ModelLight(id: 'light_1', kind: lightKindPoint);
      controller.addDocumentLight(light);
      expect(controller.model!.lighting.lights, [light]);
      controller.removeDocumentLight(light);
      expect(controller.model!.lighting.lights, isEmpty);

      final group = ModelGroup(id: 'group_1', name: 'G');
      controller.addGroup(group);
      expect(controller.model!.groups, [group]);
      controller.removeGroup(group);
      expect(controller.model!.groups, isEmpty);
      controller.dispose();
    });
  });

  group('ModelNode placement', () {
    test('worldPosition and worldBounds use the mirrored frame', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());

      expect(node.worldPosition.x, closeTo(0.5, 1e-6));
      expect(node.worldPosition.z, closeTo(0.5, 1e-6));

      final bounds = node.worldBounds;
      expect(bounds.min.x, closeTo(-0.5, 1e-6));
      expect(bounds.max.x, closeTo(1.5, 1e-6));
      expect(bounds.min.y, closeTo(0, 1e-6));
      expect(bounds.max.y, closeTo(1, 1e-6));
      controller.dispose();
    });

    test('setPlacement and setWorldPlacement update the object', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());

      node.setPlacement(x: 2, y: 1, rotY: 90);
      expect(node.object.x, 2);
      expect(node.object.y, 1);
      expect(node.object.rotY, 90);

      node.setWorldPlacement(x: 0.5, z: 0.5);
      expect(node.object.x, closeTo(1, 1e-6));
      expect(node.object.z, closeTo(2, 1e-6));
      controller.dispose();
    });
  });

  group('ModelNode materials', () {
    test('exposes document faces', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());
      final keys = node.faces.map((face) => face.key).toSet();
      expect(keys, contains('+z'));
      expect(keys, contains('-y'));
      expect(node.faces.first.node, same(node));
      controller.dispose();
    });

    test('setTexture and setColor mutate the document material', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());

      node.setTexture('wallpaper_beige.png');
      expect(node.object.material!.type, MaterialType.texture);
      expect(node.object.material!.key, 'wallpaper_beige.png');

      node.setColor(const Color(0xFF808080));
      expect(node.object.material!.type, MaterialType.color);
      expect(node.object.material!.color, [128, 128, 128]);

      node.setTexture('window_4.png', faceKey: '+z', fromSprites: true);
      final face = node.object.faces['+z']!;
      expect(face.type, MaterialType.sprite);
      expect(face.key, 'window_4.png');
      controller.dispose();
    });
  });

  group('ModelNode glTF', () {
    test('non-glTF objects expose no clips and ignore play', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());
      expect(node.isGltf, isFalse);
      expect(node.gltfName, isEmpty);
      expect(node.animationClips, isEmpty);
      expect(node.gltfBounds, isNull);
      node.play('walk');
      expect(node.animation, isEmpty);
      controller.dispose();
    });
  });
}
