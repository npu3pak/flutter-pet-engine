import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Сцена со всеми видами простейшей геометрии движка.
doc.ModelData buildPrimitivesScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'cube',
      name: 'Куб',
      kind: 'cuboid',
      x: 1.5,
      z: 2,
      dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
      material: colorMat(SceneColors.red),
    ),
    sceneObject(
      id: 'rounded',
      name: 'Куб со скруглением',
      kind: 'cuboid',
      x: 3.5,
      z: 2,
      dims: const {
        'w': 1.2,
        'h': 1.2,
        'd': 1.2,
        'roundR': 0.25,
        'roundSegments': 12,
      },
      material: colorMat(SceneColors.green),
    ),
    sceneObject(
      id: 'trapezoid',
      name: 'Трапеция',
      kind: 'trapezoid',
      x: 5.5,
      z: 2,
      dims: const {
        'bottomW': 1.4,
        'bottomD': 1.4,
        'topW': 0.6,
        'topD': 0.6,
        'h': 1.2,
      },
      material: colorMat(SceneColors.blue),
    ),
    sceneObject(
      id: 'cylinder',
      name: 'Цилиндр',
      kind: 'cylinder',
      x: 7.5,
      z: 2,
      dims: const {'bottomR': 0.55, 'topR': 0.55, 'h': 1.2, 'segments': 24},
      material: colorMat(SceneColors.orange),
    ),
    sceneObject(
      id: 'cone',
      name: 'Конус',
      kind: 'cylinder',
      x: 1.5,
      z: 5,
      dims: const {'bottomR': 0.55, 'topR': 0.0, 'h': 1.2, 'segments': 24},
      material: colorMat(SceneColors.purple),
    ),
    sceneObject(
      id: 'plane_h',
      name: 'Горизонтальная плоскость',
      kind: 'plane',
      x: 3.5,
      z: 5,
      dims: const {'w': 1.6, 'd': 1.6},
      material: colorMat(SceneColors.gray),
    ),
    sceneObject(
      id: 'plane_v',
      name: 'Вертикальная плоскость',
      kind: 'plane',
      x: 5.5,
      z: 5,
      dims: const {'w': 1.6, 'd': 1.6, 'vertical': 1},
      material: colorMat(SceneColors.yellow),
    ),
    sceneObject(
      id: 'sprite',
      name: 'Спрайт',
      kind: 'sprite',
      x: 7.5,
      y: 0.45,
      z: 5,
      dims: const {'w': 0.9, 'h': 0.9},
      material: colorMat(SceneColors.cyan),
    ),
  ];
  return doc.ModelData(
    id: 'primitives_all',
    name: 'Все примитивы',
    size: doc.ModelSize(w: 9, l: 7, h: 3),
    objects: objects,
  );
}

final FeatureSpec primitivesAllFeature = FeatureSpec(
  id: 'primitives_all',
  group: kFeatureGroups[0],
  title: 'Все примитивы',
  phase: 1,
  description:
      'На одной сцене собраны все виды простейшей геометрии движка: '
      'куб, куб со скруглёнными рёбрами, трапеция, цилиндр, конус, '
      'горизонтальная и вертикальная плоскости и спрайт. Каждый объект '
      'окрашен в свой цвет; названия и цвета перечислены в списке управления.',
  checks: const [
    'В рабочей области видно восемь объектов: куб, скруглённый куб, трапеция, цилиндр, конус, две плоскости и спрайт.',
    'Форма и цвет каждого объекта совпадают с его названием в списке управления.',
    'Спрайт разворачивается к камере при облёте сцены, а остальные объекты сохраняют ориентацию.',
  ],
  build: buildPrimitivesScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _PrimitivesControls(),
);

class _PrimitivesControls extends StatelessWidget {
  const _PrimitivesControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Что показано'),
        fcLegend([
          LegendEntry(rgbColor(SceneColors.red), 'Куб (cuboid)'),
          LegendEntry(rgbColor(SceneColors.green), 'Скруглённый куб (roundR)'),
          LegendEntry(rgbColor(SceneColors.blue), 'Трапеция (trapezoid)'),
          LegendEntry(rgbColor(SceneColors.orange), 'Цилиндр (cylinder)'),
          LegendEntry(rgbColor(SceneColors.purple), 'Конус (topR = 0)'),
          LegendEntry(rgbColor(SceneColors.gray), 'Горизонтальная плоскость'),
          LegendEntry(rgbColor(SceneColors.yellow), 'Вертикальная плоскость'),
          LegendEntry(rgbColor(SceneColors.cyan), 'Спрайт (повёрнут к камере)'),
        ]),
        fcNote(
          'Удерживайте правую кнопку мыши, чтобы осмотреть сцену; '
          'W, A, S, D перемещают камеру, Q и E меняют высоту, Shift ускоряет.',
        ),
      ],
    );
  }
}
