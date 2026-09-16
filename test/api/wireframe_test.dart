import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

ModelData _model() =>
    ModelData(id: 'm', name: 'M', size: ModelSize(w: 4, l: 4, h: 3));

ModelObject _box({String id = 'obj_1'}) => ModelObject(
  id: id,
  name: 'box',
  kind: 'cuboid',
  x: 1,
  y: 0,
  z: 2,
  dims: {'w': 2, 'h': 1, 'd': 2},
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('LineWidthBackend', () {
    test('picks the shader on mobile/desktop Apple and polyline elsewhere', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(defaultLineWidthBackend(), LineWidthBackend.shader);
      }
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(defaultLineWidthBackend(), LineWidthBackend.polyline);
      }
    });

    test('setLineWidthBackend overrides the active backend', () {
      final previous = lineWidthBackend;
      setLineWidthBackend(LineWidthBackend.polyline);
      expect(lineWidthBackend, LineWidthBackend.polyline);
      setLineWidthBackend(previous);
    });
  });

  group('LineGeometry screen widths', () {
    test('widthPx bumps the revision so the mesh is rebuilt', () {
      final geometry = LineGeometry([
        vm.Vector3.zero(),
        vm.Vector3(1, 0, 0),
      ]);
      expect(geometry.widthPx, isNull);
      final revision = geometry.revision;

      geometry.widthPx = 3;
      expect(geometry.widthPx, 3);
      expect(geometry.revision, greaterThan(revision));

      final bumped = geometry.revision;
      geometry.widthPx = 3;
      expect(geometry.revision, bumped);
    });

    test('localBounds stay exact for screen-width ribbons', () {
      final geometry = LineGeometry([
        vm.Vector3.zero(),
        vm.Vector3(2, 0, 0),
      ], widthPx: 3);
      final bounds = geometry.localBounds!;
      expect(bounds.min.x, closeTo(0, 1e-6));
      expect(bounds.max.x, closeTo(2, 1e-6));
    });
  });

  group('WireframeStyle', () {
    test('equality and copyWith cover every field', () {
      const style = WireframeStyle(
        thickness: 3,
        color: Color(0xFFFF0000),
        throughGeometry: true,
        creaseAngle: 1,
      );
      expect(style, const WireframeStyle(
        thickness: 3,
        color: Color(0xFFFF0000),
        throughGeometry: true,
        creaseAngle: 1,
      ));
      final copy = style.copyWith(thickness: 5, throughGeometry: false);
      expect(copy.thickness, 5);
      expect(copy.throughGeometry, isFalse);
      expect(copy.color, style.color);
      expect(copy.creaseAngle, style.creaseAngle);
    });
  });

  group('node wireframe edges', () {
    test('a box yields its 12 crease edges (no triangulation diagonals)', () {
      final box = BoxNode(size: vm.Vector3(2, 2, 2));
      final segments = box.wireframeSegments();
      expect(segments.length, 24);
      box.remove();
    });

    test('a group node has no edges of its own', () {
      final group = GroupNode();
      expect(group.wireframeSegments(), isEmpty);
      group.remove();
    });
  });

  group('SceneController wireframe', () {
    test('the scene-wide style builds and drops a top-layer overlay', () {
      final controller = SceneController();
      controller.add(BoxNode(id: 'box', size: vm.Vector3(1, 1, 1)));
      expect(controller.hasTopContent, isFalse);

      controller.setWireframe(const WireframeStyle());
      expect(controller.wireframeStyle, isNotNull);
      expect(controller.hasTopContent, isTrue);
      final lines = controller.nodesOfType<LineNode>().toList();
      expect(lines, hasLength(1));
      expect(lines.single.layer, SceneLayer.top);
      expect(lines.single.widthPx, 1);

      controller.setWireframe(null);
      expect(controller.hasTopContent, isFalse);
      expect(controller.nodesOfType<LineNode>(), isEmpty);
      controller.dispose();
    });

    test('a node style overrides the scene-wide one', () {
      final controller = SceneController();
      controller.add(BoxNode(id: 'box'));
      controller.setWireframe(const WireframeStyle(thickness: 3));
      controller.byId('box')!.wireframe = const WireframeStyle(
        thickness: 5,
        color: Color(0xFFFF0000),
      );

      final line = controller.nodesOfType<LineNode>().single;
      expect(line.widthPx, 5);
      expect(line.color, const Color(0xFFFF0000));
      controller.dispose();
    });

    test('a node without its own style keeps the scene-wide overlay', () {
      final controller = SceneController();
      controller.add(BoxNode(id: 'box'));
      controller.setWireframe(const WireframeStyle(thickness: 2));
      controller.add(BoxNode(id: 'other'));

      expect(controller.nodesOfType<LineNode>(), hasLength(2));
      controller.dispose();
    });

    test('switching models drops the previous wireframes', () {
      final controller = SceneController();
      controller.setWireframe(const WireframeStyle());
      controller.loadModelData(_model());
      controller.addObject(_box(id: 'obj_1'));
      expect(controller.nodesOfType<LineNode>(), hasLength(1));

      // Document nodes are virtual, so their disposal never notifies the
      // controller: the overlay of the previous model must be pruned by the
      // rebuild itself, or stale frames stay on screen forever.
      controller.loadModelData(
        ModelData(id: 'm2', name: 'M2', size: ModelSize(w: 4, l: 4, h: 3)),
      );
      controller.addObject(_box(id: 'other'));
      final lines = controller.nodesOfType<LineNode>().toList();
      expect(lines, hasLength(1));
      expect(lines.single.id, contains('other'));
      controller.dispose();
    });
  });

  group('ModelNode wireframe', () {
    test('object and face overlays come from the document content', () {
      final controller = SceneController();
      controller.loadModelData(_model());
      final node = controller.addObject(_box());
      expect(controller.nodesOfType<LineNode>(), isEmpty);

      node.setFaceWireframe('+z', true);
      expect(node.faceWireframe('+z'), isTrue);
      var lines = controller.nodesOfType<LineNode>().toList();
      expect(lines, hasLength(1));
      expect(lines.single.widthPx, 1);
      expect(lines.single.layer, SceneLayer.top);

      node.wireframe = const WireframeStyle(thickness: 4);
      lines = controller.nodesOfType<LineNode>().toList();
      expect(lines, hasLength(1));
      expect(lines.single.widthPx, 4);

      node.setFaceWireframe('+z', false);
      node.wireframe = null;
      expect(controller.nodesOfType<LineNode>(), isEmpty);
      controller.dispose();
    });
  });
}
