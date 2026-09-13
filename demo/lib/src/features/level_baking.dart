import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

doc.ModelData buildBakingScene(FeatureBuildContext context) =>
    buildLevelShell().data;

/// План запекания оболочки в выбранном режиме: чистые данные, без видеокарты.
LevelBakePlan bakingPlan(BakeMode mode) {
  final model = buildLevelShell();
  for (final element in model.elements) {
    setBakeMode(element, mode);
  }
  return LevelBaker(TextureCache()).plan(model);
}

final FeatureSpec levelBakingFeature = FeatureSpec(
  id: 'level_baking',
  group: kFeatureGroups[5],
  project: 'Pet',
  title: 'Запекание',
  phase: 3,
  description:
      'План запекания оболочки уровня в трёх режимах: общий меш по '
      'материалу (объединение), общий меш по форме и материалу (пакет) и '
      'отдельные узлы. В управлении видно, сколько мешей получится в каждом '
      'режиме и сколько элементов останется отдельными узлами.',
  checks: const [
    'Режим «общий меш по материалу» объединяет полы, потолки, стены и блоки в несколько мешей.',
    'Режим «общий меш по форме и материалу» даёт больше мешей, чем объединение по материалу.',
    'Режим «отдельные узлы» оставляет каждый элемент самостоятельным узлом.',
    'Общее число элементов во всех режимах одинаково — меняется только способ запекания.',
    'Внешний вид сцены при переключении режимов не меняется.',
  ],
  build: buildBakingScene,
  camera: CameraMode.free,
  controls: (context, feature) => _BakingControls(feature: feature),
);

class _BakingControls extends StatefulWidget {
  const _BakingControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_BakingControls> createState() => _BakingControlsState();
}

class _BakingControlsState extends State<_BakingControls> {
  String _mode = 'merge';

  @override
  Widget build(BuildContext context) {
    final mode = switch (_mode) {
      'batch' => BakeMode.batch,
      'node' => BakeMode.node,
      _ => BakeMode.merge,
    };
    final plan = bakingPlan(mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Режим запекания'),
        fcChoice<String>(
          label: 'Как объединять',
          values: const ['merge', 'batch', 'node'],
          selected: _mode,
          labelOf: (v) => switch (v) {
            'batch' => 'по форме и материалу',
            'node' => 'отдельные узлы',
            _ => 'по материалу',
          },
          onChanged: (v) => setState(() => _mode = v),
        ),
        Text(
          'элементов: ${plan.modes.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'объединённых мешей: ${plan.mergedMeshes}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'пакетных мешей: ${plan.batchMeshes}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'отдельных узлов: ${plan.separateNodes}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote(
          'План запекания — чистые данные: он строится без видеокарты и '
          'проверяется автотестами. Само запекание выполняется при сборке '
          'сцены.',
        ),
      ],
    );
  }
}
