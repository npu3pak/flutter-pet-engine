import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';

/// 1×1 transparent PNG.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('staticSkyboxRotation', () {
    test('game camera at rest faces north with the first panel centered', () {
      final controller = GameViewController();
      expect(staticSkyboxRotation(controller), closeTo(0.125, 1e-9));
    });

    test('game camera turn interpolation matches skyboxRotation', () {
      final controller = GameViewController()
        ..animation = AnimationType.turnLeft
        ..moveProgress = 0.5;
      expect(staticSkyboxRotation(controller), closeTo(0.25, 1e-9));
      controller
        ..facing = Direction.east
        ..animation = AnimationType.none
        ..moveProgress = 0;
      expect(staticSkyboxRotation(controller), closeTo(0.375, 1e-9));
    });

    test('free camera derives the heading from its forward vector', () {
      final camera = GameCamera();
      final controller = FreeCameraController(camera);
      expect(staticSkyboxRotation(controller), closeTo(0.125, 1e-9),
          reason: 'yaw = π смотрит на север');
      camera.yaw = math.pi / 2;
      expect(staticSkyboxRotation(controller), closeTo(0.875, 1e-9),
          reason: 'запад = 270° + 45° = 315/360');
      camera.yaw = 0;
      expect(staticSkyboxRotation(controller), closeTo(0.625, 1e-9),
          reason: 'юг = 180° + 45° = 225/360');
    });
  });

  group('loadSkyboxImage', () {
    test('decodes panorama bytes', () async {
      final image = await loadSkyboxImage(_pngBytes);
      expect(image, isNotNull);
      expect((image!.width, image.height), (1, 1));
      image.dispose();
    });

    test('empty bytes and garbage decode to null', () async {
      expect(await loadSkyboxImage(null), isNull);
      expect(await loadSkyboxImage(Uint8List(0)), isNull);
      expect(await loadSkyboxImage(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  testWidgets('StaticSkybox paints a preloaded image and repaints on rotation',
      (tester) async {
    final image = await tester.runAsync(() => loadSkyboxImage(_pngBytes));
    expect(image, isNotNull);
    await tester.pumpWidget(
      SizedBox(
        width: 200,
        height: 100,
        child: StaticSkybox(image: image, rotation: 0.125),
      ),
    );
    expect(find.byType(StaticSkybox), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      SizedBox(
        width: 200,
        height: 100,
        child: StaticSkybox(
          image: image,
          rotation: 0.5,
          fogColor: const ui.Color(0xFF102030),
          fogStrength: 0.4,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    image!.dispose();
  });

  testWidgets('StaticSkybox draws nothing without an image', (tester) async {
    await tester.pumpWidget(
      const SizedBox(
        width: 200,
        height: 100,
        child: StaticSkybox(image: null, rotation: 0),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
