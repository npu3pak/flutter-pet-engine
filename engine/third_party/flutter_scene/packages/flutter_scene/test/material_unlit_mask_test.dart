import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

// Coverage for the unlit MASK alpha mode and the two-sided culling it
// enables. Cutout walls (gates, open doors, fences) must stay in the opaque
// pass with a depth-writing alpha test, so `doubleSided` is honored.
//
// Building the GPU material needs a Flutter GPU context the headless harness
// lacks (see material_double_sided_test.dart); the pass split and the cull
// mode are pure Dart and tested here.

void main() {
  group('UnlitMaterial MASK alpha mode', () {
    test('defaults to opaque with a 0.5 cutoff', () {
      final material = UnlitMaterial();
      expect(material.alphaMode, AlphaMode.opaque);
      expect(material.alphaCutoff, 0.5);
      expect(material.isOpaque(), isTrue);
      expect(material.depthAlphaMasked, isFalse);
    });

    test('mask is drawn in the opaque pass and depth-masked', () {
      final material = UnlitMaterial()..alphaMode = AlphaMode.mask;
      expect(material.isOpaque(), isTrue);
      expect(material.depthAlphaMasked, isTrue);
    });

    test('blend is translucent and never depth-masked', () {
      final material = UnlitMaterial()..alphaMode = AlphaMode.blend;
      expect(material.isOpaque(), isFalse);
      expect(material.depthAlphaMasked, isFalse);
    });

    test('double-sided mask disables back-face culling', () {
      final oneSided = UnlitMaterial()..alphaMode = AlphaMode.mask;
      final twoSided = UnlitMaterial()
        ..alphaMode = AlphaMode.mask
        ..doubleSided = true;
      expect(oneSided.renderCullMode, gpu.CullMode.backFace);
      expect(twoSided.renderCullMode, gpu.CullMode.none);
    });

    test('double-sided opaque still disables back-face culling', () {
      final material = UnlitMaterial()..doubleSided = true;
      expect(material.renderCullMode, gpu.CullMode.none);
    });

    test('blend stays back-face culled even when double-sided', () {
      final material = UnlitMaterial()
        ..alphaMode = AlphaMode.blend
        ..doubleSided = true;
      expect(material.renderCullMode, gpu.CullMode.backFace);
    });
  });
}
