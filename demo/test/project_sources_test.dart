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

  test('House читается из папки projects/House', () {
    final source = sourceForProject('House');
    expect(source, isA<DirectoryProjectSource>());
    expect(
      (source as DirectoryProjectSource).root.path,
      endsWith('projects/House'),
    );
  });

  test('House открывается и содержит модель house', () async {
    final controller = SceneController();
    await controller.open(sourceForProject('House'));
    final resources = controller.resources!;
    expect(resources.modelIds, contains('house'));
    expect(resources.textureKeys, isNotEmpty);
    expect(resources.spriteKeys, isNotEmpty);
    controller.dispose();
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
