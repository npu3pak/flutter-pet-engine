import 'package:example/src/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  testWidgets('раздел показывает версии и историю изменений', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AboutScreen(info: testInfo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Версия приложения'), findsOneWidget);
    expect(find.text(testInfo.appVersion), findsOneWidget);
    expect(find.text('Версия движка'), findsOneWidget);
    expect(find.text(testInfo.engineVersion), findsOneWidget);
    expect(find.text('История изменений для теста.'), findsOneWidget);
  });

  testWidgets('непереданные версии показываются как «неизвестно»', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AboutScreen(info: testInfo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('неизвестно'), findsWidgets);
  });
}
