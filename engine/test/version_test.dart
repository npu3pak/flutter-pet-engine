import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';

void main() {
  test('kPetEngineVersion совпадает с версией в pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'в pubspec.yaml нет строки version');
    expect(kPetEngineVersion, match!.group(1));
  });

  test('engine/CHANGELOG.md существует и упоминает версию', () {
    final changelog = File('CHANGELOG.md');
    expect(changelog.existsSync(), isTrue,
        reason: 'нужен engine/CHANGELOG.md для раздела «О приложении»');
    expect(changelog.readAsStringSync(), contains(kPetEngineVersion));
  });
}
