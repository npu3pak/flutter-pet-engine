import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted list of recently opened projects (paths, newest first).
/// Stale paths (deleted folders) are dropped on load.
class RecentProjects {
  static const _key = 'recent_projects';
  static const _max = 8;

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is String && e.isNotEmpty && Directory(e).existsSync()) e,
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> remember(String path) async {
    final list = await load();
    list
      ..remove(path)
      ..insert(0, path);
    if (list.length > _max) list.removeRange(_max, list.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
    return list;
  }

  /// Removes [path] from the history (no-op if it was not there).
  static Future<List<String>> forget(String path) async {
    final list = await load();
    if (!list.remove(path)) return list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
    return list;
  }

  /// Clears the whole history.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
