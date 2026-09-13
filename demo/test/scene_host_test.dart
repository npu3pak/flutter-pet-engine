import 'package:demo/src/features/feature_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'test_helpers/test_app.dart';

/// Фича с параметром размера: проверяем, что хост сохраняет и сбрасывает
/// параметры при пересборке и смене фичи.
FeatureSpec _boxFeature(String id, {String group = 'Документ сцены'}) =>
    FeatureSpec(
      id: id,
      group: group,
      title: 'Фича $id',
      phase: 1,
      description: 'Тестовая возможность с параметром размера для автотеста.',
      checks: const ['Параметр размера применяется к объекту сцены.'],
      build: (context) {
        final size = context.param<double>('size') ?? 1.0;
        return doc.ModelData(
          id: id,
          name: id,
          size: doc.ModelSize(w: 2, l: 2, h: 2),
          objects: [
            doc.ModelObject(
              id: 'obj',
              name: 'obj',
              kind: 'cuboid',
              dims: {'w': size, 'h': 1, 'd': 1},
            ),
          ],
        );
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('параметры сцены сохраняются при пересборке той же фичи', () async {
    final host = FakeSceneHost(paths: testPaths());
    final spec = _boxFeature('a');
    await host.showFeature(spec);
    expect(host.lastScene!.objectById('obj')!.dims['w'], 1.0);

    host.updateFeatureParams({'size': 2.5});
    await pumpEventQueue();
    expect(host.lastScene!.objectById('obj')!.dims['w'], 2.5);
  });

  test('параметры сбрасываются при смене фичи', () async {
    final host = FakeSceneHost(paths: testPaths());
    final first = _boxFeature('a');
    final second = _boxFeature('b', group: 'Свет и картинка');
    await host.showFeature(first);
    host.updateFeatureParams({'size': 2.5});
    await pumpEventQueue();
    expect(host.lastScene!.objectById('obj')!.dims['w'], 2.5);

    await host.showFeature(second);
    await host.showFeature(first);
    expect(
      host.lastScene!.objectById('obj')!.dims['w'],
      1.0,
      reason: 'после смены фичи параметры не должны переноситься',
    );
  });

  test('пересборка сохраняет камеру, resetCamera сбрасывает', () async {
    final host = FakeSceneHost(paths: testPaths());
    await host.showFeature(_boxFeature('a'));
    expect(host.cameraApplies, 1);

    host.reloadFeature();
    await pumpEventQueue();
    expect(host.cameraApplies, 1, reason: 'пересборка камеру не трогает');

    host.reloadFeature(resetCamera: true);
    await pumpEventQueue();
    expect(host.cameraApplies, 2, reason: 'resetCamera сбрасывает камеру');
  });
}
