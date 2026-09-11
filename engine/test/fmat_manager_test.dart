import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine.dart';

void main() {
  group('FmatManager', () {
    test('reports failure and falls back when the loader throws', () async {
      final manager = FmatManager(
        slots: const [
          FmatSlot(name: 'glow', sourcePath: 'assets/shaders/fx_glow.fmat'),
        ],
        loader: (_) => throw StateError('no fmat bundle'),
      );

      expect(manager.loaded, isFalse);
      expect(manager.ready, isFalse);
      expect(manager.materialFor('glow'), isNull);

      await manager.load();

      expect(manager.loaded, isTrue);
      expect(manager.ready, isFalse);
      expect(manager.materialFor('glow'), isNull);
    });

    test('is idempotent', () async {
      var calls = 0;
      final manager = FmatManager(
        slots: const [
          FmatSlot(name: 'glow', sourcePath: 'a.fmat', instances: 2),
        ],
        loader: (_) {
          calls++;
          throw StateError('unavailable');
        },
      );

      await manager.load();
      await manager.load();
      expect(calls, 2); // one per instance, once
    });

    test('returns null for unknown slots, instances and before load', () async {
      final manager = FmatManager(
        slots: const [
          FmatSlot(name: 'glow', sourcePath: 'a.fmat'),
        ],
        loader: (_) => throw StateError('unavailable'),
      );

      expect(manager.materialFor('missing'), isNull);
      await manager.load();
      expect(manager.materialFor('glow', instance: 1), isNull);
      expect(manager.materialFor('glow', instance: -1), isNull);
    });

    test('dispose resets the manager for a reload', () async {
      var calls = 0;
      final manager = FmatManager(
        slots: const [
          FmatSlot(name: 'glow', sourcePath: 'a.fmat'),
        ],
        loader: (_) {
          calls++;
          throw StateError('unavailable');
        },
      );

      await manager.load();
      manager.dispose();
      expect(manager.loaded, isFalse);
      await manager.load();
      expect(calls, 2);
    });
  });
}
