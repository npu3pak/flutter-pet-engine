import 'feature_registry.dart';
import 'camera_modes.dart';
import 'dynamics_objects.dart';
import 'gizmos.dart';
import 'picking_hit.dart';
import 'screen_projection.dart';

/// Фичи группы «Динамика и взаимодействие» (раздел 6.4 плана).
final List<FeatureSpec> dynamicsFeatures = [
  dynamicObjectsFeature,
  cameraModesFeature,
  pickingHitFeature,
  screenProjectionFeature,
  gizmosFeature,
];
