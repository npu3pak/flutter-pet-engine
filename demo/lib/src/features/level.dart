import 'biome_scenes.dart';
import 'feature_registry.dart';
import 'legacy_chunks.dart';
import 'level_baking.dart';
import 'level_docking.dart';
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
  levelDockingFeature,
  levelValidationFeature,
  levelBakingFeature,
  levelLoadingFeature,
  legacyChunksFeature,
  biomeDungeonFeature,
  biomeForestFeature,
  biomeAbandonedBuildingFeature,
  levelStressFeature,
];
