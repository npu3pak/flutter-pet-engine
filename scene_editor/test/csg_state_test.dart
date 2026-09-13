import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/state/app_state.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_csg_state');
    app = AppState();
    await app.createProject(dir.path, name: 'test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  /// Model with the floor removed and two cuboids `a`, `b` added at the root.
  ModelData seedModel() {
    app.createModel();
    final model = app.currentModel!;
    final floor = model.objects.first.id;
    app.deleteObject(floor);
    app.selectObject(null);
    app.addObject('cuboid');
    final a = app.selectedObject()!;
    app.setObjectPos(a.id, 0.5, 0, 0.5);
    app.addObject('cuboid');
    final b = app.selectedObject()!;
    app.setObjectPos(b.id, 1.5, 0, 0.5);
    return app.currentModel!;
  }

  void selectTwo(String aId, String bId) {
    app.selectObject(null);
    app.selectObject(aId);
    app.selectObject(bId, shift: true);
  }

  test('union hides operands and renders through the result node', () {
    final model = seedModel();
    final a = model.objects[0];
    final b = model.objects[1];
    selectTwo(a.id, b.id);
    expect(app.canCombineSelection, isTrue);
    app.createCsgOperation(csgOpUnion);
    final node = app.selectedObject()!;
    expect(node.kind, csgKind);
    expect(node.op, csgOpUnion);
    expect(node.operands, [a.id, b.id]);
    expect(app.currentModel!.visibleObjects().map((o) => o.id),
        isNot(contains(a.id)));
    expect(app.currentModel!.visibleObjects().map((o) => o.id),
        isNot(contains(b.id)));
    // One undo: the node disappears, the operands are visible again.
    app.undo();
    expect(app.currentModel!.objects.length, 2);
    expect(app.currentModel!.visibleObjects().length, 2);
    app.redo();
    expect(app.currentModel!.visibleObjects().length, 1);
  });

  test('subtract direction follows operand order and swap flips it', () {
    final model = seedModel();
    final a = model.objects[0];
    final b = model.objects[1];
    selectTwo(a.id, b.id);
    app.createCsgOperation(csgOpDifference);
    var node = app.selectedObject()!;
    expect(node.operands, [a.id, b.id]);
    app.swapCsgOperands(node.id);
    expect(node.operands, [b.id, a.id]);
    app.undo();
    expect(node.operands, [a.id, b.id]);
    app.redo();
    expect(node.operands, [b.id, a.id]);
  });

  test('operations only on two free convex solids', () {
    final model = seedModel();
    final a = model.objects[0];
    final b = model.objects[1];
    // One selected — not enough.
    app.selectObject(a.id);
    expect(app.canCombineSelection, isFalse);
    // Three selected — too many.
    app.addObject('cuboid');
    selectTwo(a.id, app.selectedObject()!.id);
    app.selectObject(model.objects[0].id, shift: true);
    expect(app.canCombineSelection, isFalse);
    // Planes are not eligible.
    app.selectObject(null);
    app.addObject('plane');
    final plane = app.selectedObject()!;
    selectTwo(a.id, plane.id);
    expect(app.canCombineSelection, isFalse);
    // After union the operands are consumed and cannot be combined again.
    app.selectObject(null);
    app.addObject('cuboid');
    final c = app.selectedObject()!;
    app.setObjectPos(c.id, 2.5, 0, 0.5);
    selectTwo(b.id, c.id);
    expect(app.canCombineSelection, isTrue);
    app.createCsgOperation(csgOpUnion);
    // b is now an operand; combining b with a free object must fail.
    selectTwo(b.id, c.id);
    expect(app.canCombineSelection, isFalse);
    // But the union result can be combined with a free object.
    app.selectObject(null);
    app.addObject('cuboid');
    final d = app.selectedObject()!;
    app.setObjectPos(d.id, 3.5, 0, 0.5);
    final union = app.currentModel!.objects
        .firstWhere((o) => o.kind == csgKind);
    selectTwo(union.id, d.id);
    expect(app.canCombineSelection, isTrue);
  });

  test('moving a csg result moves its leaves (gizmo/group move)', () {
    final model = seedModel();
    final a = model.objects[0];
    selectTwo(a.id, model.objects[1].id);
    app.createCsgOperation(csgOpUnion);
    final node = app.selectedObject()!;
    final ax = a.x;
    app.moveGroup(1, 0, 0);
    expect(a.x, ax + 1);
    expect(node.x, 0); // the node itself has no geometry
  });

  test('deleting an operand cascades into the operation (dissolve)', () {
    final model = seedModel();
    final a = model.objects[0];
    selectTwo(a.id, model.objects[1].id);
    app.createCsgOperation(csgOpUnion);
    app.undo(); // back to the plain selection
    app.selectObject(a.id);
    app.deleteObject(a.id);
    expect(app.currentModel!.objects.length, 1); // only the other cuboid
    expect(app.currentModel!.visibleObjects().length, 1);
    app.undo();
    expect(app.currentModel!.objects.length, 2);
    app.redo();
    expect(app.currentModel!.objects.length, 1);
  });

  test('deleting a result node dissolves the subtree (operands stay)', () {
    final model = seedModel();
    final a = model.objects[0];
    final b = model.objects[1];
    selectTwo(a.id, b.id);
    app.createCsgOperation(csgOpUnion);
    final node = app.selectedObject()!;
    app.deleteObject(node.id);
    expect(app.currentModel!.objects.length, 2);
    expect(app.currentModel!.visibleObjects().length, 2);
    expect(app.currentModel!.csgRoots(), isEmpty);
    app.undo();
    expect(app.currentModel!.csgRoots().single.id, node.id);
    app.redo();
    expect(app.currentModel!.csgRoots(), isEmpty);
  });

  test('duplicating a result deep-copies its subtree', () {
    final model = seedModel();
    final a = model.objects[0];
    selectTwo(a.id, model.objects[1].id);
    app.createCsgOperation(csgOpUnion);
    final node = app.selectedObject()!;
    app.duplicateObject();
    final model2 = app.currentModel!;
    final roots = model2.csgRoots();
    expect(roots.length, 2);
    final copy = roots.firstWhere((o) => o.id != node.id);
    expect(copy.id, isNot(node.id));
    final copyLeaf = model2.objectById(copy.operands!.first)!;
    expect(copyLeaf.id, isNot(a.id));
    expect(model2.objectById(a.id), isNotNull); // original untouched
    // Moving the copy's leaf leaves the original alone.
    app.selectObject(copyLeaf.id);
    final ax = a.x;
    app.moveGroup(0.5, 0, 0);
    expect(copyLeaf.x, ax + 0.8); // duplicate offset 0.3 + move 0.5
    expect(a.x, ax);
    app.undo();
  });

  test('grouping a csg operand is blocked', () {
    final model = seedModel();
    final a = model.objects[0];
    selectTwo(a.id, model.objects[1].id);
    app.createCsgOperation(csgOpUnion);
    app.selectObject(a.id);
    app.createGroup();
    expect(app.currentModel!.groups, isEmpty);
  });
}
