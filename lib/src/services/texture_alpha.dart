import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import 'app_log.dart';

/// Classification of a diffuse texture's alpha channel, used to pick a sane
/// engine [AlphaMode] for glTF materials that arrive as `BLEND` but are
/// authored as cut-out textures.
///
/// The engine's `blend` pass is depth-sorted per object, not per triangle,
/// and renders without the opaque pass's per-fragment depth — a single
/// skinned mesh with self-overlapping parts (legs crossing the body) shows
/// its hidden geometry through itself. Such models are routinely exported
/// with `alphaMode: BLEND` while their texture is actually binary
/// (transparent background + hard edges); routing them through the
/// alpha-test `mask` pass restores correct occlusion.
enum TextureAlphaKind {
  /// No transparent/semi-transparent texels: render as opaque.
  opaqueOnly,

  /// Binary alpha (only 0/255) or mostly binary with a thin AA edge:
  /// alpha-test via `mask`.
  binaryMask,

  /// Real smooth translucency: the engine's translucent pass is used as-is
  /// (best effort; see the class doc for its limitation).
  smoothBlend,
}

/// Sampled alpha statistics of a texture.
class TextureAlphaStats {
  /// Number of sampled texels.
  final int total;

  /// Sampled texels with alpha == 0.
  final int transparent;

  /// Sampled texels with 0 < alpha < 255.
  final int semiTransparent;

  const TextureAlphaStats({
    required this.total,
    required this.transparent,
    required this.semiTransparent,
  });

  double get semiRatio => total == 0 ? 0 : semiTransparent / total;
}

/// Decodes [pngBytes] and samples its alpha channel (every ~200k texels,
/// evenly spaced). Returns null when the bytes are not decodable.
Future<TextureAlphaStats?> analyzeTextureAlpha(Uint8List pngBytes) async {
  try {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final w = image.width, h = image.height;
      final totalTexels = w * h;
      // Sample evenly: aim for ~200k samples regardless of texture size.
      final stride = (totalTexels / 200000).ceil().clamp(1, 1024);
      var total = 0, transparent = 0, semi = 0;
      for (var y = 0; y < h; y += stride) {
        final row = y * w * 4;
        for (var x = 0; x < w; x += stride) {
          total++;
          final a = rgba[row + x * 4 + 3];
          if (a == 0) {
            transparent++;
          } else if (a < 255) {
            semi++;
          }
        }
      }
      return TextureAlphaStats(
        total: total,
        transparent: transparent,
        semiTransparent: semi,
      );
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Picks the [TextureAlphaKind] for sampled [stats].
TextureAlphaKind classifyTextureAlpha(TextureAlphaStats stats) {
  if (stats.total == 0) return TextureAlphaKind.opaqueOnly;
  if (stats.transparent == 0 && stats.semiTransparent == 0) {
    return TextureAlphaKind.opaqueOnly;
  }
  if (stats.semiTransparent == 0) return TextureAlphaKind.binaryMask;
  // Thin semi-transparent fringe (anti-aliased silhouette edges) still
  // cuts cleanly with a mask; genuine translucency is left to blend.
  if (stats.semiRatio < 0.05) return TextureAlphaKind.binaryMask;
  return TextureAlphaKind.smoothBlend;
}

/// The external diffuse image URIs of the `BLEND` materials used by the
/// glTF document's primitives, in primitive usage order (a material used by
/// several primitives repeats). GLB-embedded images (`bufferView` instead
/// of `uri`) and `data:` URIs are skipped — their bytes are not addressable
/// from the glTF folder.
///
/// Pure: the engine import path pairs this list positionally with the
/// engine's own blend materials (see [configureGltfBlendMaterials]), and
/// unit tests exercise the mapping without a GPU.
List<String> blendMaterialImageUris(Map<String, Object?> gltfDoc) {
  final materials = (gltfDoc['materials'] as List?) ?? const [];
  final images = (gltfDoc['images'] as List?) ?? const [];
  final textures = (gltfDoc['textures'] as List?) ?? const [];
  final meshes = (gltfDoc['meshes'] as List?) ?? const [];

  // glTF material index -> diffuse image file URI (only BLEND materials
  // with an external image).
  String? diffuseImageUri(int materialIndex) {
    if (materialIndex < 0 || materialIndex >= materials.length) return null;
    final material = materials[materialIndex];
    if (material is! Map) return null;
    if (material['alphaMode'] != 'BLEND') return null;
    Map<String, Object?>? pbr;
    final extensions = material['extensions'];
    final sg = extensions is Map
        ? extensions['KHR_materials_pbrSpecularGlossiness']
        : null;
    final pbrMr = material['pbrMetallicRoughness'];
    if (sg is Map) {
      pbr = Map<String, Object?>.from(sg);
    } else if (pbrMr is Map) {
      pbr = Map<String, Object?>.from(pbrMr);
    }
    if (pbr == null) return null;
    final texInfo = (pbr['baseColorTexture'] ?? pbr['diffuseTexture']);
    if (texInfo is! Map) return null;
    final texIdx = texInfo['index'];
    if (texIdx is! int || texIdx >= textures.length) return null;
    final texture = textures[texIdx];
    if (texture is! Map) return null;
    final imgIdx = texture['source'];
    if (imgIdx is! int || imgIdx >= images.length) return null;
    final image = images[imgIdx];
    if (image is! Map) return null;
    final uri = image['uri'];
    if (uri is! String || uri.isEmpty || uri.startsWith('data:')) return null;
    return uri;
  }

  final out = <String>[];
  for (final mesh in meshes) {
    if (mesh is! Map) continue;
    for (final prim in ((mesh['primitives'] as List?) ?? const [])) {
      if (prim is! Map) continue;
      final mi = prim['material'];
      if (mi is! int) continue;
      final uri = diffuseImageUri(mi);
      if (uri != null) out.add(uri);
    }
  }
  return out;
}

/// Reclassifies the [root]'s `alphaMode: blend` materials whose external
/// diffuse texture is actually binary (transparent background, possibly
/// with a thin AA fringe) or fully opaque into the engine's alpha-test
/// `mask`/`opaque` passes.
///
/// Why: the engine's translucent pass sorts per object, not per triangle,
/// and skips per-fragment depth — on a single skinned mesh with
/// self-overlapping parts (legs crossing the body) that lets hidden
/// geometry show through the model. Cut-out models routinely ship as
/// `BLEND` with a binary-alpha texture; the real fix for them is `mask`.
/// Genuinely smooth translucency stays `blend` (engine limitation).
///
/// [gltfDoc] is the parsed glTF JSON of the resource, [readImage] resolves
/// an image URI relative to the glTF's folder (override-aware when the
/// caller has texture overrides). The doc's blend materials and the
/// engine's are paired positionally: `meshNodes`/primitive order mirrors
/// the document's node/mesh order. GLB-embedded textures are not analyzed.
///
/// Never throws: a decode/read failure leaves the material as `blend`.
Future<void> configureGltfBlendMaterials(
  Node root, {
  required Map<String, Object?> gltfDoc,
  required Future<Uint8List?> Function(String uri) readImage,
  String? label,
}) async {
  // The same materials as the engine instantiated them (meshNodes order
  // mirrors the document's node/mesh order).
  final engineBlend = <PhysicallyBasedMaterial>[];
  for (final meshNode in root.meshNodes) {
    final mesh = meshNode.mesh;
    if (mesh == null) continue;
    for (final prim in mesh.primitives) {
      final m = prim.material;
      if (m is PhysicallyBasedMaterial && m.alphaMode == AlphaMode.blend) {
        engineBlend.add(m);
      }
    }
  }
  await configureBlendMaterials(
    engineBlend,
    gltfDoc: gltfDoc,
    readImage: readImage,
    label: label,
  );
}

/// [configureGltfBlendMaterials] over an explicit engine-material list, in
/// the document's blend-material usage order. Split out so the pairing and
/// classification logic is unit-testable without a GPU (building a [Mesh]
/// needs one).
Future<void> configureBlendMaterials(
  Iterable<PhysicallyBasedMaterial> engineBlend, {
  required Map<String, Object?> gltfDoc,
  required Future<Uint8List?> Function(String uri) readImage,
  String? label,
}) async {
  try {
    final uris = blendMaterialImageUris(gltfDoc);
    if (uris.isEmpty) return;

    final materials = engineBlend.toList();
    if (materials.length != uris.length) {
      logStage(
        'models',
        '${label == null ? 'gltf' : '$label:'} blend materials mismatch '
            '(doc ${uris.length} vs engine ${materials.length}) — '
            'alpha config skipped',
      );
      return;
    }

    for (var i = 0; i < materials.length; i++) {
      final bytes = await readImage(uris[i]);
      if (bytes == null) continue;
      final stats = await analyzeTextureAlpha(bytes);
      if (stats == null) {
        logStage(
          'models',
          '${label == null ? 'gltf' : '$label:'} diffuse texture '
              '${uris[i]} not decodable — blend kept',
        );
        continue;
      }
      final material = materials[i];
      switch (classifyTextureAlpha(stats)) {
        case TextureAlphaKind.opaqueOnly:
          material.alphaMode = AlphaMode.opaque;
          logStage(
            'models',
            '${label == null ? 'gltf' : '$label:'} ${uris[i]} -> opaque'
                ' (${stats.total} samples, no transparency)',
          );
        case TextureAlphaKind.binaryMask:
          material.alphaMode = AlphaMode.mask;
          logStage(
            'models',
            '${label == null ? 'gltf' : '$label:'} ${uris[i]} -> mask'
                ' (transparent=${stats.transparent}'
                ' semi=${stats.semiTransparent}/${stats.total})',
          );
        case TextureAlphaKind.smoothBlend:
          logStage(
            'models',
            '${label == null ? 'gltf' : '$label:'} ${uris[i]} smooth alpha'
                ' (${stats.semiRatio.toStringAsFixed(3)}) — stays blend',
          );
      }
    }
  } catch (e) {
    logStage(
      'models',
      '${label == null ? 'gltf' : '$label:'} alpha config FAIL: $e',
    );
  }
}
