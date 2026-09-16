import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/engine/game_resource_manager.dart'
    show GameResourceManager;

/// The real Pet sample project (repo root).
final Directory petProjectDir =
    Directory('${Directory.current.path}/../projects/Pet');

void main() {
  group('GameResourceManager over the directory source', () {
    test('opens the Pet project: models, resources, gltf catalog', () async {
      final manager =
          GameResourceManager(DirectoryProjectSource(petProjectDir));
      await manager.open();

      expect(manager.name, 'Pet');
      expect(manager.modelIds, containsAll(['model_1', 'model_2']));
      expect(manager.model('model_2'), isNotNull);
      expect(manager.textureKeys, isNotEmpty);
      expect(manager.spriteKeys, isNotEmpty);
      expect(manager.gltfCatalogReady, isTrue);

      final entry = manager.gltfEntry('cat');
      expect(entry, isNotNull);
      expect(entry!.isFolder, isTrue);
      expect(entry.sourcePath, startsWith('3d_models/cat/'));
      expect(manager.gltfEntry('puppy'), isNotNull);
      expect(manager.gltfEntry('missing'), isNull);
    });

    test('scenes resolve model refs through the manager catalog', () async {
      final manager =
          GameResourceManager(DirectoryProjectSource(petProjectDir));
      await manager.open();
      final scene2 = manager.model('model_2')!;
      final ref = scene2.objects.firstWhere((o) => o.isModelRef);
      expect(manager.model(ref.refModelId), isNotNull);
    });
  });
}
