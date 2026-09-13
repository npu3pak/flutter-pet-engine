import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/ui/form_fields.dart';

void main() {
  group('parseDoubleInput', () {
    test('valid numbers parse (dot and comma)', () {
      expect(parseDoubleInput('1.5'), 1.5);
      expect(parseDoubleInput('3,75'), 3.75);
      expect(parseDoubleInput('-3'), -3);
      expect(parseDoubleInput('0'), 0);
    });

    test('incomplete and invalid input returns null', () {
      expect(parseDoubleInput(''), isNull);
      expect(parseDoubleInput('1.'), isNull);
      expect(parseDoubleInput('-'), isNull);
      expect(parseDoubleInput('abc'), isNull);
      expect(parseDoubleInput('1.2.3'), isNull);
    });
  });

  group('DoubleField spinner', () {
    Future<List<double>> pumpField(
      WidgetTester tester, {
      double initial = 1.0,
      double step = 0.1,
    }) async {
      final values = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoubleField(initial: initial, step: step, onChanged: values.add),
          ),
        ),
      );
      return values;
    }

    testWidgets('▲ steps up by the widget step', (tester) async {
      final values = await pumpField(tester, initial: 1.0, step: 0.25);
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      expect(values, [1.25]);
    });

    testWidgets('▼ steps down by the widget step', (tester) async {
      final values = await pumpField(tester, initial: 1.0, step: 0.25);
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      expect(values, [0.75]);
    });

    testWidgets('default step is 0.1', (tester) async {
      final values = await pumpField(tester, initial: 1.0);
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      expect(values, [1.1]);
    });

    testWidgets('holding ▲ keeps stepping', (tester) async {
      final values = await pumpField(tester, initial: 1.0, step: 0.1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_drop_up)),
      );
      // Immediate step on press.
      await tester.pump();
      expect(values, [1.1]);
      // Initial delay (350 ms) → first repeat.
      await tester.pump(const Duration(milliseconds: 350));
      expect(values, [1.1, 1.2]);
      // Repeats every 80 ms while held.
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 80));
      expect(values, [1.1, 1.2, 1.3, 1.4]);
      await gesture.up();
      await tester.pump();
      // No further steps after release.
      await tester.pump(const Duration(milliseconds: 400));
      expect(values, [1.1, 1.2, 1.3, 1.4]);
    });
  });

  group('IntField spinner', () {
    testWidgets('▲ steps up by 1 within min/max', (tester) async {
      final values = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntField(
              initial: 3,
              min: 0,
              max: 5,
              onChanged: values.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      expect(values, [4]);
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      expect(values, [4, 5]);
      // Clamped at max.
      await tester.tap(find.byIcon(Icons.arrow_drop_up));
      expect(values, [4, 5]);
    });
  });
}
