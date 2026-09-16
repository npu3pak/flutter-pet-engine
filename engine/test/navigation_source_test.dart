import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _modelJson = '''
{
  "format": "model_v1",
  "id": "nav_test",
  "name": "nav",
  "size": {"w": 5, "l": 5, "h": 3},
  "objects": [],
  "meta": [
    {"id": "m1", "kind": "box", "name": "unpassable",
     "pos": [0.5, 0.0, 0.5], "size": {"w": 1, "h": 1, "d": 1}},
    {"id": "m2", "kind": "box", "name": "door",
     "pos": [2.0, 0.0, 2.0], "size": {"w": 1, "h": 1, "d": 1}}
  ]
}
''';

void main() {
  group('BoxMarkupNavigation.fromModel', () {
    late BoxMarkupNavigation source;

    setUpAll(() {
      final model = doc.ModelData.fromJson(_modelJson, id: 'nav_test');
      source = BoxMarkupNavigation.fromModel(model, radius: 0.2);
    });

    test('mirrors model boxes into world and keeps the bounds', () {
      expect(source.bounds.min.x, closeTo(-2.5, 1e-9));
      expect(source.bounds.max.x, closeTo(2.5, 1e-9));
      expect(source.bounds.min.y, closeTo(-2.5, 1e-9));
      expect(source.bounds.max.y, closeTo(2.5, 1e-9));
      // Кресло модели (0.5, 0.5) → мир (1.5, −1.5), бокс 1×1.
      expect(source.isPassable(vm.Vector2(1.5, -1.5)), isFalse);
      // Мета-бокс с другим именем (door) в проходимость не входит.
      expect(source.isPassable(vm.Vector2(0.0, 0.0)), isTrue);
      // За границей комнаты.
      expect(source.isPassable(vm.Vector2(3.0, 0.0)), isFalse);
    });

    test('radius inflates the obstacle', () {
      // Мир без радиуса: бокс [1, 2]×[−2, −1]; с радиусом 0.2 —
      // [0.8, 2.2]×[−2.2, −0.8].
      expect(source.isPassable(vm.Vector2(0.9, -1.5)), isFalse);
      expect(source.isPassable(vm.Vector2(0.7, -1.5)), isTrue);
      expect(source.isPassable(vm.Vector2(1.5, -0.9)), isFalse);
    });

    test('segment queries use the exact rectangle test', () {
      expect(
        source.isSegmentPassable(vm.Vector2(0.0, -1.5), vm.Vector2(2.4, -1.5)),
        isFalse,
      );
      expect(
        source.isSegmentPassable(vm.Vector2(0.0, 0.0), vm.Vector2(0.0, -2.0)),
        isTrue,
      );
    });

    test('nearestPassable leaves an obstacle', () {
      final nearest = source.nearestPassable(vm.Vector2(1.5, -1.5));
      expect(nearest, isNotNull);
      expect(source.isPassable(nearest!), isTrue);
      expect((nearest - vm.Vector2(1.5, -1.5)).length, lessThan(1.0));
    });

    test('clearance reports free space up to the inflated box', () {
      final distance = source.clearance(
        vm.Vector2(0.5, -1.5),
        vm.Vector2(1, 0),
      );
      expect(distance, closeTo(0.3, 1e-9));
    });
  });

  group('BoxMarkupNavigation from explicit rectangles', () {
    test('empty source is fully passable inside bounds', () {
      final source = BoxMarkupNavigation(
        obstacles: const [],
        bounds: vm.Aabb2.minMax(vm.Vector2(-2.5, -2.5), vm.Vector2(2.5, 2.5)),
      );
      expect(source.isPassable(vm.Vector2(0, 0)), isTrue);
      expect(source.isPassable(vm.Vector2(2.6, 0)), isFalse);
      expect(
        source.isSegmentPassable(vm.Vector2(-2, 0), vm.Vector2(2, 0)),
        isTrue,
      );
    });
  });
}
