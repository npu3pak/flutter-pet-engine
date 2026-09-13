import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Приложения не импортируют типы форка и внутренности движка: публичный
/// контракт — только `package:pet_engine_v2/pet_engine_v2.dart` (и
/// `models.dart`). Этот тест — страж границы.
void main() {
  test('в scene_editor/lib нет импортов flutter_scene и src движка', () {
    final root = Directory('lib');
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('package:flutter_scene/')) {
        offenders.add('${entity.path}: package:flutter_scene');
      }
      if (text.contains('package:pet_engine_v2/src/')) {
        offenders.add('${entity.path}: package:pet_engine_v2/src/');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
