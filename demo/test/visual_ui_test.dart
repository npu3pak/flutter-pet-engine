import 'dart:io';

import 'package:demo/src/app_shell.dart';
import 'package:demo/src/features/feature_registry.dart';
import 'package:demo/src/paths.dart';
import 'package:demo/src/visual/visual_tests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppPaths visualPaths() {
    final dir = Directory('temp/visual_ui');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/visual_tests.json');
    if (file.existsSync()) file.deleteSync();
    return AppPaths(dir);
  }

  List<FeatureSpec> twoFeatures() => [
    testFeature(id: 'alpha', title: 'Альфа'),
    testFeature(id: 'beta', title: 'Бета'),
  ];

  Future<void> pumpVisualShell(WidgetTester tester, AppPaths paths) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          paths: paths,
          info: testInfo,
          host: FakeSceneHost(paths: paths),
          features: twoFeatures(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('список проверок фильтрует проверенные фичи', (tester) async {
    final paths = visualPaths();
    await pumpVisualShell(tester, paths);

    await tester.tap(find.byKey(const Key('nav-checklist')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-alpha')), findsOneWidget);
    expect(find.byKey(const Key('check-beta')), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-alpha')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('answer-ok')), findsOneWidget);

    await tester.tap(find.byKey(const Key('answer-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-alpha')), findsNothing);
    expect(find.byKey(const Key('check-beta')), findsOneWidget);

    await tester.tap(find.byKey(const Key('checklist-show-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check-alpha')), findsOneWidget);
    expect(find.text('фаза 1 · проверена'), findsOneWidget);
  });

  testWidgets('ответ «есть замечание» создаёт замечание', (tester) async {
    final paths = visualPaths();
    await pumpVisualShell(tester, paths);

    await tester.tap(find.byKey(const Key('nav-checklist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-beta')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('answer-issue')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('issue-text')),
      'капли слишком крупные',
    );
    await tester.ensureVisible(find.byKey(const Key('issue-save')));
    await tester.tap(find.byKey(const Key('issue-save')));
    await tester.pumpAndSettle();

    expect(find.text('фаза 1 · есть замечания'), findsOneWidget);

    final store = VisualTestStore(file: paths.visualTestsFile)..load();
    expect(store.openBugCount('beta'), 1);
    expect(store.check('beta')!.comment, 'капли слишком крупные');
    expect(store.check('beta')!.version, contains('engine'));
  });

  testWidgets('журнал: исправлено, вернулось, сообщение', (tester) async {
    final paths = visualPaths();
    await pumpVisualShell(tester, paths);

    // Открываем фичу и сообщаем о проблеме через кнопку-жука.
    await tester.tap(find.byKey(const Key('feature-alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bug-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bug-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('bug-new-text')),
      'мерцают стены',
    );
    await tester.tap(find.byKey(const Key('bug-new-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bug-bug_1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bug-bug_1')));
    await tester.pumpAndSettle();
    expect(find.text('мерцают стены'), findsWidgets);

    await tester.tap(find.byKey(const Key('bug-fixed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bug-reopen')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('bug-message')),
      'вернулось на слабом устройстве',
    );
    await tester.tap(find.byKey(const Key('bug-reopen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bug-fixed')), findsOneWidget);
    expect(find.text('вернулось на слабом устройстве'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('bug-message')),
      'дополнил описание',
    );
    await tester.tap(find.byKey(const Key('bug-message-save')));
    await tester.pumpAndSettle();
    expect(find.text('дополнил описание'), findsOneWidget);
  });

  testWidgets('заметки агента не показываются в журнале', (tester) async {
    final paths = visualPaths();
    final store = VisualTestStore(file: paths.visualTestsFile)
      ..load()
      ..reportBug(featureId: 'alpha', text: 'баг', version: 'v1');
    final bug = store.bugsOf('alpha').single;
    store.addMessage(
      bugId: bug.id,
      text: 'уменьшил спрайт, пересобрал атлас',
      version: 'v2',
      author: 'agent',
    );

    await pumpVisualShell(tester, paths);
    await tester.tap(find.byKey(const Key('feature-alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bug-button')));
    await tester.pumpAndSettle();
    expect(find.text('баг'), findsWidgets);
    expect(find.text('уменьшил спрайт, пересобрал атлас'), findsNothing);
  });

  testWidgets('значок жука у фичи отражает состояние', (tester) async {
    final paths = visualPaths();
    await pumpVisualShell(tester, paths);
    expect(find.byIcon(Icons.bug_report), findsNothing);

    await tester.tap(find.byKey(const Key('nav-checklist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-alpha')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('answer-issue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('issue-text')), 'ошибка');
    await tester.ensureVisible(find.byKey(const Key('issue-save')));
    await tester.tap(find.byKey(const Key('issue-save')));
    await tester.pumpAndSettle();

    // Значок жука появился у пункта «Альфа» и у кнопки в рабочей области.
    expect(find.byIcon(Icons.bug_report), findsWidgets);
  });

  testWidgets('повреждённый файл проверок не роняет каркас', (tester) async {
    final paths = visualPaths();
    paths.visualTestsFile.writeAsStringSync('{не json');
    await pumpVisualShell(tester, paths);
    await tester.tap(find.byKey(const Key('nav-checklist')));
    await tester.pumpAndSettle();
    expect(find.textContaining('повреждён'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('в визуальной проверке видны органы управления фичи', (
    tester,
  ) async {
    final paths = visualPaths();
    final feature = testFeature(
      id: 'alpha',
      title: 'Альфа',
      controls: (context, feature) =>
          const Text('орган управления', key: Key('test-control')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          paths: paths,
          info: testInfo,
          host: FakeSceneHost(paths: paths),
          features: [feature],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-checklist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-alpha')));
    await tester.pumpAndSettle();

    // Сцены проверки должны совпадать со сценами «Возможностей движка»:
    // панель управления (слайдеры, содержимое) видна и здесь.
    expect(find.byKey(const Key('feature-controls')), findsOneWidget);
    expect(find.byKey(const Key('test-control')), findsOneWidget);
  });
}
