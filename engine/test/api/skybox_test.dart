import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:pet_engine_v2/src/api/skybox/skybox_background.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _FakeBackend extends SceneViewportBackend {
  @override
  Widget build(BuildContext context, SceneViewportContext viewport) =>
      const ColoredBox(color: Color(0xFF112233));

  @override
  Future<Uint8List> capture(
    SceneViewportContext viewport, {
    double? pixelRatio,
  }) async => Uint8List(0);
}

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 320, height: 200, child: child)),
);

Future<ui.Image> _image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366AA),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('skyRotationFor', () {
    test('first-person camera uses the panel center and turn progress', () {
      final camera = FirstPersonCameraController(facing: Direction.east);
      expect(skyRotationFor(camera), closeTo(0.375, 1e-9));
      camera
        ..facing = Direction.north
        ..animation = AnimationType.turnLeft
        ..moveProgress = 0.5;
      expect(skyRotationFor(camera), closeTo(0.25, 1e-9));
      camera.dispose();
    });

    test('free camera derives the heading from forward', () {
      final camera = FlyCameraController(yaw: math.pi, pitch: 0);
      expect(skyRotationFor(camera), closeTo(0.125, 1e-6));
      camera.dispose();
    });
  });

  group('loadSkyboxImage', () {
    test('null and empty bytes decode to null', () async {
      expect(await loadSkyboxImage(null), isNull);
      expect(await loadSkyboxImage(Uint8List(0)), isNull);
      expect(
        await loadSkyboxImage(Uint8List.fromList(const [1, 2, 3])),
        isNull,
      );
    });
  });

  group('SkyboxBackground', () {
    testWidgets('the viewport draws the sky node layers', (tester) async {
      final image = await _image(8, 4);
      final controller = SceneController();
      controller.add(
        SkyboxNode(backgroundColor: const Color(0xFF101820))
          ..addLayer(
            SkyboxColorLayer(
              topColor: const Color(0xFF203040),
              bottomColor: const Color(0xFF8090A0),
            ),
          )
          ..addLayer(
            SkyboxImageLayer(
              image: image,
              fogColor: const Color(0xFF808080),
              fogStrength: 0.4,
            ),
          )
          ..addLayer(SkyboxStarsLayer(count: 20))
          ..addLayer(
            SkyboxBodyLayer(direction: vm.Vector3(0.3, 0.4, -1), glow: 0.5),
          ),
      );

      await tester.pumpWidget(
        _host(SceneViewport(controller: controller, backend: _FakeBackend())),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(SkyboxBackground), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      image.dispose();
    });

    testWidgets('no sky node means no background widget', (tester) async {
      final controller = SceneController();
      await tester.pumpWidget(
        _host(SceneViewport(controller: controller, backend: _FakeBackend())),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(SkyboxBackground), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  });
}
