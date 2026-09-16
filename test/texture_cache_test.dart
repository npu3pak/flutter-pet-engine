import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/src/services/texture_cache.dart'
    show TextureCache;

void main() {
  group('TextureCache', () {
    test('texture and sprite futures are cached per family', () async {
      final dir = await Directory.systemTemp.createTemp('texture_cache_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = TextureCache(
        texturesDir: dir.path,
        spritesDir: dir.path,
      );
      // Both families resolve to null here (no files) — the point is the
      // future IDENTITY: a file name present in BOTH folders must not
      // resolve to the other family's cached future.
      final tex = cache.texture('k.png');
      final sprite = cache.sprite('k.png');
      expect(identical(tex, sprite), isFalse);
      expect(identical(tex, cache.texture('k.png')), isTrue);
      expect(identical(sprite, cache.sprite('k.png')), isTrue);
      expect(await tex, isNull);
      expect(await sprite, isNull);
      expect(cache.textureSize('k.png'), isNull);
      expect(cache.spriteSize('k.png'), isNull);
      expect(cache.isTextureMissing('k.png'), isTrue);
      expect(cache.isSpriteMissing('k.png'), isTrue);
    });

    test('setRoot drops the future cache and sizes', () async {
      final dir = await Directory.systemTemp.createTemp('texture_cache_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = TextureCache(texturesDir: dir.path);
      final f1 = cache.texture('k.png');
      cache.setRoot('${dir.path}/other');
      final f2 = cache.texture('k.png');
      expect(identical(f1, f2), isFalse);
      expect(cache.textureSize('k.png'), isNull);
    });

    test('invalidate drops the caches', () async {
      final dir = await Directory.systemTemp.createTemp('texture_cache_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = TextureCache(texturesDir: dir.path);
      final f1 = cache.texture('k.png');
      cache.invalidate();
      final f2 = cache.texture('k.png');
      expect(identical(f1, f2), isFalse);
    });
  });
}
