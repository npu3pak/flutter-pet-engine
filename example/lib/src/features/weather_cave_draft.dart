import 'package:pet_engine/pet_engine.dart';

import 'feature_registry.dart';
import 'weather_common.dart';

final FeatureSpec weatherCaveDraftFeature = FeatureSpec(
  id: 'weather_cave_draft',
  group: kFeatureGroups[4],
  title: 'Сквозняк',
  phase: 2,
  description:
      'Пресет сквозняка для пещер: два слоя частиц — тёмные струи '
      'воздуха и светлые блики поверх них. Вместе они дают ощущение тяги '
      'воздуха в замкнутом помещении; интенсивность меняет плотность обоих '
      'слоёв.',
  checks: const [
    'В сцене видны два вида частиц: тёмные струи и светлые блики поверх них.',
    'Оба слоя движутся в одном направлении и не падают вниз.',
    'Светлые блики складываются по яркости с фоном, а не затемняют его.',
    'При увеличении интенсивности оба слоя становятся плотнее одновременно.',
  ],
  build: (context) => buildWeatherScene(context, 'weather_cave_draft'),
  camera: CameraMode.free,
  controls: (context, feature) => WeatherControls(
    feature: feature,
    preset: ParticlePresets.caveWindStreak,
    secondPreset: ParticlePresets.caveWindGlint,
    note:
        'Пресет «сквозняк для пещер» состоит из двух слоёв: струи и '
        'аддитивные блики поверх них.',
  ),
);
