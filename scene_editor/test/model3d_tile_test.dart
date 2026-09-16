import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/ui/resources/model3d_tile.dart';
import 'package:pet_engine/pet_engine.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF20242C),
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, height: 240, child: child)),
    ),
  );
}

void main() {
  const entry = Model3dEntry(
    name: 'cat',
    isFolder: true,
    sourcePath: '/project/3d_models/cat/scene.gltf',
    sizeBytes: 2048,
  );

  testWidgets('single click selects, double click opens the viewer', (
    tester,
  ) async {
    var tapCount = 0;
    var openCount = 0;
    await tester.pumpWidget(
      _wrap(
        Model3dTile(
          entry: entry,
          isSelected: false,
          onTap: () => tapCount++,
          onOpen: () => openCount++,
        ),
      ),
    );

    final center = tester.getCenter(find.byType(Model3dTile));
    // First click: only the selection handler runs.
    var g = await tester.startGesture(center);
    await g.up();
    await tester.pump();
    expect(tapCount, 1);
    expect(openCount, 0);

    // Second click inside the double-click window: opens the viewer.
    g = await tester.startGesture(center);
    await g.up();
    await tester.pump();
    expect(tapCount, 2);
    expect(openCount, 1);
  });

  testWidgets('tile shows name, format and size', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Model3dTile(
          entry: entry,
          isSelected: true,
          onTap: () {},
          onOpen: () {},
        ),
      ),
    );
    expect(find.text('cat'), findsOneWidget);
    expect(find.text('glTF • 2 КБ'), findsOneWidget);
  });

  testWidgets('single click is not delayed by the double-click window', (
    tester,
  ) async {
    var tapCount = 0;
    var openCount = 0;
    await tester.pumpWidget(
      _wrap(
        Model3dTile(
          entry: entry,
          isSelected: false,
          onTap: () => tapCount++,
          onOpen: () => openCount++,
        ),
      ),
    );
    // Without awaiting the double-tap timeout the selection must already
    // have fired (the Listener pattern never delays the single click).
    final center = tester.getCenter(find.byType(Model3dTile));
    final g = await tester.startGesture(center);
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapCount, 1);
    expect(openCount, 0);
    await tester.pump(kDoubleTapTimeout);
  });
}
