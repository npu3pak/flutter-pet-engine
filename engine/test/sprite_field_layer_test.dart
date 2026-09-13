import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/src/render/sprite_field_layer.dart';

void main() {
  group('SpriteFieldLayer', () {
    test('stores screenParallelYaw and keeps it across packs', () {
      final layer = SpriteFieldLayer(
        sprites: const [],
        capacity: 8,
        facing: SpriteFieldFacing.screenParallel,
      );
      expect(layer.screenParallelYaw, 0.0);

      layer.screenParallelYaw = 1.25;
      expect(layer.screenParallelYaw, 1.25);

      // Пачка без атласа безопасна и сохраняет yaw слоя.
      layer.update(const []);
      expect(layer.screenParallelYaw, 1.25);

      // Параметр update перекрывает сохранённый yaw.
      layer.update(const [], screenParallelYaw: -0.5);
      expect(layer.screenParallelYaw, -0.5);

      layer.dispose();
    });
  });
}
