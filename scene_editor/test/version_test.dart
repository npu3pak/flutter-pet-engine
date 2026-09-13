import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene_editor/src/version.dart';

void main() {
  test('версия приложения совпадает с pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'в pubspec.yaml нет version');
    expect(match!.group(1), kSceneEditorAppVersion);
  });
}
