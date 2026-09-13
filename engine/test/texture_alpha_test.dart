import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pet_engine_v2/src/services/texture_alpha.dart';

/// Encodes a W×H RGBA PNG with the given alpha channel [draw].
Uint8List _png(int w, int h, void Function(img.Image im) draw) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  draw(image);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('analyzeTextureAlpha', () {
    test('fully opaque texture has no transparent/semi texels', () async {
      final bytes = _png(64, 64, (im) {
        img.fill(im, color: img.ColorRgba8(200, 100, 50, 255));
      });
      final stats = await analyzeTextureAlpha(bytes);
      expect(stats, isNotNull);
      expect(stats!.transparent, 0);
      expect(stats.semiTransparent, 0);
      expect(stats.total, greaterThan(0));
    });

    test('binary alpha (0/255) counts only transparent texels', () async {
      final bytes = _png(32, 32, (im) {
        for (var y = 0; y < 32; y++) {
          for (var x = 0; x < 32; x++) {
            final inside = (x + y) % 2 == 0;
            im.setPixelRgba(
              x,
              y,
              100,
              100,
              100,
              inside ? 255 : 0,
            );
          }
        }
      });
      final stats = await analyzeTextureAlpha(bytes);
      expect(stats, isNotNull);
      expect(stats!.semiTransparent, 0);
      expect(stats.transparent, greaterThan(0));
    });

    test('smooth semi-transparent block is counted', () async {
      final bytes = _png(64, 64, (im) {
        img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
        img.fillRect(
          im,
          x1: 0,
          y1: 0,
          x2: 63,
          y2: 63,
          color: img.ColorRgba8(120, 120, 120, 128),
        );
      });
      final stats = await analyzeTextureAlpha(bytes);
      expect(stats, isNotNull);
      expect(stats!.semiTransparent, greaterThan(0));
    });
  });

  group('classifyTextureAlpha', () {
    const opaque = TextureAlphaStats(total: 100, transparent: 0, semiTransparent: 0);
    const binary = TextureAlphaStats(total: 100, transparent: 40, semiTransparent: 0);
    const aaEdge = TextureAlphaStats(total: 100, transparent: 40, semiTransparent: 2);
    const smooth = TextureAlphaStats(total: 100, transparent: 10, semiTransparent: 60);

    test('picks opaque for fully opaque textures', () {
      expect(classifyTextureAlpha(opaque), TextureAlphaKind.opaqueOnly);
    });

    test('picks mask for binary alpha', () {
      expect(classifyTextureAlpha(binary), TextureAlphaKind.binaryMask);
    });

    test('picks mask for a thin AA fringe under 5% semi', () {
      expect(classifyTextureAlpha(aaEdge), TextureAlphaKind.binaryMask);
    });

    test('keeps blend for real smooth translucency', () {
      expect(classifyTextureAlpha(smooth), TextureAlphaKind.smoothBlend);
    });
  });

  group('blendMaterialImageUris', () {
    /// A glTF document with [materials], a single mesh whose primitives use
    /// them in order, and the given images/textures.
    Map<String, Object?> doc({
      required List<Object?> materials,
      List<Object?>? images,
      List<Object?>? textures,
    }) =>
        {
          'materials': materials,
          'images': images ??
              [
                {'uri': 'textures/diffuse.png'},
              ],
          'textures': textures ??
              [
                {'source': 0},
              ],
          'meshes': [
            {
              'primitives': [
                for (var i = 0; i < materials.length; i++) {'material': i},
              ],
            },
          ],
        };

    test('maps a specular-glossiness BLEND material to its diffuse URI', () {
      final d = doc(materials: [
        {
          'alphaMode': 'BLEND',
          'extensions': {
            'KHR_materials_pbrSpecularGlossiness': {
              'diffuseTexture': {'index': 0},
            },
          },
        },
      ]);
      expect(blendMaterialImageUris(d), ['textures/diffuse.png']);
    });

    test('maps a metallic-roughness BLEND baseColorTexture', () {
      final d = doc(materials: [
        {
          'alphaMode': 'BLEND',
          'pbrMetallicRoughness': {
            'baseColorTexture': {'index': 0},
          },
        },
      ]);
      expect(blendMaterialImageUris(d), ['textures/diffuse.png']);
    });

    test('skips OPAQUE materials, data: URIs and GLB-embedded images', () {
      final d = doc(
        materials: [
          {
            'alphaMode': 'OPAQUE',
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 0},
            },
          },
          {
            'alphaMode': 'BLEND',
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 0},
            },
          },
          {
            'alphaMode': 'BLEND',
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 1},
            },
          },
          {
            'alphaMode': 'BLEND',
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 2},
            },
          },
        ],
        images: [
          {'uri': 'data:image/png;base64,AAAA'},
          {'bufferView': 0},
          {'uri': 'textures/real.png'},
        ],
        textures: [
          {'source': 0},
          {'source': 1},
          {'source': 2},
        ],
      );
      expect(blendMaterialImageUris(d), ['textures/real.png']);
    });

    test('repeats a material used by several primitives in usage order', () {
      final d = <String, Object?>{
        'materials': [
          {
            'alphaMode': 'BLEND',
            'pbrMetallicRoughness': {
              'baseColorTexture': {'index': 0},
            },
          },
        ],
        'images': [
          {'uri': 'textures/a.png'},
        ],
        'textures': [
          {'source': 0},
        ],
        'meshes': [
          {
            'primitives': [
              {'material': 0},
              {'material': 0},
            ],
          },
        ],
      };
      expect(blendMaterialImageUris(d),
          ['textures/a.png', 'textures/a.png']);
    });

    test('returns empty for a document without BLEND materials', () {
      final d = doc(materials: [
        {
          'pbrMetallicRoughness': {
            'baseColorTexture': {'index': 0},
          },
        },
      ]);
      expect(blendMaterialImageUris(d), isEmpty);
    });
  });

  group('configureBlendMaterials', () {
    Map<String, Object?> blendDoc() => {
          'materials': [
            {
              'alphaMode': 'BLEND',
              'pbrMetallicRoughness': {
                'baseColorTexture': {'index': 0},
              },
            },
          ],
          'images': [
            {'uri': 'textures/diffuse.png'},
          ],
          'textures': [
            {'source': 0},
          ],
          'meshes': [
            {
              'primitives': [
                {'material': 0},
              ],
            },
          ],
        };

    test('binary-alpha BLEND becomes mask', () async {
      final material = PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend;
      final png = _png(32, 32, (im) {
        for (var y = 0; y < 32; y++) {
          for (var x = 0; x < 32; x++) {
            im.setPixelRgba(x, y, 100, 100, 100, (x + y) % 2 == 0 ? 255 : 0);
          }
        }
      });
      await configureBlendMaterials(
        [material],
        gltfDoc: blendDoc(),
        readImage: (_) async => png,
      );
      expect(material.alphaMode, AlphaMode.mask);
    });

    test('fully opaque BLEND becomes opaque', () async {
      final material = PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend;
      final png = _png(16, 16, (im) {
        img.fill(im, color: img.ColorRgba8(10, 20, 30, 255));
      });
      await configureBlendMaterials(
        [material],
        gltfDoc: blendDoc(),
        readImage: (_) async => png,
      );
      expect(material.alphaMode, AlphaMode.opaque);
    });

    test('smooth translucency stays blend', () async {
      final material = PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend;
      final png = _png(16, 16, (im) {
        img.fill(im, color: img.ColorRgba8(10, 20, 30, 128));
      });
      await configureBlendMaterials(
        [material],
        gltfDoc: blendDoc(),
        readImage: (_) async => png,
      );
      expect(material.alphaMode, AlphaMode.blend);
    });

    test('a material/doc count mismatch leaves every material untouched',
        () async {
      final a = PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend;
      final b = PhysicallyBasedMaterial()..alphaMode = AlphaMode.blend;
      await configureBlendMaterials(
        [a, b],
        gltfDoc: blendDoc(),
        readImage: (_) async => null,
      );
      expect(a.alphaMode, AlphaMode.blend);
      expect(b.alphaMode, AlphaMode.blend);
    });
  });
}
