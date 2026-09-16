import 'package:pet_engine/pet_engine.dart';

import 'feature_registry.dart';
import 'weather_common.dart';

final FeatureSpec weatherWindFeature = FeatureSpec(
  id: 'weather_wind',
  group: kFeatureGroups[4],
  title: 'Ветер',
  phase: 2,
  description:
      'Пресет ветра для перевала: лёгкие светлые частицы летят '
      'горизонтально по направлению ветра короткими рывками, не падая вниз. '
      'Интенсивность меняет плотность потока.',
  checks: const [
    'Частицы ветра летят горизонтально и не падают вниз.',
    'Направление движения совпадает с направлением ветра в пресете.',
    'Поток выглядит прерывистым (отдельные струи), а не сплошной завесой.',
    'При увеличении интенсивности струй становится больше, при нуле ветер исчезает.',
  ],
  build: (context) => buildWeatherScene(context, 'weather_wind'),
  camera: CameraMode.free,
  controls: (context, feature) => WeatherControls(
    feature: feature,
    preset: ParticlePresets.passWind,
    note:
        'Пресет «ветер для перевала»: частицы скользят над землёй вдоль '
        'направления ветра.',
  ),
);
