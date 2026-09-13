import 'package:demo/src/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FakeSceneHost> pumpPanel(
    WidgetTester tester, {
    bool showFps = true,
    ValueChanged<bool>? onShowFpsChanged,
  }) async {
    final host = FakeSceneHost(paths: testPaths());
    await host.showFeature(testFeature(id: 'settings'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            host: host,
            showFps: showFps,
            onShowFpsChanged: onShowFpsChanged ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return host;
  }

  testWidgets('переключатели панели применяются к сцене', (tester) async {
    final host = await pumpPanel(tester);

    expect(host.settings!.ssao, isFalse);
    await tester.tap(find.byKey(const Key('settings-ssao')));
    await tester.pumpAndSettle();
    expect(host.settings!.ssao, isTrue);

    expect(host.settings!.shadows, isFalse);
    await tester.tap(find.byKey(const Key('settings-shadows')));
    await tester.pumpAndSettle();
    expect(host.settings!.shadows, isTrue);

    expect(host.settings!.wireframe, isFalse);
    await tester.tap(find.byKey(const Key('settings-wireframe')));
    await tester.pumpAndSettle();
    expect(host.settings!.wireframe, isTrue);
  });

  testWidgets('переключатель тумана включает и выключает туман', (
    tester,
  ) async {
    final host = await pumpPanel(tester);

    expect(host.settings!.fogEnabled, isFalse);
    await tester.tap(find.byKey(const Key('settings-fog')));
    await tester.pumpAndSettle();
    expect(host.settings!.fogEnabled, isTrue);

    await tester.tap(find.byKey(const Key('settings-fog')));
    await tester.pumpAndSettle();
    expect(host.settings!.fogEnabled, isFalse);
  });

  testWidgets('переключатель частоты кадров сообщает наружу', (tester) async {
    bool? changed;
    await pumpPanel(
      tester,
      showFps: true,
      onShowFpsChanged: (value) => changed = value,
    );

    await tester.tap(find.byKey(const Key('settings-fps')));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
  });
}
