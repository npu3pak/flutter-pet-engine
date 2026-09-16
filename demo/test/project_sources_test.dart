import 'package:demo/src/project_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Pet по умолчанию читается из папки projects/Pet', () {
    final source = sourceForProject('Pet');
    expect(source, isA<DirectoryProjectSource>());
    expect(
      (source as DirectoryProjectSource).root.path,
      endsWith('projects/Pet'),
    );
  });

  test('Streets читается из папки projects/Streets', () {
    final source = sourceForProject('Streets');
    expect(source, isA<DirectoryProjectSource>());
    expect(
      (source as DirectoryProjectSource).root.path,
      endsWith('projects/Streets'),
    );
  });

  test('биомные проекты читаются из папок projects/<Имя>', () {
    for (final name in const ['Dungeon', 'Forest', 'AbandonedBuilding']) {
      final source = sourceForProject(name);
      expect(source, isA<DirectoryProjectSource>(), reason: name);
      expect(
        (source as DirectoryProjectSource).root.path,
        endsWith('projects/$name'),
        reason: name,
      );
    }
  });

  test('биомные проекты открываются и содержат сцены', () async {
    for (final name in const ['Dungeon', 'Forest', 'AbandonedBuilding']) {
      final controller = SceneController();
      await controller.open(sourceForProject(name));
      expect(controller.resources?.modelIds, isNotEmpty, reason: name);
      controller.dispose();
    }
  });

  test('сцена из кода использует пустой источник', () {
    expect(sourceForProject(null), isA<EmptyProjectSource>());
  });

  test('эталонная сцена Pet читается и содержит кота', () async {
    final controller = SceneController();
    await controller.open(sourceForProject('Pet'));
    final resources = controller.resources!;
    expect(resources.modelIds, contains('model_2'));
    expect(resources.gltfEntry('cat'), isNotNull);
    expect(resources.textureKeys, isNotEmpty);
    controller.dispose();
  });
}
