import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelData _model(int w, int l, int h) => ModelData.fromJson(
      jsonEncode({
        'format': 'model_v1',
        'id': 'm',
        'name': 'm',
        'size': {'w': w, 'l': l, 'h': h},
        'objects': <Object>[],
      }),
      id: 'm',
    );

void main() {
  group('FlyCameraController.configureForExtent', () {
    test('классические сцены сохраняют дефолты', () {
      final fly = FlyCameraController();
      // Диагональ легаси-максимума 64×64×32 ≈ 94.3.
      fly.configureForExtent(94.3);
      expect(fly.projection.near, FlyCameraController.defaultNear);
      expect(fly.projection.far, FlyCameraController.defaultFar);
      expect(fly.flySpeed, FlyCameraController.defaultFlySpeed);
    });

    test('крупная карта расширяет клип-плоскости и ускоряет полёт', () {
      final fly = FlyCameraController();
      fly.configureForExtent(5000);
      expect(fly.projection.near, closeTo(0.5, 1e-9));
      expect(fly.projection.far, closeTo(20000, 1e-9));
      // Скорость пропорциональна диагонали: 12 ед/с на 94 единицы, как на
      // легаси-сетке — карта пересекается за тот же относительный темп.
      expect(
        fly.flySpeed,
        closeTo(
          FlyCameraController.defaultFlySpeed *
              5000 /
              FlyCameraController.flySpeedReferenceExtent,
          1e-9,
        ),
      );
      expect(fly.flySpeed, greaterThan(FlyCameraController.defaultFlySpeed));
    });

    test('скорость масштабируется линейно от диагонали', () {
      final small = FlyCameraController()..configureForExtent(1000);
      final large = FlyCameraController()..configureForExtent(2000);
      expect(
        small.flySpeed,
        closeTo(
          FlyCameraController.defaultFlySpeed *
              1000 /
              FlyCameraController.flySpeedReferenceExtent,
          1e-9,
        ),
      );
      expect(large.flySpeed, closeTo(small.flySpeed * 2, 1e-9));
    });

    test('одиночный шаг нажатия использует текущую скорость полёта', () {
      final fly = FlyCameraController(
        eye: vm.Vector3.zero(),
        yaw: 0,
        pitch: 0,
      )..configureForExtent(5000);
      fly.startFly();
      final before = fly.eye.clone();
      fly.keyDown(0x57);
      // eye хранится во float32 — сравниваем с запасом.
      expect((fly.eye - before).length, closeTo(0.016 * fly.flySpeed, 1e-4));
      fly.stopFly();
    });

    test('setClip игнорирует неположительные значения', () {
      final fly = FlyCameraController();
      final before = fly.projection;
      fly.setClip(near: -1, far: 0);
      expect(identical(fly.projection, before), isTrue);
      fly.setClip(far: 1000);
      expect(fly.projection.far, 1000);
      expect(fly.projection.near, FlyCameraController.defaultNear);
    });
  });

  group('frameModel на крупных картах', () {
    test('камера не прижимается к полу на карте 1:1', () {
      final fly = FlyCameraController();
      fly.frameModel(_model(4576, 2816, 400));
      // Высота камеры обязана масштабироваться вместе с картой, а не
      // упираться в легаси-потолок 120.
      expect(fly.eye.y, greaterThan(500));
      expect(fly.yaw, closeTo(3.141592653589793, 1e-9));
      expect(fly.pitch, closeTo(0.5, 1e-9));
    });

    test('высокая модель поднимает камеру выше легаси-потолка 60', () {
      final fly = FlyCameraController();
      fly.frameModel(_model(20, 20, 200));
      expect(fly.eye.y, greaterThan(60));
    });
  });
}
