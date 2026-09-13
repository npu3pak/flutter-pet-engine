import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/left_panel.dart';

void main() {
  late AppState app;
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_left_panel_test');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    Directory('${dir.path}/models').createSync();
    app = AppState();
    await app.createProject(dir.path, name: 'test');
    app.createModel();
    // The template button asks about unsaved changes; these tests exercise
    // the templates, so start from a clean project.
    await app.saveAll();
  });

  tearDown(() {
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    // The main screen wraps the panel in a ListenableBuilder on the AppState
    // — mirror it, or the panel never rebuilds on app changes.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, _) => LeftPanel(app: app),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // The object list lives on the «Объекты» tab.
    await tester.tap(find.text('Объекты'));
    await tester.pumpAndSettle();
  }

  testWidgets('single click selects instantly (no double-tap wait)',
      (tester) async {
    await pumpPanel(tester);
    final obj = app.currentModel!.objects.first;
    await tester.tap(find.text(obj.name));
    // One frame is enough — selection must not wait for kDoubleTapTimeout.
    await tester.pump();
    expect(app.selectedObjectId, obj.id);
  });

  testWidgets('double click selects and focuses the camera', (tester) async {
    final focused = <String>[];
    app.onFocusObject = (o) => focused.add(o.id);
    await pumpPanel(tester);
    final obj = app.currentModel!.objects.first;
    final tile = find.text(obj.name);
    await tester.tap(tile);
    await tester.tap(tile);
    await tester.pump();
    expect(app.selectedObjectId, obj.id);
    expect(focused, [obj.id]);
  });

  testWidgets('double click on different objects does not focus',
      (tester) async {
    final focused = <String>[];
    app.onFocusObject = (o) => focused.add(o.id);
    app.addObject('cuboid');
    await pumpPanel(tester);
    final names = [for (final o in app.currentModel!.objects) o.name];
    expect(names.length, 2);
    // Fast click on two different rows — must not count as a double click.
    await tester.tap(find.text(names.first).last);
    await tester.tap(find.text(names.last).last);
    await tester.pump();
    expect(focused, isEmpty);
  });

  testWidgets('«Выделить все» selects every object', (tester) async {
    await pumpPanel(tester);
    app.addObject('cuboid');
    await tester.pump();
    await tester.tap(find.text('Выделить все'));
    await tester.pump();
    expect(app.selectedCount, 2);
    expect(app.selectedObjectId, app.currentModel!.objects.first.id);
  });

  testWidgets('«Снять выделение» clears the selection', (tester) async {
    await pumpPanel(tester);
    app.addObject('cuboid');
    await tester.pump();
    await tester.tap(find.text('Выделить все'));
    await tester.pump();
    expect(app.selectedCount, 2);
    await tester.tap(find.text('Снять выделение'));
    await tester.pump();
    expect(app.selectedCount, 0);
  });

  testWidgets('selection buttons appear above the tree', (tester) async {
    await pumpPanel(tester);
    // «Выделить все» shows for any non-empty model; «Снять выделение»
    // only once something is selected.
    expect(find.text('Выделить все'), findsOneWidget);
    expect(find.text('Снять выделение'), findsNothing);
    await tester.tap(find.text('Выделить все'));
    await tester.pump();
    expect(find.text('Снять выделение'), findsOneWidget);
  });

  testWidgets('«По шаблону» → «Комната» generates an indoor room',
      (tester) async {
    await pumpPanel(tester);
    // The template button lives on the «Модели» tab.
    await tester.tap(find.text('Модели'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('По шаблону'));
    await tester.tap(find.text('По шаблону'));
    await tester.pumpAndSettle();
    // The dialog lists all four template kinds.
    expect(find.text('Создать по шаблону'), findsOneWidget);
    await tester.tap(find.text('Комната'));
    await tester.pumpAndSettle();
    // Room sections appear: wall type rows for every side.
    for (final label in ['Северная', 'Восточная', 'Южная', 'Западная']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.ensureVisible(find.text('Создать'));
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    final model = app.currentModel!;
    expect(model.objects.any((o) => o.name == 'Стена Север'), isTrue);
    expect(model.objects.any((o) => o.name == 'Пол'), isTrue);
    expect(model.objects.any((o) => o.name == 'Потолок'), isTrue);
    expect(model.size.w, 5);
    expect(model.size.l, 5);
  });

  testWidgets('«Комната» without an entrance cannot be created',
      (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('Модели'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('По шаблону'));
    await tester.tap(find.text('По шаблону'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комната'));
    await tester.pumpAndSettle();
    // Default walls: only the south wall is a «Вход» — switching it to
    // «Глухая» leaves the room with no entrance. Wall rows run
    // north/east/south/west, so the south row's «Глухая» segment is the
    // third of the «Глухая» texts (its «Вход» is already selected).
    await tester.ensureVisible(find.text('Глухая').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Глухая').at(2));
    await tester.pumpAndSettle();
    expect(find.text('Хотя бы одна стена должна быть входом'), findsOneWidget);
    final create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Создать'));
    expect(create.onPressed, isNull);
  });

  // ── Освещение (light sources) ────────────────────────────────────────

  testWidgets('lighting mode lists the light sources and selects them',
      (tester) async {
    app.setMode(EditorMode.lighting);
    app.setCursor(1, 0, 1);
    app.addLight('point');
    app.addLight('directional');
    await pumpPanel(tester);
    expect(find.text('Освещение'), findsOneWidget);
    expect(find.text('Точечный свет'), findsOneWidget);
    expect(find.text('Направленный свет'), findsOneWidget);
    // The lighting mode hides the object/group rows.
    expect(find.text('floor'), findsNothing);
    await tester.tap(find.text('Направленный свет'));
    await tester.pump();
    expect(app.selectedLightId, app.currentModel!.lighting.lights.last.id);
  });
}
