import 'dart:io';

import 'package:example/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('версия приложения совпадает с pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'в pubspec.yaml нет строки version');
    expect(kDemoAppVersion, match!.group(1));
  });
}
