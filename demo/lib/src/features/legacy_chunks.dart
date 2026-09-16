import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

/// Преобразует старый чанк проекта Streets в сцену `model_v1`.
Future<doc.ModelData> buildLegacyChunkScene(FeatureBuildContext context) async {
  final project = context.project;
  final index = context.param<int>('index') ?? 1;
  if (project == null) return buildLevelShell().data;
  final bytes = await project.readBytes('chunks/chunk_$index.json');
  if (bytes == null) return buildLevelShell().data;
  return convertLegacyChunk(utf8.decode(bytes), id: 'legacy_chunk_$index');
}

/// Итоги переноса одного чанка: сколько объектов и разметки получилось.
class LegacySummary {
  const LegacySummary({
    required this.objects,
    required this.blocked,
    required this.doors,
    required this.entries,
    required this.front,
  });

  final int objects;
  final int blocked;
  final int doors;
  final int entries;
  final String front;
}

Future<LegacySummary?> summarizeLegacyChunk(
  SceneResources project,
  int index,
) async {
  final bytes = await project.readBytes('chunks/chunk_$index.json');
  if (bytes == null) return null;
  final model = convertLegacyChunk(utf8.decode(bytes), id: 'chunk_$index');
  return LegacySummary(
    objects: model.objects.length,
    blocked: model.metas.where((m) => m.name == metaNameUnpassable).length,
    doors: model.metas.where((m) => m.name == metaNameDoor).length,
    entries: model.entries.length,
    front: model.front?.name ?? 'нет',
  );
}

final FeatureSpec legacyChunksFeature = FeatureSpec(
  id: 'legacy_chunks',
  group: kFeatureGroups[5],
  project: 'Streets',
  title: 'Перенос старых чанков',
  phase: 3,
  description:
      'Импорт совместимости: старый чанк проекта Streets (форматы '
      'chunk_v1/v2/v3) читается и преобразуется в сцену model_v1 — это не '
      'новый формат уровней, а перенос старых данных. Непроходимые клетки '
      'становятся боксами «непроходимо», проходы на границе — боксами «дверь», '
      'входные и лицевая стороны переносятся в поля сцены. Управление '
      'выбирает чанк; в управлении видно, сколько объектов и разметки '
      'получилось.',
  checks: const [
    'Старый чанк отображается в рабочей области без ошибок и пропавших объектов.',
    'Непроходимые клетки чанка стали боксами «непроходимо», их число совпадает с исходным.',
    'Проходы на границе стали боксами «дверь», клетки проходов не закрыты как непроходимые.',
    'Входные и лицевая стороны чанка перенесены в поля сцены.',
    'Переключение номера чанка показывает другой чанк с пересчитанными числами.',
  ],
  build: (context) => buildLevelShell().data,
  asyncBuild: buildLegacyChunkScene,
  camera: CameraMode.free,
  controls: (context, feature) => _LegacyControls(feature: feature),
);

class _LegacyControls extends StatefulWidget {
  const _LegacyControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_LegacyControls> createState() => _LegacyControlsState();
}

class _LegacyControlsState extends State<_LegacyControls> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.feature.params['index'] as int? ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Старый чанк'),
        fcChoice<int>(
          label: 'Номер чанка',
          values: const [1, 2, 3, 4, 5],
          selected: _index,
          labelOf: (v) => 'chunk_$v',
          onChanged: (v) {
            setState(() => _index = v);
            widget.feature.updateParams({'index': v});
          },
        ),
        FutureBuilder<LegacySummary?>(
          future: widget.feature.project == null
              ? null
              : summarizeLegacyChunk(widget.feature.project!, _index),
          builder: (context, snapshot) {
            final summary = snapshot.data;
            if (summary == null) {
              return fcNote('Проект Streets не открыт: перенос недоступен.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'объектов: ${summary.objects}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'непроходимых клеток: ${summary.blocked}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'дверей: ${summary.doors}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  'входных сторон: ${summary.entries}, лицевая: '
                  '${summary.front}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
