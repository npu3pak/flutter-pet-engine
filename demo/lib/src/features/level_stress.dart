import 'package:flutter/material.dart';

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

final FeatureSpec levelStressFeature = FeatureSpec(
  id: 'level_stress',
  group: kFeatureGroups[5],
  project: 'Pet',
  title: 'Стресс-проверка',
  phase: 3,
  description:
      'Отдельный экран для больших уровней: размер стороны сетки от '
      '10 до 100, число клеток, предупреждение о заминке интерфейса и оценка '
      'времени по последнему измерению. Кнопка «Запустить» собирает уровень, '
      'запекает его и показывает время сборки и запекания, число элементов и '
      'узлов, вершины, треугольники и частоту кадров. Результат дописывается '
      'в журнал docs/perf_journal.md.',
  checks: const [
    'Ползунок размера ограничен значениями от 10 до 100, рядом показано число клеток.',
    'Перед запуском видно предупреждение, что окно на время сборки перестанет отвечать.',
    'После первого запуска появляется оценка времени по последнему измерению.',
    'Экран результатов показывает время сборки, запекания, число элементов, объединённых мешей, отдельных узлов, вершин, треугольников и частоту кадров.',
    'Секция с результатом дописывается в docs/perf_journal.md, старая история не удаляется.',
    'Кнопка «Назад» возвращает в приложение к списку возможностей.',
  ],
  build: (context) => buildLevelShell().data,
  camera: CameraMode.fixed,
  controls: (context, feature) => _StressEntryControls(feature: feature),
);

class _StressEntryControls extends StatefulWidget {
  const _StressEntryControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_StressEntryControls> createState() => _StressEntryControlsState();
}

class _StressEntryControlsState extends State<_StressEntryControls> {
  int _size = 50;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Размер стресс-уровня'),
        fcSlider(
          label: 'Сторона сетки',
          value: _size.toDouble(),
          min: 10,
          max: 100,
          format: (v) => v.round().toString(),
          onChanged: (v) => setState(() => _size = v.round()),
        ),
        Text(
          'клеток: ${_size * _size}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote(
          'Сборка и запекание выполняются сразу: для больших уровней окно '
          'на время проверки перестанет отвечать.',
        ),
        fcButton('Запустить', () => widget.feature.openStress(_size)),
      ],
    );
  }
}
