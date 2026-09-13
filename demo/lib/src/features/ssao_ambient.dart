import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Углы и стыки поверхностей: затенение в стыках (SSAO) затемняет щели и
/// внутренние углы, яркость окружения задаёт общий уровень заливки.
doc.ModelData buildSsaoScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'floor',
      name: 'Пол',
      kind: 'plane',
      x: 5,
      z: 5,
      dims: const {'w': 10, 'd': 10},
      material: colorMat(SceneColors.gray),
    ),
    sceneObject(
      id: 'back_wall',
      name: 'Задняя стена',
      kind: 'cuboid',
      x: 5,
      z: 0.3,
      dims: const {'w': 10, 'h': 3, 'd': 0.6},
      material: colorMat(SceneColors.white),
    ),
    sceneObject(
      id: 'side_wall',
      name: 'Боковая стена',
      kind: 'cuboid',
      x: 0.3,
      z: 5,
      dims: const {'w': 0.6, 'h': 3, 'd': 10},
      material: colorMat(SceneColors.white),
    ),
    for (var i = 0; i < 3; i++)
      sceneObject(
        id: 'step_$i',
        name: 'Ступень $i',
        kind: 'cuboid',
        x: 3 + i * 1.2,
        z: 3,
        dims: {'w': 1.2, 'h': 0.4 + i * 0.4, 'd': 1.2},
        material: colorMat(SceneColors.orange),
      ),
    sceneObject(
      id: 'corner_box',
      name: 'Коробка в углу',
      kind: 'cuboid',
      x: 1.2,
      z: 1.2,
      dims: const {'w': 0.8, 'h': 0.8, 'd': 0.8},
      material: colorMat(SceneColors.green),
    ),
    sceneObject(
      id: 'divider',
      name: 'Перегородка',
      kind: 'cuboid',
      x: 7.5,
      z: 4,
      dims: const {'w': 0.4, 'h': 1.6, 'd': 4},
      material: colorMat(SceneColors.blue),
    ),
  ];
  return doc.ModelData(
    id: 'ssao_ambient',
    name: 'Затенение в стыках',
    size: doc.ModelSize(w: 10, l: 10, h: 4),
    objects: objects,
  );
}

final FeatureSpec ssaoAmbientFeature = FeatureSpec(
  id: 'ssao_ambient',
  group: kFeatureGroups[1],
  title: 'Затенение в стыках (SSAO)',
  phase: 2,
  description:
      'Комната с углами, ступенями и перегородкой. Затенение в '
      'стыках (SSAO) затемняет щели и внутренние углы, делая объём читаемым; '
      'яркость окружения задаёт общий уровень заливки сцены.',
  checks: const [
    'При включённом SSAO внутренние углы и стыки ступеней заметно темнее ровных участков.',
    'При выключенном SSAO углы теряют затемнение и становятся такими же светлыми, как стены.',
    'Увеличение яркости окружения поднимает общую освещённость и ослабляет видимость затемнения.',
    'Включение SSAO заметно снижает частоту кадров по сравнению с выключенным состоянием.',
  ],
  build: buildSsaoScene,
  camera: CameraMode.free,
  controls: (context, feature) => _SsaoControls(feature: feature),
);

class _SsaoControls extends StatefulWidget {
  const _SsaoControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_SsaoControls> createState() => _SsaoControlsState();
}

class _SsaoControlsState extends State<_SsaoControls> {
  @override
  Widget build(BuildContext context) {
    final host = widget.feature.host;
    final settings = host.settings;
    final ssao = settings?.ssao ?? false;
    final ambient = settings?.ambient ?? 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Затенение в стыках'),
        fcSwitch(
          label: 'Включить SSAO',
          value: ssao,
          onChanged: (v) {
            host.applySsao(v);
            setState(() {});
          },
        ),
        fcSlider(
          label: 'Яркость окружения',
          value: ambient,
          min: 0,
          max: 2,
          onChanged: (v) {
            host.applyAmbient(v);
            setState(() {});
          },
        ),
        fcNote(
          'Затенение в стыках считает затемнение по глубине соседних '
          'пикселей; это самая дорогая из настроек картинки.',
        ),
      ],
    );
  }
}
