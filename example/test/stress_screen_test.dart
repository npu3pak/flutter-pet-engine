import 'dart:io';

import 'package:example/src/paths.dart';
import 'package:example/src/stress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StressResult cannedResult(int size) => StressResult(
  size: size,
  buildMs: 20,
  bakeMs: 20616,
  elements: size * size * 2 + size * 4,
  mergedMeshes: 3,
  batchMeshes: 0,
  separateNodes: 0,
  vertices: 489600,
  triangles: 244800,
  fps: 60.5,
  at: DateTime(2026, 9, 10, 21),
);

/// Каталоги приложения в temp с отдельным каталогом docs.
AppPaths stressPaths() {
  final appDir = Directory('temp/stress_app/example');
  Directory('temp/stress_app/docs').createSync(recursive: true);
  appDir.createSync(recursive: true);
  final file = File('temp/stress_app/docs/perf_journal.md');
  if (file.existsSync()) file.deleteSync();
  return AppPaths(appDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('секция журнала содержит все метрики', () {
    final section = PerfJournal.stressSection(cannedResult(100));
    expect(section, contains('100×100'));
    expect(section, contains('Сборка `ConstructionModel` (BuildOps) | 20 мс'));
    expect(section, contains('Запекание `LevelBaker.bake` | 20616 мс'));
    expect(section, contains('489600 / 244800'));
    expect(section, contains('60.5'));
  });

  test('журнал дописывается и сохраняет историю', () {
    final paths = stressPaths();
    final file = paths.perfJournalFile;
    expect(PerfJournal.appendStress(file, cannedResult(10)), isNull);
    expect(PerfJournal.appendStress(file, cannedResult(20)), isNull);
    final text = file.readAsStringSync();
    expect('10×10'.allMatches(text).length, 1);
    expect('20×20'.allMatches(text).length, 1);
  });

  testWidgets('экран стресса: границы, запуск и результаты', (tester) async {
    final paths = stressPaths();
    final slider = Slider(value: 50, min: 10, max: 100, onChanged: (_) {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StressScreen(
            paths: paths,
            initialSize: 50,
            runner: (size) async => cannedResult(size),
            fpsLabel: () => '60.5 FPS · 16.2 мс/кадр',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final widget = tester.widget<Slider>(find.byKey(const Key('stress-size')));
    expect(widget.min, 10);
    expect(widget.max, 100);
    expect(slider.min, 10);
    expect(find.text('клеток: 2500'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stress-run')));
    await tester.pumpAndSettle();

    expect(find.text('Результаты'), findsOneWidget);
    expect(find.text('20616 мс'), findsOneWidget);
    expect(find.text('489600 / 244800'), findsOneWidget);
    expect(find.text('60.5 FPS'), findsOneWidget);
    expect(paths.perfJournalFile.existsSync(), isTrue);
    expect(paths.perfJournalFile.readAsStringSync(), contains('50×50'));
  });

  testWidgets('оценка времени появляется после измерения', (tester) async {
    lastStressResult = cannedResult(50);
    final paths = stressPaths();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StressScreen(
            paths: paths,
            initialSize: 100,
            runner: (size) async => cannedResult(size),
            fpsLabel: () => '—',
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Оценка запекания'), findsOneWidget);
    lastStressResult = null;
  });

  testWidgets('кнопка «Назад» вызывает возврат', (tester) async {
    var back = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StressScreen(
            paths: stressPaths(),
            initialSize: 10,
            runner: (size) async => cannedResult(size),
            fpsLabel: () => '—',
            onBack: () => back = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stress-back')));
    await tester.pumpAndSettle();
    expect(back, isTrue);
  });
}
