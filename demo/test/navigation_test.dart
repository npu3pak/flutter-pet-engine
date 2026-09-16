import 'package:demo/src/navigation/cell_nav.dart';
import 'package:demo/src/perf/fps_meter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  test('поворот влево и вправо меняет сторону света', () {
    expect(
      cellStep(
        row: 3,
        column: 4,
        facing: Direction.north,
        type: AnimationType.turnLeft,
      ),
      (row: 3, column: 4, facing: Direction.west),
    );
    expect(
      cellStep(
        row: 3,
        column: 4,
        facing: Direction.north,
        type: AnimationType.turnRight,
      ),
      (row: 3, column: 4, facing: Direction.east),
    );
  });

  test('шаг вперёд и назад двигает по клеткам согласно стороне', () {
    expect(
      cellStep(
        row: 3,
        column: 4,
        facing: Direction.north,
        type: AnimationType.stepForward,
      ),
      (row: 2, column: 4, facing: Direction.north),
    );
    expect(
      cellStep(
        row: 3,
        column: 4,
        facing: Direction.north,
        type: AnimationType.stepBackward,
      ),
      (row: 4, column: 4, facing: Direction.north),
    );
    expect(
      cellStep(
        row: 3,
        column: 4,
        facing: Direction.east,
        type: AnimationType.stepForward,
      ),
      (row: 3, column: 5, facing: Direction.east),
    );
  });

  test('измеритель частоты кадров публикует подпись', () {
    final meter = FpsMeter();
    var published = false;
    for (var i = 0; i < 60; i++) {
      if (meter.tick(1 / 60)) published = true;
    }
    expect(published, isTrue);
    expect(meter.label, contains('FPS'));
  });

  test('контроллер по клеткам двигает привязанную камеру', () {
    final camera = FirstPersonCameraController(
      row: 0,
      column: 0,
      facing: Direction.north,
    );
    final nav = CellNavController(camera);

    nav.step(AnimationType.stepForward);
    expect(camera.row, -1);
    expect(camera.column, 0);
    expect(camera.animation, AnimationType.stepForward);
    expect(camera.moveProgress, 1.0);

    // Движок ведёт анимацию в кадре: прогресс идёт от 1 (прежняя поза) к 0.
    camera.update(CellNavController.stepDuration / 2);
    expect(camera.moveProgress, closeTo(0.5, 0.01));
    expect(nav.animating, isTrue);

    camera.update(CellNavController.stepDuration / 2 + 0.01);
    expect(camera.animation, AnimationType.none);
    expect(camera.moveProgress, 0.0);
    expect(nav.animating, isFalse);
    camera.dispose();
  });
}
