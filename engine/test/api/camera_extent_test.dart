import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

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
      expect(fly.flySpeed, closeTo(5000 / 300, 1e-9));
      expect(fly.flySpeed, greaterThan(FlyCameraController.defaultFlySpeed));
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
