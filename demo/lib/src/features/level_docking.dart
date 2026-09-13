import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

/// Ряд домов проекта Streets через [ScenePlacement].
Future<doc.ModelData> buildDockingScene(FeatureBuildContext context) async {
  final project = context.project;
  if (project == null) return buildLevelShell().data;
  final houses = streetHouses(project.models.toList());
  final row = buildStreetsRow(houses);
  return row?.data ?? buildLevelShell().data;
}

/// Итог автоматической проверки стыковки ряда домов.
class DockingSummary {
  const DockingSummary({
    required this.houses,
    required this.overlaps,
    required this.dockedPairs,
    required this.sharedSides,
  });

  final int houses;
  final int overlaps;
  final int dockedPairs;
  final List<String> sharedSides;
}

DockingSummary summarizeDocking(SceneResources project) {
  final houses = streetHouses(project.models.toList());
  if (houses.isEmpty) {
    return const DockingSummary(
      houses: 0,
      overlaps: 0,
      dockedPairs: 0,
      sharedSides: [],
    );
  }
  final placements = <ScenePlacement>[];
  var col = 0;
  for (final house in houses) {
    final placement = ScenePlacement(
      scene: house,
      originRow: 0,
      originCol: col,
    );
    placements.add(placement);
    col += placement.footprintCols;
  }
  final layout = SceneLayout(placements);
  var docked = 0;
  final sides = <String>[];
  for (var i = 0; i + 1 < placements.length; i++) {
    final a = placements[i];
    final b = placements[i + 1];
    if (layout.dockedWith(a, b)) {
      docked++;
      sides.add(
        '${i + 1}–${i + 2}: '
        '${SceneLayout.sharedSide(a, b)?.name ?? '—'}',
      );
    }
  }
  return DockingSummary(
    houses: houses.length,
    overlaps: layout.overlaps.length,
    dockedPairs: docked,
    sharedSides: sides,
  );
}

final FeatureSpec levelDockingFeature = FeatureSpec(
  id: 'level_docking',
  group: kFeatureGroups[5],
  title: 'Стыковка сцен',
  project: 'Streets',
  phase: 3,
  description:
      'Ряд домов из проекта Streets собирается из сцен-домов через '
      'размещение на клетках: дома ставятся вплотную, стыковка проверяется '
      'автоматически (общие грани, входные и лицевая стороны). В управлении '
      'видно число домов, пар с общей гранью и найденных наложений.',
  checks: const [
    'Дома выстроены в ряд вплотную друг к другу, без зазоров и наложений.',
    'Автоматическая проверка показывает пары домов с общей гранью и сторону стыка.',
    'Входные и лицевая стороны домов не пересекаются с соседними стенами.',
    'В управлении указано число домов и отсутствие наложений.',
  ],
  build: (context) => buildLevelShell().data,
  asyncBuild: buildDockingScene,
  camera: CameraMode.free,
  controls: (context, feature) => _DockingControls(feature: feature),
);

class _DockingControls extends StatelessWidget {
  const _DockingControls({required this.feature});

  final FeatureContext feature;

  @override
  Widget build(BuildContext context) {
    final project = feature.project;
    if (project == null) {
      return fcNote('Проект Streets не открыт: ряд домов недоступен.');
    }
    final summary = summarizeDocking(project);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Ряд домов'),
        Text(
          'домов: ${summary.houses}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'наложений: ${summary.overlaps}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          'пар с общей гранью: ${summary.dockedPairs}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        for (final side in summary.sharedSides)
          Text(
            side,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        fcNote(
          'Дома — это сцены проекта Streets; каждая вставлена как '
          'отдельная модель (kind «model») и запечена как отдельный узел.',
        ),
      ],
    );
  }
}
