import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('EngineMaterial.pbr', () {
    test('applies the construction parameters', () {
      final material = EngineMaterial.pbr(
        color: vm.Vector4(0.5, 0.4, 0.3, 0.8),
        roughness: 0.9,
        metallic: 0.2,
        emissive: vm.Vector4(0.1, 0.2, 0.3, 0),
        alphaMode: EngineAlphaMode.mask,
        alphaCutoff: 0.4,
        doubleSided: true,
        fogStartOverride: 0.5,
        blendOrder: -1,
      );
      expect(material.isPbr, isTrue);
      expect(material.isUnlit, isFalse);
      expect(material.isFmat, isFalse);
      expect(material.color, vm.Vector4(0.5, 0.4, 0.3, 0.8));
      expect(material.roughness, 0.9);
      expect(material.metallic, 0.2);
      expect(material.emissive, vm.Vector4(0.1, 0.2, 0.3, 0));
      expect(material.alphaMode, EngineAlphaMode.mask);
      expect(material.alphaCutoff, 0.4);
      expect(material.doubleSided, isTrue);
      expect(material.fogStartOverride, 0.5);
      expect(material.blendOrder, -1);
    });

    test('setters update the underlying factors', () {
      final material = EngineMaterial.pbr();
      material
        ..roughness = 0.35
        ..metallic = 0.55
        ..alphaMode = EngineAlphaMode.blend
        ..color = vm.Vector4.all(0.25);
      expect(material.roughness, 0.35);
      expect(material.metallic, 0.55);
      expect(material.alphaMode, EngineAlphaMode.blend);
      expect(material.color, vm.Vector4.all(0.25));
    });
  });

  group('EngineMaterial.unlit', () {
    test('applies the construction parameters', () {
      final material = EngineMaterial.unlit(
        color: vm.Vector4(1, 1, 1, 0.5),
        alphaMode: EngineAlphaMode.blend,
        doubleSided: true,
      );
      expect(material.isUnlit, isTrue);
      expect(material.color, vm.Vector4(1, 1, 1, 0.5));
      expect(material.alphaMode, EngineAlphaMode.blend);
      expect(material.doubleSided, isTrue);
    });
  });
}
