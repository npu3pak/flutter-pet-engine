import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

doc.ModelData buildLevelShellScene(FeatureBuildContext context) {
  final withDecor = context.param<bool>('withDecor') ?? true;
  final withWindow = context.param<bool>('withWindow') ?? true;
  return buildLevelShell(withDecor: withDecor, withWindow: withWindow).data;
}

final FeatureSpec levelShellFeature = FeatureSpec(
  id: 'level_shell',
  group: kFeatureGroups[5],
  title: 'Оболочка уровня',
  project: 'Pet',
  phase: 3,
  description:
      'Новая композиция уровня из клеток: полы и потолки только под '
      'открытыми клетками, твёрдые клетки нарисованы целыми блоками на всю '
      'высоту, стены стоят по границе открытых клеток, над проходом — '
      'дверная перемычка, в стене — настоящий оконный проём с тёмной нишей '
      'за ним, в первой комнате декор. Камера находится внутри комнаты; '
      'отдельная кнопка показывает уровень целиком снаружи.',
  checks: const [
    'Твёрдые клетки выглядят целыми блоками без дырок и щелей между соседними блоками.',
    'Полы и потолки есть только под открытыми клетками, над твёрдыми блоками их нет.',
    'Стены не мерцают при движении камеры: совпадающих граней между телами нет.',
    'Дверной проём перекрыт перемычкой сверху, проход остаётся свободным.',
    'Оконный проём в северной стене свободен, за ним видна тёмная ниша, а не сплошная стена.',
    'Коврик стоит с отступом от стен и не растянут на всю клетку; декор виден из камеры в комнате.',
    'Кнопка «Обзор уровня» показывает всю оболочку снаружи, кнопка «В комнату» возвращает камеру внутрь.',
  ],
  build: buildLevelShellScene,
  camera: CameraMode.cell,
  startCell: (2, 4),
  controls: (context, feature) => _LevelShellControls(feature: feature),
);

class _LevelShellControls extends StatefulWidget {
  const _LevelShellControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_LevelShellControls> createState() => _LevelShellControlsState();
}

class _LevelShellControlsState extends State<_LevelShellControls> {
  late bool _decor;
  late bool _window;

  @override
  void initState() {
    super.initState();
    _decor = widget.feature.params['withDecor'] as bool? ?? true;
    _window = widget.feature.params['withWindow'] as bool? ?? true;
  }

  void _showOverview() {
    final game = widget.feature.controller;
    if (game == null) return;
    widget.feature.setCellNavigation(false);
    final camera = FlyCameraController();
    final model = game.model;
    if (model != null) camera.frameModel(model);
    game.camera = camera;
    widget.feature.refresh();
  }

  void _goInside() {
    final game = widget.feature.controller;
    if (game == null) return;
    widget.feature.setCellNavigation(true);
    game.camera = FirstPersonCameraController(
      facing: Direction.north,
      row: -1,
      column: 0,
    );
    widget.feature.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Оболочка'),
        fcSwitch(
          label: 'Декор комнаты',
          value: _decor,
          onChanged: (v) {
            setState(() => _decor = v);
            widget.feature.updateParams({'withDecor': v});
          },
        ),
        fcSwitch(
          label: 'Окно на стене',
          value: _window,
          onChanged: (v) {
            setState(() => _window = v);
            widget.feature.updateParams({'withWindow': v});
          },
        ),
        Wrap(
          spacing: 6,
          children: [
            fcButton('Обзор уровня', _showOverview),
            fcButton('В комнату', _goInside),
          ],
        ),
        fcNote(
          'Кнопки внизу рабочей области двигают камеру по клеткам; '
          '«Обзор уровня» временно переключает её на свободную.',
        ),
      ],
    );
  }
}
