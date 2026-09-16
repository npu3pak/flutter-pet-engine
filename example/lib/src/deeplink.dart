import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Схема диплинков приложения-примера: `pet-engine-example://…`.
const String kDeeplinkScheme = 'pet-engine-example';

/// Канал, по которому обвязка macOS передаёт приложению открытые URL.
const MethodChannel kDeeplinkChannel = MethodChannel('example/deeplink');

/// Регион снимка: всё окно приложения.
const String kScreenshotRegionWindow = 'window';

/// Регион снимка: только трёхмерная рабочая область.
const String kScreenshotRegionViewport = 'viewport';

/// Пауза перед снимком по умолчанию: сцена готова, но текстуры ещё
/// догружаются.
const int kScreenshotDefaultDelayMs = 2000;

/// Разобранная команда диплинка.
sealed class DeeplinkCommand {
  const DeeplinkCommand();
}

/// `pet-engine-example://scene?id=<фича>&<параметр>=<значение>…` —
/// открыть сцену возможности движка.
final class OpenSceneCommand extends DeeplinkCommand {
  const OpenSceneCommand({
    required this.featureId,
    this.params = const {},
    this.panelsHidden = false,
  });

  final String featureId;
  final Map<String, Object?> params;

  /// Скрыть панели интерфейса и оставить только рабочую область.
  final bool panelsHidden;
}

/// `pet-engine-example://screenshot?name=<имя>&delay=<мс>&region=…` —
/// снять текущее состояние приложения.
final class ScreenshotCommand extends DeeplinkCommand {
  const ScreenshotCommand({
    this.name,
    this.region = kScreenshotRegionWindow,
    this.delayMs = kScreenshotDefaultDelayMs,
    this.scale,
    this.panelsHidden = true,
  });

  /// Имя файла без расширения; по умолчанию — идентификатор фичи.
  final String? name;

  /// `window` (всё окно) или `viewport` (только рабочая область).
  final String region;

  /// Пауза перед снимком, миллисекунды.
  final int delayMs;

  /// Масштаб снимка; null — плотность пикселей экрана.
  final double? scale;

  /// Скрыть панели интерфейса перед снимком.
  final bool panelsHidden;
}

/// `pet-engine-example://capture?id=<фича>&name=<имя>&…` — открыть сцену и
/// сразу снять её (удобно для автоматического прогона).
final class CaptureCommand extends DeeplinkCommand {
  const CaptureCommand({
    required this.featureId,
    required this.name,
    this.params = const {},
    this.region = kScreenshotRegionWindow,
    this.delayMs = kScreenshotDefaultDelayMs,
    this.scale,
    this.panelsHidden = true,
  });

  final String featureId;
  final String name;
  final Map<String, Object?> params;
  final String region;
  final int delayMs;
  final double? scale;
  final bool panelsHidden;
}

/// `pet-engine-example://screen?name=checklist|about` — открыть служебный
/// экран приложения.
final class OpenScreenCommand extends DeeplinkCommand {
  const OpenScreenCommand({required this.screen});

  /// Имя экрана: `checklist` или `about`.
  final String screen;
}

/// `pet-engine-example://settings?fog=1&fogStart=4&ssao=1…` — настройки
/// текущей сцены для визуальной проверки переключаемых возможностей.
final class SettingsCommand extends DeeplinkCommand {
  const SettingsCommand({required this.values});

  /// Значения настроек из строки запроса (имена совпадают с панелью
  /// настроек: `fog`, `fogStart`, `fogEnd`, `fogOpacity`, `fogColor`,
  /// `ssao`, `shadows`, `ambient`).
  final Map<String, String> values;
}

/// Ключи, которые не попадают в параметры фичи.
const Set<String> kDeeplinkReservedKeys = {
  'id',
  'name',
  'delay',
  'region',
  'scale',
  'screen',
  'panels',
};

/// Разбирает URL диплинка. Возвращает null, если схема или команда не
/// распознаны.
DeeplinkCommand? parseDeeplink(Uri uri) {
  if (uri.scheme != kDeeplinkScheme) return null;
  switch (uri.host) {
    case 'scene':
      final id = _clean(uri.queryParameters['id']);
      if (id == null) return null;
      return OpenSceneCommand(
        featureId: id,
        params: featureParams(uri.queryParameters),
        panelsHidden: _parsePanels(uri.queryParameters['panels'], false),
      );
    case 'screenshot':
      return ScreenshotCommand(
        name: _clean(uri.queryParameters['name']),
        region: parseScreenshotRegion(uri.queryParameters['region']),
        delayMs: _parseInt(
          uri.queryParameters['delay'],
          kScreenshotDefaultDelayMs,
        ),
        scale: _parseDouble(uri.queryParameters['scale']),
        panelsHidden: _parsePanels(uri.queryParameters['panels'], true),
      );
    case 'capture':
      final id = _clean(uri.queryParameters['id']);
      if (id == null) return null;
      return CaptureCommand(
        featureId: id,
        name: _clean(uri.queryParameters['name']) ?? id,
        params: featureParams(uri.queryParameters),
        region: parseScreenshotRegion(uri.queryParameters['region']),
        delayMs: _parseInt(
          uri.queryParameters['delay'],
          kScreenshotDefaultDelayMs,
        ),
        scale: _parseDouble(uri.queryParameters['scale']),
        panelsHidden: _parsePanels(uri.queryParameters['panels'], true),
      );
    case 'screen':
      final screen = _clean(uri.queryParameters['name']);
      if (screen == null) return null;
      return OpenScreenCommand(screen: screen);
    case 'settings':
      if (uri.queryParameters.isEmpty) return null;
      return SettingsCommand(values: Map.of(uri.queryParameters));
  }
  return null;
}

/// Скрывать ли панели интерфейса: `hide` — да, `show` — нет, иначе
/// [fallback].
bool _parsePanels(String? raw, bool fallback) => switch (raw) {
  'hide' => true,
  'show' => false,
  _ => fallback,
};

/// Регион снимка из строки запроса; неизвестное значение — всё окно.
String parseScreenshotRegion(String? raw) => raw == kScreenshotRegionViewport
    ? kScreenshotRegionViewport
    : kScreenshotRegionWindow;

/// Параметры фичи из строки запроса: все ключи, кроме зарезервированных.
/// Значения выводятся из текста: `true`/`false` — логическое, целое или
/// дробное число — число, остальное — строка.
Map<String, Object?> featureParams(Map<String, String> query) {
  final result = <String, Object?>{};
  query.forEach((key, value) {
    if (kDeeplinkReservedKeys.contains(key)) return;
    result[key] = inferParamValue(value);
  });
  return result;
}

/// Значение параметра из текста.
Object? inferParamValue(String raw) {
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  final intValue = int.tryParse(raw);
  if (intValue != null) return intValue;
  final doubleValue = double.tryParse(raw);
  if (doubleValue != null) return doubleValue;
  return raw;
}

/// Имя файла снимка: латиница, цифры, `_` и `-`; пустое — `screenshot`.
String sanitizeScreenshotName(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  return cleaned.isEmpty ? 'screenshot' : cleaned;
}

/// Принимает URL диплинков и выполняет команды по очереди: следующая
/// команда ждёт завершения предыдущей, поэтому снимок всегда относится к
/// уже собранной сцене.
class DeeplinkController {
  DeeplinkController({MethodChannel? channel, this.onLog})
    : _channel = channel ?? kDeeplinkChannel;

  final MethodChannel _channel;

  /// Сообщение для журнала (stdout и `temp/deeplink.log`).
  final void Function(String message)? onLog;

  /// Обработчик команд; завершение Future означает, что команда выполнена.
  Future<void> Function(DeeplinkCommand command)? onCommand;

  final List<DeeplinkCommand> _queue = [];
  bool _processing = false;
  bool _started = false;

  /// Подписывается на канал macOS/iOS и сообщает обвязке, что обработчик
  /// готов: до этого URL копятся в нативной очереди (холодный старт).
  void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onCall);
    unawaited(
      _channel.invokeMethod<void>('ready').then((_) {}, onError: (_) {}),
    );
  }

  /// Отписывается от канала.
  void dispose() {
    _channel.setMethodCallHandler(null);
    _queue.clear();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'open') return;
    final raw = call.arguments;
    if (raw is! String) return;
    await handleRawUrl(raw);
  }

  /// Разбирает URL и ставит команду в очередь (используется и тестами).
  Future<void> handleRawUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      _log('не разобран URL: $raw');
      return;
    }
    final command = parseDeeplink(uri);
    if (command == null) {
      _log('неизвестная команда: $raw');
      return;
    }
    _queue.add(command);
    await _drain();
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final command = _queue.removeAt(0);
        _log('команда: ${describeDeeplinkCommand(command)}');
        try {
          await onCommand?.call(command);
        } catch (error) {
          _log('ошибка команды: $error');
        }
      }
    } finally {
      _processing = false;
    }
  }

  void _log(String message) => onLog?.call('[deeplink] $message');
}

/// Текст команды для журнала.
String describeDeeplinkCommand(DeeplinkCommand command) {
  return switch (command) {
    OpenSceneCommand(:final featureId, :final params, :final panelsHidden) =>
      'scene $featureId ${jsonEncode(params)} panels=${panelsHidden ? 'hide' : 'show'}',
    ScreenshotCommand(
      :final name,
      :final region,
      :final delayMs,
      :final panelsHidden,
    ) =>
      'screenshot ${name ?? '—'} region=$region delay=$delayMs panels=${panelsHidden ? 'hide' : 'show'}',
    CaptureCommand(:final featureId, :final name, :final panelsHidden) =>
      'capture $featureId → $name panels=${panelsHidden ? 'hide' : 'show'}',
    OpenScreenCommand(:final screen) => 'screen $screen',
    SettingsCommand(:final values) => 'settings ${jsonEncode(values)}',
  };
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

int _parseInt(String? raw, int fallback) =>
    raw == null ? fallback : (int.tryParse(raw) ?? fallback);

double? _parseDouble(String? raw) => raw == null ? null : double.tryParse(raw);
