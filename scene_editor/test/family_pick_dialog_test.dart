import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/ui/resources/resource_screen.dart';

void main() {
  /// Opens the dialog and stores its pop result into [out] (the async
  /// continuation runs after the dialog closes, so a plain return can't
  /// capture it).
  Future<void> pumpDialog(WidgetTester tester, List<String?> out) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              out.add(await showDialog<String>(
                context: context,
                builder: (_) => const FamilyPickDialog(),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to texture and pops with the chosen family',
      (WidgetTester tester) async {
    final out = <String?>[];
    await pumpDialog(tester, out);

    final seg = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>));
    expect(seg.selected, {'texture'});

    await tester.tap(find.text('Импортировать'));
    await tester.pumpAndSettle();
    expect(out.single, 'texture');
  });

  testWidgets('switching to «Спрайт» sticks and pops sprite',
      (WidgetTester tester) async {
    final out = <String?>[];
    await pumpDialog(tester, out);

    await tester.tap(find.text('Спрайт'));
    await tester.pumpAndSettle();

    // The selection must survive the rebuild.
    final seg = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>));
    expect(seg.selected, {'sprite'});

    // The hint text switched to the sprite explanation.
    expect(find.textContaining('sprites/'), findsOneWidget);

    await tester.tap(find.text('Импортировать'));
    await tester.pumpAndSettle();
    expect(out.single, 'sprite');
  });

  testWidgets('cancel pops null', (WidgetTester tester) async {
    final out = <String?>[];
    await pumpDialog(tester, out);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(out.single, isNull);
  });
}
