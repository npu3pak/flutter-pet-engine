import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Сцена с объектами разметки: комментарий, маркер и боксы с именами.
///
/// Движок не рисует объекты разметки: это данные для редактора и игровой
/// логики. Чтобы было видно, где они находятся, на их местах стоят цветные
/// тела-подстановки с тегом `meta_preview`.
doc.ModelData buildMetaModel() {
  final metas = <doc.ModelMeta>[
    doc.ModelMeta(
      id: 'meta_comment',
      kind: doc.metaKindComment,
      name: 'Комментарий',
      comment: 'Здесь начинается разметка сцены',
      x: 1,
      y: 1.2,
      z: 1,
    ),
    doc.ModelMeta(
      id: 'meta_marker',
      kind: doc.metaKindMarker,
      name: 'Точка обзора',
      comment: 'Проверка маркера камеры',
      x: 2.5,
      z: 1,
    ),
    doc.ModelMeta(
      id: 'meta_box_spawn',
      kind: doc.metaKindBox,
      name: 'зона_спавна',
      x: 6,
      y: 0,
      z: 3,
      dims: const {'w': 2, 'h': 1, 'd': 2},
    ),
    doc.ModelMeta(
      id: 'meta_box_spawn_2',
      kind: doc.metaKindBox,
      name: 'зона_спавна',
      x: 6,
      y: 0,
      z: 5,
      dims: const {'w': 1, 'h': 1, 'd': 1},
    ),
    doc.ModelMeta(
      id: 'meta_box_blocked',
      kind: doc.metaKindBox,
      name: 'непроходимо',
      x: 9,
      y: 0,
      z: 3,
      dims: const {'w': 1.5, 'h': 2, 'd': 1.5},
    ),
  ];

  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'preview_comment',
      name: 'Подстановка комментария',
      kind: 'cuboid',
      x: 1,
      y: 0,
      z: 1,
      dims: const {'w': 0.4, 'h': 0.4, 'd': 0.4},
      material: colorMat(SceneColors.green),
      tag: 'meta_preview',
    ),
    sceneObject(
      id: 'preview_marker',
      name: 'Подстановка маркера',
      kind: 'cuboid',
      x: 2.5,
      y: 0,
      z: 1,
      dims: const {'w': 0.4, 'h': 1.2, 'd': 0.4},
      material: colorMat(SceneColors.yellow),
      tag: 'meta_preview',
    ),
    sceneObject(
      id: 'preview_spawn_1',
      name: 'Подстановка бокса «зона_спавна»',
      kind: 'cuboid',
      x: 6,
      y: 0,
      z: 3,
      dims: const {'w': 2, 'h': 1, 'd': 2},
      material: colorMat(SceneColors.blue),
      tag: 'meta_preview',
    ),
    sceneObject(
      id: 'preview_spawn_2',
      name: 'Подстановка бокса «зона_спавна»',
      kind: 'cuboid',
      x: 6,
      y: 0,
      z: 5,
      dims: const {'w': 1, 'h': 1, 'd': 1},
      material: colorMat(SceneColors.cyan),
      tag: 'meta_preview',
    ),
    sceneObject(
      id: 'preview_blocked',
      name: 'Подстановка бокса «непроходимо»',
      kind: 'cuboid',
      x: 9,
      y: 0,
      z: 3,
      dims: const {'w': 1.5, 'h': 2, 'd': 1.5},
      material: colorMat(SceneColors.red),
      tag: 'meta_preview',
    ),
  ];

  return doc.ModelData(
    id: 'meta_objects',
    name: 'Объекты разметки',
    size: doc.ModelSize(w: 12, l: 7, h: 3),
    objects: objects,
    metas: metas,
  );
}

doc.ModelData buildMetaScene(FeatureBuildContext context) => buildMetaModel();

/// Уникальные имена боксов разметки в сцене.
List<String> metaBoxNames(doc.ModelData model) {
  final names = <String>{};
  for (final meta in model.metas) {
    if (meta.isBox && meta.name.isNotEmpty) names.add(meta.name);
  }
  return names.toList()..sort();
}

/// Клетки, накрытые боксами с именем [name].
Set<(int, int)> metaBoxCells(doc.ModelData model, String name) =>
    ScenePlacement(
      scene: model,
      originRow: 0,
      originCol: 0,
    ).cellsUnderBoxes(name);

final FeatureSpec metaObjectsFeature = FeatureSpec(
  id: 'meta_objects',
  group: kFeatureGroups[0],
  title: 'Объекты разметки',
  phase: 1,
  description:
      'В сцене есть объекты разметки: комментарий, маркер и боксы с '
      'именами. Движок не рисует разметку — это данные; на местах объектов '
      'стоят цветные тела-подстановки. Управление показывает запросы: какие '
      'боксы имеют заданное имя и какие клетки закрыты боксами.',
  checks: const [
    'В управлении перечислены имена боксов сцены, и у каждого видно число закрытых клеток.',
    'Боксы с одинаковым именем «зона_спавна» объединяются в один результат запроса.',
    'Подстановки на месте боксов совпадают по положению и размеру с данными разметки.',
    'Комментарий и маркер перечислены отдельно и не попадают в список боксов.',
  ],
  build: buildMetaScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _MetaControls(),
);

class _MetaControls extends StatelessWidget {
  const _MetaControls();

  @override
  Widget build(BuildContext context) {
    final model = buildMetaModel();
    final names = metaBoxNames(model);
    final comments = model.metas
        .where(
          (m) => m.kind == doc.metaKindComment || m.kind == doc.metaKindMarker,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Боксы разметки'),
        for (final name in names)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '«$name» — клеток: ${metaBoxCells(model, name).length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        fcTitle('Комментарии и маркеры'),
        for (final meta in comments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${meta.kind == doc.metaKindComment ? 'Комментарий' : 'Маркер'} '
              '«${meta.name}» в клетке (${meta.x.round()}, ${meta.z.round()})',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        fcNote(
          'Правило движка: клетка занята, если её центр попал внутрь '
          'бокса. Бокс «непроходимо» закрывает клетки, боксы с другими '
          'именами — только разметка.',
        ),
      ],
    );
  }
}
