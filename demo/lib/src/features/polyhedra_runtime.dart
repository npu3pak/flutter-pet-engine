import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';
import 'polyhedra_common.dart';

/// Куб как runtime-узел: [PolyMesh.box] + материал по умолчанию и
/// переопределение верхней грани.
PolyhedronNode buildRuntimeBoxNode() => PolyhedronNode(
  name: 'Куб (PolyMesh.box)',
  mesh: PolyMesh.box(w: 1.2, h: 1.2, d: 1.2),
  material: SceneMaterial.pbr(color: rgbColor(SceneColors.gray)),
  faceMaterials: {
    '+y': SceneMaterial.pbr(color: rgbColor(SceneColors.green)),
  },
);

/// Вогнутая L-призма как runtime-узел: цвета по граням через `faces`.
PolyhedronNode buildRuntimePrismNode() => PolyhedronNode(
  name: 'L-призма (extrudeProfile)',
  mesh: extrudeProfile(
    profile: [
      vm.Vector2(-1.2, -1.2),
      vm.Vector2(1.2, -1.2),
      vm.Vector2(1.2, -0.4),
      vm.Vector2(-0.4, -0.4),
      vm.Vector2(-0.4, 1.2),
      vm.Vector2(-1.2, 1.2),
    ],
    height: 1.6,
  ),
  material: SceneMaterial.pbr(color: rgbColor(SceneColors.blue)),
  faceMaterials: {
    '+y': SceneMaterial.pbr(color: rgbColor(SceneColors.green)),
    'side_0': SceneMaterial.pbr(color: rgbColor(SceneColors.cyan)),
    'side_1': SceneMaterial.pbr(color: rgbColor(SceneColors.orange)),
    'side_4': SceneMaterial.pbr(color: rgbColor(SceneColors.purple)),
  },
);

/// Плита с отверстием как runtime-узел: красные стенки отверстия.
PolyhedronNode buildRuntimeSlabNode() => PolyhedronNode(
  name: 'Плита с отверстием (plateWithHole)',
  mesh: plateWithHole(
    width: 1.8,
    depth: 1.8,
    thickness: 0.35,
    holeWidth: 0.9,
    holeDepth: 0.9,
  ),
  material: SceneMaterial.pbr(color: rgbColor(SceneColors.cyan)),
  faceMaterials: {
    'hole_0': SceneMaterial.pbr(color: rgbColor(SceneColors.red)),
    'hole_1': SceneMaterial.pbr(color: rgbColor(SceneColors.red)),
    'hole_2': SceneMaterial.pbr(color: rgbColor(SceneColors.red)),
    'hole_3': SceneMaterial.pbr(color: rgbColor(SceneColors.red)),
  },
);

/// Документ фичи: только площадка. Сами многогранники — runtime-узлы,
/// которые управление добавляет в сцену напрямую ([PolyhedronNode]).
doc.ModelData buildPolyhedraRuntimeScene(FeatureBuildContext context) {
  return doc.ModelData(
    id: 'polyhedra_runtime',
    name: 'Многогранники: runtime-узлы',
    size: doc.ModelSize(w: 6, l: 4, h: 3),
    objects: [
      sceneObject(
        id: 'ground',
        name: 'Площадка',
        kind: 'plane',
        x: 3,
        z: 2,
        dims: const {'w': 6, 'd': 4},
        material: colorMat(SceneColors.gray),
      ),
    ],
  );
}

final FeatureSpec polyhedraRuntimeFeature = FeatureSpec(
  id: 'polyhedra_runtime',
  group: kFeatureGroups[8],
  title: 'Runtime-узел PolyhedronNode',
  phase: 6,
  description:
      'Три многогранника добавлены в сцену напрямую узлом PolyhedronNode, '
      'без документа: узел принимает PolyMesh, общий материал и материалы '
      'по граням. Ползунок вытягивает куб по Y (масштаб по осям наследуется '
      'от SceneNode), переключатель снимает и возвращает переопределение '
      'верхней грани.',
  checks: const [
    'Три многогранника стоят на площадке: куб, L-призма и плита с отверстием.',
    'Ползунок вытягивает только куб по высоте — остальные не меняются.',
    'Переключатель «Верх куба зелёный» мгновенно меняет материал грани +y.',
    'Красные стенки отверстия видны сквозь плиту: материалы по граням работают.',
  ],
  build: buildPolyhedraRuntimeScene,
  camera: CameraMode.free,
  controls: (context, feature) => _PolyhedraRuntimeControls(feature: feature),
);

class _PolyhedraRuntimeControls extends StatefulWidget {
  const _PolyhedraRuntimeControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_PolyhedraRuntimeControls> createState() =>
      _PolyhedraRuntimeControlsState();
}

class _PolyhedraRuntimeControlsState extends State<_PolyhedraRuntimeControls> {
  GroupNode? _root;
  PolyhedronNode? _box;
  SceneMaterial? _boxTop;
  bool _topEnabled = true;
  double _stretch = 1.0;

  @override
  void initState() {
    super.initState();
    final controller = widget.feature.controller;
    if (controller == null) return;
    final root = attachFeatureRoot(controller, 'polyhedra-runtime');
    _root = root;

    final box = buildRuntimeBoxNode();
    _box = box;
    _boxTop = box.faceMaterial('+y');
    box.position = featureWorldPoint(controller, 1.5, 0, 2);
    root.add(box);

    final prism = buildRuntimePrismNode();
    prism.position = featureWorldPoint(controller, 3, 0, 2);
    root.add(prism);

    final slab = buildRuntimeSlabNode();
    slab.position = featureWorldPoint(controller, 4.5, 0.9, 2);
    root.add(slab);
  }

  @override
  void dispose() {
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Runtime-узел'),
        fcSlider(
          label: 'Вытянуть куб (scale.y)',
          value: _stretch,
          min: 0.5,
          max: 3,
          onChanged: (value) {
            setState(() => _stretch = value);
            _box?.scale = vm.Vector3(1, value, 1);
          },
        ),
        fcSwitch(
          label: 'Верх куба зелёный',
          value: _topEnabled,
          onChanged: (value) {
            setState(() => _topEnabled = value);
            _box?.setFaceMaterial('+y', value ? _boxTop : null);
          },
        ),
        fcLegend([
          LegendEntry(rgbColor(SceneColors.gray), 'Куб: материал узла'),
          LegendEntry(rgbColor(SceneColors.green), 'Куб: faces[«+y»]'),
          LegendEntry(rgbColor(SceneColors.blue), 'L-призма: faceMaterials'),
          LegendEntry(rgbColor(SceneColors.red), 'Стенки отверстия плиты'),
        ]),
        fcNote(
          'PolyhedronNode(mesh: ..., material: ..., faceMaterials: {...}) — '
          'один узел на всю сеть. Материал ищется по ключу грани, как в '
          'документе: setFaceMaterial(«+y», null) возвращает общий материал.',
        ),
      ],
    );
  }
}
