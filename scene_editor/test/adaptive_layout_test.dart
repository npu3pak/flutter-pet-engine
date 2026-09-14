import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/bottom_bars.dart';
import 'package:scene_editor/src/ui/main_screen.dart';

void main() {
  test('narrow layout threshold: < 900px uses drawers', () {
    expect(isNarrowLayout(899), isTrue);
    expect(isNarrowLayout(768), isTrue);
    expect(isNarrowLayout(900), isFalse);
    expect(isNarrowLayout(1024), isFalse);
    expect(isNarrowLayout(1200), isFalse);
  });

  group('TopBar rotate-mode toggle', () {
    late Directory dir;
    late AppState app;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('scene_editor_toggle_test');
      app = AppState();
      await app.createProject(dir.path, name: 'test');
      app.createModel();
    });

    tearDown(() {
      app.dispose();
      dir.deleteSync(recursive: true);
    });

    testWidgets('toggles rotateGizmoMode and back', (tester) async {
      // Wide surface so the toolbar's flex layout engages and everything
      // fits on screen.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (context, _) => TopBar(app: app),
          ),
        ),
      ));
      expect(app.rotateGizmoMode, isFalse);

      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pump();
      expect(app.rotateGizmoMode, isTrue);
      expect(find.byIcon(Icons.rotate_left), findsOneWidget);

      await tester.tap(find.byIcon(Icons.rotate_left));
      await tester.pump();
      expect(app.rotateGizmoMode, isFalse);
    });

    testWidgets('кнопка «Многогранник» добавляет куб-сеть', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (context, _) => TopBar(app: app),
          ),
        ),
      ));
      await tester.tap(find.byIcon(Icons.polyline));
      await tester.pump();
      final added = app.currentModel!.objects.last;
      expect(added.kind, 'polyhedron');
      expect(added.mesh!.faces, hasLength(6));
      expect(app.selectedObjectId, added.id);
    });
  });
}
