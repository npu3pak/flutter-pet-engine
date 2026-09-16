import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/model_renderer.dart'
    show ModelRenderer;
import 'package:pet_engine/src/services/texture_cache.dart'
    show TextureCache;

ModelObject textured(String id, String key) => ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      dims: const {'w': 1, 'h': 1, 'd': 1},
      material: ModelMaterial(type: MaterialType.texture, key: key),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed read marks the key missing synchronously', () async {
    final cache = TextureCache(
      texturesDir: 'textures',
      spritesDir: 'sprites',
      byteLoader: (path) async => null,
    );
    expect(cache.isTextureMissing('wall.png'), isFalse);
    expect(await cache.texture('wall.png'), isNull);
    expect(cache.isTextureMissing('wall.png'), isTrue);
    expect(cache.isSpriteMissing('wall.png'), isFalse);
    await cache.sprite('wall.png');
    expect(cache.isSpriteMissing('wall.png'), isTrue);
  });

  test('invalidate drops the missing flags with the cache', () async {
    final cache = TextureCache(
      texturesDir: 'textures',
      byteLoader: (path) async => null,
    );
    await cache.texture('wall.png');
    expect(cache.isTextureMissing('wall.png'), isTrue);
    cache.invalidate();
    expect(cache.isTextureMissing('wall.png'), isFalse);
  });

  test('resolveMaterial renders fuchsia for a key settled as missing',
      () async {
    final cache = TextureCache(
      texturesDir: 'textures',
      byteLoader: (path) async => null,
    );
    await cache.texture('wall.png');
    final renderer = ModelRenderer(cache);
    final material = renderer.resolveMaterial(textured('a', 'wall.png'), '+x');
    expect(material, isA<PhysicallyBasedMaterial>());
    final pbr = material! as PhysicallyBasedMaterial;
    expect(pbr.baseColorFactor.x, 1.0);
    expect(pbr.baseColorFactor.y, 0.0);
    expect(pbr.baseColorFactor.z, 1.0);
  });

  test('resolveMaterial renders gray while a texture is still loading', () {
    final renderer = ModelRenderer(TextureCache());
    final material = renderer.resolveMaterial(textured('a', 'wall.png'), '+x');
    expect(material, isA<PhysicallyBasedMaterial>());
    final pbr = material! as PhysicallyBasedMaterial;
    expect(pbr.baseColorFactor.x, closeTo(0.78, 1e-5));
    expect(pbr.baseColorFactor.y, closeTo(0.78, 1e-5));
    expect(pbr.baseColorFactor.z, closeTo(0.78, 1e-5));
  });
}
