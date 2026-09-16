import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Объекты для проверки проецирования на экран.
doc.ModelData buildProjectionScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 4,
      dims: const {'w': 8, 'd': 8},
      material: colorMat(SceneColors.gray),
    ),
    sceneObject(
      id: 'cube',
      name: 'Куб',
      kind: 'cuboid',
      x: 2,
      z: 2,
      dims: const {'w': 1.0, 'h': 1.0, 'd': 1.0},
      material: colorMat(SceneColors.red),
    ),
    sceneObject(
      id: 'tall_box',
      name: 'Высокий ящик',
      kind: 'cuboid',
      x: 6,
      z: 2,
      dims: const {'w': 0.8, 'h': 2.2, 'd': 0.8},
      material: colorMat(SceneColors.green),
    ),
    sceneObject(
      id: 'cylinder',
      name: 'Цилиндр',
      kind: 'cylinder',
      x: 2,
      z: 6,
      dims: const {'bottomR': 0.6, 'topR': 0.6, 'h': 1.4, 'segments': 24},
      material: colorMat(SceneColors.blue),
    ),
    sceneObject(
      id: 'cone',
      name: 'Конус',
      kind: 'cylinder',
      x: 6,
      z: 6,
      dims: const {'bottomR': 0.6, 'topR': 0.0, 'h': 1.4, 'segments': 24},
      material: colorMat(SceneColors.orange),
    ),
  ];
  return doc.ModelData(
    id: 'screen_projection',
    name: 'Проецирование на экран',
    size: doc.ModelSize(w: 8, l: 8, h: 3),
    objects: objects,
  );
}

final FeatureSpec screenProjectionFeature = FeatureSpec(
  id: 'screen_projection',
  group: kFeatureGroups[3],
  title: 'Проецирование на экран',
  phase: 2,
  description:
      'Над объектами сцены рисуются подписи, а вокруг них — рамки, '
      'построенные проецированием трёхмерных координат на экран. Подписи и '
      'рамки пересчитываются каждый кадр, поэтому остаются привязанными к '
      'объектам при движении камеры.',
  checks: const [
    'Подпись каждого объекта расположена над его верхней точкой и не отстаёт при полёте камеры.',
    'Рамка плотно охватывает проекцию объекта и меняет размер при приближении и удалении.',
    'При уходе объекта за край экрана подпись и рамка скрываются, а не остаются на краю.',
    'Переключатели убирают подписи или рамки по отдельности.',
  ],
  build: buildProjectionScene,
  camera: CameraMode.free,
  controls: (context, feature) => _ProjectionControls(feature: feature),
);

class _ProjectionControls extends StatefulWidget {
  const _ProjectionControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_ProjectionControls> createState() => _ProjectionControlsState();
}

class _ProjectionControlsState extends State<_ProjectionControls> {
  bool _labels = true;
  bool _frames = true;

  @override
  void initState() {
    super.initState();
    _installOverlay();
  }

  @override
  void dispose() {
    widget.feature.setOverlay(null);
    super.dispose();
  }

  void _installOverlay() {
    widget.feature.setOverlay(
      (size) => _ProjectionOverlay(
        game: widget.feature.controller,
        size: size,
        showLabels: _labels,
        showFrames: _frames,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Метки и рамки'),
        fcSwitch(
          label: 'Показывать подписи',
          value: _labels,
          onChanged: (v) {
            setState(() => _labels = v);
            _installOverlay();
            widget.feature.refresh();
          },
        ),
        fcSwitch(
          label: 'Показывать рамки',
          value: _frames,
          onChanged: (v) {
            setState(() => _frames = v);
            _installOverlay();
            widget.feature.refresh();
          },
        ),
        fcNote(
          'Подписи и рамки строятся функцией проецирования '
          'worldToScreen: каждый кадр трёхмерные точки объекта переводятся '
          'в экранные координаты.',
        ),
      ],
    );
  }
}

/// Слой подписей и рамок поверх сцены; пересчитывается каждый кадр.
class _ProjectionOverlay extends StatefulWidget {
  const _ProjectionOverlay({
    required this.game,
    required this.size,
    required this.showLabels,
    required this.showFrames,
  });

  final SceneController? game;
  final Size size;
  final bool showLabels;
  final bool showFrames;

  @override
  State<_ProjectionOverlay> createState() => _ProjectionOverlayState();
}

class _ProjectionOverlayState extends State<_ProjectionOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Mark> _marks = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.game != null) _ticker.start();
  }

  @override
  void didUpdateWidget(_ProjectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.game != null && !_ticker.isActive) {
      _ticker.start();
    } else if (widget.game == null && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final game = widget.game;
    if (game == null) {
      if (_marks.isNotEmpty) setState(_marks.clear);
      return;
    }
    final marks = <_Mark>[];
    final model = game.model;
    if (model != null) {
      for (final object in model.visibleObjects()) {
        final node = game.objectNode(object.id);
        if (node == null) continue;
        final position = game.worldToScreen(node.worldPosition);
        if (position == null) continue;
        marks.add(
          _Mark(
            name: object.name,
            position: position,
            rect: game.screenRect(node.worldBounds),
          ),
        );
      }
    }
    setState(() {
      _marks
        ..clear()
        ..addAll(marks);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final mark in _marks) ...[
          if (widget.showFrames && mark.rect != null)
            Positioned.fromRect(
              rect: mark.rect!,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.cyanAccent, width: 2),
                ),
              ),
            ),
          if (widget.showLabels)
            Positioned(
              left: mark.position.dx + 8,
              top: mark.position.dy - 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  mark.name,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Mark {
  _Mark({required this.name, required this.position, required this.rect});

  final String name;
  final Offset position;
  final Rect? rect;
}
