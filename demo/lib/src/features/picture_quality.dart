import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Сцена для сравнения настроек картинки: тонкие столбики и наклонные
/// коробки показывают сглаживание кромок, масштаб отрисовки и фильтр
/// увеличения; яркость окружения видна по освещённости сцены.
doc.ModelData buildPictureScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'floor',
      name: 'Пол',
      kind: 'plane',
      x: 6,
      z: 6,
      dims: const {'w': 12, 'd': 12},
      material: colorMat(SceneColors.gray),
    ),
    for (var i = 0; i < 10; i++)
      sceneObject(
        id: 'pole_$i',
        name: 'Тонкий столбик $i',
        kind: 'cuboid',
        x: 1 + i.toDouble(),
        z: 1.5,
        dims: const {'w': 0.08, 'h': 1.4, 'd': 0.08},
        material: colorMat(SceneColors.white),
      ),
    for (var i = 0; i < 6; i++)
      sceneObject(
        id: 'slanted_$i',
        name: 'Наклонная коробка $i',
        kind: 'cuboid',
        x: 2 + i * 1.6,
        z: 10,
        rotY: 30 * i.toDouble(),
        dims: const {'w': 1.2, 'h': 0.8, 'd': 0.2},
        material: colorMat(i.isEven ? SceneColors.red : SceneColors.blue),
      ),
  ];
  return doc.ModelData(
    id: 'picture_quality',
    name: 'Картинка',
    size: doc.ModelSize(w: 12, l: 12, h: 3),
    objects: objects,
  );
}

final FeatureSpec pictureQualityFeature = FeatureSpec(
  id: 'picture_quality',
  group: kFeatureGroups[1],
  title: 'Картинка',
  phase: 2,
  description:
      'Сравнительная сцена с тонкими столбиками и наклонными '
      'коробками. Камера закреплена, поэтому настройки картинки сравниваются '
      'с одного и того же вида: сглаживание кромок, масштаб отрисовки, фильтр '
      'увеличения и яркость отражённого света.',
  checks: const [
    'Сглаживание ВЫКЛ оставляет рваные кромки на тонких столбиках, FXAA и MSAA их смягчают.',
    'Уменьшение масштаба отрисовки делает картинку заметно мягче или пиксельнее.',
    'Фильтр «резкий» сохраняет чёткие границы, «мягкий» размывает их при увеличении.',
    'Яркость отражённого света равномерно меняет освещённость сцены, не трогая источники.',
  ],
  build: buildPictureScene,
  camera: CameraMode.fixed,
  controls: (context, feature) => _PictureControls(feature: feature),
);

class _PictureControls extends StatefulWidget {
  const _PictureControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_PictureControls> createState() => _PictureControlsState();
}

class _PictureControlsState extends State<_PictureControls> {
  @override
  Widget build(BuildContext context) {
    final host = widget.feature.host;
    final settings = host.settings;
    final aa = settings?.antiAliasing ?? SceneAntiAliasing.auto;
    final filter = settings?.filterQuality ?? FilterQuality.none;
    final scale = settings?.renderScale ?? 1.0;
    final environment = settings?.environmentIntensity ?? 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Качество картинки'),
        fcChoice<SceneAntiAliasing>(
          label: 'Сглаживание кромок',
          values: SceneAntiAliasing.values,
          selected: aa,
          labelOf: (v) => switch (v) {
            SceneAntiAliasing.none => 'выключено',
            SceneAntiAliasing.fxaa => 'FXAA',
            SceneAntiAliasing.msaa => 'MSAA',
            SceneAntiAliasing.auto => 'автоматически',
          },
          onChanged: (v) {
            host.applyAntiAliasing(v);
            setState(() {});
          },
        ),
        fcChoice<FilterQuality>(
          label: 'Фильтр увеличения',
          values: const [FilterQuality.none, FilterQuality.low],
          selected: filter,
          labelOf: (v) => v == FilterQuality.low ? 'мягкий' : 'резкий',
          onChanged: (v) {
            host.applyRenderScale(scale, filterQuality: v);
            setState(() {});
          },
        ),
        fcSlider(
          label: 'Масштаб отрисовки',
          value: scale,
          min: 0.25,
          max: 1.5,
          onChanged: (v) {
            host.applyRenderScale(v);
            setState(() {});
          },
        ),
        fcSlider(
          label: 'Яркость окружения',
          value: environment,
          min: 0,
          max: 2,
          onChanged: (v) {
            host.applyEnvironmentIntensity(v);
            setState(() {});
          },
        ),
        fcNote(
          'Камера закреплена: сцена всегда показана с одного вида, '
          'поэтому настройки сравниваются честно.',
        ),
      ],
    );
  }
}
