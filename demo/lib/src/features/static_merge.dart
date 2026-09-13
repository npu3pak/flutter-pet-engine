import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Сцена с большой группой одинаковых блоков и несколькими уникальными —
/// сравнение числа узлов до и после объединения статики.
doc.ModelData buildStaticMergeScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 5,
      dims: const {'w': 8, 'd': 11},
      material: colorMat(SceneColors.gray),
    ),
    for (var x = 0; x < 6; x++)
      for (var z = 0; z < 6; z++)
        sceneObject(
          id: 'block_${x}_$z',
          name: 'Одинаковый блок $x,$z',
          kind: 'cuboid',
          x: 1 + x * 1.2,
          z: 1 + z * 1.2,
          dims: const {'w': 0.6, 'h': 0.6, 'd': 0.6},
          material: colorMat(SceneColors.red),
        ),
    for (final (i, color) in const [
      (0, SceneColors.green),
      (1, SceneColors.blue),
      (2, SceneColors.orange),
      (3, SceneColors.purple),
      (4, SceneColors.cyan),
      (5, SceneColors.yellow),
    ])
      sceneObject(
        id: 'unique_$i',
        name: 'Уникальный блок $i',
        kind: 'cuboid',
        x: 1 + i * 1.2,
        z: 8.8,
        dims: const {'w': 0.6, 'h': 0.6, 'd': 0.6},
        material: colorMat(color),
      ),
  ];
  return doc.ModelData(
    id: 'static_merge',
    name: 'Слияние статики',
    size: doc.ModelSize(w: 8, l: 11, h: 3),
    objects: objects,
  );
}

/// Сколько узлов останется после объединения статики: объекты группируются
/// по материалу, как в `mergeStaticNodes`. Спрайты, вставки сцен и glTF в
/// объединении не участвуют.
class MergePlan {
  const MergePlan({required this.objects, required this.groups});

  /// Число статических объектов до объединения.
  final int objects;

  /// Число объединённых мешей после (по одному на материал).
  final int groups;
}

MergePlan mergePlanOf(doc.ModelData model) {
  var objects = 0;
  final groups = <String>{};
  for (final object in model.objects) {
    if (object.kind == 'sprite' || object.isModelRef || object.isGltfRef) {
      continue;
    }
    objects++;
    groups.add(_materialKey(object.material));
  }
  return MergePlan(objects: objects, groups: groups.length);
}

String _materialKey(doc.ModelMaterial? material) {
  if (material == null) return 'default';
  return switch (material.type) {
    doc.MaterialType.color => 'color:${material.color.join(',')}',
    _ => '${material.type.name}:${material.key}',
  };
}

final FeatureSpec staticMergeFeature = FeatureSpec(
  id: 'static_merge',
  group: kFeatureGroups[2],
  title: 'Слияние статики',
  phase: 2,
  description:
      'Сцена из 36 одинаковых красных блоков, шести уникальных '
      'синих блоков и пола. Приложение-пример собирает сцену с включённым '
      'объединением неподвижной геометрии: блоки с одинаковым материалом '
      'сливаются в один меш. В управлении видно число узлов до и после '
      'объединения — внешний вид при этом не меняется.',
  checks: const [
    'Сцена выглядит как 36 одинаковых красных блоков, 6 синих и серый пол — без пропавших объектов.',
    'В управлении указано, что до объединения было 43 объекта, а после остаётся 8 объединённых мешей.',
    'Слияние не затрагивает спрайты, вставки сцен и модели glTF — они всегда остаются отдельными.',
    'Сцена с объединением отрисовывается быстрее сцены без объединения при том же внешнем виде.',
  ],
  build: buildStaticMergeScene,
  camera: CameraMode.free,
  controls: (context, feature) => _StaticMergeControls(feature: feature),
);

class _StaticMergeControls extends StatelessWidget {
  const _StaticMergeControls({required this.feature});

  final FeatureContext feature;

  @override
  Widget build(BuildContext context) {
    final plan = mergePlanOf(
      buildStaticMergeScene(
        FeatureBuildContext(project: null, paths: feature.paths),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Объединение статики'),
        Text(
          'Объектов до объединения: ${plan.objects}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'Объединённых мешей после: ${plan.groups}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote(
          'Пример работает с включённым объединением статики: блоки с '
          'одинаковым материалом собираются в один меш. Спрайты, вставки '
          'сцен и glTF не объединяются и остаются отдельными узлами.',
        ),
      ],
    );
  }
}
