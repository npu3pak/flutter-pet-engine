import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка с ориентирами — фон для двух гизмо.
doc.ModelData buildGizmosScene(FeatureBuildContext context) {
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
      ('post_1', 0.6, 0.6, SceneColors.blue),
      ('post_2', 7.4, 0.6, SceneColors.green),
      ('post_3', 0.6, 5.4, SceneColors.orange),
      ('post_4', 7.4, 5.4, SceneColors.red),
    ])
      sceneObject(
        id: id,
        name: 'Ориентир $id',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: const {'w': 0.4, 'h': 1.0, 'd': 0.4},
        material: colorMat(color),
      ),
  ];
  return doc.ModelData(
    id: 'gizmos',
    name: 'Гизмо',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

final FeatureSpec gizmosFeature = FeatureSpec(
  id: 'gizmos',
  group: kFeatureGroups[3],
  title: 'Гизмо переноса и вращения',
  phase: 2,
  description:
      'Два гизмо движка показаны одновременно: слева стрелки переноса, '
      'справа кольца вращения. Потяните стрелку или кольцо мышью (пальцем) — '
      'объект поедет по оси или повернётся вокруг неё. Размер гизмо в '
      'пикселях постоянен и не зависит от расстояния до камеры; сами гизмо '
      'видны сквозь сцену и перехватывают нажатие раньше объектов.',
  checks: const [
    'Оба гизмо видны одновременно и не меняют размер при приближении камеры.',
    'Драг стрелки двигает объект по её оси, драг кольца вращает вокруг оси.',
    'Гизмо видно сквозь ориентиры, а нажатие по нему не выбирает объекты.',
  ],
  build: buildGizmosScene,
  controls: (context, feature) => _GizmoControls(feature: feature),
);

class _GizmoControls extends StatefulWidget {
  const _GizmoControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_GizmoControls> createState() => _GizmoControlsState();
}

class _GizmoControlsState extends State<_GizmoControls> {
  GroupNode? _root;
  BoxNode? _moveBox;
  BoxNode? _spinBox;
  GizmoNode? _moveGizmo;
  GizmoNode? _spinGizmo;
  late vm.Vector3 _moveStart;
  late vm.Vector3 _spinStart;
  bool _dragging = false;
  String _status = 'потяните стрелку или кольцо';

  @override
  void initState() {
    super.initState();
    widget.feature.setPointerHandlers(
      down: _pointerDown,
      move: _pointerMove,
      up: _pointerUp,
    );
    _install();
  }

  @override
  void dispose() {
    widget.feature.setPointerHandlers();
    _remove();
    super.dispose();
  }

  void _install() {
    final controller = widget.feature.controller;
    if (controller == null) return;
    final root = attachFeatureRoot(controller, 'gizmos');
    _root = root;

    final moveBox = BoxNode(
      id: 'gizmo_move_box',
      name: 'Ящик переноса',
      size: vm.Vector3(1, 1, 1),
      material: SceneMaterial.pbr(
        color: const Color(0xFFE8B34B),
        roughness: 0.7,
      ),
    );
    moveBox.position = featureWorldPoint(controller, 2.2, 0.5, 2.0);
    root.add(moveBox);
    _moveBox = moveBox;
    _moveStart = moveBox.position.clone();

    final spinBox = BoxNode(
      id: 'gizmo_spin_box',
      name: 'Ящик вращения',
      size: vm.Vector3(1, 1, 1),
      material: SceneMaterial.pbr(
        color: const Color(0xFF6FA8DC),
        roughness: 0.7,
      ),
    );
    spinBox.position = featureWorldPoint(controller, 5.8, 0.5, 4.0);
    root.add(spinBox);
    _spinBox = spinBox;
    _spinStart = spinBox.position.clone();

    _moveGizmo = controller.addGizmo(
      GizmoNode(
        id: 'gizmo_move',
        mode: GizmoMode.translate,
        anchor: moveBox.position,
        target: moveBox,
      ),
    );
    _spinGizmo = controller.addGizmo(
      GizmoNode(
        id: 'gizmo_spin',
        mode: GizmoMode.rotate,
        anchor: spinBox.position,
        target: spinBox,
      ),
    );
  }

  void _remove() {
    final controller = widget.feature.controller;
    if (controller != null) {
      final move = _moveGizmo;
      if (move != null) controller.removeGizmo(move);
      final spin = _spinGizmo;
      if (spin != null) controller.removeGizmo(spin);
    }
    _moveGizmo = null;
    _spinGizmo = null;
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    _root = null;
    _moveBox = null;
    _spinBox = null;
  }

  void _pointerDown(Offset position, Size size) {
    final controller = widget.feature.controller;
    if (controller == null) return;
    final hit = controller.beginGizmoDrag(position);
    _dragging = hit != null;
    if (hit == null) return;
    final mode = hit.gizmo.mode == GizmoMode.translate ? 'перенос' : 'поворот';
    setState(() => _status = '$mode · ось ${hit.axis.name.toUpperCase()}');
  }

  void _pointerMove(Offset position, Size size) {
    if (!_dragging) return;
    widget.feature.controller?.updateGizmoDrag(position);
  }

  void _pointerUp(Offset position, Size size) {
    if (!_dragging) return;
    widget.feature.controller?.endGizmoDrag();
    _dragging = false;
  }

  void _reset() {
    final move = _moveBox;
    final spin = _spinBox;
    if (move != null) move.position = _moveStart.clone();
    if (spin != null) {
      spin.position = _spinStart.clone();
      spin.rotation = vm.Vector3.zero();
    }
    setState(() => _status = 'положение сброшено');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fcTitle('Гизмо'),
        fcNote(
          'Слева — перенос (стрелки), справа — вращение (кольца). '
          'Потяните ручку: объект следует за указателем.',
        ),
        fcNote('Статус: $_status'),
        const SizedBox(height: 8),
        fcButton('Сбросить положение', _reset),
        const SizedBox(height: 8),
        fcNote(
          'Оба гизмо остаются одного размера в пикселях при любой дистанции '
          'и видны сквозь ориентиры.',
        ),
      ],
    );
  }
}
