import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'feature_registry.dart';
import 'weather_common.dart';

final FeatureSpec weatherRainFeature = FeatureSpec(
  id: 'weather_rain',
  group: kFeatureGroups[4],
  title: 'Дождь',
  phase: 2,
  description:
      'Пресет дождя для улицы: вертикальные штрихи капель падают '
      'на площадку и растворяются у земли. Интенсивность меняет число капель '
      'и плотность поля; сцена из строений и фонаря показывает, как дождь '
      'ложится на разные поверхности.',
  checks: const [
    'Капли падают сверху вниз и слегка вытянуты по направлению падения.',
    'При увеличении интенсивности капель становится больше, при нуле дождь исчезает.',
    'Капли привязаны к клеткам сцены: при полёте камеры поле не следует за ней.',
    'Дождь не просвечивает сквозь крыши строений и корректно ложится на площадку.',
  ],
  build: (context) => buildWeatherScene(context, 'weather_rain'),
  camera: CameraMode.free,
  controls: (context, feature) => WeatherControls(
    feature: feature,
    preset: ParticlePresets.streetRain,
    note:
        'Пресет «дождь для улицы»: штрихи вытягиваются по скорости '
        'падения, поэтому ливень выглядит как косые струи.',
  ),
);
