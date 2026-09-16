import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';
import 'weather_common.dart';

/// Направление ветра в МИРОВЫХ осях для метки компаса. Мир зеркалит X
/// модели (`chunkWorld`): восток модели (рост столбца) — это world −X,
/// поэтому метки переводятся с учётом зеркала — иначе снос и наклон идут
/// против выбранной стороны.
vm.Vector3 windDirectionFor(String compass) => switch (compass) {
  'east' => vm.Vector3(-1, 0, 0),
  'south' => vm.Vector3(0, 0, 1),
  'west' => vm.Vector3(1, 0, 0),
  _ => vm.Vector3(0, 0, -1),
};

/// Площадка с коридором для проверки параметров частиц.
doc.ModelData buildParticleParamsScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 6,
      z: 6,
      dims: const {'w': 12, 'd': 12},
      material: colorMat(SceneColors.gray),
    ),
    for (final (id, x, z) in const [
      ('wall_1', 4.0, 4.0),
      ('wall_2', 8.0, 4.0),
      ('wall_3', 4.0, 8.0),
      ('wall_4', 8.0, 8.0),
    ])
      sceneObject(
        id: id,
        name: 'Стена $id',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: const {'w': 1.2, 'h': 2.4, 'd': 1.2},
        material: colorMat(SceneColors.blue),
      ),
  ];
  return doc.ModelData(
    id: 'particle_params',
    name: 'Параметры частиц',
    size: doc.ModelSize(w: 12, l: 12, h: 4),
    objects: objects,
  );
}

final FeatureSpec particleParamsFeature = FeatureSpec(
  id: 'particle_params',
  group: kFeatureGroups[4],
  title: 'Параметры частиц',
  phase: 2,
  description:
      'Один слой частиц дождя с настраиваемыми параметрами: '
      'плотность (число частиц в клетке), кольца полной плотности, дальность '
      'показа, направление и скорость ветра, а также ограничение поля только '
      'проходимыми клетками.',
  checks: const [
    'Увеличение плотности добавляет частицы в каждой клетке, уменьшение — разрежает поле.',
    'Кольца полной плотности задают, на сколько клеток вокруг центра частицы идут без прореживания.',
    'Дальность показа ограничивает радиус, за которым частиц нет.',
    'Направление и скорость ветра сносят частицы, направление совпадает с выбранным.',
    'При включённом ограничении частицы остаются только над проходимыми клетками (шахматный порядок).',
  ],
  build: buildParticleParamsScene,
  camera: CameraMode.free,
  controls: (context, feature) => _ParticleParamsControls(feature: feature),
);

class _ParticleParamsControls extends StatefulWidget {
  const _ParticleParamsControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_ParticleParamsControls> createState() =>
      _ParticleParamsControlsState();
}

class _ParticleParamsControlsState extends State<_ParticleParamsControls> {
  ParticleNode? _layer;
  GroupNode? _root;
  double _density = 8;
  double _rings = 2;
  double _viewRadius = 12;
  String _wind = 'north';
  double _windSpeed = 1.0;
  bool _passableOnly = false;

  @override
  void initState() {
    super.initState();
    // Параметры диплинка (визуальные проверки): wind, windSpeed, density.
    final params = widget.feature.params;
    final wind = params['wind'];
    if (wind is String && wind.isNotEmpty) _wind = wind;
    final windSpeed = params['windSpeed'];
    if (windSpeed is num) _windSpeed = windSpeed.toDouble();
    final density = params['density'];
    if (density is num) _density = density.toDouble();
    _build();
  }

  @override
  void dispose() {
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  vm.Vector3 get _windDirection => windDirectionFor(_wind);

  void _build() {
    final game = widget.feature.controller;
    if (game == null) return;
    _layer?.remove();
    _layer = null;
    final root = _root ?? attachFeatureRoot(game, 'particle-params-demo');
    _root = root;
    final model = game.model;
    final rows = model?.size.l ?? 12;
    final columns = model?.size.w ?? 12;
    final field = ParticleField(
      rows: rows,
      columns: columns,
      origin: chunkWorld(0, 0, columns, rows),
      seed: 5,
      allowsCell: _passableOnly ? (row, col) => (row + col) % 2 == 0 : null,
    );
    final config = copyParticleConfig(
      ParticlePresets.streetRain,
      maxPerCell: _density.round(),
      fullDensityRings: _rings.round(),
      viewRadius: _viewRadius.round(),
      windSpeed: _windSpeed,
      windDirection: _windDirection,
    );
    final layer = ParticleNode(
      name: 'particle-params',
      config: config,
      field: field,
      intensity: 1.0,
    )..focus = field.cellCenter(rows ~/ 2, columns ~/ 2);
    root.add(layer);
    unawaited(layer.prepare());
    _layer = layer;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Параметры слоя'),
        fcSlider(
          label: 'Плотность',
          value: _density,
          min: 1,
          max: 32,
          format: (v) => v.round().toString(),
          onChanged: (v) {
            setState(() => _density = v);
            _build();
          },
        ),
        fcSlider(
          label: 'Кольца плотности',
          value: _rings,
          min: 0,
          max: 10,
          format: (v) => v.round().toString(),
          onChanged: (v) {
            setState(() => _rings = v);
            _build();
          },
        ),
        fcSlider(
          label: 'Дальность показа',
          value: _viewRadius,
          min: 4,
          max: 20,
          format: (v) => '${v.round()} кл.',
          onChanged: (v) {
            setState(() => _viewRadius = v);
            _build();
          },
        ),
        fcChoice<String>(
          label: 'Направление ветра',
          values: const ['north', 'east', 'south', 'west'],
          selected: _wind,
          labelOf: (v) => switch (v) {
            'east' => 'восток',
            'south' => 'юг',
            'west' => 'запад',
            _ => 'север',
          },
          onChanged: (v) {
            setState(() => _wind = v);
            _build();
          },
        ),
        fcSlider(
          label: 'Скорость ветра',
          value: _windSpeed,
          min: 0,
          max: 4,
          onChanged: (v) {
            setState(() => _windSpeed = v);
            _build();
          },
        ),
        fcSwitch(
          label: 'Только проходимые клетки',
          value: _passableOnly,
          onChanged: (v) {
            setState(() => _passableOnly = v);
            _build();
          },
        ),
        fcNote(
          'Ограничение проверяет клетку через функцию проходимости: '
          'частицы появляются только там, где клетка разрешена.',
        ),
      ],
    );
  }
}
