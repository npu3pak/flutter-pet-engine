import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  group('SceneMaterial.pbr', () {
    test('defaults and predicates', () {
      final material = SceneMaterial.pbr();
      expect(material.isPbr, isTrue);
      expect(material.isUnlit, isFalse);
      expect(material.isShader, isFalse);
      expect(material.color, const Color(0xFFFFFFFF));
      expect(material.roughness, 1.0);
      expect(material.metallic, 0.0);
      expect(material.alphaMode, SceneAlphaMode.opaque);
      expect(material.alphaCutoff, 0.5);
      expect(material.doubleSided, isFalse);
      expect(material.blendOrder, 0.0);
      expect(material.emissive, isNull);
      expect(material.fogStartOverride, isNull);
      material.dispose();
    });

    test('applies parameters to the compiled material', () {
      final material = SceneMaterial.pbr(
        color: const Color(0xFF808080),
        roughness: 0.25,
        metallic: 0.75,
        alphaMode: SceneAlphaMode.mask,
        alphaCutoff: 0.3,
        doubleSided: true,
        emissive: const Color(0xFF102030),
        fogStartOverride: 12,
        blendOrder: 3,
      );
      final raw = material.raw as fs.PhysicallyBasedMaterial;
      expect(raw.baseColorFactor.x, closeTo(math.pow(128 / 255, 2.2), 1e-6));
      expect(raw.baseColorFactor.w, 1.0);
      expect(raw.roughnessFactor, 0.25);
      expect(raw.metallicFactor, 0.75);
      expect(raw.alphaMode, fs.AlphaMode.mask);
      expect(raw.alphaCutoff, 0.3);
      expect(raw.doubleSided, isTrue);
      expect(raw.emissiveFactor.x, closeTo(math.pow(16 / 255, 2.2), 1e-6));
      expect(raw.fogStartOverride, 12);
      expect(raw.blendOrder, 3);
      material.dispose();
    });

    test('mutations update the compiled material and notify', () {
      final material = SceneMaterial.pbr();
      final raw = material.raw as fs.PhysicallyBasedMaterial;
      var notified = 0;
      material.addListener(() => notified++);

      material.roughness = 0.1;
      material.metallic = 0.2;
      material.alphaCutoff = 0.9;
      material.doubleSided = true;
      material.blendOrder = 5;
      material.color = const Color(0xFF000000);

      expect(raw.roughnessFactor, 0.1);
      expect(raw.metallicFactor, 0.2);
      expect(raw.alphaCutoff, 0.9);
      expect(raw.doubleSided, isTrue);
      expect(raw.blendOrder, 5);
      expect(raw.baseColorFactor.x, 0.0);
      expect(notified, 6);
      material.dispose();
    });
  });

  group('SceneMaterial.unlit', () {
    test('builds an unlit material with alpha settings', () {
      final material = SceneMaterial.unlit(
        color: const Color(0xFFFFFFFF),
        alphaMode: SceneAlphaMode.blend,
        doubleSided: true,
        blendOrder: 2,
      );
      expect(material.isUnlit, isTrue);
      final raw = material.raw as fs.UnlitMaterial;
      expect(raw.alphaMode, fs.AlphaMode.blend);
      expect(raw.alphaCutoff, 0.5);
      expect(raw.doubleSided, isTrue);
      expect(raw.blendOrder, 2);
      material.dispose();
    });

    test('passes alphaCutoff to the compiled material', () {
      final material = SceneMaterial.unlit(
        alphaMode: SceneAlphaMode.mask,
        alphaCutoff: 0.3,
      );
      final raw = material.raw as fs.UnlitMaterial;
      expect(raw.alphaMode, fs.AlphaMode.mask);
      expect(raw.alphaCutoff, 0.3);

      material.alphaCutoff = 0.7;
      expect(raw.alphaCutoff, 0.7);
      material.dispose();
    });

    test('copy keeps alphaCutoff', () {
      final material = SceneMaterial.unlit(alphaCutoff: 0.3);
      final copy = material.copy();
      expect((copy.raw as fs.UnlitMaterial).alphaCutoff, 0.3);
      copy.dispose();
      material.dispose();
    });
  });

  group('ShaderLibrary', () {
    test('isolates load failures', () async {
      final library = ShaderLibrary(
        loader: (path) async => throw StateError('no asset: $path'),
      );
      expect(library.isLoaded, isFalse);

      final material = await library.load('assets/shaders/missing.fmat');
      expect(material, isNull);
      expect(library.failures, contains('assets/shaders/missing.fmat'));
      expect(library.isLoaded, isFalse);
      library.dispose();
    });

    test('reload drops the failed state', () async {
      final library = ShaderLibrary(
        loader: (path) async => throw StateError('no asset'),
      );
      await library.load('a.fmat');
      expect(library.failures, isNotEmpty);
      await library.reload();
      expect(library.failures, isEmpty);
      library.dispose();
    });
  });
}
