import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Длинная дорога с метками через равные расстояния: туман скрывает дальние
/// метки, видно его начало, конец и плотность.
doc.ModelData buildFogScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'road',
      name: 'Дорога',
      kind: 'plane',
      x: 3,
      z: 24,
      dims: const {'w': 6, 'd': 48},
      material: colorMat(SceneColors.gray),
    ),
    for (final (index, z, color) in const [
      (0, 4.0, SceneColors.red),
      (1, 10.0, SceneColors.green),
      (2, 18.0, SceneColors.blue),
      (3, 28.0, SceneColors.yellow),
      (4, 40.0, SceneColors.cyan),
    ])
      sceneObject(
        id: 'marker_$index',
        name: 'Метка ${z.round()} м',
        kind: 'cuboid',
        x: 3,
        z: z,
        dims: const {'w': 0.6, 'h': 1.6, 'd': 0.6},
        material: colorMat(color),
      ),
    sceneObject(
      id: 'far_wall',
      name: 'Дальняя стена',
      kind: 'cuboid',
      x: 3,
      z: 47,
      dims: const {'w': 6, 'h': 3, 'd': 0.4},
      material: colorMat(SceneColors.purple),
    ),
  ];
  return doc.ModelData(
    id: 'fog_distance',
    name: 'Туман',
    size: doc.ModelSize(w: 6, l: 48, h: 3),
    objects: objects,
  );
}

final FeatureSpec fogDistanceFeature = FeatureSpec(
  id: 'fog_distance',
  group: kFeatureGroups[1],
  title: 'Туман',
  phase: 2,
  description:
      'Длинная дорога с цветными метками на 4, 10, 18, 28 и 40 '
      'метрах. Управление включает туман, задаёт его цвет, начало, конец и '
      'плотность: дальние метки постепенно скрываются в дымке.',
  checks: const [
    'При включённом тумане ближние метки видны отчётливо, а дальние постепенно растворяются.',
    'Ползунок начала тумана сдвигает границу, с которой появляется дымка.',
    'Ползунок конца тумана определяет, на каком расстоянии объекты скрываются полностью.',
    'Плотность управляет непрозрачностью дымки: при нуле туман не виден, при единице дальние объекты полностью скрыты.',
    'Смена цвета тумана окрашивает дымку, не меняя освещение сцены.',
  ],
  build: buildFogScene,
  camera: CameraMode.free,
  controls: (context, feature) => _FogControls(feature: feature),
);

class _FogControls extends StatefulWidget {
  const _FogControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_FogControls> createState() => _FogControlsState();
}

class _FogControlsState extends State<_FogControls> {
  bool _enabled = false;
  String _color = 'blueGray';
  double _start = 4;
  double _end = 30;
  double _opacity = 0.75;

  @override
  void initState() {
    super.initState();
    final settings = widget.feature.host.settings;
    _enabled = settings?.fogEnabled ?? false;
    _start = settings?.fogStart ?? 4;
    _end = settings?.fogEnd ?? 30;
    _opacity = settings?.fogOpacity ?? 0.75;
  }

  Color get _fogColor => switch (_color) {
    'white' => const Color(0xFFD9DEE6),
    'green' => const Color(0xFF73997A),
    _ => const Color(0xFF8C99AD),
  };

  void _apply() {
    widget.feature.host.applyFog(
      _enabled
          ? SceneFog(
              color: _fogColor,
              start: _start,
              end: _end,
              maxOpacity: _opacity,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Туман'),
        fcSwitch(
          label: 'Включить туман',
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _apply();
          },
        ),
        fcChoice<String>(
          label: 'Цвет',
          values: const ['blueGray', 'white', 'green'],
          selected: _color,
          labelOf: (v) => switch (v) {
            'white' => 'белый',
            'green' => 'зелёный',
            _ => 'серо-голубой',
          },
          onChanged: (v) {
            setState(() => _color = v);
            _apply();
          },
        ),
        fcSlider(
          label: 'Начало',
          value: _start,
          min: 0,
          max: 20,
          format: (v) => '${v.toStringAsFixed(0)} м',
          onChanged: (v) {
            setState(() => _start = v);
            _apply();
          },
        ),
        fcSlider(
          label: 'Конец',
          value: _end,
          min: 5,
          max: 60,
          format: (v) => '${v.toStringAsFixed(0)} м',
          onChanged: (v) {
            setState(() => _end = v);
            _apply();
          },
        ),
        fcSlider(
          label: 'Плотность',
          value: _opacity,
          min: 0,
          max: 1,
          onChanged: (v) {
            setState(() => _opacity = v);
            _apply();
          },
        ),
        fcNote(
          'Расстояния указаны от камеры; дальняя стена на 47 метрах '
          'скрывается при плотном тумане.',
        ),
      ],
    );
  }
}
