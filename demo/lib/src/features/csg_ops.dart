import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Объединение, вычитание и пересечение двух тел, вложенная операция и
/// исходные тела для сравнения.
doc.ModelData buildCsgScene(FeatureBuildContext context) {
  final showSources = context.param<bool>('showSources') ?? true;
  final resultColorName = context.param<String>('resultColor') ?? 'gray';
  final resultColor = switch (resultColorName) {
    'yellow' => SceneColors.yellow,
    'green' => SceneColors.green,
    _ => SceneColors.gray,
  };
  final objects = <doc.ModelObject>[];

  if (showSources) {
    objects.add(
      sceneObject(
        id: 'src_a',
        name: 'Исходное тело А',
        kind: 'cuboid',
        x: 2,
        z: 2,
        dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
        material: colorMat(SceneColors.red),
      ),
    );
    objects.add(
      sceneObject(
        id: 'src_b',
        name: 'Исходное тело Б',
        kind: 'cuboid',
        x: 2.6,
        y: 0.6,
        z: 2.4,
        dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
        material: colorMat(SceneColors.blue),
      ),
    );
  }

  final operations = <(String, double)>[
    (doc.csgOpUnion, 4.5),
    (doc.csgOpDifference, 6.7),
    (doc.csgOpIntersect, 8.9),
  ];
  for (var i = 0; i < operations.length; i++) {
    final (op, x) = operations[i];
    objects.addAll(
      _binaryResult(
        id: 'result_${i + 1}',
        op: op,
        x: x,
        material: colorMat(resultColor),
      ),
    );
  }

  objects.addAll(_nestedResult(material: colorMat(resultColor)));

  return doc.ModelData(
    id: 'csg_ops',
    name: 'Логические операции над телами',
    size: doc.ModelSize(w: 11, l: 8, h: 3),
    objects: objects,
  );
}

List<doc.ModelObject> _binaryResult({
  required String id,
  required String op,
  required double x,
  required doc.ModelMaterial material,
}) {
  final a = sceneObject(
    id: '${id}_a',
    name: '$id тело А',
    kind: 'cuboid',
    x: x,
    z: 2,
    dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
    material: colorMat(SceneColors.red),
  );
  final b = sceneObject(
    id: '${id}_b',
    name: '$id тело Б',
    kind: 'cuboid',
    x: x + 0.6,
    y: 0.6,
    z: 2.4,
    dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
    material: colorMat(SceneColors.blue),
  );
  final result = sceneObject(
    id: id,
    name: 'Результат $id',
    kind: doc.csgKind,
    op: op,
    operands: ['${id}_a', '${id}_b'],
    material: material,
  );
  return [a, b, result];
}

List<doc.ModelObject> _nestedResult({required doc.ModelMaterial material}) {
  final a = sceneObject(
    id: 'nested_a',
    name: 'Вложенная операция, тело А',
    kind: 'cuboid',
    x: 3,
    z: 5.5,
    dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
    material: colorMat(SceneColors.red),
  );
  final b = sceneObject(
    id: 'nested_b',
    name: 'Вложенная операция, тело Б',
    kind: 'cuboid',
    x: 3.6,
    y: 0.6,
    z: 5.9,
    dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
    material: colorMat(SceneColors.blue),
  );
  final union = sceneObject(
    id: 'nested_union',
    name: 'Вложенная операция: объединение',
    kind: doc.csgKind,
    op: doc.csgOpUnion,
    operands: const ['nested_a', 'nested_b'],
    material: colorMat(SceneColors.green),
  );
  final tool = sceneObject(
    id: 'nested_c',
    name: 'Вложенная операция, тело В',
    kind: 'cuboid',
    x: 3.9,
    y: 0.9,
    z: 6.2,
    dims: const {'w': 0.9, 'h': 0.9, 'd': 0.9},
    material: colorMat(SceneColors.purple),
  );
  final result = sceneObject(
    id: 'nested_result',
    name: 'Вложенная операция: результат',
    kind: doc.csgKind,
    op: doc.csgOpDifference,
    operands: const ['nested_union', 'nested_c'],
    material: material,
  );
  return [a, b, union, tool, result];
}

final FeatureSpec csgOpsFeature = FeatureSpec(
  id: 'csg_ops',
  group: kFeatureGroups[0],
  title: 'Логические операции над телами',
  phase: 1,
  description:
      'Три результата булевых операций над двумя пересекающимися '
      'кубами: объединение, вычитание и пересечение. Ниже показана вложенная '
      'операция: сначала тела объединяются, затем из объединения вычитается '
      'третий куб. Исходные тела можно показать или скрыть, цвет результата '
      'переключается.',
  checks: const [
    'Объединение повторяет внешнюю форму обоих тел без внутренней перегородки.',
    'Вычитание оставляет углубление там, где второе тело перекрывало первое.',
    'Пересечение оставляет только общий объём двух тел.',
    'Вложенная операция сначала объединяет тела, а затем вычитает третье — видно и объединение, и вырез.',
    'Переключатель исходных тел показывает два разноцветных куба; материал результата меняет цвет всех результатов.',
  ],
  build: buildCsgScene,
  camera: CameraMode.free,
  controls: (context, feature) => _CsgControls(feature: feature),
);

class _CsgControls extends StatefulWidget {
  const _CsgControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_CsgControls> createState() => _CsgControlsState();
}

class _CsgControlsState extends State<_CsgControls> {
  late bool _showSources;
  late String _resultColor;

  @override
  void initState() {
    super.initState();
    _showSources = widget.feature.params['showSources'] as bool? ?? true;
    _resultColor = widget.feature.params['resultColor'] as String? ?? 'gray';
  }

  void _update() {
    widget.feature.updateParams({
      'showSources': _showSources,
      'resultColor': _resultColor,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Операции'),
        fcNote(
          'Слева направо: объединение, вычитание, пересечение. '
          'Ниже — вложенная операция (объединение, затем вычитание).',
        ),
        fcSwitch(
          label: 'Показывать исходные тела',
          value: _showSources,
          onChanged: (v) {
            setState(() => _showSources = v);
            _update();
          },
        ),
        fcChoice<String>(
          label: 'Материал результата',
          values: const ['gray', 'yellow', 'green'],
          selected: _resultColor,
          labelOf: (v) => switch (v) {
            'yellow' => 'жёлтый',
            'green' => 'зелёный',
            _ => 'серый',
          },
          onChanged: (v) {
            setState(() => _resultColor = v);
            _update();
          },
        ),
      ],
    );
  }
}
