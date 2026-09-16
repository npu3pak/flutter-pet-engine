import 'feature_registry.dart';
import 'fmat_effects.dart';
import 'particle_params.dart';
import 'weather_cave_draft.dart';
import 'weather_rain.dart';
import 'weather_snow.dart';
import 'weather_wind.dart';

/// Фичи группы «Частицы и эффекты» (раздел 6.5 плана).
final List<FeatureSpec> particleFeatures = [
  weatherRainFeature,
  weatherSnowFeature,
  weatherWindFeature,
  weatherCaveDraftFeature,
  particleParamsFeature,
  fmatEffectsFeature,
];
