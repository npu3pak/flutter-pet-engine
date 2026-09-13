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
    dir = Directory.systemTemp.createTempSync('scene_editor_level_fields_test');
    Directory('${dir.path}/textures').createSync();
    Directory('${dir.path}/sprites').createSync();
    Directory('${dir.path}/models').createSync();
    app = AppState();
    await app.createProject(dir.path, name: 'test');
    app.createModel();
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('entry sides toggle with undo/redo', () {
    app.toggleEntrySide(ModelSide.north);
    expect(app.currentModel!.entries, {ModelSide.north});
    app.toggleEntrySide(ModelSide.east);
    expect(app.currentModel!.entries, {ModelSide.north, ModelSide.east});
    app.undo();
    expect(app.currentModel!.entries, {ModelSide.north});
    app.undo();
    expect(app.currentModel!.entries, isEmpty);
    app.redo();
    expect(app.currentModel!.entries, {ModelSide.north});
  });

  test('front side sets and clears with undo', () {
    app.setFrontSide(ModelSide.south);
    expect(app.currentModel!.front, ModelSide.south);
    app.setFrontSide(null);
    expect(app.currentModel!.front, isNull);
    app.undo();
    expect(app.currentModel!.front, ModelSide.south);
  });

  test('the cell brush paints one undoable stroke', () {
    app.beginCellStroke();
    app.paintCellMeta(metaNameUnpassable, 1, 2);
    app.paintCellMeta(metaNameUnpassable, 2, 2);
    app.paintCellMeta(metaNameUnpassable, 2, 2); // duplicate: no-op
    app.endCellStroke();
    final metas = app.currentModel!.metas;
    expect(metas, hasLength(2));
    expect(metas.first.name, metaNameUnpassable);
    expect(metas.first.kind, metaKindBox);
    expect((metas.first.x, metas.first.z), (1.0, 2.0));
    expect(metas.first.dim('w', 0), 1.0);
    expect(metas.first.dim('d', 0), 1.0);
    app.undo();
    expect(app.currentModel!.metas, isEmpty);
    app.redo();
    expect(app.currentModel!.metas, hasLength(2));
  });

  test('the brush name and armed state are app state', () {
    expect(app.cellBrushName, metaNameUnpassable);
    expect(app.cellBrushArmed, isFalse);
    app.setCellBrushName('door');
    expect(app.cellBrushName, 'door');
    app.setCellBrushArmed(true);
    expect(app.cellBrushArmed, isTrue);
    app.setCellBrushArmed(false);
    expect(app.cellBrushArmed, isFalse);
  });

  test('entries/front survive save and load', () async {
    app.toggleEntrySide(ModelSide.south);
    app.setFrontSide(ModelSide.south);
    await app.project!.saveModel(app.currentModel!);
    final controller = SceneController();
    await controller.open(DirectoryProjectSource(dir));
    final reloaded = controller.project.models.values.single;
    expect(reloaded.entries, {ModelSide.south});
    expect(reloaded.front, ModelSide.south);
  });

  test('биомные проекты открываются и отдают поля сцены (редактор ↔ игра)',
      () async {
    // Сцена-представитель каждого биома: id, входные стороны, лицевая.
    const expected = {
      'Streets': ('chunk_2', {ModelSide.south}, ModelSide.south),
      'Dungeon': (
        'chunk_1',
        {ModelSide.north, ModelSide.east, ModelSide.south, ModelSide.west},
        null,
      ),
      'Forest': (
        'chunk_1',
        {ModelSide.east, ModelSide.south, ModelSide.west},
        null,
      ),
      'AbandonedBuilding': ('chunk_1', {ModelSide.south}, ModelSide.south),
    };
    for (final entry in expected.entries) {
      final dir = Directory('../projects/${entry.key}');
      if (!dir.existsSync()) return; // run from the scene_editor package
      final controller = SceneController();
      await controller.open(DirectoryProjectSource(dir));
      final (id, entries, front) = entry.value;
      final model = controller.project.models[id];
      expect(model, isNotNull, reason: entry.key);
      expect(model!.entries, entries, reason: '${entry.key}/$id: входы');
      expect(model.front, front, reason: '${entry.key}/$id: лицевая');

      // Движок читает те же поля: кромка на входных сторонах проходима,
      // двери — проходимые клетки.
      final placement =
          ScenePlacement(scene: model, originRow: 0, originCol: 0);
      for (final side in entries) {
        expect(placement.hasEntry(side), isTrue, reason: '${entry.key}/$id');
        expect(placement.openBorderCells(side), isNotEmpty,
            reason: '${entry.key}/$id: кромка $side');
      }
      for (final (x, z) in placement.doorCells) {
        expect(placement.isCellPassable(x, z), isTrue,
            reason: '${entry.key}/$id: дверь ($x,$z)');
      }
    }
  });

  testWidgets('markup panel edits entries, front and the brush',
      (tester) async {
    app.setMode(EditorMode.markup);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: ListenableBuilder(
            listenable: app,
            builder: (_, _) => RightPanel(app: app),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Входные стороны (entries)'), findsOneWidget);
    expect(find.text('Лицевая сторона (front)'), findsOneWidget);
    expect(find.text('Кисть клеточных мет'), findsOneWidget);

    await tester.tap(find.text('Юг'));
    await tester.pump();
    expect(app.currentModel!.entries, {ModelSide.south});

    await tester.tap(find.text('Кисть включена'));
    await tester.pump();
    expect(app.cellBrushArmed, isTrue);
    await tester.tap(find.text('door'));
    await tester.pump();
    expect(app.cellBrushName, 'door');
  });
}
