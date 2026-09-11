import 'dart:convert';

import 'legacy_chunk_converter.dart';
import 'model_scene.dart';

/// Reads a scene JSON of any supported format into a [ModelData]:
/// - `model_v1` — parsed directly by [ModelData.fromJson];
/// - legacy `chunk_v1/v2/v3` — through the converter (`blocked`/`meta_pass`
///   → meta boxes, `entries`/`front` → scene fields).
///
/// The single loading entry point for files on disk: it keeps
/// [ModelData.fromJson] pure (the document model knows nothing about the
/// converter) and the converter free of back-references — no import cycle
/// (review note 4).
ModelData loadModelData(String jsonStr, {required String id}) {
  final m = jsonDecode(jsonStr) as Map<String, Object?>;
  if (isLegacyChunkFormat(m['format'])) {
    return convertLegacyChunkMap(m, id: id);
  }
  return ModelData.fromJson(jsonStr, id: id);
}
