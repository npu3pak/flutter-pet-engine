import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/editor_viewport.dart';
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

  testWidgets('отмена указателя завершает драг гизмо', (tester) async {
    await pumpViewport(tester);
    final model = app.currentModel!;
    final object = model.objects.first;
    app.selectObject(object.id);
    await tester.pump();

    final fly = app.controller.camera as FlyCameraController;
    fly.frameModel(model);
    await tester.pump();
    final moveGizmo = app.controller.gizmos
        .firstWhere((g) => g.mode == GizmoMode.translate);
    moveGizmo.applyScreenScale(1.0);
    await tester.pump();

    final handle = app.controller.worldToScreen(
      moveGizmo.anchor + gizmoAxisDirection(GizmoAxis.x),
    )!;
    final x0 = object.x;
    final gesture = await tester.startGesture(
      handle,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();

    // Два события до кадра: шаг ещё не применён — позиция копится в очереди.
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(30, 0));
    expect(moveGizmo.dragging, isTrue);
    expect(object.x, closeTo(x0, 1e-6), reason: 'коалесинг ждёт кадр/отпускание');

    await gesture.cancel();
    await tester.pump();
    expect(object.x, isNot(closeTo(x0, 1e-6)),
        reason: 'отмена применяет последнюю точку и завершает драг');
    expect(moveGizmo.dragging, isFalse, reason: 'отмена завершает драг');

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

  testWidgets('пересоздание вьюпорта снимает старые оверлеи и гизмо', (
    tester,
  ) async {
    await pumpViewport(tester);
    app.selectObject(app.currentModel!.objects.first.id);
    await tester.pump();

    final oldOverlays = app.controller.byId('editor-overlays')!;
    final oldSelection = app.controller.byId('editor-selection')!;
    final oldLightRoot = app.controller.byId('light-gizmos')!;
    final oldGizmos = List.of(app.controller.gizmos);
    expect(oldGizmos, hasLength(2));

    // Вкладка «Ресурсы»: EditorViewport (и его EditorScene) уничтожается,
    // контроллер остаётся жив — ноды старой сцены должны уйти с него.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(oldOverlays.isDisposed, isTrue,
        reason: 'старые оверлеи должны сниматься с контроллера');
    expect(oldSelection.isDisposed, isTrue);
    expect(oldLightRoot.isDisposed, isTrue);
    for (final gizmo in oldGizmos) {
      expect(gizmo.isDisposed, isTrue);
    }
    expect(app.controller.gizmos, isEmpty);

    // Возврат в «Композицию»: ровно один новый комплект.
    await pumpViewport(tester);
    expect(app.controller.gizmos, hasLength(2));
    expect(app.controller.byId('editor-overlays'), isNot(same(oldOverlays)));
    final overlays = app.controller.byId('editor-overlays') as GroupNode;
    expect(
      overlays.children,
      hasLength(4),
      reason: 'сетка, рамка, курсор и слой выделения — по одному',
    );

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('armed-добавление вершины ставит её на грань под нажатием',
      (tester) async {
    app.addObject('polyhedron');
    final obj = app.currentModel!.objects.last;
    app.setPolyEditMode(PolyEditMode.vertices);
    app.togglePolyAddVertex();
    await pumpViewport(tester);

    // Камера сверху над кубом: наводим на центр верхней грани.
    final fly = app.controller.camera as FlyCameraController;
    final model = app.currentModel!;
    final anchor = chunkWorld(obj.x, obj.z, model.size.w, model.size.l);
    fly.eye = vm.Vector3(anchor.x, 6, anchor.z + 0.01);
    fly.yaw = 0;
    fly.pitch = math.pi / 2;
    await tester.pump();
    final top = vm.Vector3(anchor.x, 1, anchor.z);
    final screen = app.controller.worldToScreen(top)!;
    final viewportTopLeft = tester
        .getTopLeft(find.byType(SceneViewport));
    await tester.tapAt(viewportTopLeft + screen);
    await tester.pump();

    expect(obj.mesh!.vertices, hasLength(9),
        reason: 'вершина добавлена в верхнюю грань');
    expect(app.selectedVertexIndices, isNotEmpty);
    expect(app.activeVertexIndex, 8);

    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
