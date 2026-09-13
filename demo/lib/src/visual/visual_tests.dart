import 'dart:convert';
import 'dart:io';

/// Состояние проверки фичи в анкете.
enum CheckStatus { ok, issue }

/// Состояние замечания.
enum BugStatus { open, fixed }

/// Вид события в истории замечания.
enum BugEventKind { reported, note, fixed, reopened, message }

/// Запись анкеты по одной фиче (ключ `checks` в файле проверок).
class CheckRecord {
  CheckRecord({
    required this.status,
    this.comment = '',
    required this.updatedAt,
    required this.phase,
    required this.version,
  });

  CheckStatus status;
  String comment;
  DateTime updatedAt;
  int phase;

  /// Строка версий на момент ответа.
  String version;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'comment': comment,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'phase': phase,
    'version': version,
  };

  factory CheckRecord.fromJson(Object? json) {
    final map = (json as Map?) ?? const {};
    return CheckRecord(
      status: map['status'] == 'issue' ? CheckStatus.issue : CheckStatus.ok,
      comment: (map['comment'] as String?) ?? '',
      updatedAt:
          DateTime.tryParse((map['updatedAt'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      phase: map['phase'] is num ? (map['phase'] as num).toInt() : 0,
      version: (map['version'] as String?) ?? '',
    );
  }
}

/// Одно событие журнала замечания.
class BugEvent {
  BugEvent({
    required this.at,
    required this.author,
    required this.kind,
    this.text = '',
    this.status,
    this.version = '',
  });

  DateTime at;

  /// `user` или `agent`.
  String author;
  BugEventKind kind;
  String text;
  BugStatus? status;
  String version;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'author': author,
    'kind': kind.name,
    if (text.isNotEmpty) 'text': text,
    if (status != null) 'status': status!.name,
    if (version.isNotEmpty) 'version': version,
  };

  factory BugEvent.fromJson(Object? json) {
    final map = (json as Map?) ?? const {};
    return BugEvent(
      at:
          DateTime.tryParse((map['at'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      author: (map['author'] as String?) ?? 'user',
      kind: BugEventKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => BugEventKind.message,
      ),
      text: (map['text'] as String?) ?? '',
      status: switch (map['status']) {
        'open' => BugStatus.open,
        'fixed' => BugStatus.fixed,
        _ => null,
      },
      version: (map['version'] as String?) ?? '',
    );
  }
}

/// Замечание с историей событий.
class BugRecord {
  BugRecord({
    required this.id,
    required this.featureId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    List<BugEvent>? events,
  }) : events = events ?? [];

  String id;
  String featureId;
  BugStatus status;
  DateTime createdAt;
  DateTime updatedAt;
  List<BugEvent> events;

  Map<String, Object?> toJson() => {
    'id': id,
    'featureId': featureId,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'events': [for (final e in events) e.toJson()],
  };

  factory BugRecord.fromJson(Object? json) {
    final map = (json as Map?) ?? const {};
    return BugRecord(
      id: (map['id'] as String?) ?? 'bug_0',
      featureId: (map['featureId'] as String?) ?? '',
      status: map['status'] == 'fixed' ? BugStatus.fixed : BugStatus.open,
      createdAt:
          DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse((map['updatedAt'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      events: [
        if (map['events'] is List)
          for (final e in map['events'] as List) BugEvent.fromJson(e),
      ],
    );
  }
}

/// Содержимое файла `visual_tests.json` (раздел 12 плана).
class VisualTestsData {
  VisualTestsData({
    this.version = 2,
    DateTime? updated,
    this.appVersion = '',
    this.engineVersion = '',
    this.platform = '',
    Map<String, CheckRecord>? checks,
    List<BugRecord>? bugs,
  }) : updated = updated ?? DateTime.now().toUtc(),
       checks = checks ?? {},
       bugs = bugs ?? [];

  int version;
  DateTime updated;
  String appVersion;
  String engineVersion;
  String platform;
  Map<String, CheckRecord> checks;
  List<BugRecord> bugs;

  Map<String, Object?> toJson() => {
    'version': version,
    'updated': updated.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'engineVersion': engineVersion,
    'platform': platform,
    'checks': {
      for (final entry in checks.entries) entry.key: entry.value.toJson(),
    },
    'bugs': [for (final bug in bugs) bug.toJson()],
  };

  factory VisualTestsData.fromJson(Object? json) {
    final map = (json as Map?) ?? const {};
    final checks = <String, CheckRecord>{};
    if (map['checks'] is Map) {
      for (final entry in (map['checks'] as Map).entries) {
        checks['${entry.key}'] = CheckRecord.fromJson(entry.value);
      }
    }
    return VisualTestsData(
      version: map['version'] is num ? (map['version'] as num).toInt() : 2,
      updated:
          DateTime.tryParse((map['updated'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      appVersion: (map['appVersion'] as String?) ?? '',
      engineVersion: (map['engineVersion'] as String?) ?? '',
      platform: (map['platform'] as String?) ?? '',
      checks: checks,
      bugs: [
        if (map['bugs'] is List)
          for (final bug in map['bugs'] as List) BugRecord.fromJson(bug),
      ],
    );
  }
}

/// Отображаемый статус фичи в списке проверок.
enum VisualStatus { notChecked, ok, issue }

/// Хранилище проверок и замечаний: читает и пишет `visual_tests.json`.
class VisualTestStore {
  VisualTestStore({required this.file, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final File file;
  final DateTime Function() _clock;
  final VisualTestsData data = VisualTestsData();

  /// Текст ошибки чтения (null — файл прочитан или отсутствует).
  String? loadError;

  /// Имя текущего файла (для интерфейса).
  String get path => file.path;

  /// Читает файл; отсутствующий файл — пустая структура, повреждённый —
  /// пустая структура и [loadError].
  void load() {
    loadError = null;
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      final loaded = VisualTestsData.fromJson(json);
      data
        ..version = loaded.version
        ..updated = loaded.updated
        ..appVersion = loaded.appVersion
        ..engineVersion = loaded.engineVersion
        ..platform = loaded.platform;
      data.checks.addAll(loaded.checks);
      data.bugs.addAll(loaded.bugs);
    } on FormatException catch (e) {
      loadError = 'Файл проверок повреждён: ${e.message}';
    } on FileSystemException catch (e) {
      loadError = 'Файл проверок недоступен: ${e.message}';
    }
  }

  /// Записывает файл (сначала во временный, затем заменой).
  String? save() {
    try {
      data.updated = _clock().toUtc();
      final text = const JsonEncoder.withIndent('  ').convert(data.toJson());
      final tmp = File('${file.path}.tmp');
      tmp.parent.createSync(recursive: true);
      tmp.writeAsStringSync(text, flush: true);
      tmp.renameSync(file.path);
      return null;
    } on FileSystemException catch (e) {
      return 'Не удалось сохранить проверки: ${e.message}';
    }
  }

  // ── проверки ─────────────────────────────────────────────────────────

  CheckRecord? check(String featureId) => data.checks[featureId];

  /// Ответ анкеты. `ok = false` дополнительно создаёт замечание.
  String? setCheck({
    required String featureId,
    required bool ok,
    String comment = '',
    required int phase,
    required String version,
  }) {
    data.checks[featureId] = CheckRecord(
      status: ok ? CheckStatus.ok : CheckStatus.issue,
      comment: comment,
      updatedAt: _clock().toUtc(),
      phase: phase,
      version: version,
    );
    if (!ok && comment.trim().isNotEmpty) {
      reportBug(featureId: featureId, text: comment, version: version);
    }
    return save();
  }

  // ── замечания ────────────────────────────────────────────────────────

  /// Открытые замечания фичи.
  List<BugRecord> openBugs(String featureId) => [
    for (final bug in data.bugs)
      if (bug.featureId == featureId && bug.status == BugStatus.open) bug,
  ];

  /// Все замечания фичи (включая исправленные).
  List<BugRecord> bugsOf(String featureId) => [
    for (final bug in data.bugs)
      if (bug.featureId == featureId) bug,
  ];

  BugRecord? bug(String id) {
    for (final bug in data.bugs) {
      if (bug.id == id) return bug;
    }
    return null;
  }

  String? reportBug({
    required String featureId,
    required String text,
    required String version,
    String author = 'user',
  }) {
    final now = _clock().toUtc();
    final bug = BugRecord(
      id: _nextBugId(),
      featureId: featureId,
      status: BugStatus.open,
      createdAt: now,
      updatedAt: now,
      events: [
        BugEvent(
          at: now,
          author: author,
          kind: BugEventKind.reported,
          text: text,
          status: BugStatus.open,
          version: version,
        ),
      ],
    );
    data.bugs.add(bug);
    return save();
  }

  String? addMessage({
    required String bugId,
    required String text,
    required String version,
    String author = 'user',
  }) {
    final record = bug(bugId);
    if (record == null) return 'Замечание $bugId не найдено';
    final now = _clock().toUtc();
    record.events.add(
      BugEvent(
        at: now,
        author: author,
        kind: author == 'agent' ? BugEventKind.note : BugEventKind.message,
        text: text,
        version: version,
      ),
    );
    record.updatedAt = now;
    return save();
  }

  String? markFixed({required String bugId, required String version}) {
    final record = bug(bugId);
    if (record == null) return 'Замечание $bugId не найдено';
    final now = _clock().toUtc();
    record
      ..status = BugStatus.fixed
      ..updatedAt = now
      ..events.add(
        BugEvent(
          at: now,
          author: 'user',
          kind: BugEventKind.fixed,
          status: BugStatus.fixed,
          version: version,
        ),
      );
    return save();
  }

  String? reopenBug({
    required String bugId,
    required String text,
    required String version,
  }) {
    final record = bug(bugId);
    if (record == null) return 'Замечание $bugId не найдено';
    final now = _clock().toUtc();
    record
      ..status = BugStatus.open
      ..updatedAt = now
      ..events.add(
        BugEvent(
          at: now,
          author: 'user',
          kind: BugEventKind.reopened,
          text: text,
          status: BugStatus.open,
          version: version,
        ),
      );
    return save();
  }

  /// Отображаемый статус фичи: «есть замечания» при открытых замечаниях или
  /// ответе «есть замечание», «проверена» при ответе «корректно» без
  /// открытых замечаний, иначе «не проверена».
  VisualStatus statusOf(String featureId) {
    final record = data.checks[featureId];
    if (openBugs(featureId).isNotEmpty) return VisualStatus.issue;
    if (record == null) return VisualStatus.notChecked;
    return record.status == CheckStatus.issue
        ? VisualStatus.issue
        : VisualStatus.ok;
  }

  /// Число открытых замечаний фичи (для значка).
  int openBugCount(String featureId) => openBugs(featureId).length;

  /// Есть ли у фичи замечания вообще (для серого значка).
  bool hasBugs(String featureId) => bugsOf(featureId).isNotEmpty;

  String _nextBugId() {
    var max = 0;
    for (final bug in data.bugs) {
      final match = RegExp(r'bug_(\d+)$').firstMatch(bug.id);
      if (match != null) {
        final value = int.tryParse(match.group(1)!) ?? 0;
        if (value > max) max = value;
      }
    }
    return 'bug_${max + 1}';
  }
}
