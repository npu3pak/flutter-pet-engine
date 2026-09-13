import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/project_files.dart';
import '../services/recent_projects.dart';
import '../state/app_state.dart';
import 'unsaved_dialog.dart';

/// Project browser: create / open a project and pick from recent ones.
///
/// macOS — any folder on disk (sandbox disabled). iPadOS — projects live in
/// the app's Documents (visible in Files, `UIFileSharingEnabled`); create =
/// a named folder in Documents, import = a folder copied in from Files.
class ProjectScreen extends StatelessWidget {
  final AppState app;
  const ProjectScreen({super.key, required this.app});

  bool get _isIos => Platform.isIOS;

  Future<void> _open(BuildContext context, String path) async {
    // Opening another project discards every in-memory model: ask first.
    if (!await confirmUnsavedChanges(context, app)) return;
    try {
      final ok = await app.openProject(path);
      if (!context.mounted) return;
      if (!ok) {
        _snackFailure(context, 'открыть проект', path);
        return;
      }
      await RecentProjects.remember(path);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The v2 controller reports per-resource load errors in its status; show
  /// them when present, otherwise a generic failure message.
  void _snackFailure(BuildContext context, String action, String path) {
    final errors = app.controller.status.errors;
    _snack(
      context,
      errors.isEmpty
          ? 'Не удалось $action: $path'
          : 'Загружено с ошибками: ${errors.map((e) => e.resource).join(', ')}',
    );
  }

  // ── macOS ─────────────────────────────────────────────────────────────

  Future<void> _pickFolder(BuildContext context, String dialogTitle) async {
    final result = await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
    if (result == null || !context.mounted) return;
    await _open(context, result);
  }

  Future<void> _createProject(BuildContext context) async {
    // Creating and opening a new project replaces the current one.
    if (!await confirmUnsavedChanges(context, app)) return;
    // 1) pick the parent folder, 2) ask for an optional project name:
    // an empty name means the project lives in the picked folder itself.
    final parent = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку для нового проекта',
    );
    if (parent == null || !context.mounted) return;
    final name = await _askProjectName(
      context,
      allowEmpty: true,
      parentPath: parent,
    );
    if (name == null || !context.mounted) return;

    final path = name.isEmpty ? parent : p.join(parent, name);
    // Manual migration: a folder with chunks/ (legacy format) becomes a
    // project. Only relevant when no fresh subfolder is created.
    if (name.isEmpty && Directory(p.join(path, 'chunks')).existsSync()) {
      final migrate = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Создать проект здесь?'),
          content: Text(
            'В папке есть «chunks/» (legacy-формат моделей). Это будет ручная '
            'миграция: файлы скопируются в «models/» и перепишутся в '
            'формат model_v1. Продолжить?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Создать проект'),
            ),
          ],
        ),
      );
      if (migrate != true) return;
    }
    // v2: creation, the legacy chunks/ migration and opening all go through
    // AppState; the migration happens inside createProject.
    final created = await app.createProject(
      path,
      name: name.isEmpty ? p.basename(path) : name,
    );
    if (!context.mounted) return;
    if (!created) {
      _snackFailure(context, 'создать проект', path);
      return;
    }
    await RecentProjects.remember(path);
  }

  // ── iPadOS (Documents) ────────────────────────────────────────────────

  Future<void> _createIosProject(BuildContext context) async {
    final docs = await getApplicationDocumentsDirectory();
    if (!context.mounted) return;
    final name = await _askProjectName(context, allowEmpty: false);
    if (name == null || !context.mounted) return;
    final path = p.join(docs.path, name);
    final created = await app.createProject(path, name: name);
    if (!context.mounted) return;
    if (!created) {
      _snackFailure(context, 'создать проект', path);
      return;
    }
    await RecentProjects.remember(path);
  }

  Future<void> _importIosProject(BuildContext context) async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Выберите папку проекта',
    );
    if (result == null || !context.mounted) return;
    final docs = await getApplicationDocumentsDirectory();
    final dst = p.join(docs.path, p.basename(result));
    final err = await copyDirectory(result, dst);
    if (err != null) {
      if (context.mounted) _snack(context, err);
      return;
    }
    if (context.mounted) await _open(context, dst);
  }

  /// Name dialog for a new project. Returns `null` on cancel; an empty string
  /// means «create without a subfolder» (macOS, [allowEmpty]) — on iPad the
  /// name is required. On macOS [parentPath] lets the dialog validate that the
  /// target folder does not already exist.
  Future<String?> _askProjectName(
    BuildContext context, {
    required bool allowEmpty,
    String? parentPath,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          String? error;
          String? validate(String value) {
            final clean = value.trim();
            if (clean.isEmpty) {
              return allowEmpty ? null : 'Введите имя проекта';
            }
            if (RegExp(r'[\\/:*?"<>|]').hasMatch(clean)) {
              return 'Имя содержит запрещённые символы \\ / : * ? " < > |';
            }
            if (RegExp(r'^\.+$').hasMatch(clean)) {
              return 'Имя не может состоять из точек';
            }
            if (allowEmpty &&
                parentPath != null &&
                Directory(p.join(parentPath, clean)).existsSync()) {
              return 'В выбранной папке уже есть каталог «$clean»';
            }
            return null;
          }

          void submit(String value) {
            final err = validate(value);
            if (err != null) {
              setState(() => error = err);
              return;
            }
            Navigator.pop(c, value.trim());
          }

          return AlertDialog(
            title: const Text('Новый проект'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Имя проекта',
                    hintText: 'Мой проект',
                    errorText: error,
                  ),
                  onSubmitted: submit,
                ),
                if (allowEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Имя необязательно: если оставить поле пустым, проект '
                    'создастся в выбранной папке без подкаталога.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => submit(controller.text),
                child: const Text('Создать'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF20242C),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _isIos ? _iosBody(context) : _macosBody(context),
        ),
      ),
    );
  }

  Widget _titleBlock(BuildContext context) {
    return Column(
      children: const [
        Icon(Icons.view_in_ar, size: 72, color: Color(0xFF8FA8C0)),
        SizedBox(height: 16),
        Text(
          'Scene Editor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Простой 3D-редактор: проекты, ресурсы, модели',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }

  Widget _macosBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _titleBlock(context),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _createProject(context),
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Создать проект'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _pickFolder(
                context,
                'Выберите папку проекта (с project.json)',
              ),
              icon: const Icon(Icons.folder_open),
              label: const Text('Открыть проект'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _recentList(context),
      ],
    );
  }

  Widget _iosBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _titleBlock(context),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _createIosProject(context),
              icon: const Icon(Icons.create_new_folder),
              label: const Text('Создать проект'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _importIosProject(context),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Импортировать из Файлов'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<String>>(
          future: getApplicationDocumentsDirectory().then((d) {
            final docs = d.path;
            return scanProjects(docs).then((projects) => projects);
          }),
          builder: (context, snap) {
            final projects = snap.data ?? const <String>[];
            if (projects.isEmpty) {
              return const Text(
                'Проектов нет — создайте или импортируйте проект. '
                'Проекты хранятся в Файлах: On My iPad/Scene Editor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Мои проекты',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final path in projects)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.folder,
                            color: Color(0xFF8FA8C0),
                          ),
                          title: Text(
                            p.basename(path),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            path,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(context, path),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _recentList(BuildContext context) =>
      _RecentListSection(onOpen: (path) => _open(context, path));
}

/// «Недавние проекты» on the start screen: a clickable list with per-item
/// removal and «clear history» (macOS-only list; iPad scans Documents).
class _RecentListSection extends StatefulWidget {
  final Future<void> Function(String path) onOpen;
  const _RecentListSection({required this.onOpen});

  @override
  State<_RecentListSection> createState() => _RecentListSectionState();
}

class _RecentListSectionState extends State<_RecentListSection> {
  List<String>? _recents;

  @override
  void initState() {
    super.initState();
    RecentProjects.load().then((list) {
      if (mounted) setState(() => _recents = list);
    });
  }

  Future<void> _remove(String path) async {
    final list = await RecentProjects.forget(path);
    if (mounted) setState(() => _recents = list);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text(
          'Все проекты будут убраны из списка недавних. '
          'Файлы проектов на диске не удаляются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RecentProjects.clear();
    if (mounted) setState(() => _recents = const []);
  }

  @override
  Widget build(BuildContext context) {
    final recents = _recents;
    if (recents == null || recents.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Недавние проекты',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Очистить'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final path in recents)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder, color: Color(0xFF8FA8C0)),
                  title: Text(
                    p.basename(path),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    path,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: () => _remove(path),
                    icon: const Icon(Icons.close, size: 16),
                    color: Colors.white38,
                    tooltip: 'Убрать из истории',
                    visualDensity: VisualDensity.compact,
                  ),
                  onTap: () => widget.onOpen(path),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
