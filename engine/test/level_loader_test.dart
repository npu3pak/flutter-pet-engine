import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';

ModelObject cuboid(String id, {ModelMaterial? material}) => ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: 0,
      y: 0,
      z: 0,
      dims: const {'w': 1, 'h': 1, 'd': 1},
      material: material,
    );

ModelMaterial textureMat(String key) =>
    ModelMaterial(type: MaterialType.texture, key: key);

ModelMaterial spriteMat(String key) =>
    ModelMaterial(type: MaterialType.sprite, key: key);

ConstructionModel modelWith(List<ModelObject> objects) =>
    ConstructionModel(id: 'level', name: 'Level', objects: objects);

class _MemorySource implements ProjectSource {
  _MemorySource(this.files);

  final Map<String, String> files;

  @override
  String get label => 'memory';

  @override
  bool get writable => false;

  @override
  Future<List<String>> listFiles(String relDir) async {
    final prefix = relDir.endsWith('/') ? relDir : '$relDir/';
    return files.keys.where((p) => p.startsWith(prefix)).toList()..sort();
  }

  @override
  Future<Uint8List?> readBytes(String relPath) async {
    final text = files[relPath];
    return text == null ? null : Uint8List.fromList(utf8.encode(text));
  }

  @override
  Future<String?> readText(String relPath) async => files[relPath];

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) async =>
      throw UnsupportedError('read-only');

  @override
  Future<void> writeText(String relPath, String text) async =>
      throw UnsupportedError('read-only');
}

GameResourceManager openManager(Map<String, String> files) {
  final manager = GameResourceManager(_MemorySource(files));
  return manager;
}

/// GPU-free baker: `LevelBaker.bake` needs Flutter GPU, the loader logic does
/// not — the fake keeps the stage/error tests running without a video card.
class _FakeBaker extends LevelBaker {
  _FakeBaker(super.textures);

  @override
  LevelBakeResult bake(
    ConstructionModel model, {
    bool collectStats = false,
    void Function()? onGeometryBuilt,
    BakedMaterialHook? onMaterial,
  }) {
    onGeometryBuilt?.call();
    return LevelBakeResult(
      root: Node(name: 'fake:${model.id}'),
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

LevelLoader loaderFor(
  GameResourceManager manager,
  ConstructionModel model, {
  bool openProject = true,
  List<LevelExtraResource> extraResources = const [],
  void Function(LevelLoadEvent event)? onEvent,
}) =>
    LevelLoader(
      resources: manager,
      model: model,
      openProject: openProject,
      extraResources: extraResources,
      onEvent: onEvent,
      baker: _FakeBaker(manager.textures),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectModelResources', () {
    test('collects element and face materials', () {
      final object = cuboid('a', material: textureMat('wall.png'));
      object.faces['south'] = spriteMat('window.png');
      final closure = collectModelResources(modelWith([object]).data);
      expect(closure.textureKeys, {'wall.png'});
      expect(closure.spriteKeys, {'window.png'});
    });

    test('walks model references recursively and records the missing ones',
        () {
      final leaf = cuboid('leaf', material: textureMat('leaf.png'));
      final mid = ModelObject(
        id: 'mid',
        name: 'mid',
        kind: modelRefKind,
        refModelId: 'leaf',
      );
      final root = ModelObject(
        id: 'root',
        name: 'root',
        kind: modelRefKind,
        refModelId: 'mid',
      );
      final missing = ModelObject(
        id: 'missing',
        name: 'missing',
        kind: modelRefKind,
        refModelId: 'ghost',
      );
      final closure = collectModelResources(
        modelWith([root, missing]).data,
        modelCatalog: (id) => switch (id) {
          'mid' => modelWith([mid]).data,
          'leaf' => modelWith([leaf]).data,
          _ => null,
        },
      );
      expect(closure.textureKeys, {'leaf.png'});
      expect(closure.modelIds, {'mid', 'leaf'});
      expect(closure.missingModelIds, {'ghost'});
    });

    test('collects gltf names', () {
      final object = ModelObject(
        id: 'cat',
        name: 'cat',
        kind: gltfRefKind,
        gltfName: 'cat',
      );
      final closure = collectModelResources(modelWith([object]).data);
      expect(closure.gltfNames, {'cat'});
    });

    test('a reference cycle terminates', () {
      final a = ModelObject(
        id: 'a',
        name: 'a',
        kind: modelRefKind,
        refModelId: 'b',
      );
      final b = ModelObject(
        id: 'b',
        name: 'b',
        kind: modelRefKind,
        refModelId: 'a',
      );
      final closure = collectModelResources(
        modelWith([a]).data,
        modelCatalog: (id) => modelWith([id == 'b' ? b : a]).data,
      );
      expect(closure.modelIds, {'a', 'b'});
    });
  });

  group('LevelLoader', () {
    test('runs the five stages, reports progress and bakes the level',
        () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
        'models/a.json': '{"format":"model_v1","id":"a"}',
      });
      final events = <LevelLoadEvent>[];
      final loader = loaderFor(
        manager,
        modelWith([cuboid('cube')]),
        onEvent: events.add,
      );
      final result = await loader.load();

      expect(result.baked, isNotNull);
      expect(result.errors, isEmpty);
      expect(manager.name, 'Тест');
      expect(events.first.kind, LevelLoadEventKind.started);
      expect(events.last.kind, LevelLoadEventKind.finished);
      expect(events.last.result, same(result));
      final stages = events
          .where((e) => e.kind == LevelLoadEventKind.progress)
          .map((e) => e.stage!)
          .toSet();
      expect(stages, LevelLoadStage.values.toSet());
      for (final event in events) {
        expect(event.fraction, inInclusiveRange(0, 1));
      }
      // The final progress of every stage is 1.
      for (final stage in LevelLoadStage.values) {
        final stageEvents = events.where((e) =>
            e.kind == LevelLoadEventKind.progress && e.stage == stage);
        expect(stageEvents.last.fraction, 1, reason: stage.name);
      }
    });

    test('a missing texture is reported and the level is still baked',
        () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
      });
      final loader = loaderFor(
        manager,
        modelWith([cuboid('wall', material: textureMat('nope.png'))]),
      );
      final result = await loader.load();
      expect(result.baked, isNotNull, reason: 'уровень показывается с заглушкой');
      expect(result.hasErrors, isTrue);
      expect(
        result.errors.map((e) => e.resource),
        contains('textures/nope.png'),
      );
      expect(result.errors.first.reason, isNotEmpty);
    });

    test('a missing sprite is reported', () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
      });
      final loader = loaderFor(
        manager,
        modelWith([cuboid('w', material: spriteMat('ghost.png'))]),
      );
      final result = await loader.load();
      expect(result.errors.map((e) => e.resource),
          contains('sprites/ghost.png'));
      expect(result.baked, isNotNull);
    });

    test('a missing model reference is reported', () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
      });
      final ref = ModelObject(
        id: 'house',
        name: 'house',
        kind: modelRefKind,
        refModelId: 'ghost_house',
      );
      final loader = loaderFor(manager, modelWith([ref]));
      final result = await loader.load();
      expect(result.errors.map((e) => e.resource),
          contains('models/ghost_house.json'));
      expect(result.baked, isNotNull);
    });

    test('a failing extra resource is reported by its label', () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
      });
      final loader = loaderFor(
        manager,
        modelWith([cuboid('cube')]),
        extraResources: [
          const LevelExtraResource('небо', _fail),
        ],
      );
      final result = await loader.load();
      expect(result.errors.map((e) => e.resource), contains('небо'));
      expect(result.baked, isNotNull);
    });

    test('an already-open manager skips project/model reads', () async {
      final manager = openManager({
        'project.json': '{"format":"project_v1","name":"Тест"}',
      });
      await manager.open();
      final events = <LevelLoadEvent>[];
      final loader = loaderFor(
        manager,
        modelWith([cuboid('cube')]),
        openProject: false,
        onEvent: events.add,
      );
      final result = await loader.load();
      expect(result.baked, isNotNull);
      final projectEvents = events.where(
          (e) => e.kind == LevelLoadEventKind.progress &&
              e.stage == LevelLoadStage.project);
      expect(projectEvents.map((e) => e.fraction), [0, 1]);
    });
  });
}

Future<void> _fail() async => throw StateError('ресурс потерян');
