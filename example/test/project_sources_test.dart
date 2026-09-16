import 'package:example/src/project_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Pet читается из ассетов example/assets/Pet', () {
    final source = sourceForProject('Pet');
    expect(source, isA<AssetProjectSource>());
    expect((source as AssetProjectSource).assetPrefix, 'assets/Pet/');
  });

  test('House читается из ассетов example/assets/House', () {
    final source = sourceForProject('House');
    expect(source, isA<AssetProjectSource>());
    expect((source as AssetProjectSource).assetPrefix, 'assets/House/');
  });

  test('Pet открывается: модели, glTF-кот, текстуры и спрайты', () async {
    final controller = SceneController();
    await controller.open(sourceForProject('Pet'));
    final resources = controller.resources!;
    expect(resources.modelIds, containsAll(['model_1', 'model_2']));
    expect(resources.gltfEntry('cat'), isNotNull);
    expect(resources.textureKeys, isNotEmpty);
    expect(resources.spriteKeys, isNotEmpty);
    controller.dispose();
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
}
