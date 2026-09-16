import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка под пересекающиеся прозрачные спрайты.
doc.ModelData buildTransparencyScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 3,
      dims: const {'w': 8, 'd': 6},
      material: colorMat(SceneColors.gray),
    ),
    sceneObject(
      id: 'back',
      name: 'Задняя стенка',
      kind: 'cuboid',
      x: 4,
      z: 0.4,
      dims: const {'w': 8, 'h': 3, 'd': 0.3},
      material: colorMat(SceneColors.white),
    ),
  ];
  return doc.ModelData(
    id: 'transparency_order',
    name: 'Прозрачность и порядок',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

final FeatureSpec transparencyOrderFeature = FeatureSpec(
  id: 'transparency_order',
  group: kFeatureGroups[2],
  project: 'Pet',
  title: 'Прозрачность и порядок',
  phase: 2,
  description:
      'Две группы пересекающихся прозрачных спрайтов: обычная '
      'прозрачность и аддитивное смешивание. Управление задаёт режим '
      'смешивания, непрозрачность и порядок отрисовки каждой группы; видно, '
      'какая группа рисуется поверх другой и как складывается яркость.',
  checks: const [
    'Обычные прозрачные спрайты затемняют то, что за ними, сохраняя рисунок.',
    'Аддитивные спрайты складывают яркость с фоном: пересечения выглядят светлее.',
    'Изменение порядка отрисовки меняет, какая группа спрайтов оказывается поверх другой.',
    'Уменьшение непрозрачности делает спрайты бледнее, не меняя их порядок.',
  ],
  build: buildTransparencyScene,
  camera: CameraMode.free,
  controls: (context, feature) => _TransparencyControls(feature: feature),
);

class _TransparencyControls extends StatefulWidget {
  const _TransparencyControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_TransparencyControls> createState() => _TransparencyControlsState();
}

class _TransparencyControlsState extends State<_TransparencyControls> {
  BillboardBatchNode? _alphaBatch;
  BillboardBatchNode? _additiveBatch;
  GroupNode? _root;
  bool _loading = true;
  String? _error;

  String _alphaBlend = 'alpha';
  String _additiveBlend = 'additive';
  double _alphaOrder = 0;
  double _additiveOrder = 0;
  double _alphaOpacity = 0.75;
  double _additiveOpacity = 0.8;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  Future<void> _load() async {
    final project = widget.feature.project;
    final game = widget.feature.controller;
    final key = projectSpriteKey(project, 'window_');
    if (project == null || game == null || key == null) {
      setState(() {
        _loading = false;
        _error =
            'Нужен проект Pet со спрайтами (запустите из каталога '
            'example на macOS).';
      });
      return;
    }
    final texture = await project.sprite(key);
    if (!mounted) return;
    if (texture == null) {
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить спрайт $key.';
      });
      return;
    }
    final alpha = BillboardBatchNode(capacity: 8, atlas: texture);
    final additive = BillboardBatchNode(capacity: 8, atlas: texture);
    final root = attachFeatureRoot(game, 'transparency-demo');
    root
      ..add(alpha)
      ..add(additive);
    setState(() {
      _root = root;
      _alphaBatch = alpha;
      _additiveBatch = additive;
      _loading = false;
    });
    _applySettings();
    _writeInstances();
  }

  void _applySettings() {
    _alphaBatch
      ?..blendMode = _alphaBlend == 'additive'
          ? SpriteBlendMode.additive
          : SpriteBlendMode.alpha
      ..blendOrder = _alphaOrder.round();
    _additiveBatch
      ?..blendMode = _additiveBlend == 'additive'
          ? SpriteBlendMode.additive
          : SpriteBlendMode.alpha
      ..blendOrder = _additiveOrder.round();
    _writeInstances();
  }

  void _writeInstances() {
    final alpha = _alphaBatch;
    final additive = _additiveBatch;
    if (alpha == null || additive == null) return;
    final game = widget.feature.controller;
    for (var i = 0; i < 3; i++) {
      alpha.setInstance(
        center: featureWorldPoint(game, 3.2 + i * 0.5, 0.9, 2.8 + i * 0.3),
        width: 1.1,
        height: 1.1,
        color: Color.fromRGBO(242, 89, 89, _alphaOpacity),
      );
      additive.setInstance(
        center: featureWorldPoint(game, 4.4 + i * 0.5, 0.9, 3.2 + i * 0.3),
        width: 1.1,
        height: 1.1,
        color: Color.fromRGBO(89, 191, 255, _additiveOpacity),
      );
    }
    alpha.commit();
    additive.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Пересекающиеся спрайты'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) fcNote(_error!),
        fcNote(
          'Красные спрайты — первая группа, синие — вторая. '
          'Они пересекаются в центре площадки.',
        ),
        fcChoice<String>(
          label: 'Смешивание первой группы',
          values: const ['alpha', 'additive'],
          selected: _alphaBlend,
          labelOf: (v) => v == 'additive' ? 'аддитивное' : 'обычное',
          onChanged: (v) {
            setState(() => _alphaBlend = v);
            _applySettings();
          },
        ),
        fcSlider(
          label: 'Непрозрачность первой',
          value: _alphaOpacity,
          min: 0.1,
          max: 1,
          onChanged: (v) {
            setState(() => _alphaOpacity = v);
            _writeInstances();
          },
        ),
        fcSlider(
          label: 'Порядок первой',
          value: _alphaOrder,
          min: -1,
          max: 1,
          onChanged: (v) {
            setState(() => _alphaOrder = v);
            _applySettings();
          },
        ),
        fcChoice<String>(
          label: 'Смешивание второй группы',
          values: const ['alpha', 'additive'],
          selected: _additiveBlend,
          labelOf: (v) => v == 'additive' ? 'аддитивное' : 'обычное',
          onChanged: (v) {
            setState(() => _additiveBlend = v);
            _applySettings();
          },
        ),
        fcSlider(
          label: 'Непрозрачность второй',
          value: _additiveOpacity,
          min: 0.1,
          max: 1,
          onChanged: (v) {
            setState(() => _additiveOpacity = v);
            _writeInstances();
          },
        ),
        fcSlider(
          label: 'Порядок второй',
          value: _additiveOrder,
          min: -1,
          max: 1,
          onChanged: (v) {
            setState(() => _additiveOrder = v);
            _applySettings();
          },
        ),
      ],
    );
  }
}
