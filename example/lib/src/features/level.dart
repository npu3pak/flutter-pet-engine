import 'feature_registry.dart';
import 'level_baking.dart';
import 'level_loading.dart';
import 'level_meta_cells.dart';
import 'level_meta_query.dart';
import 'level_shell.dart';
import 'level_stress.dart';
import 'level_validation.dart';

/// Фичи группы «Уровневый слой» (раздел 6.6 плана).
final List<FeatureSpec> levelFeatures = [
  levelShellFeature,
  levelMetaCellsFeature,
  levelMetaQueryFeature,
  levelValidationFeature,
  levelBakingFeature,
  levelLoadingFeature,
  levelStressFeature,
];
