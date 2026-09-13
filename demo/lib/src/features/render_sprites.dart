import 'feature_registry.dart';
import 'billboard_batch.dart';
import 'sprite_atlas.dart';
import 'static_merge.dart';
import 'transparency_order.dart';

/// Фичи группы «Отрисовка и спрайты» (раздел 6.3 плана).
final List<FeatureSpec> renderSpriteFeatures = [
  billboardBatchFeature,
  spriteAtlasFeature,
  transparencyOrderFeature,
  staticMergeFeature,
];
