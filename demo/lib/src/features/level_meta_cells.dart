import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Боксы разметки уровня: непроходимая стена, дверь и окно.
List<doc.ModelMeta> levelMetaBoxes() => [
  doc.ModelMeta(
    id: 'meta_blocked',
    kind: doc.metaKindBox,
    name: metaNameUnpassable,
    x: 3,
    y: 0,
    z: 3,
    dims: const {'w': 5, 'h': 1, 'd': 1},
  ),
  doc.ModelMeta(
    id: 'meta_door',
    kind: doc.metaKindBox,
    name: metaNameDoor,
    x: 3,
    y: 0,
    z: 3,
    dims: const {'w': 1, 'h': 1, 'd': 1},
  ),
  doc.ModelMeta(
    id: 'meta_window',
    kind: doc.metaKindBox,
    name: metaNameWindow,
    x: 1,
    y: 0,
    z: 2,
    dims: const {'w': 1, 'h': 1, 'd': 1},
  ),
];

doc.ModelData buildLevelMetaModel() {
  final model = doc.ModelData(
    id: 'level_meta_cells',
    name: 'Боксы разметки и клетки',
    size: doc.ModelSize(w: 7, l: 6, h: 3),
    metas: levelMetaBoxes(),
  );
  // Подстановки на месте боксов: видно, какие клетки закрыты.
  var index = 0;
  for (final meta in model.metas) {
    model.objects.add(
      sceneObject(
        id: 'preview_${index++}',
        name: 'Подстановка ${meta.name}',
        kind: 'cuboid',
        x: meta.x,
        y: meta.y,
        z: meta.z,
        dims: {
          'w': meta.dim('w', 1),
          'h': meta.dim('h', 1),
          'd': meta.dim('d', 1),
        },
        material: colorMat(
          meta.name == metaNameUnpassable
              ? SceneColors.red
              : meta.name == metaNameDoor
              ? SceneColors.green
              : SceneColors.cyan,
        ),
        tag: 'meta_preview',
      ),
    );
  }
  return model;
}

doc.ModelData buildLevelMetaScene(FeatureBuildContext context) =>
    buildLevelMetaModel();

/// Итоги правила «клетка занята, если её центр внутри бокса».
class LevelMetaSummary {
  const LevelMetaSummary({
    required this.blocked,
    required this.doors,
    required this.windows,
    required this.doorPassable,
    required this.blockedPassable,
  });

  final int blocked;
  final int doors;
  final int windows;
  final bool doorPassable;
  final bool blockedPassable;
}

LevelMetaSummary summarizeLevelMeta() {
  final placement = ScenePlacement(
    scene: buildLevelMetaModel(),
    originRow: 0,
    originCol: 0,
  );
  return LevelMetaSummary(
    blocked: placement.unpassableCells.length,
    doors: placement.doorCells.length,
    windows: placement.windowCells.length,
    doorPassable: placement.isCellPassable(3, 3),
    blockedPassable: placement.isCellPassable(1, 3),
  );
}

final FeatureSpec levelMetaCellsFeature = FeatureSpec(
  id: 'level_meta_cells',
  group: kFeatureGroups[5],
  title: 'Боксы разметки и клетки',
  phase: 3,
  description:
      'Правило уровневого слоя: клетка занята, если её центр попал '
      'внутрь бокса разметки. Бокс «непроходимо» закрывает клетки, бокс '
      '«дверь» делает клетку проходимой даже поверх запрета, бокс «окно» — '
      'только разметка. Подстановки показывают, какие клетки закрыты.',
  checks: const [
    'В управлении видно число клеток, закрытых боксами «непроходимо», «дверь» и «окно».',
    'Клетка под боксом «дверь» считается проходимой, даже если накрыта боксом «непроходимо».',
    'Клетка под боксом «непроходимо» без двери считается непроходимой.',
    'Окно не влияет на проходимость: клетка под ним остаётся проходимой.',
  ],
  build: buildLevelMetaScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _LevelMetaControls(),
);

class _LevelMetaControls extends StatelessWidget {
  const _LevelMetaControls();

  @override
  Widget build(BuildContext context) {
    final summary = summarizeLevelMeta();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Клетки под боксами'),
        Text(
          '«непроходимо»: ${summary.blocked} клеток',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          '«дверь»: ${summary.doors} клеток',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          '«окно»: ${summary.windows} клеток',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote(
          'Дверная клетка проходима: '
          '${summary.doorPassable ? 'да' : 'нет'}. '
          'Клетка стены проходима: '
          '${summary.blockedPassable ? 'да' : 'нет'}.',
        ),
      ],
    );
  }
}
