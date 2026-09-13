import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_editor/main.dart' show configureFilePicker;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('на macOS отключает проверку entitlements file_picker', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    FilePickerMacOS.registerWith();

    await configureFilePicker();

    if (Platform.isMacOS) {
      expect(
        calls.map((call) => call.method),
        contains('skipEntitlementsChecks'),
        reason: 'без этого file_picker падает с ENTITLEMENT_NOT_FOUND',
      );
    } else {
      expect(calls, isEmpty);
    }
  });
}
