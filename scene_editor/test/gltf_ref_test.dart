import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/scene/editor_scene.dart';
import 'package:scene_editor/src/state/app_state.dart';
import 'package:scene_editor/src/ui/right_panel.dart';
import 'package:pet_engine/pet_engine.dart';

/// A glTF/GLB instance fixture: footprint [-1, 0, -0.5] × [1, 1, 0.5] at the
/// anchor (2, 0, 3), rotY 90, uniform scale [scale].
ModelObject gltfInstance({
  String gltfName = 'cat',
  double scale = 1,
  List<double>? bounds = const [-1.0, 0.0, -0.5, 1.0, 1.0, 0.5],
  String anim = '',
}) =>
    ModelObject(
      id: 'obj_7',
      name: gltfName,
      kind: gltfRefKind,
      x: 2,
      y: 0,
      z: 3,
      rotY: 90,
      gltfName: gltfName,
      scale: scale,
      gltfBounds: bounds == null ? null : List.of(bounds),
      anim: anim,
    );

/// A fake glTF catalog folder `3d_models/<name>/scene.gltf` (the catalog is
/// discovered purely from disk — the content bytes are never read).
void addGltfFolder(String projectPath, String name) {
  final dir = Directory('$projectPath/3d_models/$name');
  dir.createSync(recursive: true);
  File('${dir.path}/scene.gltf').writeAsStringSync('{"asset":{"version":"2.0"}}');
}

/// A fake GLB catalog file `3d_models/<name>.glb`.
void addGlbFile(String projectPath, String name) {
  final dir = Directory('$projectPath/3d_models');
  dir.createSync(recursive: true);
  File('${dir.path}/$name.glb').writeAsBytesSync([0, 0, 0]);
}

void main() {
  group('gltf instance JSON (kind gltf)', () {
    test('roundtrip keeps resource, scale, bounds, animation and placement',
        () {
      final obj = gltfInstance(scale: 1.5, anim: 'SKM_Cat|SKM_Cat|Cat_Walk');
      final model = ModelData(id: 'room', name: 'Комната', size: ModelSize(w: 6, l: 6, h: 3))
        ..objects.add(obj);
      final json = jsonDecode(
        const JsonEncoder().convert(model.toJson()),
      ) as Map<String, Object?>;
      final o = (json['objects'] as List).first as Map<String, Object?>;
      expect(o['kind'], gltfRefKind);
      expect(o['gltf'], 'cat');
      expect(o['scale'], 1.5);
      expect(o['bounds'], [-1.0, 0.0, -0.5, 1.0, 1.0, 0.5]);
      expect(o['anim'], 'SKM_Cat|SKM_Cat|Cat_Walk');
      expect(o['rotY'], 90);
      expect(o.containsKey('material'), isFalse);
      expect(o.containsKey('faces'), isFalse);

      final restored =
          ModelData.fromJson(const JsonEncoder().convert(model.toJson()), id: 'room');
      final r = restored.objects.single;
      expect(r.isGltfRef, isTrue);
      expect(r.gltfName, 'cat');
      expect(r.scale, 1.5);
      expect(r.gltfBounds, [-1.0, 0.0, -0.5, 1.0, 1.0, 0.5]);
      expect(r.anim, 'SKM_Cat|SKM_Cat|Cat_Walk');
      expect(r.x, 2);
      expect(r.rotY, 90);
      expect(r.material, isNull);
      expect(r.faces, isEmpty);
      expect(r.dims, isEmpty);
    });

    test('defaults parse without scale/bounds/anim', () {
      const json = '{"id":"obj_1","name":"x","kind":"gltf",'
          '"pos":[1,2,3],"gltf":"cat"}';
      final obj = ModelObject.fromJson(jsonDecode(json));
      expect(obj.isGltfRef, isTrue);
      expect(obj.gltfName, 'cat');
      expect(obj.scale, 1.0);
      expect(obj.gltfBounds, isNull);
      expect(obj.anim, '');
      expect(obj.dims, isEmpty);
    });

    test('no faces, not csg-eligible', () {
      final obj = gltfInstance();
      expect(facesOf(obj), isEmpty);
      expect(isCsgEligible(obj), isFalse);
    });
  });

  group('gltf footprint helpers', () {
    test('footprint box covers the cached bounds (default 1×1×1)', () {
      final ref = gltfInstance();
      final box = gltfFootprintBox(ref);
      expect(box.kind, 'cuboid');
      expect(box.x, 0);
      expect(box.dim('w', 0), closeTo(2, 1e-9));
      expect(box.dim('h', 0), closeTo(1, 1e-9));
      expect(box.dim('d', 0), closeTo(1, 1e-9));

      final plain = gltfInstance(bounds: null);
      final fallback = gltfFootprintBox(plain);
      expect(fallback.dim('w', 0), 1);
      expect(fallback.dim('h', 0), 1);
      expect(fallback.dim('d', 0), 1);
    });

    test('fuchsia placeholder occupies the cached footprint', () {
      final ref = gltfInstance(bounds: const [-0.5, 0.0, -0.4, 0.5, 1.2, 0.4]);
      // The engine colors the footprint box fuchsia for a deleted resource;
      // the public document-side shape is [gltfFootprintBox].
      final cube = gltfFootprintBox(ref);
      expect(cube.kind, 'cuboid');
      expect(cube.dim('w', 0), closeTo(1, 1e-9));
      expect(cube.dim('h', 0), closeTo(1.2, 1e-9));
      expect(cube.dim('d', 0), closeTo(0.8, 1e-9));
    });
  });

  group('unionAabbResolved of a gltf instance', () {
    test('folds in the cached footprint with rotation and scale', () {
      // footprint x ±1, y 0..1, z ±0.5 at anchor (2, 0, 3); rotY 90 swings
      // the box to x ±0.5, z ±1 (symmetric corners: x' = z, z' = −x).
      final ref = gltfInstance(scale: 1);
      final r = unionAabbResolved([ref]);
      expect(r.$1, closeTo(1.5, 1e-9));
      expect(r.$4, closeTo(2.5, 1e-9));
      expect(r.$2, closeTo(0, 1e-9));
      expect(r.$5, closeTo(1, 1e-9));
      expect(r.$3, closeTo(2, 1e-9));
      expect(r.$6, closeTo(4, 1e-9));
    });

    test('unknown bounds fall back to a 1×1×1 cube at the anchor', () {
      final ref = gltfInstance(bounds: null, scale: 2);
      final r = unionAabbResolved([ref]);
      // 1×1×1 box scaled ×2 → x/z ±1, y 0..2 around the anchor (2, 0, 3).
      expect(r.$1, closeTo(1, 1e-9));
      expect(r.$4, closeTo(3, 1e-9));
      expect(r.$3, closeTo(2, 1e-9));
      expect(r.$6, closeTo(4, 1e-9));
      expect(r.$5, closeTo(2, 1e-9));
    });

    test('two instances of the same resource both contribute', () {
      final a = gltfInstance();
      final b = gltfInstance()..x = 10;
      final r = unionAabbResolved([a, b]);
      // Each footprint spans x ±0.5 (after rotY 90), z 2..4 around the anchor.
      expect(r.$1, closeTo(1.5, 1e-9));
      expect(r.$4, closeTo(10.5, 1e-9));
    });
  });

  group('objectEdgeSegments of a gltf instance', () {
    test('outlines the footprint box through the instance anchor', () {
      // Default footprint 1×1×1: world anchor x = −(2−2) = 0, z = 3.
      final ref = gltfInstance(bounds: const [-0.5, 0.0, -0.5, 0.5, 2.0, 0.5]);
      final segs = objectEdgeSegments(ref, billboardYaw: 0, originX: 2, originZ: 0);
      expect(segs.length, 12); // the 12 cuboid edges of the placeholder
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
      expect(minX, closeTo(-0.5, 1e-9));
      expect(maxX, closeTo(0.5, 1e-9));
      expect(minY, closeTo(0, 1e-9));
      expect(maxY, closeTo(2, 1e-9));
      expect(minZ, closeTo(2.5, 1e-9));
      expect(maxZ, closeTo(3.5, 1e-9));
    });
  });

  group('picking inside a gltf instance (document node)', () {
    late Directory dir;
    late AppState app;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('gltf_pick_test');
      addGltfFolder(dir.path, 'cat');
      app = AppState();
      await app.createProject(dir.path, name: 'test');
      await app.model3d.reload();
      app.createModel();
      app.createModel();
      app.addGltfRef('cat');
    });

    tearDown(() {
      app.closeProject();
      dir.deleteSync(recursive: true);
    });

    test('a hit on a content node resolves to the obj wrapper id', () {
      // The engine wraps the whole gltf instance in ONE document node keyed
      // by the object id — a hit on any content part resolves to it (the
      // old ancestor walk lives engine-side now).
      final obj = app.currentModel!.objects.last;
      final node = app.controller.objectNode(obj.id);
      expect(node, isNotNull);
      expect(node!.object.id, obj.id);
      expect(node.object.isGltfRef, isTrue);
      expect(app.controller.byId(obj.id), same(node));
    });

    test('a plain document object keeps its own semantics', () {
      final floor = app.currentModel!.objects.first;
      final node = app.controller.objectNode(floor.id);
      expect(node, isNotNull);
      expect(node!.object.id, floor.id);
      expect(node.object.isGltfRef, isFalse);
    });
  });

  group('AppState glTF/GLB instances', () {
    late Directory dir;
    late AppState app;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('gltf_ref_test');
      addGltfFolder(dir.path, 'cat');
      addGlbFile(dir.path, 'dog');
      app = AppState();
      await app.createProject(dir.path, name: 'test');
      await app.model3d.reload();
    });

    tearDown(() {
      app.closeProject();
      dir.deleteSync(recursive: true);
    });

    ModelData current() => app.project!.models[app.currentModelId]!;

    test('addGltfRef places an instance and selects it', () {
      app.createModel(); // model_1
      app.setCursor(3, 0, 4);
      app.createModel(); // model_2
      app.addGltfRef('cat');

      final room = app.project!.models['model_2']!;
      expect(room.objects.length, 2); // floor + instance
      final o = room.objects.last;
      expect(o.isGltfRef, isTrue);
      expect(o.gltfName, 'cat');
      expect(o.name, 'cat');
      expect(o.scale, 1);
      expect(o.gltfBounds, isNull);
      expect(o.x, 3);
      expect(o.z, 4);
      expect(app.selectedObjectId, o.id);
      // undo removes it again
      app.undo();
      expect(room.objects.length, 1);
      app.redo();
      expect(room.objects.length, 2);
    });

    test('addGltfRef rejects an unknown resource', () {
      app.createModel();
      final before = current().objects.length;
      app.addGltfRef('giraffe');
      expect(current().objects.length, before);
    });

    test('replaceGltfRef swaps the resource and keeps the placement', () {
      app.createModel(); // model_1
      app.createModel(); // model_2
      app.addGltfRef('cat');
      final room = app.project!.models['model_2']!;
      final instance = room.objects.last;
      app.selectObject(instance.id);
      app.setObjectScale(instance.id, 1.5);
      app.replaceGltfRef(instance.id, 'dog');
      final ref = room.objects.last;
      expect(ref.gltfName, 'dog');
      expect(ref.name, 'dog');
      expect(ref.scale, 1.5); // placement survives
      expect(ref.x, instance.x);
      // replacing onto an unknown resource or the same one is rejected
      app.replaceGltfRef(ref.id, 'giraffe');
      expect(ref.gltfName, 'dog');
      app.replaceGltfRef(ref.id, 'dog');
      expect(ref.gltfName, 'dog');
    });

    test('setGltfAnim stores the choice and undoes', () {
      app.createModel();
      app.createModel();
      app.addGltfRef('cat');
      final id = current().objects.last.id;
      app.setGltfAnim(id, 'Cat_Walk');
      expect(current().objects.last.anim, 'Cat_Walk');
      app.undo(); // rapid same-object edits merge into one command
      expect(current().objects.last.anim, '');
      app.redo();
      expect(current().objects.last.anim, 'Cat_Walk');
      app.setGltfAnim(id, '');
      expect(current().objects.last.anim, '');
    });

    test('deleteGltfResource warns about users and keeps the references', () {
      app.createModel(); // model_1
      app.createModel(); // model_2
      app.addGltfRef('cat');
      expect(app.modelsUsingGltf('cat'), ['model_2']);
      expect(app.modelsUsingGltf('dog'), isEmpty);

      expect(app.deleteGltfResource('cat'), isNull);
      // the scene keeps the (broken) reference — it renders as a cube
      final ref = app.project!.models['model_2']!.objects.last;
      expect(ref.isGltfRef, isTrue);
      expect(ref.gltfName, 'cat');
      expect(app.modelsUsingGltf('cat'), ['model_2']);
      expect(Directory('${dir.path}/3d_models/cat').existsSync(), isFalse);
      expect(app.deleteGltfResource('giraffe'), isNotNull);
    });

    test('renameGltfResource repoints every reference', () async {
      app.createModel();
      app.createModel();
      app.addGltfRef('cat');
      expect(app.renameGltfResource('cat', 'kitten'), isNull);
      final ref = app.project!.models['model_2']!.objects.last;
      expect(ref.gltfName, 'kitten');
      expect(app.project!.models['model_2']!.dirty, isTrue);
      expect(app.modelsUsingGltf('cat'), isEmpty);
      expect(app.modelsUsingGltf('kitten'), ['model_2']);
      await app.model3d.reload();
      expect(app.model3d.entry('kitten'), isNotNull);
      expect(app.model3d.entry('cat'), isNull);
      expect(app.renameGltfResource('cat', 'x'), isNotNull); // gone
    });
  });

  group('right panel of a gltf instance', () {
    testWidgets('shows the resource, replace action and animation section',
        (tester) async {
      final dir = Directory.systemTemp.createTempSync('gltf_panel_test');
      addGltfFolder(dir.path, 'cat');
      final app = AppState();
      // Real file I/O inside testWidgets needs runAsync (the test body runs
      // in a fake-async zone where I/O futures never complete).
      await tester.runAsync(() async {
        await app.createProject(dir.path, name: 'test');
        await app.model3d.reload();
      });
      app.createModel();
      app.createModel();
      app.addGltfRef('cat');
      app.selectObject(app.currentModel!.objects.last.id);
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
      expect(find.text('GLB/GLTF'), findsOneWidget);
      expect(find.text('Заменить ресурс…'), findsOneWidget);
      expect(find.textContaining('Ресурс: cat · glTF'), findsOneWidget);
      expect(
        find.text('Модель загружается — список анимаций появится '
            'после загрузки.'),
        findsOneWidget,
      );
      app.closeProject();
      dir.deleteSync(recursive: true);
    });
  });
}
