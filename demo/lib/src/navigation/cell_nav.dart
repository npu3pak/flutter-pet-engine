import 'package:pet_engine/pet_engine.dart';

/// Результат шага камеры по клеткам.
typedef CellPose = ({int row, int column, Direction facing});

/// Чистый расчёт поворота/шага камеры по клеткам: поворот меняет сторону
/// света, шаг двигает на одну клетку вперёд или назад с учётом стороны.
CellPose cellStep({
  required int row,
  required int column,
  required Direction facing,
  required AnimationType type,
}) {
  var nextRow = row;
  var nextColumn = column;
  var nextFacing = facing;
  final (fx, fz) = _forward(facing);
  switch (type) {
    case AnimationType.turnLeft:
      nextFacing = Direction.values[(facing.index + 3) % 4];
    case AnimationType.turnRight:
      nextFacing = Direction.values[(facing.index + 1) % 4];
    case AnimationType.stepForward:
      nextRow += fz.round();
      nextColumn -= fx.round();
    case AnimationType.stepBackward:
      nextRow -= fz.round();
      nextColumn += fx.round();
    case AnimationType.none:
    case AnimationType.strafeLeft:
    case AnimationType.strafeRight:
      break;
  }
  return (row: nextRow, column: nextColumn, facing: nextFacing);
}

/// Направление взгляда камеры по клеткам в мировых осях (зеркальный мир).
(double, double) _forward(Direction d) => switch (d) {
  Direction.north => (0.0, -1.0),
  Direction.east => (-1.0, 0.0),
  Direction.south => (0.0, 1.0),
  Direction.west => (1.0, 0.0),
};

/// Анимация поворота/шага игровой камеры: цель обновляется сразу, а сам
/// переход от прежней позы к новой ведёт [FirstPersonCameraController.update]
/// в кадре движка (progress 1 → 0).
class CellNavController {
  CellNavController(this.controller);

  final FirstPersonCameraController controller;

  /// Длительность одного шага/поворота в секундах (делегируется камере).
  static const double stepDuration = 0.3;

  bool get animating => controller.animation != AnimationType.none;

  /// Выполняет шаг или поворот, обновляя цель и запуская анимацию.
  void step(AnimationType type) {
    final pose = cellStep(
      row: controller.row,
      column: controller.column,
      facing: controller.facing,
      type: type,
    );
    controller
      ..stepDuration = stepDuration
      ..row = pose.row
      ..column = pose.column
      ..facing = pose.facing
      ..animation = type
      ..moveProgress = 1.0;
  }
}
