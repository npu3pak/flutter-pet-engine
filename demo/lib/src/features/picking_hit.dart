import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка для проверки попадания.
doc.ModelData buildPickingScene(FeatureBuildContext context) {
  return doc.ModelData(
    id: 'picking_hit',
    name: 'Попадание по объекту',
    size: doc.ModelSize(w: 6, l: 10, h: 3),
    objects: [
      sceneObject(
        id: 'ground',
        name: 'Пол',
        kind: 'plane',
        x: 3,
        z: 5,
        dims: const {'w': 6, 'd': 10},
        material: colorMat(SceneColors.gray),
      ),
    ],
  );
}

final FeatureSpec pickingHitFeature = FeatureSpec(
  id: 'picking_hit',
  group: kFeatureGroups[3],
  title: 'Попадание по объекту',
  phase: 2,
  description:
      'Пять целей на разной дальности. Нажатие в рабочей области '
      'выбирает объект двумя способами: по расстоянию до экранной проекции '
      'объекта (рамки) с порогом попадания и лучом через трёхмерную сцену. '
      'Результат показывается в управлении именем объекта.',
  checks: const [
    'В режиме «по расстоянию на экране» нажатие рядом с объектом выбирает его, даже если луч прошёл мимо.',
    'Уменьшение порога попадания делает выбор строже: далёкие от центра нажатия перестают выбирать объект.',
    'В режиме «лучом» выбирается объект, который реально находится под указателем, включая дальние цели.',
    'Нажатие по пустому месту даёт результат «промах» в обоих режимах.',
  ],
  build: buildPickingScene,
  camera: CameraMode.free,
  controls: (context, feature) => _PickingControls(feature: feature),
);

class _PickingControls extends StatefulWidget {
  const _PickingControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_PickingControls> createState() => _PickingControlsState();
}

class _PickingControlsState extends State<_PickingControls> {
  GroupNode? _root;
  final List<BoxNode> _targets = [];
  String _mode = 'screen';
  double _threshold = 60;
  String _result = 'нажмите по объекту в рабочей области';

  static const _colors = [
    Color(0xFFD64C4C),
    Color(0xFFE69646),
    Color(0xFFDEC458),
    Color(0xFF60BA70),
    Color(0xFF5684D6),
  ];

  @override
  void initState() {
    super.initState();
    widget.feature.setTap(_handleTap);
    _installTargets();
  }

  @override
  void dispose() {
    widget.feature.setTap(null);
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  void _installTargets() {
    final controller = widget.feature.controller;
    if (controller == null) return;
    final root = attachFeatureRoot(controller, 'picking-targets');
    _root = root;
    for (var i = 0; i < 5; i++) {
      final node = BoxNode(
        name: 'Цель $i',
        size: vm.Vector3(0.9, 0.9, 0.9),
        material: SceneMaterial.pbr(color: _colors[i], roughness: 0.8),
      );
      node.position = featureWorldPoint(controller, 3, 0.45, 1.5 + i * 1.7);
      root.add(node);
      _targets.add(node);
    }
  }

  void _handleTap(Offset position, Size size) {
    final game = widget.feature.controller;
    if (game == null) return;
    if (_mode == 'ray') {
      final hit = game.raycast(position);
      setState(() {
        _result = hit == null ? 'промах' : 'лучом: ${hit.node.name}';
      });
      return;
    }
    // По расстоянию: сравниваем нажатие с экранной рамкой проекции объекта,
    // а не с одной точкой якоря, иначе верхние части целей не попадают.
    SceneNode? picked;
    var bestDistance = _threshold;
    for (final node in _targets) {
      final bounds = node.worldBounds;
      if (bounds == null) continue;
      final rect = game.screenRect(bounds);
      if (rect == null) continue;
      final distance = rect.contains(position)
          ? 0.0
          : _distanceToRect(position, rect);
      if (distance <= bestDistance) {
        bestDistance = distance;
        picked = node;
      }
    }
    setState(() {
      _result = picked == null ? 'промах' : 'по экрану: ${picked.name}';
    });
  }

  double _distanceToRect(Offset point, Rect rect) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : (point.dy > rect.bottom ? point.dy - rect.bottom : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Выбор объекта'),
        fcChoice<String>(
          label: 'Способ выбора',
          values: const ['screen', 'ray'],
          selected: _mode,
          labelOf: (v) => v == 'ray' ? 'лучом' : 'по расстоянию на экране',
          onChanged: (v) => setState(() => _mode = v),
        ),
        if (_mode == 'screen')
          fcSlider(
            label: 'Порог попадания',
            value: _threshold,
            min: 10,
            max: 200,
            format: (v) => '${v.round()} пикс.',
            onChanged: (v) => setState(() => _threshold = v),
          ),
        fcNote('Результат: $_result'),
      ],
    );
  }
}
