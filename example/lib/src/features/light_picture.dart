import 'feature_registry.dart';
import 'fog_distance.dart';
import 'lights_sources.dart';
import 'picture_quality.dart';
import 'shadow_cascades.dart';
import 'skybox_static.dart';
import 'ssao_ambient.dart';

/// Фичи группы «Свет и картинка» (раздел 6.2 плана).
final List<FeatureSpec> lightPictureFeatures = [
  lightSourcesFeature,
  shadowCascadesFeature,
  fogDistanceFeature,
  pictureQualityFeature,
  ssaoAmbientFeature,
  skyboxStaticFeature,
];
