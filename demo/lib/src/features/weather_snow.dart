import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'feature_registry.dart';
import 'weather_common.dart';

final FeatureSpec weatherSnowFeature = FeatureSpec(
  id: 'weather_snow',
  group: kFeatureGroups[4],
  title: 'Снег',
  phase: 2,
  description:
      'Пресет снега для перевала: отдельные снежинки медленно '
      'опускаются, покачиваются из стороны в сторону, вращаются и сносятся '
      'ветром. Интенсивность меняет густоту снегопада.',
  checks: const [
    'Снежинки опускаются заметно медленнее капель дождя и покачиваются при падении.',
    'Снежинки вращаются вокруг своей оси, рисунок не выглядит статичным.',
    'При усилении ветра снег сносит в сторону, направление сноса совпадает с ветром.',
    'При увеличении интенсивности снегопад становится гуще, при нуле исчезает.',
  ],
  build: (context) => buildWeatherScene(context, 'weather_snow'),
  camera: CameraMode.free,
  controls: (context, feature) => WeatherControls(
    feature: feature,
    preset: ParticlePresets.passSnow,
    note:
        'Пресет «снег для перевала»: падение медленное, с покачиванием, '
        'вращением и сносом по ветру.',
  ),
);
