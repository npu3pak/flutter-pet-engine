import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/model_renderer.dart'
    show ModelRenderer;
import 'package:pet_engine/src/services/texture_cache.dart'
    show TextureCache;

ModelObject tagged(String id, String? tag) => ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      dims: const {'w': 1, 'h': 1, 'd': 1},
      material:
          ModelMaterial(type: MaterialType.color, color: const [10, 20, 30]),
      tag: tag,
    );

void main() {
  test('the same spec with different tags resolves to distinct materials', () {
    final renderer = ModelRenderer(TextureCache());
    final a = renderer.resolveMaterial(tagged('a', 'wall_0'), '+x');
    final b = renderer.resolveMaterial(tagged('b', 'wall_1'), '+x');
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(identical(a, b), isFalse,
        reason: 'тег входит в идентичность материала (рецепты по направлениям)');
  });

  test('the same tag still shares one material instance', () {
    final renderer = ModelRenderer(TextureCache());
    final a = renderer.resolveMaterial(tagged('a', 'wall_0'), '+x');
    final b = renderer.resolveMaterial(tagged('b', 'wall_0'), '+x');
    expect(identical(a, b), isTrue);
  });

  test('untagged objects share as before', () {
    final renderer = ModelRenderer(TextureCache());
    final a = renderer.resolveMaterial(tagged('a', null), '+x');
    final b = renderer.resolveMaterial(tagged('b', null), '+x');
    expect(identical(a, b), isTrue);
  });
}
