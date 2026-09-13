import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:pet_engine_v2/src/camera/animation_type.dart' as eng;
import 'package:pet_engine_v2/src/camera/direction.dart' as eng;
import 'package:pet_engine_v2/src/camera/game_camera_math.dart' as eng;
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlyCameraController', () {
    test('exposes projection, direction and matrix', () {
      final camera = FlyCameraController(eye: vm.Vector3(0, 2, 0), yaw: 0);
      expect(camera.projection.fovY, closeTo(FlyCameraController.fovY, 1e-9));
      expect(camera.forwardH.x, closeTo(0, 1e-9));
      expect(camera.forwardH.z, closeTo(1, 1e-9));
      final matrix = camera.matrix;
      expect(matrix.getTranslation().y, closeTo(2, 1e-6));
      camera.dispose();
    });

    test('lookAt points the camera at the target', () {
      final camera = FlyCameraController(eye: vm.Vector3(0, 0, 10), yaw: 0);
      camera.lookAt(vm.Vector3.zero());
      expect(camera.forwardH.z, closeTo(-1, 1e-6));
      camera.dispose();
    });

    test('frameBounds centers the camera on the bounds', () {
      final camera = FlyCameraController();
      camera.frameBounds(
        vm.Aabb3.minMax(vm.Vector3(-1, 0, -1), vm.Vector3(1, 2, 1)),
      );
      expect(camera.forwardH.x, closeTo(0, 0.2));
      expect(camera.forwardH.z, closeTo(-1, 0.2));
      expect(camera.eye.y, greaterThan(0));
      camera.dispose();
    });

    test('flyLook turns and pitches', () {
      final camera = FlyCameraController(yaw: 0, pitch: 0);
      camera.flyLook(10, 5, sensitivity: 0.01);
      expect(camera.yaw, closeTo(0.1, 1e-6));
      expect(camera.pitch, closeTo(0.05, 1e-6));
      camera.dispose();
    });

    test('update flies while started', () {
      final camera = FlyCameraController(
        eye: vm.Vector3.zero(),
        yaw: 0,
        pitch: 0,
      );
      camera.startFly();
      camera.keyDown(0x57);
      camera.update(1.0);
      expect(camera.eye.z, closeTo(camera.flySpeed, 0.5));
      camera.stopFly();
      camera.dispose();
    });
  });

  group('FirstPersonCameraController', () {
    test('matrix matches the engine first-person transform', () {
      final camera = FirstPersonCameraController(
        facing: Direction.east,
        row: 3,
        column: 5,
      );
      final expected = eng.gameCameraNodeTransformAnimated(
        eng.Direction.east,
        3,
        5,
        animationType: eng.AnimationType.none,
        moveProgress: 0,
        y: 0.5,
      );
      expect(camera.matrix, expected);
      camera.dispose();
    });

    test('forwardH points north for the default facing', () {
      final camera = FirstPersonCameraController();
      expect(camera.forwardH.z, closeTo(-1, 1e-6));
      expect(camera.projection.fovY, closeTo(eng.kGameCameraFovY, 1e-9));
      camera.dispose();
    });

    test('update advances the step animation to the destination', () {
      final camera = FirstPersonCameraController();
      camera.animation = AnimationType.stepForward;
      camera.moveProgress = 1.0;
      camera.update(0.15);
      expect(camera.moveProgress, closeTo(0.5, 0.01));
      camera.update(0.16);
      expect(camera.animation, AnimationType.none);
      expect(camera.moveProgress, 0.0);
      camera.dispose();
    });

    test('mutating state notifies listeners', () {
      final camera = FirstPersonCameraController();
      var notified = 0;
      camera.addListener(() => notified++);
      camera.facing = Direction.south;
      camera.row = 2;
      camera.animation = AnimationType.stepForward;
      camera.moveProgress = 0.5;
      expect(notified, 4);
      camera.dispose();
    });
  });

  group('OrbitCameraController', () {
    test('places the eye around the target', () {
      final camera = OrbitCameraController(
        target: vm.Vector3(1, 0, 1),
        distance: 5,
        yaw: 0,
        pitch: 0,
      );
      expect(camera.eye.x, closeTo(1, 1e-6));
      expect(camera.eye.z, closeTo(1 - 5, 1e-6));
      camera.dispose();
    });

    test('orbit, zoom and framing', () {
      final camera = OrbitCameraController(distance: 10, yaw: 0, pitch: 0);
      camera.orbit(100, 0, sensitivity: 0.01);
      expect(camera.yaw, closeTo(1.0, 1e-6));
      camera.zoom(-100);
      expect(camera.distance, lessThan(10));
      camera.frameBounds(
        vm.Aabb3.minMax(vm.Vector3(-2, 0, -2), vm.Vector3(2, 2, 2)),
      );
      expect(camera.target.x, closeTo(0, 1e-6));
      expect(camera.distance, greaterThan(0));
      camera.dispose();
    });
  });

  group('CameraInput', () {
    test('secondary drag looks around', () {
      final controller = SceneController();
      final fly = FlyCameraController(yaw: 0, pitch: 0);
      controller.camera = fly;
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );

      input.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
          position: const Offset(100, 100),
        ),
        info,
      );
      input.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          position: const Offset(110, 100),
          delta: const Offset(10, 0),
        ),
        info,
      );
      expect(fly.yaw, closeTo(0.05, 1e-6));
      input.onPointerUp(PointerUpEvent(pointer: 1), info);
      controller.dispose();
    });

    test('secondary button enables keyboard flight', () {
      final controller = SceneController();
      final fly = FlyCameraController(yaw: 0, pitch: 0);
      controller.camera = fly;
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );

      input.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
          position: const Offset(100, 100),
        ),
        info,
      );
      expect(fly.flying, isTrue);
      // Полёт сам по себе не двигает камеру: только WASD/QE.
      final before = fly.eye.clone();
      fly.update(1.0);
      expect((fly.eye - before).length, lessThan(1e-9));
      fly.keyDown(0x57);
      fly.update(1.0);
      expect((fly.eye - before).length, greaterThan(0.5));
      input.onPointerUp(PointerUpEvent(pointer: 1), info);
      expect(fly.flying, isFalse);
      controller.dispose();
    });

    test('primary drag pans without enabling flight', () {
      final controller = SceneController();
      final fly = FlyCameraController(eye: vm.Vector3(0, 0, 10), yaw: 0, pitch: 0);
      controller.camera = fly;
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );
      final before = fly.eye.x;
      input.onPointerDown(
        PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
          position: const Offset(100, 100),
        ),
        info,
      );
      expect(fly.flying, isFalse);
      input.onPointerMove(
        PointerMoveEvent(
          pointer: 1,
          position: const Offset(140, 100),
          delta: const Offset(40, 0),
        ),
        info,
      );
      expect(fly.eye.x, isNot(closeTo(before, 1e-6)));
      input.onPointerUp(PointerUpEvent(pointer: 1), info);
      controller.dispose();
    });

    test('wheel zooms the fly camera', () {
      final controller = SceneController();
      final fly = FlyCameraController(eye: vm.Vector3(0, 0, 10), yaw: 0);
      controller.camera = fly;
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );
      final before = fly.eye.z;
      input.onPointerSignal(
        PointerScrollEvent(scrollDelta: const Offset(0, -100)),
        info,
      );
      expect((fly.eye.z - 20).abs(), lessThan((before - 20).abs()));
      controller.dispose();
    });

    test('W key flies while the fly mode is on', () {
      final controller = SceneController();
      final fly = FlyCameraController(eye: vm.Vector3.zero(), yaw: 0, pitch: 0);
      controller.camera = fly;
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );
      final node = FocusNode();
      final result = input.onKey(
        node,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
        info,
      );
      expect(result, KeyEventResult.handled);
      fly.startFly();
      fly.update(1.0);
      expect(fly.eye.z, greaterThan(0));
      controller.dispose();
      node.dispose();
    });

    test('other keys are ignored', () {
      final controller = SceneController();
      final input = CameraInput();
      final info = SceneViewportInfo(
        size: const Size(400, 300),
        pixelRatio: 1,
        controller: controller,
      );
      final node = FocusNode();
      final result = input.onKey(
        node,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyZ,
          logicalKey: LogicalKeyboardKey.keyZ,
          timeStamp: Duration.zero,
        ),
        info,
      );
      expect(result, KeyEventResult.ignored);
      controller.dispose();
      node.dispose();
    });
  });

  group('SceneController camera application', () {
    test('first-person camera drives the camera node', () {
      final controller = SceneController();
      final camera = FirstPersonCameraController(
        facing: Direction.north,
        row: 4,
        column: -2,
      );
      controller.camera = camera;
      final position = controller.cameraNode.position;
      expect(position.x, closeTo(2, 1e-5));
      expect(position.z, closeTo(4, 1e-5));
      controller.dispose();
    });
  });
}
