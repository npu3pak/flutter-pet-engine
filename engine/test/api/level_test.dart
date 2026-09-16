import 'dart:io' show Directory;

import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/level/level_baker.dart'
    show LevelMaterialHook;
import 'package:pet_engine/src/render/engine_material.dart';
import 'package:pet_engine/src/services/texture_cache.dart'
    show TextureCache;
import 'package:vector_math/vector_math.dart' as vm;

class _FakeBaker extends LevelBaker {
  _FakeBaker() : super(TextureCache());

  int bakes = 0;
  bool callHook = false;

  @override
  LevelBakeResult bake(
    ConstructionModel model, {
    bool collectStats = false,
    void Function()? onGeometryBuilt,
    LevelMaterialHook? onMaterial,
  }) {
    bakes++;
    onGeometryBuilt?.call();
    if (callHook) {
      onMaterial?.call(
        EngineMaterial.pbr(color: vm.Vector4(1, 0, 0, 1)),
        sprite: false,
        tags: {'a', 'b'},
      );
    }
    return LevelBakeResult(
      root: Node(name: 'baked:${model.id}'),
      nodes: const {},
      stats: LevelBakeStats(
        elements: model.elements.length,
        mergedMeshes: 0,
        batchMeshes: 0,
        separateNodes: model.elements.length,
        vertices: 0,
        triangles: 0,
      ),
      buildTime: Duration.zero,
    );
  }
}

Future<SceneController> _opened() async {
  final controller = SceneController();
  await controller.open(DirectoryProjectSource(Directory('../demo/assets/Pet')));
  return controller;
}

void main() {
  group('SceneController.loadLevel', () {
    test('loads through the loader and reports ready', () async {
      final controller = await _opened();
      final baker = _FakeBaker();
      final result = await controller.loadLevel(
        ConstructionModel(id: 'test'),
        baker: baker,
      );

      expect(result.baked, isNotNull);
      expect(result.errors, isEmpty);
      expect(baker.bakes, 1);
      expect(controller.status.isReady, isTrue);
      controller.dispose();
    });

    test('without an open project returns an error result', () async {
      final controller = SceneController();
      final result = await controller.loadLevel(ConstructionModel(id: 'x'));
      expect(result.baked, isNull);
      expect(result.hasErrors, isTrue);
      expect(result.errors.first.resource, 'уровень');
      controller.dispose();
    });

    test('forwards the material hook as SceneMaterial', () async {
      final controller = await _opened();
      final baker = _FakeBaker()..callHook = true;
      SceneMaterial? seen;
      List<String>? seenTags;
      await controller.loadLevel(
        ConstructionModel(id: 'test'),
        baker: baker,
        options: LevelBakeOptions(
          onMaterial:
              (material, {required bool sprite, required List<String> tags}) {
                seen = material;
                seenTags = tags;
              },
        ),
      );
      expect(seen, isNotNull);
      expect(seen!.isPbr, isTrue);
      expect(seenTags, ['a', 'b']);
      controller.dispose();
    });
  });

  group('SceneController.mountLevel', () {
    LevelBakeResult baked(String id) => LevelBakeResult(
      root: Node(name: 'baked:$id'),
      nodes: const {},
      stats: LevelBakeStats(
        elements: 0,
        mergedMeshes: 0,
        batchMeshes: 0,
        separateNodes: 0,
        vertices: 0,
        triangles: 0,
      ),
      buildTime: Duration.zero,
    );

    test('mounts, offsets and unmounts a level', () {
      final controller = SceneController();
      final node = controller.mountLevel(
        baked('a'),
        offset: vm.Matrix4.translation(vm.Vector3(1, 2, 3)),
      );
      expect(controller.level, same(node));
      expect(controller.byId(node.id), same(node));
      final offset = node.engine.raw.localTransform.getTranslation();
      expect(offset.x, 1);
      expect(offset.y, 2);
      expect(offset.z, 3);

      controller.unmountLevel();
      expect(controller.level, isNull);
      expect(controller.byId(node.id), isNull);
      controller.dispose();
    });

    test('mounting a second level replaces the first', () {
      final controller = SceneController();
      final first = controller.mountLevel(baked('a'));
      final second = controller.mountLevel(baked('b'));
      expect(controller.level, same(second));
      expect(controller.byId(first.id), isNull);
      expect(controller.byId(second.id), same(second));
      controller.dispose();
    });
  });
}
