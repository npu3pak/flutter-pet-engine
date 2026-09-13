import 'package:flutter_test/flutter_test.dart';
import 'package:scene_editor/src/deeplink.dart';

void main() {
  group('parseDeeplink', () {
    test('model opens a project and a model', () {
      final command = parseDeeplink(
        Uri.parse('pet-scene-editor://model?project=/tmp/Pet&id=model_1'),
      );
      expect(command, isA<OpenModelCommand>());
      final open = command! as OpenModelCommand;
      expect(open.projectPath, '/tmp/Pet');
      expect(open.modelId, 'model_1');
    });

    test('capture parses name, region and delay', () {
      final command = parseDeeplink(
        Uri.parse(
          'pet-scene-editor://capture?id=model_2&name=shot&region=viewport&delay=500',
        ),
      );
      final capture = command! as CaptureCommand;
      expect(capture.name, 'shot');
      expect(capture.modelId, 'model_2');
      expect(capture.region, kScreenshotRegionViewport);
      expect(capture.delayMs, 500);
      expect(capture.panelsHidden, isTrue);
    });

    test('unknown scheme, host and missing fields return null', () {
      expect(parseDeeplink(Uri.parse('other://model')), isNull);
      expect(parseDeeplink(Uri.parse('pet-scene-editor://nope')), isNull);
      expect(parseDeeplink(Uri.parse('pet-scene-editor://capture')), isNull);
      expect(parseDeeplink(Uri.parse('pet-scene-editor://screen')), isNull);
    });

    test('settings and screen commands', () {
      expect(
        parseDeeplink(Uri.parse('pet-scene-editor://screen?name=start')),
        isA<OpenScreenCommand>(),
      );
      final settings = parseDeeplink(
        Uri.parse('pet-scene-editor://settings?ssao=1'),
      );
      expect(settings, isA<SettingsCommand>());
      expect((settings! as SettingsCommand).values['ssao'], '1');
    });
  });

  group('helpers', () {
    test('sanitizeScreenshotName keeps a safe alphabet', () {
      expect(sanitizeScreenshotName('model 1'), 'model_1');
      expect(sanitizeScreenshotName(''), 'screenshot');
      expect(sanitizeScreenshotName('Модель 1'), isNot(contains('М')));
    });

    test('inferParamValue reads numbers and booleans', () {
      expect(inferParamValue('true'), isTrue);
      expect(inferParamValue('3'), 3);
      expect(inferParamValue('1.5'), 1.5);
      expect(inferParamValue('abc'), 'abc');
    });

    test('describeDeeplinkCommand covers every command', () {
      expect(
        describeDeeplinkCommand(
          const OpenModelCommand(projectPath: '/p', modelId: 'm'),
        ),
        contains('/p'),
      );
      expect(
        describeDeeplinkCommand(const ScreenshotCommand(name: 's')),
        contains('screenshot s'),
      );
      expect(
        describeDeeplinkCommand(const OpenScreenCommand(screen: 'start')),
        contains('start'),
      );
    });
  });
}
