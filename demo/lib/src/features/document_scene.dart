import 'feature_registry.dart';
import 'csg_ops.dart';
import 'gltf_models.dart';
import 'meta_objects.dart';
import 'model_refs.dart';
import 'primitives_all.dart';
import 'primitives_textured.dart';
import 'rounded_box.dart';

/// Фичи группы «Документ сцены» (раздел 6.1 плана).
final List<FeatureSpec> documentSceneFeatures = [
  primitivesAllFeature,
  primitivesTexturedFeature,
  roundedBoxFeature,
  csgOpsFeature,
  modelRefsFeature,
  gltfModelsFeature,
  metaObjectsFeature,
];
