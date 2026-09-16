import 'model_scene.dart';

/// Reads a scene JSON of format `model_v1` into a [ModelData].
///
/// The single loading entry point for files on disk: it keeps
/// [ModelData.fromJson] pure (the document model knows nothing about file
/// I/O).
ModelData loadModelData(String jsonStr, {required String id}) =>
    ModelData.fromJson(jsonStr, id: id);
