import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _FakeBackend extends SceneViewportBackend {
  int builds = 0;
  SceneViewportContext? last;
  double? capturedPixelRatio;

  @override
  Widget build(BuildContext context, SceneViewportContext viewport) {
    builds++;
    last = viewport;
    return const ColoredBox(color: Color(0xFF112233));
  }

  @override
  Future<Uint8List> capture(
    SceneViewportContext viewport, {
    double? pixelRatio,
  }) async {
    capturedPixelRatio = pixelRatio;
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

class _RecordingInput extends SceneInput {
  final downs = <PointerDownEvent>[];
  final moves = <PointerMoveEvent>[];
  final ups = <PointerUpEvent>[];
  final signals = <PointerSignalEvent>[];

  @override
  void onPointerDown(PointerDownEvent event, SceneViewportInfo info) =>
      downs.add(event);

  @override
  void onPointerMove(PointerMoveEvent event, SceneViewportInfo info) =>
      moves.add(event);

  @override
  void onPointerUp(PointerUpEvent event, SceneViewportInfo info) =>
      ups.add(event);

  @override
  void onPointerSignal(PointerSignalEvent event, SceneViewportInfo info) =>
      signals.add(event);
}

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(devicePixelRatio: 2),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  group('SceneViewSpec', () {
    test('factories select layers and order', () {
      expect(SceneViewSpec.main().layerMask & SceneLayer.base, isNot(0));
      expect(SceneViewSpec.main().layerMask & SceneLayer.overlay, 0);
      expect(SceneViewSpec.overlay().layerMask, SceneLayer.overlay);
      expect(SceneViewSpec.top().layerMask, SceneLayer.top);
      expect(
        SceneViewSpec.overlay().order,
        greaterThan(SceneViewSpec.main().order),
      );
    });
  });

  group('SceneViewport', () {
    testWidgets('reports its size and drives the frame', (tester) async {
      final controller = SceneController();
      final backend = _FakeBackend();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            height: 100,
            child: SceneViewport(controller: controller, backend: backend),
          ),
        ),
      );
      await tester.pump();

      expect(controller.viewportSize, const Size(200, 100));
      expect(controller.pixelRatio, 2);
      expect(backend.builds, greaterThan(0));
      expect(
        backend.last!.views.single.layerMask,
        SceneViewSpec.main().layerMask,
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.elapsed, greaterThan(Duration.zero));

      controller.dispose();
    });

    testWidgets('autoTick false leaves the frame to the application', (
      tester,
    ) async {
      final controller = SceneController();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              controller: controller,
              autoTick: false,
              backend: _FakeBackend(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.elapsed, Duration.zero);
      controller.update(0.5);
      expect(controller.elapsed, const Duration(milliseconds: 500));
      controller.dispose();
    });

    testWidgets('shows the loading builder while loading', (tester) async {
      final controller = SceneController();
      final source = _SlowSource();
      final loading = <SceneLoadStatus>[];
      unawaited(controller.open(source));

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              controller: controller,
              backend: _FakeBackend(),
              loadingBuilder: (context, status) {
                loading.add(status);
                return const Text('загрузка', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('загрузка'), findsOneWidget);

      source.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('загрузка'), findsNothing);
      controller.dispose();
    });

    testWidgets('renders background and overlay builders', (tester) async {
      final controller = SceneController();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              controller: controller,
              backend: _FakeBackend(),
              backgroundBuilder: (context, size) => const ColoredBox(
                key: ValueKey('background'),
                color: Color(0xFF000000),
              ),
              overlayBuilder: (context, size) => const ColoredBox(
                key: ValueKey('overlay'),
                color: Color(0x00000000),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('background')), findsOneWidget);
      expect(find.byKey(const ValueKey('overlay')), findsOneWidget);
      controller.dispose();
    });

    testWidgets('forms taps and double taps', (tester) async {
      final controller = SceneController();
      final taps = <SceneTapEvent>[];
      final doubles = <SceneTapEvent>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            height: 200,
            child: SceneViewport(
              controller: controller,
              backend: _FakeBackend(),
              onTap: taps.add,
              onDoubleTap: doubles.add,
            ),
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(SceneViewport));
      final point = topLeft + const Offset(50, 60);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, hasLength(1));
      expect(taps.first.screenPosition.dx, closeTo(50, 0.5));
      expect(taps.first.screenPosition.dy, closeTo(60, 0.5));
      expect(taps.first.ray.direction.length, closeTo(1, 1e-6));

      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      expect(doubles, hasLength(1));
      controller.dispose();
    });

    testWidgets('tap ray passes through the projected world point', (
      tester,
    ) async {
      final controller = SceneController();
      final fly = FlyCameraController();
      controller.camera = fly;
      fly.eye = vm.Vector3(3, 2, 3);
      fly.lookAt(vm.Vector3(0.2, 0.3, -0.1));
      final taps = <SceneTapEvent>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            height: 200,
            child: SceneViewport(
              controller: controller,
              backend: _FakeBackend(),
              onTap: taps.add,
            ),
          ),
        ),
      );
      await tester.pump();

      final target = vm.Vector3(0.2, 0.3, -0.1);
      final screen = controller.worldToScreen(target)!;
      final topLeft = tester.getTopLeft(find.byType(SceneViewport));
      await tester.tapAt(topLeft + screen);
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, hasLength(1));

      final ray = taps.first.ray;
      final toTarget = target - ray.origin;
      final along = toTarget.dot(ray.direction);
      expect(along, greaterThan(0), reason: 'точка должна быть перед камерой');
      final offAxis = (toTarget - ray.direction * along).length;
      expect(offAxis, lessThan(1e-6));
      controller.dispose();
    });

    testWidgets('forwards raw pointer events to the input handler', (
      tester,
    ) async {
      final controller = SceneController();
      final input = _RecordingInput();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              controller: controller,
              input: input,
              backend: _FakeBackend(),
            ),
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(SceneViewport));
      final gesture = await tester.startGesture(topLeft + const Offset(10, 10));
      await gesture.moveBy(const Offset(5, 0));
      await gesture.up();
      await tester.pump();

      expect(input.downs, hasLength(1));
      expect(input.moves, hasLength(1));
      expect(input.ups, hasLength(1));
      controller.dispose();
    });

    testWidgets('keeps the input handler for the duration of a gesture', (
      tester,
    ) async {
      final controller = SceneController();
      final first = _RecordingInput();
      final second = _RecordingInput();
      Widget viewport(SceneInput input) => _host(
        SizedBox(
          width: 100,
          height: 100,
          child: SceneViewport(
            controller: controller,
            input: input,
            backend: _FakeBackend(),
          ),
        ),
      );

      await tester.pumpWidget(viewport(first));
      final topLeft = tester.getTopLeft(find.byType(SceneViewport));
      final gesture = await tester.startGesture(topLeft + const Offset(10, 10));
      await gesture.moveBy(const Offset(5, 0));

      // Пересборка посреди жеста с новым обработчиком: указатель не теряется.
      await tester.pumpWidget(viewport(second));
      await gesture.moveBy(const Offset(5, 0));
      await gesture.up();
      await tester.pump();

      expect(first.downs, hasLength(1));
      expect(first.moves, hasLength(2));
      expect(first.ups, hasLength(1));
      expect(second.downs, isEmpty);
      expect(second.moves, isEmpty);
      expect(second.ups, isEmpty);

      // После отпускания новый обработчик обслуживает следующий жест.
      final next = await tester.startGesture(topLeft + const Offset(20, 20));
      await next.moveBy(const Offset(5, 0));
      await next.up();
      await tester.pump();

      expect(second.downs, hasLength(1));
      expect(second.moves, hasLength(1));
      expect(second.ups, hasLength(1));
      controller.dispose();
    });

    testWidgets('camera look survives an input swap mid-drag', (tester) async {
      final controller = SceneController();
      final fly = FlyCameraController(yaw: 0, pitch: 0);
      controller.camera = fly;
      Widget viewport(CameraInput input) => _host(
        SizedBox(
          width: 200,
          height: 200,
          child: SceneViewport(
            controller: controller,
            input: input,
            backend: _FakeBackend(),
          ),
        ),
      );
      // Роли как в pet_demo: ЛКМ — осмотр, ПКМ — панорама.
      CameraInput input() => CameraInput(
        pointerLookButton: kPrimaryButton,
        pointerFlyButton: kPrimaryButton,
        pointerPanButton: kSecondaryButton,
      );

      await tester.pumpWidget(viewport(input()));
      final topLeft = tester.getTopLeft(find.byType(SceneViewport));
      final gesture = await tester.startGesture(
        topLeft + const Offset(50, 50),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await gesture.moveBy(const Offset(10, 0));
      final afterFirstMove = fly.yaw;
      expect(afterFirstMove, greaterThan(0));

      // Пересборка со свежим CameraInput — как перерисовка FPS-метра в игре.
      // Раньше новые события уходили пустому экземпляру и камера замирала.
      await tester.pumpWidget(viewport(input()));
      await gesture.moveBy(const Offset(10, 0));
      await gesture.up();
      await tester.pump();

      expect(
        fly.yaw,
        greaterThan(afterFirstMove),
        reason: 'камера должна следовать за мышью и после пересборки',
      );
      controller.dispose();
    });

    testWidgets('nodes added during a build do not break the viewport', (
      tester,
    ) async {
      final controller = SceneController();
      final backend = _FakeBackend();
      var added = false;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              if (!added) {
                added = true;
                controller.add(BoxNode(id: 'late'));
              }
              return SceneViewport(controller: controller, backend: backend);
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.byId('late'), isNotNull);
      controller.dispose();
    });

    testWidgets('capture delegates to the backend', (tester) async {
      final controller = SceneController();
      final backend = _FakeBackend();
      final key = GlobalKey<SceneViewportState>();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              key: key,
              controller: controller,
              backend: backend,
            ),
          ),
        ),
      );
      await tester.pump();

      final bytes = await key.currentState!.capture(pixelRatio: 3);
      expect(bytes, [1, 2, 3]);
      expect(backend.capturedPixelRatio, 3);
      controller.dispose();
    });

    testWidgets('custom views are passed to the backend', (tester) async {
      final controller = SceneController();
      final backend = _FakeBackend();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 100,
            height: 100,
            child: SceneViewport(
              controller: controller,
              backend: backend,
              views: [
                SceneViewSpec.main(),
                SceneViewSpec.overlay(),
                SceneViewSpec.top(),
              ],
            ),
          ),
        ),
      );
      expect(backend.last!.views, hasLength(3));
      controller.dispose();
    });
  });
}

class _SlowSource extends ProjectSource {
  final Completer<void> _gate = Completer<void>();

  void complete() => _gate.complete();

  @override
  String get label => 'slow';

  @override
  bool get writable => false;

  @override
  Future<Uint8List?> readBytes(String relPath) async => null;

  @override
  Future<List<String>> listFiles(String relDir) async {
    await _gate.future;
    return [];
  }

  @override
  Future<void> writeBytes(String relPath, Uint8List bytes) async {
    throw UnsupportedError('read-only');
  }
}
