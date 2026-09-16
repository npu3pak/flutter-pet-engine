import 'package:example/src/features/feature_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('левая панель показывает группы и пункты каталога', (
    tester,
  ) async {
    final features = [
      testFeature(
        id: 'primitives',
        group: 'Документ сцены',
        title: 'Все примитивы',
      ),
      testFeature(id: 'shadows', group: 'Свет и картинка', title: 'Тени'),
    ];
    await pumpShell(tester, features: features);

    expect(find.text('Все примитивы'), findsOneWidget);
    expect(find.text('Тени'), findsOneWidget);
    expect(find.text('ДОКУМЕНТ СЦЕНЫ'), findsOneWidget);
    expect(find.text('СВЕТ И КАРТИНКА'), findsOneWidget);
    expect(find.byKey(const Key('welcome')), findsOneWidget);
    expect(find.byKey(const Key('nav-about')), findsOneWidget);
  });

  testWidgets('выбор пункта открывает сцену, статус и управление', (
    tester,
  ) async {
    final features = [
      testFeature(
        id: 'primitives',
        title: 'Все примитивы',
        controls: (context, feature) => const Text('Управление тестовой фичи'),
      ),
    ];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: features, host: host);

    await tester.tap(find.byKey(const Key('feature-primitives')));
    await tester.pumpAndSettle();

    expect(host.ready, isTrue);
    expect(host.modelId, 'primitives');
    expect(find.byKey(const Key('viewport')), findsOneWidget);
    expect(find.byKey(const Key('status-card')), findsOneWidget);
    expect(find.text('Управление тестовой фичи'), findsOneWidget);
  });

  testWidgets('камера по клеткам показывает кнопки навигации', (tester) async {
    final features = [
      testFeature(
        id: 'cells',
        title: 'Камера по клеткам',
        camera: CameraMode.cell,
      ),
    ];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: features, host: host);

    await tester.tap(find.byKey(const Key('feature-cells')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cell-turn-left')), findsOneWidget);
    expect(find.byKey(const Key('cell-forward')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cell-turn-left')));
    await tester.pump();
    expect(host.cameraSteps, contains('turnLeft'));
  });

  testWidgets('кнопка настроек открывает правую панель', (tester) async {
    final features = [testFeature(id: 'a', title: 'Фича')];
    await pumpShell(tester, features: features);

    await tester.tap(find.byKey(const Key('feature-a')));
    await tester.pumpAndSettle();
    expect(find.text('Настройки сцены'), findsNothing);

    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    expect(find.text('Настройки сцены'), findsOneWidget);
  });

  testWidgets('раздел «О приложении» открывается из левой панели', (
    tester,
  ) async {
    await pumpShell(tester, features: [testFeature(id: 'a')]);
    await tester.tap(find.byKey(const Key('nav-about')));
    await tester.pumpAndSettle();
    expect(find.text('Версия приложения'), findsOneWidget);
    expect(find.text(testInfo.engineVersion), findsOneWidget);
  });

  testWidgets('ошибка сборки сцены показывается понятным текстом', (
    tester,
  ) async {
    final features = [
      testFeature(
        id: 'bad',
        title: 'Сломанная фича',
        build: () => throw StateError('нет данных'),
      ),
    ];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: features, host: host);

    await tester.tap(find.byKey(const Key('feature-bad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scene-error')), findsOneWidget);
    expect(find.textContaining('Не удалось открыть фичу'), findsOneWidget);
    expect(host.ready, isFalse);
  });

  testWidgets('раскладка не ломается на широком и узком окне', (tester) async {
    addTearDown(tester.view.reset);
    final features = [testFeature(id: 'a', title: 'Фича с длинным названием')];

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    await pumpShell(tester, features: features);
    await tester.tap(find.byKey(const Key('feature-a')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель управления занимает высоту под карточкой статуса', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    final host = FakeSceneHost(paths: testPaths());
    final features = [
      testFeature(
        id: 'tall',
        title: 'Высокая фича',
        controls: (context, feature) =>
            Column(children: [for (var i = 0; i < 60; i++) Text('строка $i')]),
      ),
    ];
    await pumpShell(tester, features: features, host: host);
    await tester.tap(find.byKey(const Key('feature-tall')));
    await tester.pumpAndSettle();

    final status = tester.getRect(find.byKey(const Key('status-card')));
    final controls = tester.getRect(find.byKey(const Key('feature-controls')));
    expect(controls.top, greaterThanOrEqualTo(status.bottom));
    expect(controls.left, status.left);
    expect(controls.height, greaterThan(500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('клавиши камеры не роняют каркас', (tester) async {
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(
      tester,
      features: [testFeature(id: 'a')],
      host: host,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель управления пересоздаётся при смене фичи', (tester) async {
    final inits = <String>[];
    final features = [
      testFeature(
        id: 'a',
        title: 'Первая',
        controls: (context, feature) =>
            _CountingControls(id: 'a', onInit: inits.add),
      ),
      testFeature(
        id: 'b',
        title: 'Вторая',
        controls: (context, feature) =>
            _CountingControls(id: 'b', onInit: inits.add),
      ),
    ];
    await pumpShell(tester, features: features);

    await tester.tap(find.byKey(const Key('feature-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feature-b')));
    await tester.pumpAndSettle();

    expect(inits, ['a', 'b']);
  });

  testWidgets('оверлей не пропадает и тумблер не сбрасывается', (tester) async {
    final features = [
      testFeature(
        id: 'overlay',
        title: 'Оверлей',
        controls: (context, feature) => _OverlayControls(feature: feature),
      ),
    ];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: features, host: host);

    await tester.tap(find.byKey(const Key('feature-overlay')));
    await tester.pumpAndSettle();
    expect(host.overlayBuilder, isNotNull);
    expect(find.byKey(const Key('overlay-marker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('overlay-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-marker')), findsNothing);

    await tester.tap(find.byKey(const Key('overlay-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overlay-marker')), findsOneWidget);
  });
}

/// Панель управления, считающая создания состояния: проверяет, что при
/// смене фичи State пересоздаётся (иначе переключение погоды ломается).
class _CountingControls extends StatefulWidget {
  const _CountingControls({required this.id, required this.onInit});

  final String id;
  final void Function(String id) onInit;

  @override
  State<_CountingControls> createState() => _CountingControlsState();
}

class _CountingControlsState extends State<_CountingControls> {
  @override
  void initState() {
    super.initState();
    widget.onInit(widget.id);
  }

  @override
  Widget build(BuildContext context) => Text('Панель ${widget.id}');
}

/// Панель с оверлеем и тумблером: проверяет владельца слота оверлея.
class _OverlayControls extends StatefulWidget {
  const _OverlayControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_OverlayControls> createState() => _OverlayControlsState();
}

class _OverlayControlsState extends State<_OverlayControls> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _install();
  }

  @override
  void dispose() {
    widget.feature.setOverlay(null);
    super.dispose();
  }

  void _install() {
    widget.feature.setOverlay(
      (size) => _on
          ? const Center(
              child: SizedBox(
                key: Key('overlay-marker'),
                width: 10,
                height: 10,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Switch(
      key: const Key('overlay-toggle'),
      value: _on,
      onChanged: (value) {
        setState(() => _on = value);
        _install();
        widget.feature.refresh();
      },
    );
  }
}
