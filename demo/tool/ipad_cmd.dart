// Управление постоянной debug-сессией приложения-примера на iPad.
//
// Сессию запускает `tool/ipad_session.sh start`: `flutter run --machine`
// читает JSON-команды из FIFO `temp/ipad/machine_in` и пишет события в
// `temp/ipad/machine.log`. Этот инструмент шлёт команды и забирает снимки.
//
// Использование (из demo):
//   fvm dart run tool/ipad_cmd.dart scene <фича> [ключ=значение …]
//   fvm dart run tool/ipad_cmd.dart capture <фича> <имя> [ключ=значение …]
//   fvm dart run tool/ipad_cmd.dart shot <имя> [delay=…] [region=…]
//   fvm dart run tool/ipad_cmd.dart reload    # hot reload
//   fvm dart run tool/ipad_cmd.dart restart   # hot restart
//   fvm dart run tool/ipad_cmd.dart stop      # остановить приложение и сессию
//
// Снимки сохраняются в pet_engine/temp/screenshots.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _extension = 'ext.example.deeplink';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(1);
  }
  final repoRoot = File.fromUri(Platform.script).parent.parent.parent.parent;
  final state = _MachineState(
    log: File('${repoRoot.path}/temp/ipad/machine.log'),
    fifo: File('${repoRoot.path}/temp/ipad/machine_in'),
    appIdFile: File('${repoRoot.path}/temp/ipad/app_id.txt'),
    shotsDir: Directory('${repoRoot.path}/temp/screenshots'),
  );
  if (!state.log.existsSync() || !state.fifo.existsSync()) {
    stderr.writeln(
      'Сессия не найдена. Запустите: tool/ipad_session.sh start',
    );
    exit(1);
  }

  final command = args.first;
  final rest = args.sublist(1);
  switch (command) {
    case 'reload':
      await state.restart(full: false);
      stdout.writeln('hot reload выполнен');
    case 'restart':
      await state.restart(full: true);
      stdout.writeln('hot restart выполнен');
    case 'stop':
      await state.stop();
      stdout.writeln('сессия остановлена');
    case 'scene':
      await state.deeplink('scene', rest);
    case 'settings':
      await state.deeplink('settings', rest);
    case 'capture':
      await state.deeplink('capture', rest, savePng: true);
    case 'shot':
      await state.deeplink('screenshot', rest, savePng: true);
    default:
      _usage();
      exit(1);
  }
}

void _usage() {
  stderr.writeln(
    'Использование: ipad_cmd.dart scene|capture|shot|reload|restart|stop …',
  );
}

class _MachineState {
  _MachineState({
    required this.log,
    required this.fifo,
    required this.appIdFile,
    required this.shotsDir,
  });

  final File log;
  final File fifo;
  final File appIdFile;
  final Directory shotsDir;

  int _nextId = 1;
  int _logOffset = 0;
  String _buffer = '';
  String? appId;

  /// Выполняет команду диплинка; при [savePng] сохраняет снимок в
  /// temp/screenshots и печатает путь.
  Future<void> deeplink(
    String kind,
    List<String> args, {
    bool savePng = false,
  }) async {
    final url = _buildUrl(kind, args);
    if (url == null) {
      _usage();
      exit(1);
    }
    await _ensureAppId();
    final id = _nextId++;
    _writeCommand({
      'method': 'app.callServiceExtension',
      'id': id,
      'params': {
        'appId': appId,
        'methodName': _extension,
        'params': {'url': url},
      },
    });
    final response = await _waitForId(id);
    final error = response['error'];
    if (error != null) {
      stderr.writeln('Ошибка команды: $error');
      exit(1);
    }
    final result = _decodeResult(response['result']);
    if (result['ok'] != true) {
      stderr.writeln('Команда не выполнена: ${result['error']}');
      exit(1);
    }
    if (!savePng) {
      stdout.writeln('ok');
      return;
    }
    final png = result['png'];
    if (png is! String) {
      stderr.writeln('В ответе нет PNG');
      exit(1);
    }
    final name = (result['name'] as String?) ?? 'screenshot';
    final file = await _saveScreenshot(name, png, result['meta']);
    stdout.writeln(file.path);
  }

  Future<void> restart({required bool full}) async {
    await _ensureAppId();
    final id = _nextId++;
    _writeCommand({
      'method': 'app.restart',
      'id': id,
      'params': {
        'appId': appId,
        'fullRestart': full,
        'reason': 'manual',
      },
    });
    await _waitForId(id);
  }

  Future<void> stop() async {
    await _ensureAppId();
    final stopId = _nextId++;
    _writeCommand({
      'method': 'app.stop',
      'id': stopId,
      'params': {'appId': appId},
    });
    await _waitForId(stopId, timeout: const Duration(seconds: 30));
    final shutdownId = _nextId++;
    _writeCommand({
      'method': 'daemon.shutdown',
      'id': shutdownId,
      'params': const <String, Object?>{},
    });
    await _waitForId(shutdownId, timeout: const Duration(seconds: 30));
  }

  /// Собирает URL диплинка: позиционные аргументы превращаются в `id`/`name`,
  /// остальные передаются как параметры сцены.
  String? _buildUrl(String kind, List<String> args) {
    final query = <String>[];
    switch (kind) {
      case 'scene':
        if (args.isEmpty) return null;
        query.add('id=${args.first}');
        query.addAll(args.sublist(1));
      case 'capture':
        if (args.length < 2) return null;
        query.add('id=${args[0]}');
        query.add('name=${args[1]}');
        query.addAll(args.sublist(2));
      case 'screenshot':
        if (args.isEmpty) return null;
        query.add('name=${args.first}');
        query.addAll(args.sublist(1));
      case 'settings':
        if (args.isEmpty) return null;
        query.addAll(args);
      default:
        return null;
    }
    return 'pet-engine-example://$kind?${query.join('&')}';
  }

  Future<void> _ensureAppId() async {
    if (appId != null) return;
    if (appIdFile.existsSync()) {
      final saved = appIdFile.readAsStringSync().trim();
      if (saved.isNotEmpty) appId = saved;
    }
    if (appId != null) return;
    stdout.writeln('Ожидание запуска приложения на iPad…');
    final deadline = DateTime.now().add(const Duration(seconds: 300));
    while (appId == null && DateTime.now().isBefore(deadline)) {
      _drainEvents();
      if (appId == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (appId == null) {
      stderr.writeln('В журнале сессии нет события app.start');
      exit(1);
    }
  }

  void _writeCommand(Map<String, Object?> command) {
    fifo.writeAsStringSync('${jsonEncode([command])}\n', flush: true);
  }

  Future<Map<String, Object?>> _waitForId(
    int id, {
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final event in _drainEvents()) {
        if (event['id'] == id) {
          _truncateLog();
          return event;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Таймаут ответа на команду $id');
  }

  /// Очищает журнал после прочитанного ответа: ответы с PNG весят много, а
  /// журнал нужен только до следующей команды. `flutter run` пишет в конец
  /// файла (append), поэтому после очистки запись продолжается корректно.
  void _truncateLog() {
    try {
      log.writeAsStringSync('');
      _logOffset = 0;
      _buffer = '';
    } on FileSystemException {
      // Не критично: журнал просто продолжит расти.
    }
  }

  /// Читает новые строки журнала и разбирает события.
  List<Map<String, Object?>> _drainEvents() {
    final raf = log.openSync();
    try {
      final length = raf.lengthSync();
      if (length > _logOffset) {
        raf.setPositionSync(_logOffset);
        final bytes = raf.readSync(length - _logOffset);
        _logOffset = length;
        _buffer += utf8.decode(bytes, allowMalformed: true);
      }
    } finally {
      raf.closeSync();
    }
    final events = <Map<String, Object?>>[];
    var index = _buffer.indexOf('\n');
    while (index >= 0) {
      final line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      if (line.isNotEmpty) {
        final event = _decodeLine(line);
        if (event != null) {
          if (event['event'] == 'app.start') {
            final params = event['params'];
            if (params is Map && params['appId'] is String) {
              appId = params['appId'] as String;
              try {
                appIdFile.writeAsStringSync(appId!);
              } on FileSystemException {
                // Не критично: идентификатор прочитается из журнала.
              }
            }
          }
          events.add(event);
        }
      }
      index = _buffer.indexOf('\n');
    }
    return events;
  }

  Map<String, Object?>? _decodeLine(String line) {
    var text = line;
    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Строка не JSON — это обычный вывод, пропускаем.
    }
    return null;
  }

  /// Результат сервис-расширения приходит строкой JSON, но некоторые версии
  /// тулинга отдают уже разобранную карту — поддерживаем оба вида.
  Map<String, Object?> _decodeResult(Object? result) {
    if (result is String) {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    if (result is Map) {
      if (result['data'] is String) {
        final decoded = jsonDecode(result['data'] as String);
        if (decoded is Map<String, dynamic>) return decoded;
      }
      return result.cast<String, Object?>();
    }
    return const {'ok': false, 'error': 'пустой ответ'};
  }

  Future<File> _saveScreenshot(
    String name,
    String base64Png,
    Object? meta,
  ) async {
    await shotsDir.create(recursive: true);
    final file = File('${shotsDir.path}/$name.png');
    await file.writeAsBytes(base64Decode(base64Png), flush: true);
    final data = <String, Object?>{
      'name': name,
      'file': file.path,
      if (meta is Map) ...meta.cast<String, Object?>(),
    };
    await File(
      '${shotsDir.path}/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }
}
