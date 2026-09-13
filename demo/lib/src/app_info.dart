import 'dart:io';
import 'dart:math' as math;

import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'paths.dart';
import 'version.dart';

/// Сведения о версиях и платформе для раздела «О приложении» и для записей
/// в `visual_tests.json`.
///
/// Версия приложения и движка — константы пакетов, остальное передаётся при
/// запуске ключами `pet.flutter`, `pet.commit`, `pet.buildDate`; если ключ не
/// передан, показывается «неизвестно».
class AppInfo {
  const AppInfo({
    required this.appVersion,
    required this.engineVersion,
    required this.flutterVersion,
    required this.dartVersion,
    required this.platform,
    required this.gpu,
    required this.commit,
    required this.buildDate,
    required this.changelog,
  });

  final String appVersion;
  final String engineVersion;
  final String flutterVersion;
  final String dartVersion;
  final String platform;
  final String gpu;
  final String commit;
  final String buildDate;

  /// Содержимое `engine/CHANGELOG.md` или встроенный краткий текст.
  final String changelog;

  static const String _flutterDefine = String.fromEnvironment('pet.flutter');
  static const String _commitDefine = String.fromEnvironment('pet.commit');
  static const String _buildDateDefine = String.fromEnvironment(
    'pet.buildDate',
  );

  /// Строка версий для записей проверок:
  /// `app 0.1.0 · engine 0.1.0-dev.1 · commit abc1234`.
  String get versionLine =>
      'app $appVersion · engine $engineVersion · commit $shortCommit';

  String get shortCommit {
    if (commit.isEmpty) return 'неизвестно';
    return commit.length <= 8 ? commit : commit.substring(0, 8);
  }

  String get flutterVersionLabel =>
      flutterVersion.isEmpty ? 'неизвестно' : flutterVersion;

  String get buildDateLabel => buildDate.isEmpty ? 'неизвестно' : buildDate;

  /// Собирает сведения; историю изменений читает с диска, при неудаче
  /// подставляет краткий встроенный текст.
  factory AppInfo.collect({required AppPaths paths}) {
    var changelog = _changelogFallback;
    try {
      if (paths.changelogFile.existsSync()) {
        changelog = paths.changelogFile.readAsStringSync().trim();
      }
    } on FileSystemException {
      // Оставляем встроенный текст.
    }
    return AppInfo(
      appVersion: kDemoAppVersion,
      engineVersion: kPetEngineVersion,
      flutterVersion: _flutterDefine,
      dartVersion: _dartVersion(),
      platform: _platformLabel(),
      gpu: detectGpuBackend().label,
      commit: _commitDefine,
      buildDate: _buildDateDefine,
      changelog: changelog,
    );
  }

  static String _dartVersion() {
    final v = Platform.version.split(' ').first;
    return v.isEmpty ? 'неизвестно' : v;
  }

  static String _platformLabel() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  static const String _changelogFallback =
      'История изменений недоступна: файл engine/CHANGELOG.md не найден.';
}

/// Укорачивает длинную строку версии для узких мест интерфейса.
String shorten(String value, int max) => value.length <= max
    ? value
    : '${value.substring(0, math.max(0, max - 1))}…';
