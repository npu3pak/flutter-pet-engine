import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/editor_viewport.dart';

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

void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('editor_viewport_test');
    app = AppState();
    await app.createProject(dir.path, name: 'P');
    app.createModel();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpViewport(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorViewport(app: app, backend: _FakeBackend())),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  }

  testWidgets('ПКМ вращает камеру, W при зажатой ПКМ летит', (tester) async {
    await pumpViewport(tester);
    final fly = app.controller.camera as FlyCameraController;
    final yaw0 = fly.yaw;

    final center = tester.getCenter(find.byType(SceneViewport));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(
      fly.yaw,
      isNot(closeTo(yaw0, 1e-6)),
      reason: 'протяжка ПКМ должна вращать камеру',
    );

    final before = fly.eye.clone();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await gesture.up();
    await tester.pump();
    expect(
      (fly.eye - before).length,
      greaterThan(0.01),
      reason: 'W при зажатой ПКМ должна двигать камеру',
    );

    await unmount(tester);
  });

  testWidgets('ЛКМ по пустому месту не летит и не вращает камеру', (tester) async {
    await pumpViewport(tester);
    final fly = app.controller.camera as FlyCameraController;
    final yaw0 = fly.yaw;
    final eye0 = fly.eye.clone();

    final center = tester.getCenter(find.byType(SceneViewport));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(80, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(fly.yaw, closeTo(yaw0, 1e-6));
    expect((fly.eye - eye0).length, lessThan(1e-6));

    await unmount(tester);
  });

  testWidgets('гизмо переноса двигает выбранный объект', (tester) async {
    await pumpViewport(tester);
    final model = app.currentModel!;
    final object = model.objects.first;
    app.selectObject(object.id);
    await tester.pump();

    // Камера смотрит на модель так же, как после открытия модели.
    final fly = app.controller.camera as FlyCameraController;
    fly.frameModel(model);
    await tester.pump();

    // В widget-тесте нет рендер-камеры, поэтому масштаб гизмо (обычно
    // обновляемый контроллером каждый кадр) задаём вручную.
    final moveGizmo = app.controller.gizmos
        .firstWhere((g) => g.mode == GizmoMode.translate);
    moveGizmo.applyScreenScale(1.0);
    await tester.pump();

    // Середина оси X движкового гизмо (мировое +X).
    final handle = app.controller.worldToScreen(
      moveGizmo.anchor + gizmoAxisDirection(GizmoAxis.x),
    );
    expect(handle, isNotNull, reason: 'ось гизмо должна быть в кадре');

    final x0 = object.x;
    final gesture = await tester.startGesture(
      handle!,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(object.x, isNot(closeTo(x0, 1e-6)), reason: 'объект должен сдвинуться');

    await unmount(tester);
  });

  testWidgets('повторная пересборка оверлеев не ломает слой выделения',
      (tester) async {
    await pumpViewport(tester);
    final model = app.currentModel!;
    final selection = app.controller.byId('editor-selection') as GroupNode;

    app.selectObject(model.objects.first.id);
    await tester.pump();
    app.controller.rebuild();
    await tester.pump();
    expect(selection.children, isNotEmpty);

    app.selectObject(model.objects.last.id);
    await tester.pump();
    app.controller.rebuild();
    await tester.pump();

    expect(selection.parent?.id, 'editor-overlays');
    expect(selection.children, isNotEmpty);
    expect(
      app.controller
          .nodesOfType<GroupNode>()
          .where((node) => node.id == 'editor-selection')
          .length,
      1,
      reason: 'слой выделения не должен дублироваться между пересборками',
    );

    await unmount(tester);
  });

  testWidgets('тумблеры теней и SSAO доходят до качества сцены', (tester) async {
    await pumpViewport(tester);
    final model = app.currentModel!;
    // Свой свет делает конфигурацию нестандартной — тумблеры активны.
    model.lighting.lights.add(
      ModelLight(
        id: 'sun',
        kind: lightKindDirectional,
        name: 'Солнце',
        intensity: 2,
        dirX: -0.4,
        dirY: -0.85,
        dirZ: -0.35,
      ),
    );
    model.lighting.shadows = false;
    model.lighting.ssao = false;

    app.setLightingShadows(true);
    app.setLightingSsao(true);
    await tester.pump();
    expect(app.controller.settings.shadows, isTrue);
    expect(app.controller.settings.ssao, isTrue);

    app.setLightingShadows(false);
    app.setLightingSsao(false);
    await tester.pump();
    expect(app.controller.settings.shadows, isFalse);
    expect(app.controller.settings.ssao, isFalse);

    await unmount(tester);
  });
}
