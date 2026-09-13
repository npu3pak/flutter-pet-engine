import 'package:flutter/material.dart' hide MaterialType;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'controls.dart';
import 'feature_registry.dart';

/// Сетка с намеренной проблемой: одна открытая клетка отрезана от остальных.
LevelGrid validationGrid() =>
    LevelGrid.fromRows(const ['#######', '#..#..#', '#..#..#', '#######']);

/// Конструкция с дубликатом идентификатора и элементом за пределами сетки.
ConstructionModel buildValidationModel() {
  final model = ConstructionModel(
    id: 'level_validation',
    name: 'Проверки уровня',
  );
  model.data.size = ModelSize(w: 7, l: 4, h: 3);
  model.add(
    ModelObject(
      id: 'wall_1',
      name: 'Стена',
      kind: 'cuboid',
      x: 1,
      y: 0,
      z: 1,
      dims: const {'w': 1, 'h': 2, 'd': 0.2},
      material: ModelMaterial(type: MaterialType.color, color: [186, 176, 152]),
    ),
  );
  // Дубликат идентификатора — валидатор обязан его заметить.
  model.add(
    ModelObject(
      id: 'wall_1',
      name: 'Вторая стена',
      kind: 'cuboid',
      x: 5,
      y: 0,
      z: 1,
      dims: const {'w': 1, 'h': 2, 'd': 0.2},
      material: ModelMaterial(type: MaterialType.color, color: [186, 176, 152]),
    ),
  );
  // Элемент за пределами сетки.
  model.add(
    ModelObject(
      id: 'outside',
      name: 'Снаружи',
      kind: 'cuboid',
      x: 20,
      y: 0,
      z: 20,
      dims: const {'w': 1, 'h': 1, 'd': 1},
      material: ModelMaterial(type: MaterialType.color, color: [190, 120, 70]),
    ),
  );
  return model;
}

/// Все замечания проверок уровня для демонстрационной сцены.
List<LevelIssue> levelValidationIssues() => const LevelValidator().validate(
  grid: validationGrid(),
  model: buildValidationModel(),
  starts: const {(1, 1)},
);

ModelData buildValidationScene(FeatureBuildContext context) {
  final grid = validationGrid();
  final model = buildValidationModel();
  // Полы открытых клеток, чтобы форма уровня читалась.
  for (final ((r, c), cell) in grid.cells) {
    if (!cell.isOpen) continue;
    model.add(
      ModelObject(
        id: 'floor_${r}_$c',
        name: 'Пол',
        kind: 'cuboid',
        x: c.toDouble(),
        y: 0,
        z: r.toDouble(),
        dims: const {'w': 1, 'h': 0.04, 'd': 1},
        material: ModelMaterial(type: MaterialType.color, color: [96, 112, 96]),
      ),
    );
  }
  // Красные маркеры на клетках с замечаниями.
  var index = 0;
  for (final issue in levelValidationIssues()) {
    final cell = issue.cell;
    if (cell == null) continue;
    model.add(
      ModelObject(
        id: 'issue_${index++}',
        name: issue.message,
        kind: 'cuboid',
        x: cell.$2.toDouble(),
        y: 2.4,
        z: cell.$1.toDouble(),
        dims: const {'w': 0.25, 'h': 0.25, 'd': 0.25},
        material: ModelMaterial(type: MaterialType.color, color: [214, 76, 76]),
      ),
    );
  }
  return model.data;
}

final FeatureSpec levelValidationFeature = FeatureSpec(
  id: 'level_validation',
  group: kFeatureGroups[5],
  title: 'Проверки уровня',
  phase: 3,
  description:
      'Уровень с намеренными ошибками: отрезанная от входа клетка, '
      'дубликат идентификатора элемента и элемент за пределами сетки. '
      'Проверки уровня находят их и перечисляют в управлении; красные '
      'маркеры в сцене показывают клетки с замечаниями.',
  checks: const [
    'Проверка связности находит отрезанную от входа клетку и указывает её координаты.',
    'Проверка конструкции находит дубликат идентификатора элемента.',
    'Проверка конструкции находит элемент, выходящий за пределы сетки.',
    'Красные маркеры стоят в клетках, указанных в списке замечаний.',
    'В управлении у замечания виден вид (например, связность или конструкция), важность и клетка, если она есть.',
  ],
  build: buildValidationScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _ValidationControls(),
);

class _ValidationControls extends StatelessWidget {
  const _ValidationControls();

  @override
  Widget build(BuildContext context) {
    final issues = levelValidationIssues();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Замечания проверок'),
        if (issues.isEmpty)
          const Text(
            'Замечаний нет',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${issue.severity == LevelIssueSeverity.error ? 'Ошибка' : 'Предупреждение'}'
              ' · ${_kindLabel(issue.kind)}: '
              '${issue.message}'
              '${issue.cell == null ? '' : ' (клетка ${issue.cell!.$1}, ${issue.cell!.$2})'}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
      ],
    );
  }

  /// Понятное название вида замечания для панели.
  String _kindLabel(LevelIssueKind kind) => switch (kind) {
    LevelIssueKind.disconnectedCell => 'связность',
    LevelIssueKind.placementOverlap => 'пересечение сцен',
    LevelIssueKind.dockingMismatch => 'стыковка сцен',
    LevelIssueKind.doorWithoutEntry => 'дверь без входа',
    LevelIssueKind.entryWithoutDoor => 'вход без двери',
    LevelIssueKind.entryFacesWall => 'вход в стену',
    LevelIssueKind.unknownRegion => 'неизвестный регион',
    _ => 'конструкция',
  };
}
