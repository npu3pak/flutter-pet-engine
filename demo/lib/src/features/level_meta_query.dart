import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Сцена с разметкой для запросов: широкий бокс «заезжает краешком» в две
/// клетки, дверь, маркер с дробным якорем и заметка (в запросах не участвует).
doc.ModelData buildMetaQueryScene() {
  final model = doc.ModelData(
    id: 'level_meta_query',
    name: 'Запросы к метам',
    size: doc.ModelSize(w: 8, l: 5, h: 3),
    metas: [
      doc.ModelMeta(
        id: 'q_blocked',
        kind: doc.metaKindBox,
        name: metaNameUnpassable,
        x: 1.5,
        y: 0,
        z: 1,
        dims: const {'w': 2, 'h': 1, 'd': 1},
      ),
      doc.ModelMeta(
        id: 'q_door',
        kind: doc.metaKindBox,
        name: metaNameDoor,
        x: 4,
        y: 0,
        z: 1,
        dims: const {'w': 1, 'h': 1, 'd': 1},
      ),
      doc.ModelMeta(
        id: 'q_spawn',
        kind: doc.metaKindMarker,
        name: 'spawn',
        x: 6.3,
        z: 3.2,
      ),
      doc.ModelMeta(
        id: 'q_note',
        kind: doc.metaKindComment,
        name: 'заметка',
        comment: 'в запросах не участвует',
        x: 0,
        z: 4,
      ),
    ],
  );
  // Подстановки: боксы — брусками, маркер — столбиком в точке якоря.
  var index = 0;
  for (final meta in model.metas) {
    if (meta.kind == doc.metaKindComment) continue;
    final isBox = meta.kind == doc.metaKindBox;
    model.objects.add(
      sceneObject(
        id: 'q_preview_${index++}',
        name: 'Подстановка ${meta.name}',
        kind: 'cuboid',
        x: meta.x,
        y: meta.y,
        z: meta.z,
        dims: isBox
            ? {
                'w': meta.dim('w', 1),
                'h': meta.dim('h', 1),
                'd': meta.dim('d', 1),
              }
            : const {'w': 0.12, 'h': 1.2, 'd': 0.12},
        material: colorMat(
          meta.name == metaNameUnpassable
              ? SceneColors.red
              : meta.name == metaNameDoor
              ? SceneColors.green
              : SceneColors.yellow,
        ),
        tag: 'meta_preview',
      ),
    );
  }
  return model;
}

/// Итоги запросов к метам: клетка, уровень из двух сцен, фильтр по имени.
class MetaQuerySummary {
  const MetaQuerySummary({
    required this.cellLabel,
    required this.cellMetas,
    required this.edgeCellLabel,
    required this.edgeCellMetas,
    required this.rotatedCellLabel,
    required this.rotatedCellMetas,
    required this.total,
    required this.names,
    required this.unpassable,
    required this.comments,
  });

  final String cellLabel;
  final List<String> cellMetas;
  final String edgeCellLabel;
  final List<String> edgeCellMetas;
  final String rotatedCellLabel;
  final List<String> rotatedCellMetas;
  final int total;
  final List<String> names;
  final int unpassable;
  final int comments;
}

MetaQuerySummary summarizeMetaQueries() {
  final sceneA = buildMetaQueryScene();
  final sceneB = doc.ModelData(
    id: 'meta_query_b',
    name: 'Повёрнутая сцена',
    size: doc.ModelSize(w: 4, l: 4, h: 3),
    metas: [
      doc.ModelMeta(
        id: 'q_b_door',
        kind: doc.metaKindBox,
        name: metaNameDoor,
        x: 0,
        z: 2,
        dims: const {'w': 1, 'h': 1, 'd': 1},
      ),
    ],
  );
  final a = ScenePlacement(scene: sceneA, originRow: 0, originCol: 0);
  final b = ScenePlacement(
    scene: sceneB,
    originRow: 0,
    originCol: sceneA.size.w,
    rotY: 90,
  );
  final layout = SceneLayout([a, b]);

  final cell = layout.metasAt(1, 1);
  final edge = layout.metasAt(1, 2);
  final rotated = layout.metasAt(0, sceneA.size.w + 1);
  final names = layout.metaNames.toList()..sort();
  return MetaQuerySummary(
    cellLabel: '(1, 1)',
    cellMetas: [for (final e in cell) e.meta.name],
    edgeCellLabel: '(1, 2)',
    edgeCellMetas: [for (final e in edge) e.meta.name],
    rotatedCellLabel: '(0, ${sceneA.size.w + 1})',
    rotatedCellMetas: [for (final e in rotated) e.meta.name],
    total: layout.allMetas.length,
    names: names,
    unpassable: layout.metasNamed(metaNameUnpassable).length,
    comments: sceneA.metas.where((m) => m.kind == doc.metaKindComment).length,
  );
}

final FeatureSpec levelMetaQueryFeature = FeatureSpec(
  id: 'level_meta_query',
  group: kFeatureGroups[5],
  title: 'Запросы к метам',
  phase: 5,
  description:
      'Запросы к мета-объектам уровневого слоя: меты клетки и '
      'мировой точки, список всех мет уровня, фильтр по имени. В запросах '
      'участвуют только боксы и маркеры: широкий бокс «заезжает краешком» в '
      'две клетки, маркер принадлежит клетке своего якоря, заметки не '
      'участвуют. Результат по клетке считается один раз и кэшируется.',
  checks: const [
    'В управлении видно, какие меты нашлись в клетке под широким боксом.',
    'Соседняя клетка того же бокса отвечает тем же именем («заезжает краешком»).',
    'Повёрнутая сцена находит свою дверь в правильной клетке уровня.',
    'В списке мет уровня три записи (бокс, дверь, маркер), заметка не попала.',
  ],
  build: (context) => buildMetaQueryScene(),
  camera: CameraMode.free,
  controls: (context, feature) => const _MetaQueryControls(),
);

class _MetaQueryControls extends StatelessWidget {
  const _MetaQueryControls();

  @override
  Widget build(BuildContext context) {
    final s = summarizeMetaQueries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Меты клетки'),
        Text(
          'клетка ${s.cellLabel}: ${s.cellMetas.join(', ')}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'клетка ${s.edgeCellLabel}: ${s.edgeCellMetas.join(', ')}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'повёрнутая ${s.rotatedCellLabel}: '
          '${s.rotatedCellMetas.join(', ')}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        fcTitle('Меты уровня'),
        Text(
          'всего: ${s.total}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'имена: ${s.names.join(', ')}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          '«непроходимо»: ${s.unpassable}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote(
          'Заметок в сцене: ${s.comments} — в запросах они не участвуют. '
          'Уровень собран из двух сцен: широкая и повёрнутая на 90°.',
        ),
      ],
    );
  }
}
