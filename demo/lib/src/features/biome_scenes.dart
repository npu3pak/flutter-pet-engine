import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

/// Сцены биомного проекта: непустые, в порядке идентификатора.
List<doc.ModelData> biomeScenes(SceneResources project) {
  final scenes = [
    for (final model in project.models)
      if (model.objects.isNotEmpty) model,
  ];
  scenes.sort((a, b) => a.id.compareTo(b.id));
  return scenes;
}

/// Ряд всех сцен биома через [ScenePlacement] — общий вид конвертированных
/// сцен и проверка расстановки.
Future<doc.ModelData> buildBiomeRow(
  FeatureBuildContext context, {
  required String id,
  required String name,
}) async {
  final project = context.project;
  if (project == null) return buildLevelShell().data;
  final row = buildSceneRow(biomeScenes(project), id: id, name: name);
  return row?.data ?? buildLevelShell().data;
}

/// Итоги биома для панели управления: сцены, геометрия, разметка, проверки.
class BiomeSummary {
  const BiomeSummary({
    required this.scenes,
    required this.objects,
    required this.doors,
    required this.unpassable,
    required this.entries,
    required this.errors,
  });

  final int scenes;
  final int objects;
  final int doors;
  final int unpassable;
  final int entries;
  final int errors;
}

BiomeSummary summarizeBiome(SceneResources project) {
  final validator = LevelValidator();
  var objects = 0, doors = 0, unpassable = 0, entries = 0, errors = 0;
  final scenes = biomeScenes(project);
  for (final scene in scenes) {
    objects += scene.objects.length;
    doors += scene.metas.where((m) => m.name == metaNameDoor).length;
    unpassable += scene.metas.where((m) => m.name == metaNameUnpassable).length;
    entries += scene.entries.length;
    errors += validator
        .checkConstruction(ConstructionModel.wrap(scene))
        .where((i) => i.severity == LevelIssueSeverity.error)
        .length;
  }
  return BiomeSummary(
    scenes: scenes.length,
    objects: objects,
    doors: doors,
    unpassable: unpassable,
    entries: entries,
    errors: errors,
  );
}

FeatureSpec _biomeFeature({
  required String id,
  required String project,
  required String title,
  required String description,
  required List<String> checks,
}) => FeatureSpec(
  id: id,
  group: kFeatureGroups[5],
  project: project,
  title: title,
  phase: 4,
  description: description,
  checks: checks,
  build: (context) => buildLevelShell().data,
  asyncBuild: (context) => buildBiomeRow(context, id: '${id}_row', name: title),
  camera: CameraMode.free,
  controls: (context, feature) => _BiomeControls(feature: feature),
);

/// Подземелье: три сцены из чанков dungeon.
final FeatureSpec biomeDungeonFeature = _biomeFeature(
  id: 'biome_dungeon',
  project: 'Dungeon',
  title: 'Биом: подземелье',
  description:
      'Биом подземелья: три сцены из чанков dungeon собраны в ряд '
      'через размещение на клетках — видно геометрию и материалы после '
      'переноса. В управлении — число объектов, разметки и входных сторон.',
  checks: const [
    'Три сцены подземелья отображаются без ошибок и пропавших объектов.',
    'Сцены стоят в ряд вплотную, без зазоров и наложений footprint-ов.',
    'Входные стороны всех четырёх сторон сохранены после переноса.',
    'Число объектов совпадает с исходными чанками dungeon.',
  ],
);

/// Лес: сцена из чанка forest с непроходимыми клетками.
final FeatureSpec biomeForestFeature = _biomeFeature(
  id: 'biome_forest',
  project: 'Forest',
  title: 'Биом: лес',
  description:
      'Биом леса: сцена из чанка forest с непроходимыми клетками и '
      'входными сторонами; проверяем, что перенос разметки виден и сцена '
      'рисуется без потерь. В управлении — число боксов «непроходимо».',
  checks: const [
    'Сцена леса отображается без ошибок и пропавших объектов.',
    'Непроходимые клетки стали боксами и стоят на своих местах.',
    'Входные стороны восток, юг и запад сохранены после переноса.',
    'Число объектов и боксов совпадает с исходным чанком forest.',
  ],
);

/// Заброшенный дом: комнаты с дверями на границе.
final FeatureSpec biomeAbandonedBuildingFeature = _biomeFeature(
  id: 'biome_abandoned_building',
  project: 'AbandonedBuilding',
  title: 'Биом: заброшенный дом',
  description:
      'Биом заброшенного дома: три комнаты-сцены с дверями на '
      'границе собраны в ряд. Проверяем двери, входные стороны и лицевую '
      'сторону после конвертации чанков в сцены.',
  checks: const [
    'Три комнаты отображаются без ошибок и пропавших объектов.',
    'Двери стали боксами «дверь» на кромке сцены и проходимы.',
    'Входные стороны и лицевая сторона сохранены у каждой комнаты.',
    'Сцены стоят в ряд вплотную, без зазоров и наложений.',
  ],
);

class _BiomeControls extends StatelessWidget {
  const _BiomeControls({required this.feature});

  final FeatureContext feature;

  @override
  Widget build(BuildContext context) {
    final project = feature.project;
    if (project == null) {
      return fcNote('Проект биома не открыт: ряд сцен недоступен.');
    }
    final summary = summarizeBiome(project);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Сцены биома'),
        Text(
          'сцен: ${summary.scenes}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'объектов: ${summary.objects}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'дверей: ${summary.doors}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'непроходимых клеток: ${summary.unpassable}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'входных сторон: ${summary.entries}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'ошибок структуры: ${summary.errors}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        for (final scene in biomeScenes(project))
          Text(
            '${scene.id}: объектов ${scene.objects.length}, '
            'мет ${scene.metas.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        fcNote(
          'Сцены — файлы models/ проекта; ряд собран через '
          'ScenePlacement, ссылки на модели каталога.',
        ),
      ],
    );
  }
}
