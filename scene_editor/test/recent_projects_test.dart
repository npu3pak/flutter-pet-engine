import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scene_editor/src/services/recent_projects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String existing;
  late String stale;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('scene_editor_recent_test');
    existing = '${dir.path}/existing';
    stale = '${dir.path}/stale';
    Directory(existing).createSync();
    // The stale path never gets created on disk.
    SharedPreferences.setMockInitialValues({});
  });

  test('empty history loads as empty list', () async {
    expect(await RecentProjects.load(), isEmpty);
  });

  test('remember prepends and drops duplicates', () async {
    await RecentProjects.remember(existing);
    await RecentProjects.remember(existing);
    final list = await RecentProjects.load();
    expect(list, [existing]);
  });

  test('load drops paths of deleted folders', () async {
    await RecentProjects.remember(existing);
    await RecentProjects.remember(stale);
    final list = await RecentProjects.load();
    expect(list, [existing]);
  });

  test('forget removes a single entry', () async {
    await RecentProjects.remember(existing);
    final list = await RecentProjects.forget(existing);
    expect(list, isEmpty);
    expect(await RecentProjects.load(), isEmpty);
  });

  test('forget of a missing path is a no-op', () async {
    await RecentProjects.remember(existing);
    final list = await RecentProjects.forget(existing);
    expect(list, isEmpty);
    final list2 = await RecentProjects.forget(existing);
    expect(list2, isEmpty);
  });

  test('clear wipes the whole history', () async {
    await RecentProjects.remember(existing);
    await RecentProjects.clear();
    expect(await RecentProjects.load(), isEmpty);
  });
}
