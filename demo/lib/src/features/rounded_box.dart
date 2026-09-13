import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Куб со скруглёнными рёбрами и углами и куб с вырезом на таком же
/// скруглённом основании: в сцене нет нескруглённых тел, форма сравнивается
/// по срезу.
doc.ModelData buildRoundedBoxScene(FeatureBuildContext context) {
  final radius = context.param<double>('radius') ?? 0.25;
  final segments = context.param<int>('segments') ?? 12;
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'rounded',
      name: 'Скруглённый куб',
      kind: 'cuboid',
      x: 2.5,
      z: 3,
      dims: {
        'w': 1.6,
        'h': 1.6,
        'd': 1.6,
        'roundR': radius,
        'roundSegments': segments,
      },
      material: colorMat(SceneColors.green),
    ),
    sceneObject(
      id: 'cut_base',
      name: 'Основание с вырезом',
      kind: 'cuboid',
      x: 6,
      z: 3,
      dims: {
        'w': 1.6,
        'h': 1.6,
        'd': 1.6,
        'roundR': radius,
        'roundSegments': segments,
      },
      material: colorMat(SceneColors.blue),
    ),
    sceneObject(
      id: 'cut_tool',
      name: 'Вырезающий куб',
      kind: 'cuboid',
      x: 6.45,
      y: 0.85,
      z: 3.45,
      dims: const {'w': 0.9, 'h': 0.9, 'd': 0.9},
      material: colorMat(SceneColors.red),
    ),
    sceneObject(
      id: 'cut_result',
      name: 'Куб с вырезом',
      kind: doc.csgKind,
      op: doc.csgOpDifference,
      operands: const ['cut_base', 'cut_tool'],
      material: colorMat(SceneColors.orange),
    ),
  ];
  return doc.ModelData(
    id: 'rounded_box',
    name: 'Скругления',
    size: doc.ModelSize(w: 9, l: 7, h: 3),
    objects: objects,
  );
}

final FeatureSpec roundedBoxFeature = FeatureSpec(
  id: 'rounded_box',
  group: kFeatureGroups[0],
  title: 'Скругления',
  phase: 1,
  description:
      'Слева куб со скруглёнными рёбрами и углами, справа — куб с '
      'вырезом на таком же скруглённом основании: срез повторяет форму '
      'скругления. Ползунки задают радиус скругления и число сегментов дуг; '
      'нескруглённых тел в сцене нет.',
  checks: const [
    'При увеличении радиуса рёбра и углы обоих кубов скругляются, плоские грани уменьшаются.',
    'При увеличении числа сегментов дуги скругления становятся глаже, форма объектов не меняется.',
    'Куб с вырезом повторяет форму скругления на срезе, а не остаётся острым.',
    'В сцене нет ни одного куба с острыми рёбрами, кроме крайнего положения ползунка радиуса (ноль).',
  ],
  build: buildRoundedBoxScene,
  camera: CameraMode.free,
  controls: (context, feature) => _RoundedControls(feature: feature),
);

class _RoundedControls extends StatefulWidget {
  const _RoundedControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_RoundedControls> createState() => _RoundedControlsState();
}

class _RoundedControlsState extends State<_RoundedControls> {
  late double _radius;
  late int _segments;

  @override
  void initState() {
    super.initState();
    _radius = widget.feature.params['radius'] as double? ?? 0.25;
    _segments = widget.feature.params['segments'] as int? ?? 12;
  }

  void _update() {
    widget.feature.updateParams({'radius': _radius, 'segments': _segments});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Форма скругления'),
        fcSlider(
          label: 'Радиус',
          value: _radius,
          min: 0,
          max: 0.6,
          onChanged: (v) {
            setState(() => _radius = v);
            _update();
          },
        ),
        fcSlider(
          label: 'Сегментов дуги',
          value: _segments.toDouble(),
          min: 3,
          max: 32,
          format: (v) => v.round().toString(),
          onChanged: (v) {
            setState(() => _segments = v.round());
            _update();
          },
        ),
        fcNote(
          'Слева — скруглённый куб, справа — куб с вырезом на таком же '
          'скруглённом основании: срез повторяет форму скругления.',
        ),
      ],
    );
  }
}
