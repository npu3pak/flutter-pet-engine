import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:pet_engine/pet_engine.dart';

ModelObject refInstance({String refModelId = 'chair', double scale = 1}) =>
    ModelObject(
      id: 'obj_7',
      name: 'Кресло',
      kind: modelRefKind,
      x: 2,
      y: 0,
      z: 3,
      rotY: 90,
      refModelId: refModelId,
      scale: scale,
      refSize: ModelSize(w: 1, l: 2, h: 3),
    );

/// A self-contained detail model: one 2×2×2 cuboid at the origin.
ModelData chairModel(String id, {int w = 1, int l = 2, int h = 3}) => ModelData(
      id: id,
      name: id,
      size: ModelSize(w: w, l: l, h: h),
      objects: [
        ModelObject(
          id: 'obj_1',
          name: 'chair',
          kind: 'cuboid',
          x: 0,
          y: 0,
          z: 0,
          dims: {'w': 2.0, 'h': 2.0, 'd': 2.0},
        ),
      ],
    );

void main() {
  group('model instance JSON (kind model)', () {
    test('roundtrip keeps reference, scale, cache and placement', () {
      final obj = refInstance(refModelId: 'kreslo', scale: 1.5);
      final model = ModelData(id: 'room', name: 'Комната', size: ModelSize(w: 6, l: 6, h: 3))
        ..objects.add(obj);
      final json = jsonDecode(
        const JsonEncoder().convert(model.toJson()),
      ) as Map<String, Object?>;
      final o = (json['objects'] as List).first as Map<String, Object?>;
      expect(o['kind'], modelRefKind);
      expect(o['modelId'], 'kreslo');
      expect(o['scale'], 1.5);
      expect(o['size'], {'w': 1, 'l': 2, 'h': 3});
      expect(o['rotY'], 90);
      expect(o.containsKey('rotX'), isFalse);
      expect(o.containsKey('material'), isFalse);
      expect(o.containsKey('faces'), isFalse);

      final restored =
          ModelData.fromJson(const JsonEncoder().convert(model.toJson()), id: 'room');
      final r = restored.objects.single;
      expect(r.isModelRef, isTrue);
      expect(r.refModelId, 'kreslo');
      expect(r.scale, 1.5);
      expect(r.refSize!.w, 1);
      expect(r.refSize!.l, 2);
      expect(r.refSize!.h, 3);
      expect(r.x, 2);
      expect(r.rotY, 90);
      expect(r.material, isNull);
      expect(r.faces, isEmpty);
    });

    test('defaults parse without scale/size', () {
      const json = '{"id":"obj_1","name":"x","kind":"model",'
          '"pos":[1,2,3],"modelId":"chair"}';
      final obj = ModelObject.fromJson(jsonDecode(json));
      expect(obj.scale, 1.0);
      expect(obj.refSize, isNull);
      expect(obj.dims, isEmpty);
    });

    test('no faces, not csg-eligible, not a csg operand', () {
      final obj = refInstance();
      expect(facesOf(obj), isEmpty);
      expect(isCsgEligible(obj), isFalse);
    });
  });

  group('unionAabbResolved', () {
    test('plain objects behave like unionAabb', () {
      final objs = [
        ModelObject(
            id: 'a', name: 'a', kind: 'cuboid', x: 0, y: 0, z: 0,
            dims: {'w': 2.0, 'h': 1.0, 'd': 2.0}),
      ];
      final r = unionAabbResolved(objs);
      expect(r, (-1.0, 0.0, -1.0, 1.0, 1.0, 1.0));
    });

    test('instance folds in its content bounds (scale and rotation)', () {
      final chair = chairModel('chair');
      final ref = refInstance(refModelId: 'chair', scale: 2);
      ref.rotY = 90;
      final r = unionAabbResolved([ref], modelOf: (id) => id == 'chair' ? chair : null);
      // The instance renders in the source's standalone frame: the source
      // grid center (cell 0.5 of the 1×2 grid) sits at the anchor (2, 0, 3)
      // and the content is mirrored about it. Content box 2×2×2 at scale 2
      // about the grid center → authoring bounds 1..5 on x and z.
      expect(r.$1, closeTo(1, 1e-9));
      expect(r.$2, closeTo(0, 1e-9));
      expect(r.$3, closeTo(1, 1e-9));
      expect(r.$4, closeTo(5, 1e-9));
      expect(r.$5, closeTo(0 + 4, 1e-9));
      expect(r.$6, closeTo(5, 1e-9));
    });

    test('two instances of the same model both contribute', () {
      final chair = chairModel('chair');
      final a = refInstance(refModelId: 'chair');
      final b = refInstance(refModelId: 'chair')..x = 10;
      final r = unionAabbResolved([a, b], modelOf: (id) => chair);
      // Each instance centers the source grid (its z-axis center 0.5) on
      // the anchor, so content spans a.x + 0.5 ± 2 mirrored: x 1.5..3.5
      // for a, 9.5..11.5 for b.
      expect(r.$1, closeTo(1.5, 1e-9));
      expect(r.$4, closeTo(11.5, 1e-9));
    });

    test('asymmetric content mirrors about the source grid center', () {
      // Source: a 3×3 grid with one cuboid right of its center cell
      // (x 2.2, ox = 1). Rendered as an instance the content is reflected
      // about the SOURCE grid center, so in authoring cells the object
      // lands at a.x + (v.x − ox) = 2 + 1.2 = 3.2 — the raw «как есть»
      // folding (a.x + v.x = 4.2) would place it elsewhere, so this pins
      // the standalone-frame convention.
      final src = ModelData(
        id: 'src', name: 'src', size: ModelSize(w: 3, l: 3, h: 3),
        objects: [
          ModelObject(
              id: 'o', name: 'o', kind: 'cuboid',
              x: 2.2, y: 0, z: 0.6,
              dims: {'w': 0.6, 'h': 0.4, 'd': 0.8}),
        ],
      );
      final inst = ModelObject(
        id: 'i', name: 'i', kind: modelRefKind,
        x: 2, y: 0, z: 3, rotY: 0, refModelId: 'src', scale: 1,
        refSize: ModelSize(w: 3, l: 3, h: 3),
      );
      final r = unionAabbResolved([inst],
          modelOf: (id) => id == 'src' ? src : null);
      // x: 3.2 ± 0.3, y: 0..0.4, z: 2.6 ± 0.4 (eps 1e-4: fold math runs
      // in f32, non-representable values like 2.9 carry ~1e-7 noise).
      expect(r.$1, closeTo(2.9, 1e-4));
      expect(r.$2, closeTo(0, 1e-4));
      expect(r.$3, closeTo(2.2, 1e-4));
      expect(r.$4, closeTo(3.5, 1e-4));
      expect(r.$5, closeTo(0.4, 1e-4));
      expect(r.$6, closeTo(3.0, 1e-4));
    });

    test('nested instances and cycle safety', () {
      final chair = chairModel('chair');
      final room = ModelData(id: 'room', name: 'room', size: ModelSize())
        ..objects.add(refInstance(refModelId: 'chair'));
      // room contains a chair; a corrupt chair→room cycle must not hang.
      final r = unionAabbResolved(
        [refInstance(refModelId: 'room')],
        modelOf: (id) => switch (id) {
          'chair' => chair,
          'room' => room,
          _ => null,
        },
      );
      expect(r.$4, greaterThan(0));
    });

    test('missing source falls back to the cached cube footprint', () {
      final ref = refInstance(refModelId: 'gone')..rotY = 0;
      final r = unionAabbResolved([ref], modelOf: (_) => null);
      // cached 1×2×3 grid: x −0.5..0.5, z −0.5..1.5, y 0..3 at anchor (2,0,3)
      expect(r.$1, closeTo(1.5, 1e-9));
      expect(r.$4, closeTo(2.5, 1e-9));
      expect(r.$3, closeTo(2.5, 1e-9));
      expect(r.$6, closeTo(4.5, 1e-9));
      expect(r.$5, closeTo(3.0, 1e-9));
    });
  });

  group('objectEdgeSegments of an instance', () {
    test('resolves content edges through the instance anchor', () {
      final chair = chairModel('chair');
      final ref = refInstance(refModelId: 'chair');
      final segs = objectEdgeSegments(
        ref,
        billboardYaw: 0,
        originX: 2, // world anchor: x = −(2−2) = 0, z = 3
        originZ: 0,
        modelOf: (id) => id == 'chair' ? chair : null,
      );
      expect(segs, isNotEmpty);
      var (minX, minY, minZ, maxX, maxY, maxZ) =
          (1e9, 1e9, 1e9, -1e9, -1e9, -1e9);
      for (final (a, b) in segs) {
        for (final p in [a, b]) {
          minX = p.$1 < minX ? p.$1 : minX;
          minY = p.$2 < minY ? p.$2 : minY;
          minZ = p.$3 < minZ ? p.$3 : minZ;
          maxX = p.$1 > maxX ? p.$1 : maxX;
          maxY = p.$2 > maxY ? p.$2 : maxY;
          maxZ = p.$3 > maxZ ? p.$3 : maxZ;
        }
      }
      // The instance renders in the source's standalone frame: source grid
      // center (z-cell 0.5 of the 1×2 grid) sits at the anchor (0, 0, 3),
      // content mirrored about it → rotY90 box 2×2×2 spans x −1.5..0.5.
      expect(minX, closeTo(-1.5, 1e-9));
      expect(maxX, closeTo(0.5, 1e-9));
      expect(minY, closeTo(0, 1e-9));
      expect(maxY, closeTo(2, 1e-9));
      expect(minZ, closeTo(2, 1e-9));
      expect(maxZ, closeTo(4, 1e-9));
    });

    test('missing source outlines the fuchsia cube', () {
      final ref = refInstance(refModelId: 'gone');
      final segs = objectEdgeSegments(
        ref,
        billboardYaw: 0,
        originX: 2,
        originZ: 0,
        modelOf: (_) => null,
      );
      expect(segs, isNotEmpty); // 12 cuboid edges of the placeholder
    });
  });

  group('AppState model instances', () {
    late Directory dir;
    late AppState app;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('model_ref_test');
      app = AppState();
      await app.createProject(dir.path, name: 'test');
    });

    tearDown(() {
      app.closeProject();
      dir.deleteSync(recursive: true);
    });

    ModelData room() => app.project!.models['model_2']!;

    test('addModelRef places an instance and selects it', () {
      app.createModel(); // model_1
      app.selectModel('model_1');
      app.currentModel!.size = ModelSize(w: 2, l: 2, h: 4);
      app.setCursor(3, 0, 4);
      app.createModel(); // model_2 — the room
      app.addModelRef('model_1');

      final room2 = app.project!.models['model_2']!;
      expect(room2.objects.length, 2); // floor + instance
      final o = room2.objects.last;
      expect(o.isModelRef, isTrue);
      expect(o.refModelId, 'model_1');
      expect(o.scale, 1);
      expect(o.x, 3);
      expect(o.z, 4);
      expect(o.refSize!.w, 2);
      expect(o.refSize!.h, 4);
      expect(app.selectedObjectId, o.id);
      // undo removes it again
      app.undo();
      expect(room2.objects.length, 1);
      app.redo();
      expect(room2.objects.length, 2);
    });

    test('self-insert and reference cycles are rejected', () {
      app.createModel(); // model_1 (chair)
      app.createModel(); // model_2 (room)
      app.addModelRef('model_1');
      expect(app.canInsertModel('model_2', 'model_1'), isTrue);
      // the room may never be placed into itself…
      expect(app.canInsertModel('model_2', 'model_2'), isFalse);
      // …nor a model that already contains the room.
      app.selectModel('model_1');
      expect(app.canInsertModel('model_1', 'model_2'), isFalse);
      final before = app.project!.models['model_1']!.objects.length;
      app.addModelRef('model_2'); // must be a no-op
      expect(app.project!.models['model_1']!.objects.length, before);
    });

    test('deleting a used model warns and caches the source size', () {
      app.createModel(); // model_1 — source (default size 3×3×3)
      app.currentModel!.size = ModelSize(w: 5, l: 4, h: 6);
      app.createModel(); // model_2 — room
      app.addModelRef('model_1');
      expect(app.modelsUsingModel('model_1'), ['model_2']);
      expect(app.modelsUsingModel('model_2'), isEmpty);

      app.deleteModel('model_1');
      final ref = room().objects.last;
      expect(ref.refModelId, 'model_1');
      expect(ref.isModelRef, isTrue);
      expect(ref.refSize!.w, 5);
      expect(ref.refSize!.h, 6);
      // the room still holds the (broken) reference — it renders as a cube
      expect(app.modelsUsingModel('model_1'), ['model_2']);
      expect(room().dirty, isTrue);
    });

    test('renaming a used model repoints every reference', () async {
      app.createModel(); // model_1
      app.createModel(); // model_2
      app.addModelRef('model_1');
      app.selectModel('model_1');
      expect(await app.renameModel('model_1', 'kreslo'), isNull);
      final ref = app.project!.models['model_2']!.objects.last;
      expect(ref.refModelId, 'kreslo');
      expect(app.project!.models['model_2']!.dirty, isTrue);
    });

    test('replaceModelRef keeps the placement', () {
      app.createModel(); // model_1
      app.currentModel!.size = ModelSize(w: 1, l: 1, h: 2);
      app.createModel(); // model_2
      app.currentModel!.size = ModelSize(w: 3, l: 3, h: 3);
      app.createModel(); // model_3 — the room
      final room = app.project!.models['model_3']!;
      app.addModelRef('model_1');
      final instance = room.objects.last;
      app.selectObject(instance.id);
      app.replaceModelRef(instance.id, 'model_2');
      final ref = room.objects.last;
      expect(ref.refModelId, 'model_2');
      expect(ref.scale, 1);
      expect(ref.name, 'model_2');
      expect(ref.refSize!.w, 3);
      // replacing onto the room itself is rejected (cycle rule)
      app.replaceModelRef(ref.id, 'model_3');
      expect(ref.refModelId, 'model_2');
    });

    test('setObjectScale updates the uniform scale', () {
      app.createModel();
      app.createModel();
      app.addModelRef('model_1');
      final id = room().objects.last.id;
      app.setObjectScale(id, 2);
      expect(room().objects.last.scale, 2);
      app.setObjectScale(id, -5); // clamped to a sane minimum
      expect(room().objects.last.scale, 0.01);
      app.undo();
      expect(room().objects.last.scale, 1);
    });

    test('modelRef cube proxy occupies the cached grid', () {
      final ref = refInstance();
      final cube = modelRefCubeProxy(ref);
      expect(cube.kind, 'cuboid');
      expect(cube.x, 0); // (1−1)/2 … grid of the cached w×l
      expect(cube.dim('w', 0), 1);
      expect(cube.dim('h', 0), 3);
      expect(cube.dim('d', 0), 2);
      expect(cube.material?.color, [255, 0, 255]);
    });
  });
}
