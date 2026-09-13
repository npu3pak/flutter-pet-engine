import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Небольшой уровень из коридора и комнаты для проверки камер.
doc.ModelData buildCameraScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'floor',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 4,
      dims: const {'w': 8, 'd': 8},
      material: colorMat(SceneColors.gray),
    ),
    for (final (id, x, z, w, d) in const [
      ('wall_n', 4.0, 0.3, 8.0, 0.4),
      ('wall_s', 4.0, 7.7, 8.0, 0.4),
      ('wall_w', 0.3, 4.0, 0.4, 8.0),
      ('wall_e', 7.7, 4.0, 0.4, 8.0),
      ('divider', 4.0, 4.0, 0.4, 4.0),
    ])
      sceneObject(
        id: id,
        name: 'Стена $id',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: {'w': w, 'h': 2.4, 'd': d},
        material: colorMat(SceneColors.white),
      ),
    sceneObject(
      id: 'crate',
      name: 'Ящик',
      kind: 'cuboid',
      x: 2,
      z: 2,
      dims: const {'w': 0.8, 'h': 0.8, 'd': 0.8},
      material: colorMat(SceneColors.orange),
    ),
  ];
  return doc.ModelData(
    id: 'camera_modes',
    name: 'Камеры',
    size: doc.ModelSize(w: 8, l: 8, h: 3),
    objects: objects,
  );
}

final FeatureSpec cameraModesFeature = FeatureSpec(
  id: 'camera_modes',
  group: kFeatureGroups[3],
  title: 'Камеры',
  phase: 2,
  description:
      'Два режима камеры на одном уровне: свободная (облёт мышью и '
      'клавишами) и игровая с перемещением по клеткам. В игровом режиме '
      'внизу рабочей области появляются кнопки поворота и шага, движение '
      'идёт с анимацией и покачиванием при ходьбе, как в игре.',
  checks: const [
    'В игровом режиме кнопки внизу рабочей области поворачивают камеру на 90 градусов и двигают на одну клетку.',
    'Поворот и шаг проигрываются с анимацией, а не мгновенно.',
    'При ходьбе камера слегка покачивается, при повороте на месте покачивания нет.',
    'Переключение на свободную камеру убирает кнопки и возвращает полёт мышью и клавишами.',
  ],
  build: buildCameraScene,
  camera: CameraMode.cell,
  startCell: (5, 2),
  controls: (context, feature) => _CameraControls(feature: feature),
);

class _CameraControls extends StatefulWidget {
  const _CameraControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_CameraControls> createState() => _CameraControlsState();
}

class _CameraControlsState extends State<_CameraControls> {
  bool _gameCamera = true;

  @override
  void initState() {
    super.initState();
    _gameCamera = widget.feature.cellNavigation;
  }

  void _apply() {
    final game = widget.feature.controller;
    widget.feature.setCellNavigation(_gameCamera);
    if (game == null) return;
    if (_gameCamera) {
      final (row, column) = cameraCellFor(game, widget.feature.spec.startCell);
      game.camera = FirstPersonCameraController(
        facing: Direction.north,
        row: row,
        column: column,
      );
    } else {
      final camera = FlyCameraController();
      final model = game.model;
      if (model != null) camera.frameModel(model);
      game.camera = camera;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Режим камеры'),
        fcSwitch(
          label: 'Игровая камера (по клеткам)',
          value: _gameCamera,
          onChanged: (v) {
            setState(() => _gameCamera = v);
            _apply();
          },
        ),
        fcNote(
          _gameCamera
              ? 'Кнопки внизу рабочей области: поворот влево и вправо, шаг '
                    'вперёд и назад. Шаг идёт с анимацией и покачиванием.'
              : 'Свободная камера: удерживайте правую кнопку мыши для осмотра, '
                    'W, A, S, D — полёт, Q и E — высота, Shift — ускорение.',
        ),
      ],
    );
  }
}
