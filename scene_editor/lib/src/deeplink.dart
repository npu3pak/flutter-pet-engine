import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Схема диплинков редактора: `pet-scene-editor://…`.
const String kDeeplinkScheme = 'pet-scene-editor';

/// Канал, по которому обвязка macOS/iOS передаёт редактору открытые URL.
const MethodChannel kDeeplinkChannel = MethodChannel('editor/deeplink');

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

/// `pet-scene-editor://model?project=<путь>&id=<модель>` — открыть проект и
/// модель.
final class OpenModelCommand extends DeeplinkCommand {
  const OpenModelCommand({
    required this.projectPath,
    this.modelId,
    this.select,
    this.mode,
  });

  /// Абсолютный путь к папке проекта; null — открыть последний/стартовый
  /// экран.
  final String? projectPath;

  /// Идентификатор модели; null — последняя открытая модель проекта.
  final String? modelId;

  /// Идентификатор объекта для выделения (визуальные проверки гизмо).
  final String? select;

  /// Режим редактора: compose|texture|lighting|markup.
  final String? mode;
}

/// `pet-scene-editor://screenshot?name=<имя>&delay=<мс>&region=…` — снять
/// текущее состояние редактора.
final class ScreenshotCommand extends DeeplinkCommand {
  const ScreenshotCommand({
    this.name,
    this.region = kScreenshotRegionWindow,
    this.delayMs = kScreenshotDefaultDelayMs,
    this.scale,
    this.panelsHidden = true,
  });

  final String? name;
  final String region;
  final int delayMs;
  final double? scale;
  final bool panelsHidden;
}

/// `pet-scene-editor://capture?project=<путь>&id=<модель>&name=<имя>` —
/// открыть модель и сразу снять её (автоматический прогон).
final class CaptureCommand extends DeeplinkCommand {
  const CaptureCommand({
    required this.name,
    this.projectPath,
    this.modelId,
    this.select,
    this.mode,
    this.region = kScreenshotRegionWindow,
    this.delayMs = kScreenshotDefaultDelayMs,
    this.scale,
    this.panelsHidden = true,
  });

  final String name;
  final String? projectPath;
  final String? modelId;

  /// Идентификатор объекта для выделения (визуальные проверки гизмо).
  final String? select;

  /// Режим редактора: compose|texture|lighting|markup.
  final String? mode;
  final String region;
  final int delayMs;
  final double? scale;
  final bool panelsHidden;
}

/// `pet-scene-editor://screen?name=start|about` — открыть служебный экран.
final class OpenScreenCommand extends DeeplinkCommand {
  const OpenScreenCommand({required this.screen});

  final String screen;
}

/// `pet-scene-editor://settings?fog=1&…` — настройки сцены для визуальной
/// проверки.
final class SettingsCommand extends DeeplinkCommand {
  const SettingsCommand({required this.values});

  final Map<String, String> values;
}

/// Ключи, которые не попадают в параметры команды.
const Set<String> kDeeplinkReservedKeys = {
  'id',
  'project',
  'select',
  'mode',
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
    case 'model':
      return OpenModelCommand(
        projectPath: _clean(uri.queryParameters['project']),
        modelId: _clean(uri.queryParameters['id']),
        select: _clean(uri.queryParameters['select']),
        mode: _clean(uri.queryParameters['mode']),
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
      final name = _clean(uri.queryParameters['name']);
      if (name == null) return null;
      return CaptureCommand(
        name: name,
        projectPath: _clean(uri.queryParameters['project']),
        modelId: _clean(uri.queryParameters['id']),
        select: _clean(uri.queryParameters['select']),
        mode: _clean(uri.queryParameters['mode']),
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

/// Параметры команды из строки запроса: все ключи, кроме зарезервированных.
Map<String, Object?> commandParams(Map<String, String> query) {
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

  /// Подписывается на канал и сообщает обвязке, что обработчик готов.
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
    OpenModelCommand(:final projectPath, :final modelId, :final select) =>
      'model project=${projectPath ?? '—'} id=${modelId ?? '—'} '
          'select=${select ?? '—'}',
    ScreenshotCommand(:final name, :final region, :final delayMs) =>
      'screenshot ${name ?? '—'} region=$region delay=$delayMs',
    CaptureCommand(:final name, :final projectPath, :final modelId,
          :final select) =>
      'capture ${modelId ?? '—'} → $name project=${projectPath ?? '—'} '
          'select=${select ?? '—'}',
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
