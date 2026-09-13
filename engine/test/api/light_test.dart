import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelData _model({ModelLighting? lighting}) => ModelData(
  id: 'm',
  name: 'M',
  size: ModelSize(w: 4, l: 4, h: 3),
  lighting: lighting,
);

void main() {
  group('LightNode', () {
    test('point light stores its parameters', () {
      final node = LightNode.point(
        color: const Color(0xFFFF8000),
        intensity: 2,
        range: 7,
        importance: 3,
      );
      expect(node.isPoint, isTrue);
      expect(node.isDirectional, isFalse);
      expect(node.intensity, 2);
      expect(node.range, 7);
      expect(node.importance, 3);
      expect(node.color, const Color(0xFFFF8000));

      node
        ..intensity = 4
        ..range = 2
        ..importance = 0.5;
      expect(node.intensity, 4);
      expect(node.range, 2);
      expect(node.importance, 0.5);
      node.dispose();
    });

    test('directional light normalizes its direction', () {
      final node = LightNode.directional(
        direction: vm.Vector3(0, -2, 0),
        castsShadow: true,
      );
      expect(node.isDirectional, isTrue);
      expect(node.direction.length, closeTo(1, 1e-6));
      expect(node.direction.y, closeTo(-1, 1e-6));
      expect(node.castsShadow, isTrue);
      node.dispose();
    });

    test('selectForBudget keeps the most important point lights', () {
      final a = LightNode.point(importance: 1);
      final b = LightNode.point(importance: 5);
      final c = LightNode.point(importance: 3);
      final lights = [a, b, c];

      expect(LightNode.selectForBudget(lights, -1), lights);
      expect(LightNode.selectForBudget(lights, 0), isEmpty);
      expect(LightNode.selectForBudget(lights, 2), [b, c]);
      expect(LightNode.selectForBudget(lights, 10), [b, c, a]);

      for (final node in lights) {
        node.dispose();
      }
    });
  });

  group('SceneController lighting', () {
    test('applyLighting builds the document sources', () {
      final controller = SceneController();
      controller.loadModelData(
        _model(
          lighting: ModelLighting(
            ambient: 0.5,
            lights: [
              ModelLight(
                id: 'p1',
                kind: lightKindPoint,
                x: 1,
                y: 2,
                z: 2,
                r: 1,
                g: 0,
                b: 0,
                intensity: 3,
                range: 5,
              ),
              ModelLight(
                id: 'd1',
                kind: lightKindDirectional,
                dirX: 0,
                dirY: -1,
                dirZ: 0,
                intensity: 2,
              ),
            ],
          ),
        ),
      );

      controller.applyLighting();
      final lights = controller.nodesOfType<LightNode>().toList();
      expect(lights, hasLength(2));

      final point = lights.firstWhere((l) => l.isPoint);
      expect(point.id, 'light_p1');
      expect(point.position.x, closeTo(0.5, 1e-6));
      expect(point.position.y, closeTo(2, 1e-6));
      expect(point.position.z, closeTo(0.5, 1e-6));
      expect(point.intensity, 3);
      expect(point.range, 5);

      final directional = lights.firstWhere((l) => l.isDirectional);
      expect(directional.id, 'light_d1');
      expect(directional.castsShadow, isTrue);

      expect(controller.environmentIntensity, 0.5);
      controller.dispose();
    });

    test('empty custom lighting builds the default rig', () {
      final controller = SceneController();
      controller.loadModelData(_model(lighting: ModelLighting(ambient: 0.75)));

      controller.applyLighting();
      final lights = controller.nodesOfType<LightNode>().toList();
      expect(lights, hasLength(2));
      expect(lights.where((l) => l.isDirectional), hasLength(1));
      final lamp = lights.firstWhere((l) => l.isPoint);
      expect(lamp.parent, controller.cameraNode);
      expect(controller.environmentIntensity, 0.75);
      controller.dispose();
    });

    test('applyLighting is idempotent for the same document config', () {
      final controller = SceneController();
      controller.loadModelData(_model(lighting: ModelLighting(ambient: 0.5)));
      controller.applyLighting();
      final lights = controller.nodesOfType<LightNode>().toList();
      expect(lights, isNotEmpty);

      // The editor calls applyLighting on every scene revision; the same
      // document config must not tear the light rig down and rebuild it.
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.applyLighting();
      expect(controller.nodesOfType<LightNode>().toList(), lights);
      expect(notifications, 0, reason: 'повторный вызов — no-op');

      // A changed config applies again.
      controller.model!.lighting.ambient = 0.9;
      controller.applyLighting();
      expect(controller.environmentIntensity, 0.9);
      controller.dispose();
    });

    test('clearLighting removes only the built light', () {
      final controller = SceneController();
      controller.loadModelData(
        _model(
          lighting: ModelLighting(
            lights: [ModelLight(id: 'p1', kind: lightKindPoint)],
          ),
        ),
      );
      final own = controller.add(LightNode.point(id: 'own'));

      controller.applyLighting();
      expect(controller.nodesOfType<LightNode>(), hasLength(2));

      controller.clearLighting();
      final left = controller.nodesOfType<LightNode>().toList();
      expect(left, [own]);
      expect(controller.byId('own'), isNotNull);
      controller.dispose();
    });

    test('maxPointLights disables the least important points', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final low = controller.add(LightNode.point(id: 'low', importance: 1));
      final high = controller.add(LightNode.point(id: 'high', importance: 5));
      final mid = controller.add(LightNode.point(id: 'mid', importance: 3));
      final sun = controller.add(
        LightNode.directional(id: 'sun', direction: vm.Vector3(0, -1, 0)),
      );

      controller.applySettings(const QualitySettings(maxPointLights: 2));
      expect(high.budgetEnabled, isTrue);
      expect(mid.budgetEnabled, isTrue);
      expect(low.budgetEnabled, isFalse);
      expect(sun.budgetEnabled, isTrue);

      controller.applySettings(const QualitySettings(maxPointLights: 0));
      expect(high.budgetEnabled, isFalse);
      expect(sun.budgetEnabled, isTrue);

      controller.applySettings(const QualitySettings(maxPointLights: -1));
      expect(low.budgetEnabled, isTrue);
      expect(mid.budgetEnabled, isTrue);
      expect(high.budgetEnabled, isTrue);
      controller.dispose();
    });
  });
}
