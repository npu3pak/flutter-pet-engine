/// The scene document model: the serializable `model_v1` scene ([ModelData]
/// and friends) plus the `3d_models/` catalog entry type.
///
/// Pure data — no engine/render types. Import this library when only the
/// document types are needed (alias-friendly: `import 'package:pet_engine_v2/
/// models.dart' as doc;`).
library;

export 'src/models/legacy_chunk_converter.dart';
export 'src/models/model3d_entry.dart';
export 'src/models/model_scene.dart';
export 'src/models/project_meta.dart';
export 'src/models/scene_loader.dart';
export 'src/scene/polyhedron.dart' show PolyMesh, PolyFace, PolyLoop;
