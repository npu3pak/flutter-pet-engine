import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Тени от направленного света: число каскадов, дальность, статические и
/// подвижные объекты.
doc.ModelData buildShadowScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 12,
      z: 7,
      dims: const {'w': 24, 'd': 14},
      material: colorMat(SceneColors.gray),
    ),
    for (final (id, x, height, color) in const [
      ('near_box', 5.0, 1.2, SceneColors.red),
      ('middle_box', 12.0, 2.0, SceneColors.green),
      ('far_box', 19.0, 2.8, SceneColors.blue),
    ])
      sceneObject(
        id: id,
        name: 'Ящик $id',
        kind: 'cuboid',
        x: x,
        z: 7,
        dims: {'w': 1.6, 'h': height, 'd': 1.6},
        material: colorMat(color),
      ),
    for (final (id, x) in const [('post_1', 8.5), ('post_2', 15.5)])
      sceneObject(
        id: id,
        name: 'Столбик $id',
        kind: 'cuboid',
        x: x,
        z: 4,
        dims: const {'w': 0.3, 'h': 1.6, 'd': 0.3},
        material: colorMat(SceneColors.orange),
      ),
  ];
  return doc.ModelData(
    id: 'shadow_cascades',
    name: 'Тени',
    size: doc.ModelSize(w: 24, l: 14, h: 5),
    objects: objects,
    lighting: doc.ModelLighting(
      ambient: 0.5,
      shadows: true,
      lights: [
        doc.ModelLight(
          id: 'sun',
          kind: doc.lightKindDirectional,
          name: 'Солнце',
          x: 12,
          y: 6,
          z: 7,
          intensity: 2.2,
          dirX: -0.4,
          dirY: -0.85,
          dirZ: -0.35,
        ),
      ],
    ),
  );
}

final FeatureSpec shadowCascadesFeature = FeatureSpec(
  id: 'shadow_cascades',
  group: kFeatureGroups[1],
  title: 'Тени',
  phase: 2,
  description:
      'Длинная площадка с ящиками на разной дальности показывает '
      'тени от направленного света. Управление включает и выключает тени, '
      'задаёт число каскадов и дальность теней; видно, насколько далеко от '
      'камеры тени остаются чёткими.',
  checks: const [
    'При включённых тенях ящики и столбики отбрасывают тень на пол в сторону от солнца.',
    'Выключение теней убирает тени, освещение объектов сохраняется.',
    'Увеличение числа каскадов делает тени дальних ящиков чёткими, а не размытыми.',
    'Уменьшение дальности теней убирает тени у дальних объектов, ближние тени остаются.',
  ],
  build: buildShadowScene,
  camera: CameraMode.free,
  controls: (context, feature) => _ShadowControls(feature: feature),
);

class _ShadowControls extends StatefulWidget {
  const _ShadowControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_ShadowControls> createState() => _ShadowControlsState();
}

class _ShadowControlsState extends State<_ShadowControls> {
  @override
  void initState() {
    super.initState();
    // Дальность из настроек сцены (150 м) для этой площадки велика; ставим
    // компактную, чтобы ползунок 1…10 был осмысленным, и включаем тени.
    final host = widget.feature.host;
    host.applyShadows(true);
    host.applyShadowCascades(4);
    host.applyShadowDistance(10);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.feature.host;
    final settings = host.settings;
    final shadows = settings?.shadows ?? true;
    final cascades = settings?.shadowCascades ?? 4;
    final distance = (settings?.shadowDistance ?? 10.0).clamp(1.0, 10.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Тени'),
        fcSwitch(
          label: 'Включить тени',
          value: shadows,
          onChanged: (v) {
            host.applyShadows(v);
            setState(() {});
          },
        ),
        fcChoice<int>(
          label: 'Число каскадов',
          values: const [1, 2, 4],
          selected: cascades,
          labelOf: (v) => '$v',
          onChanged: (v) {
            host.applyShadowCascades(v);
            setState(() {});
          },
        ),
        fcSlider(
          label: 'Дальность',
          value: distance,
          min: 1,
          max: 10,
          format: (v) => '${v.toStringAsFixed(0)} м',
          onChanged: (v) {
            host.applyShadowDistance(v);
            setState(() {});
          },
        ),
        fcNote(
          'Каскады делят область теней на зоны: чем больше каскадов, тем '
          'чётче тени вдали. Дальность ограничивает расстояние, на котором '
          'тени вообще считаются.',
        ),
      ],
    );
  }
}
