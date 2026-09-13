import 'package:flutter_test/flutter_test.dart';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:scene_editor/src/scene/meta_renderer.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

SceneHit hit(double distance) => SceneHit(
      node: BoxNode(id: 'n'),
      distance: distance,
      worldPoint: vm.Vector3.zero(),
      localPoint: vm.Vector3.zero(),
      worldNormal: vm.Vector3(0, 1, 0),
    );

void main() {
  group('meta label text', () {
    test('comment bubble shows the comment only', () {
      final m = ModelMeta(
        id: 'meta_1',
        kind: metaKindComment,
        name: 'Комментарий',
        comment: '  здесь кошка  ',
      );
      expect(metaLabelText(m), 'здесь кошка');
      expect(metaHasLabel(m), isTrue);
      expect(metaNeedsCollapse(m), isFalse);
    });

    test('long comment collapses by default policy', () {
      final m = ModelMeta(
        id: 'meta_1',
        kind: metaKindComment,
        name: 'Комментарий',
        comment: 'очень длинный комментарий ' * 10,
      );
      expect(metaNeedsCollapse(m), isTrue);
    });

    test('marker bubble is name + comment', () {
      final m = ModelMeta(
        id: 'meta_2',
        kind: metaKindMarker,
        name: 'камера',
        comment: 'вид с юга',
      );
      expect(metaLabelText(m), 'камера\nвид с юга');
      expect(metaHasLabel(m), isTrue);
    });

    test('marker without comment shows its name only', () {
      final m = ModelMeta(id: 'meta_2', kind: metaKindMarker, name: 'камера');
      expect(metaLabelText(m), 'камера');
    });

    test('empty metas have no bubble', () {
      final m = ModelMeta(
        id: 'meta_2',
        kind: metaKindMarker,
        name: 'камера',
        comment: '   ',
      );
      expect(metaHasLabel(m), isTrue); // the name alone still shows
      final empty = ModelMeta(id: 'm', kind: metaKindComment, name: 'c');
      expect(metaHasLabel(empty), isFalse);
      expect(metaLabelText(empty), isEmpty);
    });
  });

  group('meta geometry helpers', () {
    final size = ModelSize(w: 5, l: 3, h: 3);

    test('bubble bottom sits above the shape for every kind', () {
      final comment = ModelMeta(
          id: 'm', kind: metaKindComment, name: 'c', y: 0.4);
      expect(
        metaBubbleBottomY(comment),
        closeTo(
          0.4 +
              kCommentBallRadius +
              kCommentDotGap +
              kCommentStemHeight +
              kMetaBubbleGap,
          1e-9,
        ),
      );
      final marker =
          ModelMeta(id: 'm', kind: metaKindMarker, name: 'камера', y: 0);
      expect(
        metaBubbleBottomY(marker),
        closeTo(
          kMarkerPinHeight + kMarkerBallRadius * 2 + kMetaBubbleGap,
          1e-9,
        ),
      );
      final box = ModelMeta(
        id: 'm',
        kind: metaKindBox,
        name: 'зона',
        y: 0,
        dims: {'h': 2.0},
      );
      expect(metaBubbleBottomY(box), closeTo(2.0 + kBoxBubbleGap, 1e-9));
    });

    test('box edges make 12 edge pairs of the cuboid corners', () {
      final box = ModelMeta(
        id: 'm',
        kind: metaKindBox,
        name: 'непроходимый',
        x: 2.0,
        y: 0.5,
        z: 1.0,
        dims: {'w': 2.0, 'h': 1.0, 'd': 1.0},
      );
      final edges = metaBoxEdges(box, size);
      expect(edges, hasLength(12));
      final pts = edges.expand((e) => [e.$1, e.$2]).toSet();
      expect(pts, hasLength(8));
      // World x mirrors the model (chunkWorld): x=2 in a 5-wide model.
      final xs = pts.map((p) => p.$1).toSet();
      expect(xs, {-1.0, 1.0}); // x=2 (w=2) spans model 1..3 → world ±1
      final ys = pts.map((p) => p.$2).toSet();
      expect(ys, {0.5, 1.5});
      // z=1 in a 3-deep model sits at the center 0, ± half depth 0.5.
      final zs = pts.map((p) => p.$3).toSet();
      expect(zs, {-0.5, 0.5});
    });

    test('occlusion samples cover shape and bubble', () {
      final comment = ModelMeta(
        id: 'm',
        kind: metaKindComment,
        name: 'c',
        x: 2,
        y: 0.3,
        z: 1,
        comment: 'привет',
      );
      final cSamples = metaOcclusionSamples(comment, size);
      expect(cSamples, hasLength(3)); // dot + «!» top + bubble
      expect(cSamples.first.y, closeTo(0.3, 1e-5));
      expect(
        cSamples[1].y,
        closeTo(
          0.3 + kCommentBallRadius + kCommentDotGap + kCommentStemHeight,
          1e-5,
        ),
      );

      final box = ModelMeta(
        id: 'm',
        kind: metaKindBox,
        name: 'зона',
        x: 2,
        y: 0,
        z: 1,
        dims: {'w': 1.0, 'h': 1.0, 'd': 1.0},
      );
      final bSamples = metaOcclusionSamples(box, size);
      expect(bSamples, hasLength(10)); // 9 through the volume + bubble
      // 8 corners at 0.9h, the center at 0.5h, the bubble above the top.
      bool yNear(double y, double want) => (y - want).abs() < 1e-4;
      expect(bSamples.where((p) => yNear(p.y, 0.9)).length, 8);
      expect(bSamples.where((p) => yNear(p.y, 0.5)).length, 1);
      expect(bSamples.where((p) => yNear(p.y, 1.0 + kBoxBubbleGap + 0.45)).length, 1);
    });
  });

  group('occlusion hit test', () {
    test('a hit closer than the target covers it', () {
      expect(anyHitCloserThan([hit(2.0), hit(5.0)], 4.0), isTrue);
      expect(anyHitCloserThan([hit(4.0002)], 4.0), isFalse); // tolerance
      expect(anyHitCloserThan(const [], 4.0), isFalse);
      // The meta's own surface at the target distance is NOT an occluder.
      expect(anyHitCloserThan([hit(3.9999)], 4.0), isFalse);
    });
  });

  group('meta colors', () {
    test('fixed palette per kind', () {
      expect(metaColor(metaKindComment).y, greaterThan(metaColor(metaKindComment).x));
      expect(metaColor(metaKindMarker).x, greaterThan(metaColor(metaKindMarker).y));
      expect(metaColor(metaKindBox).z, greaterThan(metaColor(metaKindBox).x));
    });
  });
}
