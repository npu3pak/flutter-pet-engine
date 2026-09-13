import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/unsaved_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('unsaved_changes_test');
    app = AppState();
    await app.createProject(dir.path, name: 'P');
  });

  tearDown(() {
    app.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a new model counts as unsaved and saveAll writes it', () async {
    expect(app.hasUnsavedChanges, isFalse);
    app.createModel();
    expect(app.hasUnsavedChanges, isTrue);
    expect(await app.saveAll(), isTrue);
    expect(app.hasUnsavedChanges, isFalse);
  });

  test('duplicating a model leaves it unsaved', () async {
    app.createModel();
    await app.saveAll();
    expect(app.hasUnsavedChanges, isFalse);
    app.duplicateModel(app.currentModelId!);
    expect(app.hasUnsavedChanges, isTrue);
  });

  testWidgets('the dialog offers save, discard and cancel', (tester) async {
    app.createModel();
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmUnsavedChanges(context, app);
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    // Cancel keeps the changes and blocks the action.
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(app.hasUnsavedChanges, isTrue);

    // Discard proceeds and leaves the in-memory changes for the caller to
    // drop (the project is being replaced).
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-discard')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(app.hasUnsavedChanges, isTrue);

    // The Save button exists and closes the dialog; the write itself is
    // covered by the plain AppState test above (real file I/O does not run
    // inside the widget-test fake async zone).
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-save')));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsNothing);
  });

  testWidgets('nothing unsaved means no dialog', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmUnsavedChanges(context, app);
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Несохранённые изменения'), findsNothing);
    expect(result, isTrue);
  });
}
