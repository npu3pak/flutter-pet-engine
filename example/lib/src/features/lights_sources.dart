import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Точечный и направленный источники света: цвет, яркость, дальность и
/// направление.
doc.ModelData buildLightSourcesScene(FeatureBuildContext context) {
  final colorName = context.param<String>('color') ?? 'white';
  final intensity = context.param<double>('intensity') ?? 2.2;
  final range = context.param<double>('range') ?? 8.0;
  final directionName = context.param<String>('direction') ?? 'leftTop';
  final rgb = switch (colorName) {
    'warm' => const [1.0, 0.72, 0.42],
    'cold' => const [0.55, 0.72, 1.0],
    _ => const [1.0, 0.97, 0.9],
  };
  final dir = switch (directionName) {
    'rightTop' => const [0.55, -0.8, 0.25],
    'front' => const [0.0, -0.55, 1.0],
    'top' => const [0.0, -1.0, 0.05],
    _ => const [-0.4, -0.85, -0.35],
  };

  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 3,
      dims: const {'w': 8, 'd': 6},
      material: colorMat(SceneColors.gray),
    ),
    for (final (id, x, height, color) in const [
      ('pillar_1', 2.0, 1.4, SceneColors.red),
      ('pillar_2', 4.0, 1.9, SceneColors.green),
      ('pillar_3', 6.0, 1.2, SceneColors.blue),
    ])
      sceneObject(
        id: id,
        name: 'Столбик $id',
        kind: 'cuboid',
        x: x,
        z: 3,
        dims: {'w': 0.7, 'h': height, 'd': 0.7},
        material: colorMat(color),
      ),
  ];

  return doc.ModelData(
    id: 'light_sources',
    name: 'Источники света',
    size: doc.ModelSize(w: 8, l: 6, h: 4),
    objects: objects,
    lighting: doc.ModelLighting(
      ambient: 0.15,
      shadows: true,
      lights: [
        doc.ModelLight(
          id: 'sun',
          kind: doc.lightKindDirectional,
          name: 'Солнце',
          intensity: intensity,
          r: rgb[0],
          g: rgb[1],
          b: rgb[2],
          dirX: dir[0],
          dirY: dir[1],
          dirZ: dir[2],
        ),
        doc.ModelLight(
          id: 'lamp',
          kind: doc.lightKindPoint,
          name: 'Лампа',
          x: 4,
          y: 2.6,
          z: 3,
          intensity: intensity,
          range: range,
          r: rgb[0],
          g: rgb[1],
          b: rgb[2],
        ),
      ],
    ),
  );
}

final FeatureSpec lightSourcesFeature = FeatureSpec(
  id: 'light_sources',
  group: kFeatureGroups[1],
  title: 'Источники света',
  phase: 2,
  description:
      'Сцену освещают два источника: направленный (солнце) и '
      'точечный (лампа над центром). Управление задаёт цвет, яркость, '
      'дальность точечного света и направление солнечного. Яркость окружения '
      'намеренно низкая, чтобы влияние источников было видно отчётливо.',
  checks: const [
    'Смена цвета источника окрашивает столбики и пол в выбранный оттенок.',
    'Увеличение яркости делает освещение светлее, уменьшение — темнее; при нуле видны только тени окружения.',
    'Уменьшение дальности точечного света сужает освещённое пятно вокруг лампы, дальние столбики остаются в тени.',
    'Смена направления солнца перемещает тени столбиков по полу.',
  ],
  build: buildLightSourcesScene,
  camera: CameraMode.free,
  controls: (context, feature) => _LightControls(feature: feature),
);

class _LightControls extends StatefulWidget {
  const _LightControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_LightControls> createState() => _LightControlsState();
}

class _LightControlsState extends State<_LightControls> {
  late String _color;
  late double _intensity;
  late double _range;
  late String _direction;

  @override
  void initState() {
    super.initState();
    final params = widget.feature.params;
    _color = params['color'] as String? ?? 'white';
    _intensity = params['intensity'] as double? ?? 2.2;
    _range = params['range'] as double? ?? 8.0;
    _direction = params['direction'] as String? ?? 'leftTop';
  }

  void _update() {
    widget.feature.updateParams({
      'color': _color,
      'intensity': _intensity,
      'range': _range,
      'direction': _direction,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Источники'),
        fcChoice<String>(
          label: 'Цвет',
          values: const ['white', 'warm', 'cold'],
          selected: _color,
          labelOf: (v) => switch (v) {
            'warm' => 'тёплый',
            'cold' => 'холодный',
            _ => 'белый',
          },
          onChanged: (v) {
            setState(() => _color = v);
            _update();
          },
        ),
        fcSlider(
          label: 'Яркость',
          value: _intensity,
          min: 0,
          max: 8,
          onChanged: (v) {
            setState(() => _intensity = v);
            _update();
          },
        ),
        fcSlider(
          label: 'Дальность лампы',
          value: _range,
          min: 1,
          max: 20,
          format: (v) => '${v.toStringAsFixed(0)} м',
          onChanged: (v) {
            setState(() => _range = v);
            _update();
          },
        ),
        fcChoice<String>(
          label: 'Направление солнца',
          values: const ['leftTop', 'rightTop', 'front', 'top'],
          selected: _direction,
          labelOf: (v) => switch (v) {
            'rightTop' => 'справа сверху',
            'front' => 'спереди',
            'top' => 'сверху',
            _ => 'слева сверху',
          },
          onChanged: (v) {
            setState(() => _direction = v);
            _update();
          },
        ),
        fcNote(
          'Дальность меняет только пятно света лампы. Тени отбрасывает '
          'направленное солнце: их длину и поворот задаёт «Направление '
          'солнца», а не дальность лампы.',
        ),
      ],
    );
  }
}
