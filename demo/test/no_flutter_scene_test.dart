import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('в demo/lib нет импортов flutter_scene и внутренних путей движка', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('package:flutter_scene') ||
          text.contains('package:pet_engine_v2/src/')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'приложение обязано использовать только публичный API',
    );
  });
}
