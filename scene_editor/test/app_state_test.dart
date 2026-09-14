import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/scene/light_renderer.dart' show kLightBallRadius;
import 'package:scene_editor/src/scene/meta_renderer.dart' show kCommentBallRadius;
import 'package:scene_editor/src/state/app_state.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('scene_editor_app_test');
    app = AppState();
    await app.createProject(dir.path, name: 'test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('create model sets current', () {
    app.createModel();
    expect(app.currentModel, isNotNull);
    expect(app.currentModel!.objects.single.name, 'floor');
    expect(app.currentModelId, 'model_1');
    app.createModel();
    expect(app.currentModelId, 'model_2');
  });

  test('openProject без моделей выгружает прошлый документ', () async {
    app.createModel();
    expect(app.currentModel, isNotNull);

    final empty = Directory.systemTemp.createTempSync('scene_editor_empty');
    addTearDown(() {
      if (empty.existsSync()) empty.deleteSync(recursive: true);
    });
    final ok = await app.createProject(empty.path, name: 'empty');
    expect(ok, isTrue);
    expect(app.currentModel, isNull,
        reason: 'прошлая модель не должна переживать смену проекта');
    expect(app.currentModelId, isNull);
    expect(app.controller.model, isNull);
    expect(app.selectedObjectId, isNull);
    expect(app.selectedIds, isEmpty);
  });

  test('create model floor covers the whole footprint', () {
    app.createModel();
    final floor = app.currentModel!.objects.single;
    final size = app.currentModel!.size;
    expect(floor.kind, 'cuboid');
    expect(floor.x, (size.w - 1) / 2);
    expect(floor.z, (size.l - 1) / 2);
    expect(floor.dims['w'], size.w);
    expect(floor.dims['d'], size.l);
    expect(floor.dims['h'], 0.05);
  });

  test('add object then undo removes it, redo restores', () {
    app.createModel();
    final before = app.currentModel!.objects.length;
    app.addObject('cuboid');
    expect(app.currentModel!.objects.length, before + 1);
    expect(app.selectedObjectId, isNotNull);
    app.undo();
    expect(app.currentModel!.objects.length, before);
    app.redo();
    expect(app.currentModel!.objects.length, before + 1);
  });

  test('addObject многогранника создаёт куб с сетью', () {
    app.createModel();
    app.addObject('polyhedron');
    final obj = app.currentModel!.objects.last;
    expect(obj.kind, polyhedronKind);
    expect(obj.mesh, isNotNull);
    expect(obj.mesh!.faces, hasLength(6));
    expect(obj.mesh!.vertices, hasLength(8));
    expect(app.selectedObjectId, obj.id);
    app.undo();
    expect(app.currentModel!.objects.contains(obj), isFalse);
  });

  test('duplicate object undo/redo', () {
    app.createModel();
    app.selectObject(app.currentModel!.objects.first.id);
    app.duplicateObject();
    final names = app.currentModel!.objects.map((o) => o.name).toList();
    expect(names.where((n) => n.startsWith('floor')).length, 2);
    app.undo();
    expect(app.currentModel!.objects.length, 1);
    app.redo();
    expect(app.currentModel!.objects.length, 2);
  });

  // ── meta objects (Разметка) ──────────────────────────────────────────

  test('addMeta places each kind at the cursor and selects it', () {
    app.createModel();
    app.setCursor(2.5, 0, 1.5);
    app.addMeta('marker');
    var metas = app.currentModel!.metas;
    expect(metas, hasLength(1));
    expect(metas.first.kind, 'marker');
    expect(metas.first.name, 'Маркер');
    expect(metas.first.x, 2.5);
    expect(metas.first.z, 1.5);
    expect(app.selectedMetaId, metas.first.id);
    // ids advance, duplicate names allowed
    app.addMeta('marker');
    metas = app.currentModel!.metas;
    expect(metas, hasLength(2));
    expect(metas.map((m) => m.id).toSet(), hasLength(2));
    expect(metas.last.name, 'Маркер');
  });

  test('addMeta comment defaults collapsed and lifted off the floor', () {
    app.createModel();
    app.setCursor(1, 0, 1);
    app.addMeta('comment');
    final m = app.currentModel!.metas.single;
    expect(m.kind, 'comment');
    expect(m.collapsed, isTrue);
    expect(m.y, closeTo(kCommentBallRadius, 1e-9));
  });

  test('addMeta box has default dims; undo removes, redo restores', () {
    app.createModel();
    app.addMeta('box');
    final m = app.currentModel!.metas.single;
    expect(m.dim('w', 0), 1.0);
    expect(m.dim('h', 0), 1.0);
    expect(m.dim('d', 0), 1.0);
    app.undo();
    expect(app.currentModel!.metas, isEmpty);
    app.redo();
    expect(app.currentModel!.metas, hasLength(1));
  });

  test('meta edits are undoable and restore in place', () {
    app.createModel();
    app.addMeta('box');
    final id = app.selectedMetaId!;
    app.setMetaName(id, 'непроходимый');
    app.setMetaComment(id, 'кошка не пройдёт');
    app.setMetaZIndex(id, 5);
    app.setMetaDim(id, 'h', 2.2);
    var m = app.currentModel!.metaById(id)!;
    expect(m.name, 'непроходимый');
    expect(m.zIndex, 5);
    expect(m.dim('h', 0), closeTo(2.2, 1e-9));
    app.undo(); // z-index
    expect(app.currentModel!.metaById(id)!.zIndex, 0);
    app.redo();
    expect(app.currentModel!.metaById(id)!.zIndex, 5);
    // same meta object restored in place (identity kept for the renderer)
    m = app.currentModel!.metaById(id)!;
    app.toggleMetaCollapsed(id);
    expect(m.collapsed, isTrue);
    app.undo();
    expect(m.collapsed, isFalse);
  });

  test('deleteMeta undo restores at the same index', () {
    app.createModel();
    app.addMeta('comment');
    app.addMeta('marker');
    app.addMeta('box');
    final id = app.currentModel!.metas[1].id;
    app.deleteMeta(id);
    expect(app.currentModel!.metas.map((m) => m.id), isNot(contains(id)));
    app.undo();
    expect(app.currentModel!.metas[1].id, id);
  });

  test('duplicateMeta copies and selects the copy', () {
    app.createModel();
    app.setCursor(1, 0, 1);
    app.addMeta('marker');
    app.setMetaName(app.selectedMetaId!, 'камера');
    final originalId = app.selectedMetaId!;
    app.duplicateMeta();
    final metas = app.currentModel!.metas;
    expect(metas, hasLength(2));
    expect(app.selectedMetaId, isNot(originalId));
    final copy = app.currentModel!.metaById(app.selectedMetaId!)!;
    expect(copy.name, 'камера_2');
    expect(copy.x, closeTo(1.3, 1e-9));
    app.undo();
    expect(app.currentModel!.metas, hasLength(1));
    expect(app.selectedMetaId, originalId);
  });

  test('meta gizmo drag pushes a single undo command', () {
    app.createModel();
    app.addMeta('marker');
    final id = app.selectedMetaId!;
    app.beginMetaGizmoDrag();
    final m = app.currentModel!.metaById(id)!;
    m.x = 3.5;
    m.z = 2;
    app.endMetaGizmoDrag(action: 'Перенос');
    expect(app.currentModel!.metaById(id)!.x, closeTo(3.5, 1e-9));
    app.undo();
    final restored = app.currentModel!.metaById(id)!;
    expect(restored.x, isNot(closeTo(3.5, 1e-9)));
    expect(restored.z, isNot(closeTo(2, 1e-9)));
    app.redo();
    expect(app.currentModel!.metaById(id)!.x, closeTo(3.5, 1e-9));
  });

  test('no-op meta drag pushes nothing', () {
    app.createModel();
    app.addMeta('marker');
    final id = app.selectedMetaId!;
    app.beginMetaGizmoDrag();
    app.endMetaGizmoDrag(action: 'Перенос');
    // addMeta pushed one command; the no-op drag must not push another —
    // a single undo therefore removes the meta.
    app.undo();
    expect(app.currentModel!.metas, isEmpty);
    expect(app.canUndo, isFalse);
    expect(app.currentModel!.metaById(id), isNull);
  });

  test('setMode(markup) keeps object selection but clears faces', () {
    app.createModel();
    app.selectObject(app.currentModel!.objects.first.id);
    app.setMode(EditorMode.markup);
    expect(app.mode, EditorMode.markup);
    expect(app.selectedObjectId, isNotNull);
    expect(app.selectedFaces, isEmpty);
    app.setMode(EditorMode.texture);
    expect(app.mode, EditorMode.texture);
  });

  // ── light sources (Освещение) ────────────────────────────────────────

  test('addLight places each kind at the cursor and selects it', () {
    app.createModel();
    app.setCursor(2.5, 0, 1.5);
    app.addLight('point');
    var lights = app.currentModel!.lighting.lights;
    expect(lights, hasLength(1));
    expect(lights.first.kind, lightKindPoint);
    expect(lights.first.name, 'Точечный свет');
    expect(lights.first.x, 2.5);
    expect(lights.first.z, 1.5);
    expect(lights.first.intensity,
        closeTo(lightDefaultIntensity(lightKindPoint), 1e-9));
    expect(app.selectedLightId, lights.first.id);
    // The second source gets the next id; kinds can mix.
    app.addLight('directional');
    lights = app.currentModel!.lighting.lights;
    expect(lights, hasLength(2));
    expect(lights.map((l) => l.id).toSet(), hasLength(2));
    expect(lights.last.kind, lightKindDirectional);
    expect(lights.last.name, 'Направленный свет');
  });

  test('addLight rejects unknown kinds and lifts the anchor off the floor',
      () {
    app.createModel();
    app.addLight('nope');
    expect(app.currentModel!.lighting.lights, isEmpty);
    app.setCursor(1, 0, 1);
    app.addLight('point');
    expect(app.currentModel!.lighting.lights.single.y,
        closeTo(kLightBallRadius, 1e-9));
  });

  test('light source edits are undoable', () {
    app.createModel();
    app.addLight('point');
    final id = app.selectedLightId!;
    app.setLightName(id, 'лампа');
    expect(app.currentModel!.lightById(id)!.name, 'лампа');
    app.setLightColor(id, 1.0, 0.5, 0.2);
    app.setLightIntensity(id, 9);
    app.setLightRange(id, 3);
    final l = app.currentModel!.lightById(id)!;
    expect(l.g, closeTo(0.5, 1e-9));
    expect(l.intensity, closeTo(9, 1e-9));
    expect(l.range, closeTo(3, 1e-9));
    // Rapid consecutive edits share one merge key — a single undo restores
    // the whole pre-edit state.
    app.undo();
    final restored = app.currentModel!.lightById(id)!;
    expect(restored.name, 'Точечный свет');
    expect(restored.g, closeTo(0.97, 1e-9));
    expect(restored.intensity,
        closeTo(lightDefaultIntensity(lightKindPoint), 1e-9));
    expect(restored.range, closeTo(kPointLightDefaultRange, 1e-9));
    app.redo();
    expect(app.currentModel!.lightById(id)!.range, closeTo(3, 1e-9));
  });

  test('setLightDirection normalizes; a null vector keeps the aim', () {
    app.createModel();
    app.addLight('directional');
    final id = app.selectedLightId!;
    app.setLightDirection(id, 3, 4, 0);
    final l = app.currentModel!.lightById(id)!;
    expect(l.dirX, closeTo(0.6, 1e-9));
    expect(l.dirY, closeTo(0.8, 1e-9));
    expect(l.dirZ, closeTo(0.0, 1e-9));
    app.setLightDirection(id, 0, 0, 0); // no-op
    expect(app.currentModel!.lightById(id)!.dirX, closeTo(0.6, 1e-9));
    // Point lights ignore the aim.
    app.addLight('point');
    final pid = app.selectedLightId!;
    app.setLightDirection(pid, 1, 0, 0);
    expect(app.currentModel!.lightById(pid)!.dirX, kLightDefaultDir[0]);
  });

  test('deleteLight undo restores at the same index', () {
    app.createModel();
    app.addLight('point');
    app.addLight('directional');
    final id = app.currentModel!.lighting.lights[1].id;
    app.deleteLight(id);
    expect(app.currentModel!.lighting.lights.map((l) => l.id),
        isNot(contains(id)));
    expect(app.selectedLightId, isNull);
    app.undo();
    expect(app.currentModel!.lighting.lights[1].id, id);
    expect(app.selectedLightId, isNull);
  });

  test('duplicateLight copies the source and is undoable', () {
    app.createModel();
    app.addLight('point');
    final originalId = app.selectedLightId!;
    final l = app.currentModel!.lightById(originalId)!;
    l.x = 1;
    l.y = 1;
    app.duplicateLight();
    final lights = app.currentModel!.lighting.lights;
    expect(lights, hasLength(2));
    expect(app.selectedLightId, isNot(originalId));
    final copy = app.currentModel!.lightById(app.selectedLightId!)!;
    expect(copy.name, 'Точечный свет_2');
    expect(copy.x, closeTo(1.3, 1e-9));
    expect(copy.z, closeTo(l.z + 0.3, 1e-9));
    expect(copy.y, closeTo(1.0, 1e-9));
    expect(copy.intensity, l.intensity);
    app.undo();
    expect(app.currentModel!.lighting.lights, hasLength(1));
    expect(app.selectedLightId, originalId);
  });

  test('light gizmo drag pushes a single undo command', () {
    app.createModel();
    app.addLight('directional');
    final id = app.selectedLightId!;
    app.beginLightGizmoDrag();
    final l = app.currentModel!.lightById(id)!;
    l.x = 3.5;
    l.z = 2;
    app.endLightGizmoDrag(action: 'Перенос');
    expect(app.currentModel!.lightById(id)!.x, closeTo(3.5, 1e-9));
    app.undo();
    final restored = app.currentModel!.lightById(id)!;
    expect(restored.x, isNot(closeTo(3.5, 1e-9)));
    expect(restored.z, isNot(closeTo(2, 1e-9)));
    app.redo();
    expect(app.currentModel!.lightById(id)!.x, closeTo(3.5, 1e-9));
  });

  test('no-op light drag pushes nothing', () {
    app.createModel();
    app.addLight('point');
    app.beginLightGizmoDrag();
    app.endLightGizmoDrag(action: 'Перенос');
    // addLight pushed one command; the no-op drag must not push another —
    // a single undo therefore removes the source.
    app.undo();
    expect(app.currentModel!.lighting.lights, isEmpty);
    expect(app.canUndo, isFalse);
  });

  test('scene lighting knobs undo/redo and toggle the default state', () {
    app.createModel();
    expect(app.currentModel!.lighting.isDefault, isTrue);
    app.setLightingAmbient(0.4);
    expect(app.currentModel!.lighting.ambient, closeTo(0.4, 1e-9));
    expect(app.currentModel!.lighting.isDefault, isFalse);
    app.setLightingShadows(true);
    expect(app.currentModel!.lighting.shadows, isTrue);
    app.setLightingSsao(true);
    expect(app.currentModel!.lighting.ssao, isTrue);
    app.undo();
    expect(app.currentModel!.lighting.ssao, isFalse);
    app.undo();
    expect(app.currentModel!.lighting.shadows, isFalse);
    app.undo();
    expect(app.currentModel!.lighting.ambient, closeTo(1.0, 1e-9));
    expect(app.currentModel!.lighting.isDefault, isTrue);
  });

  test('hiding the light gizmos drops the light selection', () {
    app.createModel();
    app.addLight('point');
    expect(app.selectedLightId, isNotNull);
    app.setLightingGizmos(false);
    expect(app.selectedLightId, isNull);
    expect(app.currentModel!.lighting.gizmos, isFalse);
  });

  test('setMode(lighting) clears the object selection; leaving clears the '
      'light selection', () {
    app.createModel();
    app.selectObject(app.currentModel!.objects.first.id);
    app.setMode(EditorMode.lighting);
    expect(app.mode, EditorMode.lighting);
    expect(app.selectedObjectId, isNull);
    expect(app.selectedIds, isEmpty);
    expect(app.selectedFaces, isEmpty);
    app.addLight('point');
    expect(app.selectedLightId, isNotNull);
    app.setMode(EditorMode.compose);
    expect(app.mode, EditorMode.compose);
    expect(app.selectedLightId, isNull);
  });

  test('selectModel clears the light selection', () {
    app.createModel();
    app.setMode(EditorMode.lighting);
    app.addLight('point');
    expect(app.selectedLightId, isNotNull);
    app.createModel();
    // createModel switches the current model but (like the meta selection)
    // does not clear — selectModel does.
    expect(app.currentModelId, 'model_2');
    app.selectModel('model_1');
    expect(app.selectedLightId, isNull);
  });

  test('model lighting survives save/load roundtrip', () async {
    app.createModel();
    app.setMode(EditorMode.lighting);
    app.addLight('point');
    app.addLight('directional');
    app.setLightingAmbient(0.6);
    final model = app.currentModel!;
    await app.project!.saveModel(model);
    final reloaded = loadModelData(
      File('${dir.path}/models/${model.id}.json').readAsStringSync(),
      id: model.id,
    );
    expect(reloaded.lighting.ambient, closeTo(0.6, 1e-9));
    expect(reloaded.lighting.lights, hasLength(2));
    expect(reloaded.lighting.lights[1].kind, lightKindDirectional);
  });

  test('delete object undo restores at the same index', () {
    app.createModel();
    app.addObject('cuboid');
    app.addObject('sprite');
    final id = app.currentModel!.objects[1].id;
    app.deleteObject(id);
    expect(app.currentModel!.objects.map((o) => o.id), isNot(contains(id)));
    app.undo();
    expect(app.currentModel!.objects[1].id, id);
  });

  test('setModelSize undo', () {
    app.createModel();
    app.setModelSize(5, 4, 2);
    expect(app.currentModel!.size.w, 5);
    app.undo();
    expect(app.currentModel!.size.w, 3);
    app.redo();
    expect(app.currentModel!.size.w, 5);
  });

  test('material edit undo restores faces', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.setMaterial(
      obj.id,
      faceKey: '+y',
      material: ModelMaterial(type: MaterialType.texture, key: 'wall.png'),
    );
    expect(obj.faces['+y']!.key, 'wall.png');
    app.undo();
    expect(obj.faces.containsKey('+y'), isFalse);
  });

  test('setObjectPos undo restores position', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.setObjectPos(obj.id, 2, 0, 3);
    expect(obj.x, 2);
    app.undo();
    expect(obj.x, 1); // floor starts at the model center
  });

  test('undo stack is per model', () {
    app.createModel();
    app.addObject('cuboid');
    app.duplicateModel(app.currentModelId!);
    expect(app.canUndo, isFalse);
    app.addObject('cylinder');
    expect(app.canUndo, isTrue);
  });

  test('rename model moves id and file', () async {
    app.createModel();
    final model = app.currentModel!;
    await app.project!.saveModel(model);
    final err = await app.renameModel('model_1', 'house_a');
    expect(err, isNull);
    expect(app.currentModelId, 'house_a');
    expect(File('${dir.path}/models/house_a.json').existsSync(), isTrue);
    expect(File('${dir.path}/models/model_1.json').existsSync(), isFalse);
  });

  test('pickResource assigns texture to selected object in texture mode', () {
    app.createModel();
    app.selectObject(app.currentModel!.objects.first.id);
    app.setMode(EditorMode.texture);
    app.pickResource('texture', 'wall.png');
    expect(app.currentModel!.objects.first.material!.key, 'wall.png');
    expect(app.currentModel!.objects.first.material!.type, MaterialType.texture);
  });

  test('pickResource adds sprite object in compose mode', () {
    app.createModel();
    app.setMode(EditorMode.compose);
    app.pickResource('sprite', 'tree.png');
    final obj = app.currentModel!.objects.last;
    expect(obj.kind, 'sprite');
    expect(obj.material!.key, 'tree.png');
  });

  test('plane is horizontal by default; setObjectFlag toggles vertical with undo', () {
    app.createModel();
    app.addObject('plane');
    final obj = app.currentModel!.objects.last;
    expect(obj.kind, 'plane');
    expect(obj.flag('vertical'), isFalse);
    app.setObjectFlag(obj.id, 'vertical', true);
    expect(obj.flag('vertical'), isTrue);
    app.undo();
    expect(obj.flag('vertical'), isFalse);
    app.redo();
    expect(obj.flag('vertical'), isTrue);
  });

  test('object parameter edits bump the scene revision', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    final rev0 = app.sceneRevision;
    app.setObjectDim(obj.id, 'w', 2);
    expect(app.sceneRevision, greaterThan(rev0));
    final rev1 = app.sceneRevision;
    app.setObjectPos(obj.id, 2, 0, 3);
    expect(app.sceneRevision, greaterThan(rev1));
    final rev2 = app.sceneRevision;
    app.setMaterial(
      obj.id,
      faceKey: '+y',
      material: ModelMaterial(type: MaterialType.texture, key: 'wall.png'),
    );
    expect(app.sceneRevision, greaterThan(rev2));
  });

  test('gizmo drag produces one undo command', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.selectObject(obj.id);
    app.beginGizmoDrag();
    app.setObjectPos(obj.id, 2.3, 0, 1.2);
    app.endGizmoDrag();
    expect(app.canUndo, isTrue);
    app.undo();
    expect(obj.x, 1); // floor starts at the model center
  });

  test('setObjectRot sets all three axes with wrap-around', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.setObjectRot(obj.id, 15, 30, -45);
    expect(obj.rotX, 15);
    expect(obj.rotY, 30);
    expect(obj.rotZ, 315); // −45 wrapped to 360
    app.setObjectRot(obj.id, 370, 0, 0);
    expect(obj.rotX, 10); // 370 wrapped
  });

  test('setObjectRot undo/redo restores the pre-edit rotation', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.setObjectRot(obj.id, 15, 30, -45);
    app.undo();
    expect(obj.rotX, 0);
    expect(obj.rotY, 0);
    expect(obj.rotZ, 0);
    app.redo();
    expect(obj.rotX, 15);
    expect(obj.rotY, 30);
    expect(obj.rotZ, 315);
  });

  test('rotation gizmo drag produces one undo command restoring rotX/rotZ', () {
    app.createModel();
    final obj = app.currentModel!.objects.first;
    app.selectObject(obj.id);
    app.beginGizmoDrag();
    app.setObjectRot(obj.id, 12, 24, 36);
    app.endGizmoDrag(action: 'Поворот');
    expect(app.canUndo, isTrue);
    app.undo();
    expect(obj.rotX, 0);
    expect(obj.rotY, 0);
    expect(obj.rotZ, 0);
    app.redo();
    expect(obj.rotX, 12);
    expect(obj.rotY, 24);
    expect(obj.rotZ, 36);
  });

  group('face snap', () {
    ModelObject target() => app.currentModel!.objects.last;
    ModelObject floor() => app.currentModel!.objects.first;

    test('setFaceSnapMode toggles', () {
      app.createModel();
      expect(app.faceSnapMode, isNull);
      app.setFaceSnapMode(FaceSnapMode.parallelToFace);
      expect(app.faceSnapMode, FaceSnapMode.parallelToFace);
      app.setFaceSnapMode(null);
      expect(app.faceSnapMode, isNull);
    });

    test('parallelToFace orients the selected object and un-arms', () {
      app.createModel();
      app.addObject('cuboid');
      app.setFaceSnapMode(FaceSnapMode.parallelToFace);
      // The floor's +x face: normal (1,0,0) → the cuboid's +Y lands on it.
      app.applyFaceSnap(
        FaceSnapMode.parallelToFace,
        floor().id,
        '+x',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      expect(app.faceSnapMode, isNull); // the click consumed the armed mode
      expect(target().rotY, closeTo(270, 1e-9)); // −90 wrapped
      expect(target().rotZ, closeTo(270, 1e-9));
      expect(target().rotX, closeTo(0, 1e-9));
      app.undo();
      expect(target().rotX, 0);
      expect(target().rotY, 0);
      expect(target().rotZ, 0);
    });

    test('moveToFace moves the anchor to the face center', () {
      app.createModel();
      app.addObject('cuboid');
      // The floor is a 3×3×0.05 slab centered on (1,0,1) (the model center
      // of a 3×3 footprint): its +y face (the top) is at y = 0.05, its
      // center is (1, 0.05, 1).
      app.applyFaceSnap(
        FaceSnapMode.moveToFace,
        floor().id,
        '+y',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      expect(target().x, closeTo(1, 1e-9));
      expect(target().y, closeTo(0.05, 1e-9));
      expect(target().z, closeTo(1, 1e-9));
      expect(app.faceSnapMode, isNull);
      app.undo();
      expect(target().y, 0);
    });

    test('moveToFace also orients the object parallel to the face', () {
      app.createModel();
      app.addObject('cuboid');
      // The object comes from a DIFFERENT face («Параллельно грани» on the
      // front) — its stale orientation points through the cube.
      app.setObjectRot(target().id, 0, 90, 0);
      // «Перенести к грани» на +x грань пола: объект встаёт на грань И
      // ориентируется по ней — иначе он «прикрепляется к противоположной
      // грани» (торчит сквозь носитель).
      app.applyFaceSnap(
        FaceSnapMode.moveToFace,
        floor().id,
        '+x',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      expect(target().x, closeTo(-0.5, 1e-9)); // the VISUAL +x face center
      expect(target().y, closeTo(0.025, 1e-9));
      // +x face: solid +Y → (1,0,0): rotY −90, rotZ −90 (wrapped).
      expect(target().rotY, closeTo(270, 1e-9));
      expect(target().rotZ, closeTo(270, 1e-9));
      expect(target().rotX, closeTo(0, 1e-9));
    });

    test('moveToFace on a horizontal face keeps the yaw', () {
      app.createModel();
      app.addObject('cuboid');
      app.setObjectRot(target().id, 0, 30, 0);
      app.applyFaceSnap(
        FaceSnapMode.moveToFace,
        floor().id,
        '+y',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      // The +y face is horizontal: the yaw is free and preserved.
      expect(target().rotY, closeTo(30, 1e-9));
      expect(target().rotX, closeTo(0, 1e-9));
      expect(target().rotZ, closeTo(0, 1e-9));
    });

    test('cylinder side: the center is mid-height at the click angle', () {
      app.createModel();
      app.addObject('cylinder');
      final cyl = target();
      cyl.x = 1;
      cyl.z = 1;
      // WorldPoint (−0.25, 0.3, 0) → model-local (1.25, 0.3, 1): θ = 0 near
      // the bottom — the anchor still lands at the face center, mid-height.
      app.applyFaceSnap(
        FaceSnapMode.moveToFace,
        cyl.id,
        'side',
        vm.Vector3(-0.25, 0.3, 0),
        billboardYaw: 0,
      );
      expect(target().x, closeTo(1.25, 1e-9));
      expect(target().y, closeTo(0.5, 1e-9)); // mid-height, not the click height
      expect(target().z, closeTo(1, 1e-9));
      // The move orients the object along the side normal at the click
      // angle. The click is on the VISUAL +x side of the cylinder (model
      // 1.25 = the rendered frame) → the object-frame θ = π → normal
      // (−1,0,0): solid +Y → the normal → rotY 90, rotZ 90.
      expect(target().rotY, closeTo(90, 1e-9));
      expect(target().rotZ, closeTo(90, 1e-9));
      expect(target().rotX, closeTo(0, 1e-9));
    });

    test('parallel then move lands the object over the face', () {
      app.createModel();
      app.addObject('cuboid');
      // The user's flow: «сначала параллельно, затем перенести» — the
      // object ends up exactly over the face with the face's rotation.
      app.applyFaceSnap(
        FaceSnapMode.parallelToFace,
        floor().id,
        '+x',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      app.applyFaceSnap(
        FaceSnapMode.moveToFace,
        floor().id,
        '+x',
        vm.Vector3.zero(),
        billboardYaw: 0,
      );
      // The floor spans x ∈ [−0.5, 2.5] at z ∈ [−0.5, 2.5]: the VISUAL +x
      // face center is (−0.5, 0.025, 1) (the rendered frame mirrors X
      // through the anchor).
      expect(target().x, closeTo(-0.5, 1e-9));
      expect(target().y, closeTo(0.025, 1e-9));
      expect(target().z, closeTo(1, 1e-9));
      // The rotation matches the +x face (solid +Y → (1,0,0)).
      expect(target().rotY, closeTo(270, 1e-9));
      expect(target().rotZ, closeTo(270, 1e-9));
      expect(app.faceSnapMode, isNull);
      expect(app.canUndo, isTrue);
    });
  });

  group('group selection', () {
    test('shift-select toggles the group and keeps the primary', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final ids = app.currentModel!.objects.map((o) => o.id).toList();
      // Single-select the first.
      app.selectObject(ids[0]);
      expect(app.selectedIds, {ids[0]});
      // Shift-select the second → group of two.
      app.selectObject(ids[1], shift: true);
      expect(app.selectedIds, {ids[0], ids[1]});
      expect(app.selectedObjectId, ids[1]);
      // Shift-toggle the first off → primary falls back.
      app.selectObject(ids[0], shift: true);
      expect(app.selectedIds, {ids[1]});
      expect(app.selectedObjectId, ids[1]);
    });

    test('shift-click on empty keeps the group', () {
      app.createModel();
      app.addObject('cuboid');
      // addObject already selected the new cuboid.
      app.selectObject(null, shift: true);
      expect(app.selectedIds.length, 1);
    });

    test('selectAllObjects selects every object, primary = first', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = app.currentModel!.objects.map((o) => o.id).toList();
      app.selectObject(all[2]);
      app.selectAllObjects();
      expect(app.selectedIds, all.toSet());
      expect(app.selectedObjectId, all.first);
      // A named group and faces are mutually exclusive with object
      // multi-selection — both are cleared.
      app.createGroup();
      expect(app.selectedGroupId, isNotNull);
      app.selectAllObjects();
      expect(app.selectedGroupId, isNull);
      expect(app.selectedFaces, isEmpty);
      expect(app.selectedObjectId, all.first);
    });

    test('selectAllObjects on an empty model is a no-op', () {
      app.selectAllObjects();
      expect(app.selectedCount, 0);
      expect(app.selectedObjectId, isNull);
    });

    test('selectObject(null) deselects everything', () {
      app.createModel();
      app.addObject('cuboid');
      app.selectAllObjects();
      expect(app.selectedCount, 2);
      app.selectObject(null);
      expect(app.selectedCount, 0);
      expect(app.selectedIds, isEmpty);
      expect(app.selectedObjectId, isNull);
    });

    test('groupCenter is the union AABB center', () {
      app.createModel();
      final ids = app.currentModel!.objects.map((o) => o.id).toList();
      app.addObject('cuboid');
      final second = app.currentModel!.objects.last.id;
      app.setObjectPos(second, 2, 0, 2);
      app.selectObject(ids.first); // floor
      app.selectObject(second, shift: true);
      final c = app.groupCenter()!;
      // Floor (size 3, at (1,0,1)) spans −0.5..2.5; cube at (2,0,2) spans
      // 1.5..2.5 — the union is the floor's extent.
      expect(c.$1, closeTo(1.0, 1e-9));
      expect(c.$3, closeTo(1.0, 1e-9));
    });

    test('moveGroup moves all and one undo restores all', () {
      app.createModel();
      app.addObject('cuboid');
      final ids = app.currentModel!.objects.map((o) => o.id).toList();
      app.selectObject(ids[0]); // floor
      app.selectObject(ids[1], shift: true); // cuboid (already selected)
      app.moveGroup(1, 0, 2);
      final moved = app.currentModel!.objects.map((o) => (o.x, o.z)).toList();
      app.undo();
      final restored = app.currentModel!.objects.map((o) => (o.x, o.z)).toList();
      // Floor moved from (1,1) to (2,3) and back.
      expect(moved[0], (2.0, 3.0));
      expect(restored[0], (1.0, 1.0));
    });

    test('setGroupMaterial applies to every object (one command)', () {
      app.createModel();
      app.addObject('cuboid');
      final ids = app.currentModel!.objects.map((o) => o.id).toList();
      app.selectObject(ids[0]);
      app.selectObject(ids[1], shift: true);
      app.setGroupMaterial(
        ModelMaterial(type: MaterialType.texture, key: 'wall.png'),
      );
      for (final o in app.currentModel!.objects) {
        expect(o.material!.key, 'wall.png');
      }
      app.undo();
      for (final o in app.currentModel!.objects) {
        expect(o.material, isNull);
      }
    });

    test('deleteSelected removes all with one undo', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final ids = app.currentModel!.objects.map((o) => o.id).toList();
      app.selectObject(ids[1]);
      app.selectObject(ids[2], shift: true);
      expect(app.currentModel!.objects.length, 3);
      app.deleteSelected();
      expect(app.currentModel!.objects.length, 1);
      expect(app.selectedCount, 0);
      app.undo();
      expect(app.currentModel!.objects.length, 3);
    });
  });


  group('named groups', () {
    List<String> ids() =>
        app.currentModel!.objects.map((o) => o.id).toList();

    test('createGroup makes a named group with the selection', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      final g = app.currentModel!.groups.single;
      expect(g.members.toSet(), {all[1], all[2]});
      expect(app.selectedGroupId, g.id);
      app.undo();
      expect(app.currentModel!.groups, isEmpty);
      app.redo();
      expect(app.currentModel!.groups, hasLength(1));
    });

    test('selectGroup selects the members', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      final g = app.currentModel!.groups.single;
      app.selectObject(all[0]);
      expect(app.selectedCount, 1);
      app.selectGroup(g.id);
      expect(app.selectedGroupId, g.id);
      expect(app.selectedIds.toSet(), {all[1], all[2]});
    });

    test('ungroupSelection dissolves the selected group', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      app.ungroupSelection();
      expect(app.currentModel!.groups, isEmpty);
      expect(app.currentModel!.objects.length, 3);
      app.undo();
      expect(app.currentModel!.groups, hasLength(1));
    });

    test('ungroupSelection extracts selected objects from their groups', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      app.selectObject(all[1]);
      app.ungroupSelection();
      expect(app.currentModel!.groups.single.members, [all[2]]);
      app.undo();
      expect(app.currentModel!.groups.single.members, hasLength(2));
    });

    test('moveObjectToGroup moves in and out', () {
      app.createModel();
      app.addObject('cuboid');
      final all = ids();
      app.selectObject(all[0]);
      app.selectObject(all[1], shift: true);
      app.createGroup();
      final gid = app.currentModel!.groups.single.id;
      app.moveObjectToGroup(all[0], null);
      expect(app.currentModel!.groups.single.members, [all[1]]);
      app.moveObjectToGroup(all[0], gid);
      expect(app.currentModel!.groups.single.members.toSet(), {all[0], all[1]});
      app.undo(); // undo the move back in
      expect(app.currentModel!.groups.single.members, [all[1]]);
      app.undo(); // undo the move out
      expect(app.currentModel!.groups.single.members, [all[0], all[1]]);
    });

    test('renameGroup is undoable', () {
      app.createModel();
      app.addObject('cuboid');
      app.selectObject(ids()[1]);
      app.createGroup();
      final gid = app.currentModel!.groups.single.id;
      app.renameGroup(gid, 'Дом');
      expect(app.currentModel!.groups.single.name, 'Дом');
      app.undo();
      expect(app.currentModel!.groups.single.name, 'Группа 1');
    });

    test('deleteGroup keeps members and is undoable', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      final gid = app.currentModel!.groups.single.id;
      app.deleteGroup(gid);
      expect(app.currentModel!.groups, isEmpty);
      expect(app.currentModel!.objects.length, 3);
      app.undo();
      expect(app.currentModel!.groups, hasLength(1));
    });

    test('duplicateGroupSelection copies the group and members', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      app.duplicateGroupSelection();
      expect(app.currentModel!.groups, hasLength(2));
      expect(app.currentModel!.objects.length, 5);
      expect(app.selectedGroupId, isNotNull);
      app.undo();
      expect(app.currentModel!.groups, hasLength(1));
      expect(app.currentModel!.objects.length, 3);
    });

    test('deleteSelected prunes group membership', () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cylinder');
      final all = ids();
      app.selectObject(all[1]);
      app.selectObject(all[2], shift: true);
      app.createGroup();
      app.deleteSelected();
      expect(app.currentModel!.groups.single.members, isEmpty);
      expect(app.currentModel!.objects.length, 1);
    });
  });


  group('undo merge', () {
    test('rapid edits of the same object collapse into one undo step', () {
      app.createModel();
      final obj = app.currentModel!.objects.first;
      app.setObjectDim(obj.id, 'w', 1.1);
      app.setObjectDim(obj.id, 'w', 1.2);
      app.setObjectDim(obj.id, 'w', 1.3);
      app.undo();
      expect(obj.dim('w', 0), 3.0); // single undo restores the original
      app.redo();
      expect(obj.dim('w', 0), closeTo(1.3, 1e-9));
    });

    test('rapid group moves collapse into one undo step', () {
      app.createModel();
      app.addObject('cuboid');
      final all = app.currentModel!.objects.map((o) => o.id).toList();
      app.selectObject(all[0]);
      app.selectObject(all[1], shift: true);
      app.moveGroup(0.1, 0, 0);
      app.moveGroup(0.1, 0, 0);
      app.moveGroup(0.1, 0, 0);
      app.undo();
      expect(app.currentModel!.objects.first.x, 1); // back at the initial 1
      app.redo();
      expect(app.currentModel!.objects.first.x, closeTo(1.3, 1e-9));
    });
  });


  group('texture faces mode', () {
    test('selectFace replaces, shift toggles off, mirror follows', () {
      app.createModel();
      final ids = [for (final o in app.currentModel!.objects) o.id];
      final obj = ids.first;
      app.selectFace(obj, '+x');
      expect(app.selectedFaces, {'$obj:+x'});
      expect(app.selectedIds, {obj});
      // Shift-click on the same face removes it.
      app.selectFace(obj, '+x', shift: true);
      expect(app.selectedFaces, isEmpty);
      expect(app.selectedIds, isEmpty);
      expect(app.selectedObjectId, isNull);
      // Add several faces; removing the primary repicks any remaining.
      app.selectFace(obj, '+x');
      app.selectFace(obj, '+z', shift: true);
      expect(app.selectedFaces, {'$obj:+x', '$obj:+z'});
      app.selectFace(obj, '+x', shift: true);
      expect(app.selectedFaces, {'$obj:+z'});
      expect(app.selectedFaceKey, '+z');
      expect(app.selectedObjectId, obj);
    });

    test('objects → faces converts every face of each selected object', () {
      app.createModel();
      app.addObject('cuboid');
      final objs = app.currentModel!.objects;
      app.selectObject(objs[0].id);
      app.selectObject(objs[1].id, shift: true);
      app.setTexSubmode(TexSubmode.faces);
      expect(app.selectedFaces, {
        '${objs[0].id}:+x', '${objs[0].id}:-x', '${objs[0].id}:+y',
        '${objs[0].id}:-y', '${objs[0].id}:+z', '${objs[0].id}:-z',
        '${objs[1].id}:+x', '${objs[1].id}:-x', '${objs[1].id}:+y',
        '${objs[1].id}:-y', '${objs[1].id}:+z', '${objs[1].id}:-z',
      });
    });

    test('faces → objects selects objects with any selected face', () {
      app.createModel();
      app.addObject('cuboid');
      final objs = app.currentModel!.objects;
      app.setTexSubmode(TexSubmode.faces);
      app.selectFace(objs[0].id, '+x');
      app.selectFace(objs[1].id, '-y', shift: true);
      app.setTexSubmode(TexSubmode.objects);
      expect(app.selectedIds, {objs[0].id, objs[1].id});
      expect(app.selectedFaces, isEmpty);
    });

    test('mode switch converts both ways (compose ↔ texture+faces)', () {
      app.createModel();
      final obj = app.currentModel!.objects.first;
      app.selectObject(obj.id);
      app.setMode(EditorMode.texture);
      app.setTexSubmode(TexSubmode.faces);
      expect(app.selectedFaces, {
        '${obj.id}:+x', '${obj.id}:-x', '${obj.id}:+y',
        '${obj.id}:-y', '${obj.id}:+z', '${obj.id}:-z',
      });
      app.selectFace(obj.id, '+x', shift: true); // drop one
      app.setMode(EditorMode.compose);
      expect(app.selectedIds, {obj.id});
      expect(app.selectedFaces, isEmpty);
    });

    test('setFacesMaterial applies to every selected face', () {
      app.createModel();
      app.addObject('cuboid');
      final objs = app.currentModel!.objects;
      app.setTexSubmode(TexSubmode.faces);
      app.selectFace(objs[0].id, '+x');
      app.selectFace(objs[1].id, '-y', shift: true);
      app.setFacesMaterial(ModelMaterial(type: MaterialType.color, color: [9, 9, 9]));
      expect(objs[0].faces['+x']?.color, [9, 9, 9]);
      expect(objs[1].faces['-y']?.color, [9, 9, 9]);
      app.resetFaces();
      expect(objs[0].faces.containsKey('+x'), isFalse);
      expect(objs[1].faces.containsKey('-y'), isFalse);
    });

    test('selectAllFaces selects all faces, shift toggles them off', () {
      app.createModel();
      final obj = app.currentModel!.objects.first.id;
      app.selectAllFaces(obj);
      expect(app.selectedFaces.length, 6);
      app.selectAllFaces(obj, shift: true);
      expect(app.selectedFaces, isEmpty);
    });
  });

  test('pickResource in texture mode assigns material, compose adds sprite', () {
    app.createModel();
    app.pickResource('sprite', 'tree.png');
    expect(app.currentModel!.objects.length, 2);
  });

  group('правка многогранника', () {
    ModelObject addPoly() {
      app.createModel();
      app.addObject('polyhedron');
      return app.currentModel!.objects.last;
    }

    test('режим сбрасывается при смене объекта и держится на нём же', () {
      final poly = addPoly();
      expect(app.polyEditMode, PolyEditMode.object);
      app.setPolyEditMode(PolyEditMode.faces);
      expect(app.polyEditMode, PolyEditMode.faces);

      app.selectObject(app.currentModel!.objects.first.id);
      expect(app.polyEditMode, PolyEditMode.object);

      app.selectObject(poly.id);
      app.setPolyEditMode(PolyEditMode.vertices);
      app.selectObject(poly.id);
      expect(app.polyEditMode, PolyEditMode.vertices,
          reason: 'повторный выбор того же объекта не выходит из режима');

      app.resetPolyEdit();
      expect(app.polyEditMode, PolyEditMode.object);
    });

    test('в грани/вершины нельзя войти у не-многогранника', () {
      app.createModel();
      final floor = app.currentModel!.objects.first;
      app.selectObject(floor.id);
      app.setPolyEditMode(PolyEditMode.faces);
      expect(app.polyEditMode, PolyEditMode.object);
    });

    test('выбор вершин: замена, Shift-группа, снятие', () {
      final poly = addPoly();
      app.setPolyEditMode(PolyEditMode.vertices);
      app.selectPolyVertex(2);
      expect(app.selectedVertexIndices, {2});
      expect(app.activeVertexIndex, 2);
      app.selectPolyVertex(3, shift: true);
      expect(app.selectedVertexIndices, {2, 3});
      expect(app.activeVertexIndex, 3);
      app.selectPolyVertex(2, shift: true);
      expect(app.selectedVertexIndices, {3});
      app.selectPolyVertex(null);
      expect(app.selectedVertexIndices, isEmpty);
      expect(app.activeVertexIndex, isNull);
      expect(poly.mesh!.vertices, hasLength(8));
    });

    test('масштаб по осям и undo', () {
      final poly = addPoly();
      app.setPolyScale(poly.id, 1, 2.5);
      expect(poly.scaleY, 2.5);
      expect(poly.scaleX, 1);
      app.undo();
      expect(poly.scaleY, 1);
    });

    test('drag вершин: один undo на жест', () {
      final poly = addPoly();
      app.setPolyEditMode(PolyEditMode.vertices);
      app.selectPolyVertex(0);
      final before = poly.mesh!.vertices[0].clone();
      app.beginPolyVertexDrag();
      app.moveSelectedPolyVertices(vm.Vector3(1, 0.5, 0));
      app.endPolyVertexDrag();
      expect(poly.mesh!.vertices[0].x, closeTo(before.x + 1, 1e-9));
      expect(poly.mesh!.vertices[0].y, closeTo(before.y + 0.5, 1e-9));
      app.undo();
      expect(poly.mesh!.vertices[0].x, closeTo(before.x, 1e-9));
      app.redo();
      expect(poly.mesh!.vertices[0].x, closeTo(before.x + 1, 1e-9));
    });

    test('удаление грани убирает её и материал, undo возвращает', () {
      final poly = addPoly();
      poly.faces['+y'] = ModelMaterial(color: [1, 2, 3]);
      app.setPolyEditMode(PolyEditMode.faces);
      app.selectFace(poly.id, '+y');
      app.deleteSelectedPolyFaces();
      expect(poly.mesh!.faces, hasLength(5));
      expect(poly.mesh!.faceByKey('+y'), isNull);
      expect(poly.faces.containsKey('+y'), isFalse);
      expect(app.selectedFaces, isEmpty);
      app.undo();
      expect(poly.mesh!.faces, hasLength(6));
      expect(poly.mesh!.faceByKey('+y'), isNotNull);
      expect(poly.faces['+y']?.color, [1, 2, 3]);
    });

    test('удаление вершины и undo', () {
      final poly = addPoly();
      app.setPolyEditMode(PolyEditMode.vertices);
      app.selectPolyVertex(0);
      app.deleteSelectedPolyVertices();
      expect(poly.mesh!.vertices, hasLength(7));
      expect(app.selectedVertexIndices, isEmpty);
      app.undo();
      expect(poly.mesh!.vertices, hasLength(8));
    });

    test('добавление вершины на ребро и undo', () {
      final poly = addPoly();
      app.setPolyEditMode(PolyEditMode.vertices);
      app.togglePolyAddVertex();
      expect(app.polyAddVertexArmed, isTrue);
      // Ребро верхней грани куба 1×1×1: (−0.5, 1, 0.5) → (0.5, 1, 0.5).
      app.addPolyVertex('+y', vm.Vector3(0, 1, 0.5));
      expect(poly.mesh!.vertices, hasLength(9));
      final index = app.activeVertexIndex;
      expect(index, 8);
      expect(app.selectedVertexIndices, {8});
      expect(app.polyAddVertexArmed, isTrue,
          reason: 'режим остаётся включённым для следующих вершин');
      app.undo();
      expect(poly.mesh!.vertices, hasLength(8));
    });

    test('добавление вершины внутри грани пробивает её без дыры', () {
      final poly = addPoly();
      poly.faces['+y'] = ModelMaterial(color: [9, 8, 7]);
      app.setPolyEditMode(PolyEditMode.vertices);
      app.togglePolyAddVertex();
      app.addPolyVertex('+y', vm.Vector3(0, 1, 0)); // центр верхней грани
      expect(app.activeVertexIndex, 8);
      expect(poly.mesh!.vertices, hasLength(9));
      expect(poly.mesh!.faces, hasLength(9),
          reason: 'верхняя грань стала четырьмя треугольниками');
      final triangles = poly.mesh!.faces
          .where((f) => f.outer.vertices.contains(8))
          .toList();
      expect(triangles, hasLength(4));
      for (final face in triangles) {
        expect(face.outer.vertices, hasLength(3));
        expect(poly.faces[face.key]?.color, [9, 8, 7],
            reason: 'материал грани перенесён на ${face.key}');
      }
      app.undo();
      expect(poly.mesh!.vertices, hasLength(8));
      expect(poly.mesh!.faces, hasLength(6));
      expect(poly.faces['+y']?.color, [9, 8, 7]);
    });

    test('конверсия кубоида в многогранник и undo', () {
      app.createModel();
      final floor = app.currentModel!.objects.first;
      app.convertToPolyhedron(floor.id);
      expect(floor.kind, polyhedronKind);
      expect(floor.mesh!.faces, hasLength(6));
      expect(floor.dims, isEmpty);
      app.undo();
      expect(floor.kind, 'cuboid');
      expect(floor.dims['w'], isNotNull);
    });

    test('конверсия CSG удаляет освободившиеся операнды, undo их вернёт',
        () {
      app.createModel();
      app.addObject('cuboid');
      app.addObject('cuboid');
      final objs = app.currentModel!.objects;
      final a = objs[objs.length - 2].id;
      final b = objs.last.id;
      app.selectObject(a);
      app.selectObject(b, shift: true);
      app.createCsgOperation('union');
      final csg = app.currentModel!.objects.last;
      expect(csg.isCsg, isTrue);
      final countBefore = app.currentModel!.objects.length;

      app.convertToPolyhedron(csg.id);
      expect(csg.kind, polyhedronKind);
      expect(csg.mesh!.faces, isNotEmpty);
      expect(app.currentModel!.objects.length, countBefore - 2,
          reason: 'операнды CSG больше не нужны');
      expect(app.currentModel!.objectById(a), isNull);

      app.undo();
      expect(csg.isCsg, isTrue);
      expect(app.currentModel!.objects.length, countBefore);
      expect(app.currentModel!.objectById(a), isNotNull);
    });

    test('лимиты: отрицательная высота и крупная модель', () {
      app.createModel();
      final floor = app.currentModel!.objects.first;
      app.setObjectPos(floor.id, 0, -50, 0);
      expect(floor.y, -50);
      app.setModelSize(200, 150, 40);
      expect(app.currentModel!.size.w, 200);
      expect(app.currentModel!.size.l, 150);
      expect(app.currentModel!.size.h, 40);
    });
    test('сетка земли: видимость переключается и уведомляет', () {
      var notified = 0;
      app.addListener(() => notified++);
      expect(app.gridVisible, isTrue, reason: 'по умолчанию сетка видна');

      app.setGridVisible(false);
      expect(app.gridVisible, isFalse);
      expect(notified, 1);

      app.setGridVisible(false);
      expect(notified, 1, reason: 'повторное значение не уведомляет');

      app.setGridVisible(true);
      expect(app.gridVisible, isTrue);
      expect(notified, 2);
    });
  });
}
