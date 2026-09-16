import 'dart:convert';
import 'dart:io';

import 'package:example/src/visual/visual_tests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clock = DateTime.utc(2026, 9, 10, 21);

  VisualTestStore storeIn(File file) =>
      VisualTestStore(file: file, clock: () => clock);

  File tempFile(String name) {
    final dir = Directory('temp/visual_tests');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$name');
    if (file.existsSync()) file.deleteSync();
    return file;
  }

  test('отсутствующий файл — пустая структура без ошибки', () {
    final store = storeIn(tempFile('missing.json'));
    store.load();
    expect(store.loadError, isNull);
    expect(store.data.checks, isEmpty);
    expect(store.data.bugs, isEmpty);
  });

  test('повреждённый файл не роняет приложение', () {
    final file = tempFile('broken.json')..writeAsStringSync('{не json');
    final store = storeIn(file);
    store.load();
    expect(store.loadError, isNotNull);
    expect(store.data.checks, isEmpty);
  });

  test('ответ «корректно» помечает фичу проверенной', () {
    final store = storeIn(tempFile('ok.json'));
    expect(
      store.setCheck(
        featureId: 'weather_rain',
        ok: true,
        phase: 2,
        version: 'app 0.2.0 · engine 0.1.0+1 · commit abc',
      ),
      isNull,
    );
    expect(store.statusOf('weather_rain'), VisualStatus.ok);
    final reloaded = storeIn(File(store.path))..load();
    expect(reloaded.statusOf('weather_rain'), VisualStatus.ok);
    expect(reloaded.check('weather_rain')!.phase, 2);
    expect(reloaded.check('weather_rain')!.version, contains('engine'));
  });

  test(
    'ответ «есть замечание» создаёт замечание и статус «есть замечания»',
    () {
      final store = storeIn(tempFile('issue.json'));
      store.setCheck(
        featureId: 'weather_rain',
        ok: false,
        comment: 'капли слишком крупные',
        phase: 2,
        version: 'v1',
      );
      expect(store.statusOf('weather_rain'), VisualStatus.issue);
      expect(store.openBugCount('weather_rain'), 1);
      final bug = store.bugsOf('weather_rain').single;
      expect(bug.status, BugStatus.open);
      expect(bug.events.single.kind, BugEventKind.reported);
      expect(bug.events.single.text, 'капли слишком крупные');
      expect(bug.events.single.status, BugStatus.open);
    },
  );

  test('история замечания: исправлено, вернулось, сообщения', () {
    final store = storeIn(tempFile('history.json'));
    store.reportBug(featureId: 'fog', text: 'дымка мигает', version: 'v1');
    final bug = store.bugsOf('fog').single;
    store.addMessage(bugId: bug.id, text: 'проверил на улице', version: 'v2');
    store.markFixed(bugId: bug.id, version: 'v2');
    expect(store.bug(bug.id)!.status, BugStatus.fixed);
    expect(store.openBugCount('fog'), 0);
    expect(store.hasBugs('fog'), isTrue);

    store.reopenBug(bugId: bug.id, text: 'вернулось', version: 'v3');
    expect(store.bug(bug.id)!.status, BugStatus.open);
    final events = store.bug(bug.id)!.events;
    expect(events.map((e) => e.kind), [
      BugEventKind.reported,
      BugEventKind.message,
      BugEventKind.fixed,
      BugEventKind.reopened,
    ]);
    expect(events.first.status, BugStatus.open);
    expect(events[2].status, BugStatus.fixed);
  });

  test('заметка агента не показывается пользователю, но хранится', () {
    final store = storeIn(tempFile('agent.json'));
    store.reportBug(featureId: 'x', text: 'баг', version: 'v1');
    final bug = store.bugsOf('x').single;
    store.addMessage(
      bugId: bug.id,
      text: 'уменьшил спрайт, пересобрал атлас',
      version: 'v2',
      author: 'agent',
    );
    final events = store.bug(bug.id)!.events;
    expect(events.last.kind, BugEventKind.note);
    expect(events.last.author, 'agent');
    expect(events.where((e) => e.author == 'user').length, 1);
  });

  test('номер замечания растёт и не повторяется', () {
    final store = storeIn(tempFile('ids.json'));
    store.reportBug(featureId: 'a', text: 'первый', version: 'v1');
    store.reportBug(featureId: 'b', text: 'второй', version: 'v1');
    expect(store.data.bugs.map((b) => b.id), ['bug_1', 'bug_2']);
  });

  test('формат файла соответствует разделу 12 плана', () {
    final file = tempFile('format.json');
    final store = storeIn(file);
    store.reportBug(featureId: 'weather_rain', text: 'капли', version: 'v1');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(json['version'], 2);
    expect(json['bugs'], isA<List>());
    final bug = (json['bugs'] as List).single as Map<String, Object?>;
    expect(bug['id'], 'bug_1');
    expect(bug['featureId'], 'weather_rain');
    expect(bug['status'], 'open');
    final event = (bug['events'] as List).single as Map<String, Object?>;
    expect(event['author'], 'user');
    expect(event['kind'], 'reported');
    expect(event['status'], 'open');
    expect(event['version'], 'v1');
  });

  test('статус без ответа и без замечаний — не проверена', () {
    final store = storeIn(tempFile('none.json'));
    expect(store.statusOf('unknown'), VisualStatus.notChecked);
  });
}
