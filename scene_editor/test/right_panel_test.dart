import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/right_panel.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  late AppState app;
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_right_panel_test');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    Directory('${dir.path}/models').createSync();
    app = AppState();
    await app.createProject(dir.path, name: 'test');
    app.createModel();
  });

  tearDown(() {
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester, {double width = 420}) async {
    // The main screen wraps the panel in a ListenableBuilder on the AppState
    // — mirror it, or the panel never rebuilds on app changes.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ListenableBuilder(
            listenable: app,
            builder: (_, _) => RightPanel(app: app),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('object panel shows both snap buttons for a solid', (tester) async {
    app.addObject('cuboid'); // selected automatically
    await pumpPanel(tester);
    expect(find.text('Перенести к грани'), findsOneWidget);
    expect(find.text('Параллельно грани'), findsOneWidget);
    expect(app.faceSnapMode, isNull);
  });

  testWidgets('snap buttons toggle the armed mode and cancel on re-click',
      (tester) async {
    app.addObject('cuboid');
    await pumpPanel(tester);
    await tapVisible(tester, 'Параллельно грани');
    expect(app.faceSnapMode, FaceSnapMode.parallelToFace);
    // The armed hint appears.
    expect(find.textContaining('Кликните грань'), findsOneWidget);
    await tapVisible(tester, 'Параллельно грани');
    expect(app.faceSnapMode, isNull);
    expect(find.textContaining('Кликните грань'), findsNothing);
  });

  testWidgets('move-to-face button arms its own mode', (tester) async {
    app.addObject('cuboid');
    await pumpPanel(tester);
    await tapVisible(tester, 'Перенести к грани');
    expect(app.faceSnapMode, FaceSnapMode.moveToFace);
    expect(find.textContaining('Кликните грань'), findsOneWidget);
  });

  testWidgets('sprites hide the parallel button (billboards do not rotate)',
      (tester) async {
    app.pickResource('sprite', 'tree.png'); // adds and selects a sprite
    await pumpPanel(tester);
    expect(find.text('Перенести к грани'), findsOneWidget);
    expect(find.text('Параллельно грани'), findsNothing);
  });

  // ── Разметка (meta-objects) ─────────────────────────────────────────

  testWidgets('markup mode with a selected meta shows its panel',
      (tester) async {
    app.setMode(EditorMode.markup);
    app.setCursor(1, 0, 1);
    app.addMeta('box');
    await pumpPanel(tester);
    expect(find.text('Бокс · Разметка'), findsOneWidget);
    expect(find.text('непроходимый'), findsNothing);
    app.setMetaName(app.selectedMetaId!, 'непроходимый');
    await pumpPanel(tester);
    expect(find.text('непроходимый'), findsWidgets);
    // A named box already carries a label: the collapse toggle is offered.
    expect(find.text('Схлопнуть подпись'), findsOneWidget);
  });

  testWidgets('markup mode without selection explains the tools',
      (tester) async {
    app.setMode(EditorMode.markup);
    await pumpPanel(tester);
    expect(find.text('Разметка'), findsOneWidget);
    expect(find.textContaining('Инструменты на верхней панели'), findsOneWidget);
  });

  testWidgets('markup meta edits propagate through the panel',
      (tester) async {
    app.setMode(EditorMode.markup);
    app.addMeta('comment');
    app.setMetaComment(app.selectedMetaId!, 'короткий');
    await pumpPanel(tester);
    expect(find.text('Раскрыть подпись'), findsOneWidget); // collapsed by default
  });

  // ── Освещение (light sources) ───────────────────────────────────────

  testWidgets('lighting mode without selection shows the scene settings',
      (tester) async {
    app.setMode(EditorMode.lighting);
    await pumpPanel(tester);
    expect(find.text('Освещение сцены'), findsOneWidget);
    expect(find.text('Показывать гизмо источников'), findsOneWidget);
    expect(find.text('Тени'), findsOneWidget);
    expect(find.textContaining('SSAO'), findsWidgets);
  });

  testWidgets('scene lighting knobs propagate through the panel',
      (tester) async {
    app.setMode(EditorMode.lighting);
    app.addLight('point');
    await pumpPanel(tester);
    // A selected source takes the panel; the scene settings return when the
    // light is deselected.
    expect(find.textContaining('· Освещение'), findsOneWidget);
    app.selectLight(null);
    await pumpPanel(tester);
    expect(find.text('Освещение сцены'), findsOneWidget);
    // Three switches: гизмо → тени → SSAO.
    expect(find.byType(Switch), findsNWidgets(3));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(app.currentModel!.lighting.shadows, isTrue);
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    expect(app.currentModel!.lighting.ssao, isTrue);
  });

  testWidgets('lighting mode with a selected source shows its panel and '
      'propagates edits', (tester) async {
    app.setMode(EditorMode.lighting);
    app.setCursor(1, 0, 1);
    app.addLight('directional');
    await pumpPanel(tester);
    expect(find.text('Направленный свет · Освещение'), findsOneWidget);
    expect(find.textContaining('азимут'), findsOneWidget);
    expect(find.text('Интенсивность'), findsOneWidget);
    expect(find.text('Дальность (0 = без ограничений)'), findsNothing);
    final id = app.selectedLightId!;
    app.setLightName(id, 'солнце');
    await pumpPanel(tester);
    expect(find.text('солнце'), findsWidgets);
    app.deleteLight(id);
    expect(app.currentModel!.lighting.lights, isEmpty);
  });

  // ── Многогранник ────────────────────────────────────────────────────

  testWidgets('панель многогранника: режим, масштаб, операции',
      (tester) async {
    app.addObject('polyhedron'); // выбран автоматически
    await pumpPanel(tester);
    expect(find.text('Многогранник'), findsWidgets);
    expect(find.text('Объект'), findsOneWidget);
    expect(find.text('Грани'), findsOneWidget);
    expect(find.text('Вершины'), findsOneWidget);
    expect(find.text('Масштаб (вытягивание по осям)'), findsOneWidget);
    // Режим граней: кнопка удаления и счётчик.
    await tapVisible(tester, 'Грани');
    expect(app.polyEditMode, PolyEditMode.faces);
    expect(find.textContaining('Граней: 6'), findsOneWidget);
    expect(find.text('Удалить грань'), findsOneWidget);
    // Режим вершин: кнопки добавления/удаления.
    await tapVisible(tester, 'Вершины');
    expect(app.polyEditMode, PolyEditMode.vertices);
    await tapVisible(tester, 'Добавить вершину');
    expect(app.polyAddVertexArmed, isTrue);
    expect(find.text('Удалить вершину'), findsOneWidget);
  });

  testWidgets('у кубоида есть кнопка конверсии в многогранник',
      (tester) async {
    app.addObject('cuboid');
    await pumpPanel(tester);
    await tapVisible(tester, 'Преобразовать в многогранник');
    final obj = app.currentModel!.objects.last;
    expect(obj.kind, polyhedronKind);
    expect(obj.mesh!.faces, hasLength(6));
    await pumpPanel(tester);
    expect(find.text('Многогранник'), findsWidgets);
  });
}
