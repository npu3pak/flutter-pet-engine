import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка и несколько ящиков — ориентиры для потока спрайтов.
doc.ModelData buildBillboardScene(FeatureBuildContext context) {
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
    for (final (id, x, z, color) in const [
      ('post_1', 1.5, 1.5, SceneColors.red),
      ('post_2', 6.5, 1.5, SceneColors.green),
      ('post_3', 1.5, 4.5, SceneColors.blue),
      ('post_4', 6.5, 4.5, SceneColors.orange),
    ])
      sceneObject(
        id: id,
        name: 'Ориентир $id',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: const {'w': 0.6, 'h': 1.2, 'd': 0.6},
        material: colorMat(color),
      ),
  ];
  return doc.ModelData(
    id: 'billboard_batch',
    name: 'Пакетная отрисовка',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

final FeatureSpec billboardBatchFeature = FeatureSpec(
  id: 'billboard_batch',
  group: kFeatureGroups[2],
  project: 'Pet',
  title: 'Пакетная отрисовка',
  phase: 2,
  description:
      'Один вызов отрисовки рисует много одинаковых спрайтов '
      '(BillboardBatch). Управление задаёт число спрайтов, режим разворота '
      '(к камере, с фиксированной осью, растяжение по скорости, параллельно '
      'экрану), режим смешивания, порядок отрисовки и кадр спрайта. Спрайты '
      'движутся по кругу, чтобы разницу режимов было видно.',
  checks: const [
    'При увеличении числа спрайтов они появляются по кольцу, частота кадров почти не падает.',
    'Режим «к камере» всегда разворачивает спрайты к наблюдателю при облёте сцены.',
    'Режим «растяжение по скорости» вытягивает спрайты вдоль направления движения.',
    'Режим «параллельно экрану» не даёт спрайтам наклоняться при взгляде сверху.',
    'Переключение смешивания «обычное / аддитивное» меняет вид пересечений: аддитивные спрайты складывают яркость.',
    'Ползунок порядка отрисовки меняет, какие спрайты рисуются поверх других.',
  ],
  build: buildBillboardScene,
  camera: CameraMode.free,
  controls: (context, feature) => _BillboardControls(feature: feature),
);

class _BillboardControls extends StatefulWidget {
  const _BillboardControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_BillboardControls> createState() => _BillboardControlsState();
}

class _BillboardControlsState extends State<_BillboardControls> {
  BillboardBatchNode? _batch;
  SceneTexture? _texture;
  GroupNode? _root;
  bool _loading = true;
  String? _error;
  double _clock = 0;

  String _facing = 'spherical';
  String _blend = 'alpha';
  double _order = 0;
  double _count = 60;
  double _frame = 0;

  @override
  void initState() {
    super.initState();
    widget.feature.setTick(_tick);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.feature.setTick(null);
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
            'demo на macOS).';
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
    final batch = BillboardBatchNode(capacity: 256, atlas: texture);
    final root = attachFeatureRoot(game, 'billboard-batch-demo');
    root.add(batch);
    setState(() {
      _texture = texture;
      _root = root;
      _batch = batch;
      _loading = false;
    });
    _applySettings();
  }

  void _applySettings() {
    final batch = _batch;
    if (batch == null) return;
    batch
      ..facing = switch (_facing) {
        'axisLocked' => BillboardFacing.axisLocked,
        'velocityStretched' => BillboardFacing.velocityStretched,
        'screenParallel' => BillboardFacing.screenParallel,
        _ => BillboardFacing.spherical,
      }
      ..blendMode = _blend == 'additive'
          ? SpriteBlendMode.additive
          : SpriteBlendMode.alpha
      ..blendOrder = _order.round();
  }

  void _tick(double dt) {
    _clock += dt;
    final batch = _batch;
    if (batch == null) return;
    final count = _count.round();
    for (var i = 0; i < count; i++) {
      final angle = _clock * 0.6 + i * 2 * math.pi / math.max(count, 1);
      final center = featureWorldPoint(
        widget.feature.controller,
        4 + math.cos(angle) * 2.5,
        0.6 + math.sin(_clock + i) * 0.15,
        3 + math.sin(angle) * 2.5,
      );
      final velocity = _facing == 'velocityStretched'
          ? vm.Vector3(-math.sin(angle), 0, math.cos(angle)) * 2.0
          : null;
      batch.setInstance(
        center: center,
        width: 0.6,
        height: 0.6,
        rotation: _clock + i * 0.4,
        frame: _frame.round(),
        velocity: velocity,
      );
    }
    batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Поток спрайтов'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) fcNote(_error!),
        if (_texture != null)
          fcNote(
            'Спрайт: ${projectSpriteKey(widget.feature.project, 'window_')}',
          ),
        fcSlider(
          label: 'Число спрайтов',
          value: _count,
          min: 1,
          max: 200,
          format: (v) => v.round().toString(),
          onChanged: (v) {
            setState(() => _count = v);
            _applySettings();
          },
        ),
        fcChoice<String>(
          label: 'Разворот',
          values: const [
            'spherical',
            'axisLocked',
            'velocityStretched',
            'screenParallel',
          ],
          selected: _facing,
          labelOf: (v) => switch (v) {
            'axisLocked' => 'фиксированная ось',
            'velocityStretched' => 'растяжение по скорости',
            'screenParallel' => 'параллельно экрану',
            _ => 'к камере',
          },
          onChanged: (v) {
            setState(() => _facing = v);
            _applySettings();
          },
        ),
        fcChoice<String>(
          label: 'Смешивание',
          values: const ['alpha', 'additive'],
          selected: _blend,
          labelOf: (v) => v == 'additive' ? 'аддитивное' : 'обычное',
          onChanged: (v) {
            setState(() => _blend = v);
            _applySettings();
          },
        ),
        fcSlider(
          label: 'Порядок отрисовки',
          value: _order,
          min: -1,
          max: 1,
          onChanged: (v) {
            setState(() => _order = v);
            _applySettings();
          },
        ),
        fcSlider(
          label: 'Кадр спрайта',
          value: _frame,
          min: 0,
          max: 1,
          format: (v) => v.round().toString(),
          onChanged: (v) => setState(() => _frame = v.roundToDouble()),
        ),
      ],
    );
  }
}
