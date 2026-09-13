import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:demo/src/deeplink.dart';
import 'package:demo/src/paths.dart';
import 'package:demo/src/screenshot_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('разбор диплинков', () {
    test('scene с параметрами и выводом типов', () {
      final command = parseDeeplink(
        Uri.parse(
          'pet-engine-example://scene?id=rounded_box&radius=0.4&segments=24&on=true&mode=smooth',
        ),
      );

      expect(command, isA<OpenSceneCommand>());
      final scene = command! as OpenSceneCommand;
      expect(scene.featureId, 'rounded_box');
      expect(scene.params, {
        'radius': 0.4,
        'segments': 24,
        'on': true,
        'mode': 'smooth',
      });
      expect(scene.panelsHidden, isFalse);
    });

    test('панели скрываются по параметру panels', () {
      final scene =
          parseDeeplink(
                Uri.parse('pet-engine-example://scene?id=a&panels=hide'),
              )!
              as OpenSceneCommand;
      expect(scene.panelsHidden, isTrue);

      final shot =
          parseDeeplink(
                Uri.parse('pet-engine-example://screenshot?panels=show'),
              )!
              as ScreenshotCommand;
      expect(shot.panelsHidden, isFalse);

      final capture =
          parseDeeplink(Uri.parse('pet-engine-example://capture?id=a'))!
              as CaptureCommand;
      expect(capture.panelsHidden, isTrue);
    });

    test('scene без идентификатора не распознаётся', () {
      expect(parseDeeplink(Uri.parse('pet-engine-example://scene')), isNull);
      expect(
        parseDeeplink(Uri.parse('pet-engine-example://scene?id=')),
        isNull,
      );
    });

    test('screenshot с настройками', () {
      final command = parseDeeplink(
        Uri.parse(
          'pet-engine-example://screenshot?name=shot&delay=3500&region=viewport&scale=1.5',
        ),
      );

      expect(command, isA<ScreenshotCommand>());
      final shot = command! as ScreenshotCommand;
      expect(shot.name, 'shot');
      expect(shot.delayMs, 3500);
      expect(shot.region, kScreenshotRegionViewport);
      expect(shot.scale, 1.5);
    });

    test('screenshot по умолчанию снимает окно', () {
      final command =
          parseDeeplink(Uri.parse('pet-engine-example://screenshot'))!
              as ScreenshotCommand;
      expect(command.name, isNull);
      expect(command.region, kScreenshotRegionWindow);
      expect(command.delayMs, kScreenshotDefaultDelayMs);
      expect(command.scale, isNull);
    });

    test('capture открывает сцену и снимает её', () {
      final command =
          parseDeeplink(
                Uri.parse(
                  'pet-engine-example://capture?id=weather_rain&name=rain&delay=3000',
                ),
              )!
              as CaptureCommand;
      expect(command.featureId, 'weather_rain');
      expect(command.name, 'rain');
      expect(command.delayMs, 3000);
    });

    test('capture без имени использует идентификатор фичи', () {
      final command =
          parseDeeplink(Uri.parse('pet-engine-example://capture?id=a'))!
              as CaptureCommand;
      expect(command.name, 'a');
    });

    test('screen открывает служебный экран', () {
      final command =
          parseDeeplink(Uri.parse('pet-engine-example://screen?name=about'))!
              as OpenScreenCommand;
      expect(command.screen, 'about');
    });

    test('settings передаёт настройки сцены', () {
      final command =
          parseDeeplink(
                Uri.parse(
                  'pet-engine-example://settings?fog=1&fogStart=4&fogColor=white&ssao=0&wireframe=1',
                ),
              )!
              as SettingsCommand;
      expect(command.values['fog'], '1');
      expect(command.values['fogStart'], '4');
      expect(command.values['fogColor'], 'white');
      expect(command.values['ssao'], '0');
      expect(command.values['wireframe'], '1');
    });

    test('чужая схема и неизвестная команда не распознаются', () {
      expect(
        parseDeeplink(Uri.parse('https://example.com/scene?id=a')),
        isNull,
      );
      expect(parseDeeplink(Uri.parse('pet-engine-example://unknown')), isNull);
    });

    test('имя снимка очищается от посторонних символов', () {
      expect(sanitizeScreenshotName('rounded box/r04'), 'rounded_box_r04');
      expect(sanitizeScreenshotName('  '), 'screenshot');
      expect(sanitizeScreenshotName('shot-1_ok'), 'shot-1_ok');
    });
  });

  test('команды выполняются по очереди', () async {
    final controller = DeeplinkController(
      channel: const MethodChannel('test/deeplink'),
    );
    addTearDown(controller.dispose);
    final order = <String>[];
    final completers = <Completer<void>>[];
    controller.onCommand = (command) async {
      final label = describeDeeplinkCommand(command);
      order.add('начало: $label');
      final completer = Completer<void>();
      completers.add(completer);
      await completer.future;
      order.add('конец: $label');
    };

    final first = controller.handleRawUrl('pet-engine-example://scene?id=a');
    await Future<void>.delayed(Duration.zero);
    final second = controller.handleRawUrl(
      'pet-engine-example://screenshot?name=x',
    );
    await Future<void>.delayed(Duration.zero);

    expect(order, ['начало: scene a {} panels=show']);

    completers[0].complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(order, [
      'начало: scene a {} panels=show',
      'конец: scene a {} panels=show',
      'начало: screenshot x region=window delay=2000 panels=hide',
    ]);

    completers[1].complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(order, [
      'начало: scene a {} panels=show',
      'конец: scene a {} panels=show',
      'начало: screenshot x region=window delay=2000 panels=hide',
      'конец: screenshot x region=window delay=2000 panels=hide',
    ]);

    await first;
    await second;
  });

  test('сохранение снимка пишет PNG и карточку', () async {
    final appDir = Directory('temp/deeplink_test_repo/engine/example')
      ..createSync(recursive: true);
    addTearDown(
      () => Directory('temp/deeplink_test_repo').deleteSync(recursive: true),
    );
    final paths = AppPaths(appDir);
    final bytes = Uint8List.fromList([137, 80, 78, 71]);

    final path = await writeScreenshotFiles(paths, 'shot', bytes, {
      'featureId': 'a',
      'ready': true,
    });

    expect(path, endsWith('temp/screenshots/shot.png'));
    expect(File(path).readAsBytesSync(), bytes);
    final sidecar = File(path.replaceAll('.png', '.json'));
    expect(sidecar.existsSync(), isTrue);
    final meta = jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
    expect(meta['name'], 'shot');
    expect(meta['featureId'], 'a');
    expect(meta['ready'], isTrue);
  });

  testWidgets('диплинк открывает сцену с параметрами', (tester) async {
    final features = [testFeature(id: 'rounded_box', title: 'Скругления')];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(tester, features: features, host: host);

    await sendDeeplink(
      tester,
      'pet-engine-example://scene?id=rounded_box&radius=0.4&segments=24',
    );
    await tester.pumpAndSettle();

    expect(host.ready, isTrue);
    expect(host.modelId, 'rounded_box');
    expect(host.context.params['radius'], 0.4);
    expect(host.context.params['segments'], 24);
    expect(find.byKey(const Key('viewport')), findsOneWidget);
  });

  testWidgets('диплинк capture отдаёт снимок в сейвер', (tester) async {
    final saved = <Map<String, Object?>>[];
    final fakeBytes = Uint8List.fromList([137, 80, 78, 71]);
    var hiddenDuringCapture = false;
    final features = [testFeature(id: 'primitives', title: 'Все примитивы')];
    final host = FakeSceneHost(paths: testPaths());
    await pumpShell(
      tester,
      features: features,
      host: host,
      screenshotCapture: (key, pixelRatio) async {
        hiddenDuringCapture = find
            .byKey(const Key('nav-list'))
            .evaluate()
            .isEmpty;
        return fakeBytes;
      },
      screenshotSaver: (name, bytes, meta) async {
        saved.add({'name': name, 'bytes': bytes, 'meta': meta});
        return '/tmp/$name.png';
      },
    );

    final pending = sendDeeplink(
      tester,
      'pet-engine-example://capture?id=primitives&name=shot&delay=0',
    );
    for (var i = 0; i < 60 && saved.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(saved, hasLength(1));
    expect(hiddenDuringCapture, isTrue);
    await tester.pumpAndSettle();
    await pending;
    await tester.pumpAndSettle();

    expect(saved.first['name'], 'shot');
    expect(saved.first['bytes'], fakeBytes);
    final meta = saved.first['meta']! as Map<String, Object?>;
    expect(meta['featureId'], 'primitives');
    expect(meta['ready'], isTrue);
    expect(meta['region'], kScreenshotRegionWindow);
    // Панели вернулись после снимка.
    expect(find.byKey(const Key('nav-list')), findsOneWidget);
  });
}

/// Отправляет URL диплинка в приложение через канал macOS.
Future<void> sendDeeplink(WidgetTester tester, String url) {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('open', url),
  );
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    kDeeplinkChannel.name,
    message,
    (_) {},
  );
}
