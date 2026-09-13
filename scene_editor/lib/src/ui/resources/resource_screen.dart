import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/resource_item.dart';
import '../../services/model3d_store.dart';
import '../../services/resource_store.dart';
import '../../state/app_state.dart';
import 'model3d_panel.dart';
import 'model3d_tile.dart';
import 'model_viewer_screen.dart';
import 'resource_editor_panel.dart';
import 'resource_tile.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// The «Ресурсы» workspace tab: grid of project resources
/// (Текстуры / Спрайты / Модели) + editor panel.
class ResourceScreen extends StatefulWidget {
  const ResourceScreen({
    super.key,
    required this.app,
    this.store,
    this.models,
  });

  /// The app state — routes model rename/delete through the scene editor
  /// (repointing scene references and warning about their users).
  final AppState app;

  /// The resource store; defaults to [AppState.resources].
  final ResourceStore? store;

  /// The `3d_models/` catalog; defaults to [AppState.model3d].
  final Model3dStore? models;

  @override
  State<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends State<ResourceScreen> {
  bool _importing = false;

  /// The selected model of the «Модели» section (its own selection state —
  /// models do not live in [ResourceStore]).
  String? _selectedModelName;

  ResourceStore get store => widget.store ?? widget.app.resources;
  Model3dStore get models => widget.models ?? widget.app.model3d;

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final family = await _askFamily();
      if (family == null) return;
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result == null) return;
      var imported = 0;
      String? lastError;
      for (final f in result.files) {
        if (f.path == null) continue;
        try {
          final name = await store.importFile(f.path!, family: family);
          if (name != null) {
            imported++;
          } else {
            lastError = 'не удалось прочитать файл ${f.name}';
          }
        } catch (e) {
          lastError = '${f.name}: $e';
        }
      }
      if (!mounted) return;
      final dir = family == 'sprite' ? 'sprites/' : 'textures/';
      _notify(
        imported > 0
            ? 'Импортировано: $imported в $dir'
            : (lastError ?? 'Ничего не импортировано'),
        isError: imported == 0,
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Explicit family choice for the imported files («Текстура» / «Спрайт»).
  /// Applies to every picked file.
  Future<String?> _askFamily() {
    return showDialog<String>(
      context: context,
      builder: (_) => const FamilyPickDialog(),
    );
  }

  /// Camera / photo-library capture (iPadOS): the picked image is copied
  /// into the project with the chosen family.
  Future<void> _pickImage(ImageSource source) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final family = await _askFamily();
      if (family == null) return;
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (picked == null) return;
      final name = await store.importFile(picked.path, family: family);
      if (!mounted) return;
      final dir = family == 'sprite' ? 'sprites/' : 'textures/';
      _notify(
        name != null
            ? 'Импортировано: $name в $dir'
            : 'Не удалось прочитать фото',
        isError: name == null,
      );
    } catch (e) {
      if (mounted) _notify('Ошибка фото: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── «Модели» (3d_models/) ───────────────────────────────────────────

  /// Where imported models go: `<project>/3d_models/`.
  static const _modelsDirLabel = '3d_models/';

  /// Asks what to import (a single file or a whole glTF folder), runs the
  /// file/directory pickers and imports into `3d_models/`.
  Future<void> _importModel() async {
    if (_importing) return;
    final source = await _askModelImportSource();
    if (source == null) return;
    setState(() => _importing = true);
    try {
      String? lastError;
      var imported = 0;
      String? firstImported;
      if (source == 'folder') {
        final path = await FilePicker.getDirectoryPath(
          dialogTitle: 'Папка с .gltf-моделью',
        );
        if (path != null) {
          final result = await models.importDirectory(path);
          if (result.error != null) {
            lastError = result.error;
          } else {
            imported = 1;
            firstImported = result.name;
          }
        }
      } else {
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          dialogTitle: 'Импорт модели (GLB или .gltf)',
          type: FileType.custom,
          allowedExtensions: const ['glb', 'gltf'],
        );
        if (result != null) {
          for (final f in result.files) {
            if (f.path == null) continue;
            final r = await models.importFile(f.path!);
            if (r.error != null) {
              lastError = r.error;
            } else {
              imported++;
              firstImported ??= r.name;
            }
          }
        }
      }
      if (!mounted) return;
      if (imported > 0) {
        _notify('Импортировано: $imported в $_modelsDirLabel');
        if (firstImported != null) {
          setState(() => _selectedModelName = firstImported);
        }
      } else if (lastError != null) {
        _notify('Ошибка импорта модели: $lastError', isError: true);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// «Файл (.glb / .gltf)» vs «Папка модели (glTF)» — a .gltf references
  /// its .bin/textures by relative paths, so folder import is the primary
  /// path for Sketchfab-style downloads.
  Future<String?> _askModelImportSource() {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF262B34),
        title: const Text(
          'Импорт модели',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'Файлы копируются в 3d_models/ проекта.\n'
          'Модель .gltf всегда импортируется вместе со своей папкой '
          '(.bin, текстуры, license).',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'file'),
            child: const Text('Файл (.glb/.gltf)',
                style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'folder'),
            child: const Text('Папку с .gltf'),
          ),
        ],
      ),
    );
  }

  void _selectModel(String name) {
    store.clearSelected(); // The image editor panel must hide.
    setState(() => _selectedModelName = name);
  }

  void _openViewer(Model3dEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ModelViewerScreen(entry: entry),
      ),
    );
  }

  Future<void> _export() async {
    final message = await store.pickExportDirectory();
    if (message != null) {
      _notify(message, isError: message.startsWith('Ничего'));
    }
  }

  /// Selects/deselects every item of one family (header toggle).
  void _toggleSelectFamily(String family) {
    final group = store.items.where((i) => i.family == family).toList();
    final allSelected = group.every((i) => i.selectedForExport);
    if (allSelected) {
      store.clearSelection(family: family);
    } else {
      store.selectAll(family: family);
    }
  }

  Future<void> _deleteSelected() async {
    final count = store.selectedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF262B34),
        title: const Text(
          'Удалить выбранные ресурсы?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          count == 1
              ? '1 файл будет безвозвратно удалён с диска (PNG и _original).'
              : '$count файлов будут безвозвратно удалены с диска '
                    '(PNG и _original).',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await store.deleteSelected();
    if (!mounted) return;
    _notify('Удалено: $deleted');
  }

  Future<void> _saveAll() async {
    final error = await store.saveAll();
    if (!mounted) return;
    _notify(error ?? 'Все изменения сохранены', isError: error != null);
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, models]),
      builder: (context, _) {
        final selected = store.selected;
        final selectedModel = _selectedModel(
          name: _selectedModelName,
          list: models.items,
        );
        final hasContent = store.items.isNotEmpty || models.items.isNotEmpty;
        return Scaffold(
          backgroundColor: const Color(0xFF20242C),
          appBar: AppBar(
            title: const Text(
              'Ресурсы',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            leadingWidth: 0,
            automaticallyImplyLeading: false,
            actions: [
              if (Platform.isIOS) ...[
                IconButton(
                  tooltip: 'Сфотографировать',
                  onPressed: _importing
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  tooltip: 'Из фототеки',
                  onPressed: _importing
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                ),
              ],
              IconButton(
                tooltip: 'Импортировать изображения',
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              IconButton(
                tooltip: 'Импортировать модель (glTF/GLB)',
                onPressed: _importing ? null : _importModel,
                icon: const Icon(Icons.view_in_ar),
              ),
              IconButton(
                tooltip: 'Сохранить все',
                onPressed: _saveAll,
                icon: const Icon(Icons.save_alt_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: !hasContent
              ? _emptyState(context)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _grid(context)),
                    if (selected != null || selectedModel != null) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 380,
                        child: selected != null
                            ? ResourceEditorPanel(
                                key: ValueKey(selected),
                                item: selected,
                                store: store,
                              )
                            : Model3dPanel(
                                key: ValueKey(selectedModel!.name),
                                entry: selectedModel,
                                store: models,
                                app: widget.app,
                                onOpen: () => _openViewer(selectedModel),
                                onRenamed: (newName) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedModelName = newName;
                                    });
                                  }
                                },
                              ),
                      ),
                    ],
                  ],
                ),
          bottomNavigationBar: hasContent ? _statusBar(context) : null,
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_search, size: 72, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'В проекте нет ресурсов',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _importing ? null : _import,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Импортировать изображения'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
                onPressed: _importing ? null : _importModel,
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: const Text('Импортировать модель'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Resolves the selected model by name — after a rename the entry is the
  /// new one; after a delete it disappears (and the selection resets).
  Model3dEntry? _selectedModel({
    required String? name,
    required List<Model3dEntry> list,
  }) {
    if (name == null) return null;
    for (final e in list) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// The resource grid grouped into «Текстуры», «Спрайты» and «Модели»
  /// sections (empty sections are hidden).
  Widget _grid(BuildContext context) {
    final items = store.items;
    final textures = items.where((i) => i.family == 'texture').toList();
    final sprites = items.where((i) => i.family == 'sprite').toList();
    final modelItems = models.items;
    final selectedModel = _selectedModel(
      name: _selectedModelName,
      list: modelItems,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 150).floor().clamp(
          2,
          12,
        );
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (textures.isNotEmpty) ...[
              _SectionHeader(
                title: 'Текстуры (${textures.length})',
                allSelected: textures.every((i) => i.selectedForExport),
                onToggle: () => _toggleSelectFamily('texture'),
              ),
              const SizedBox(height: 8),
              _SectionGrid(
                delegate: gridDelegate,
                items: textures,
                onTile: (item) => ResourceTile(
                  item: item,
                  isSelected: store.selected == item,
                  onTap: () {
                    setState(() => _selectedModelName = null);
                    store.select(item);
                  },
                  onToggleExport: () => store.toggleExport(item),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (sprites.isNotEmpty) ...[
              _SectionHeader(
                title: 'Спрайты (${sprites.length})',
                allSelected: sprites.every((i) => i.selectedForExport),
                onToggle: () => _toggleSelectFamily('sprite'),
              ),
              const SizedBox(height: 8),
              _SectionGrid(
                delegate: gridDelegate,
                items: sprites,
                onTile: (item) => ResourceTile(
                  item: item,
                  isSelected: store.selected == item,
                  onTap: () {
                    setState(() => _selectedModelName = null);
                    store.select(item);
                  },
                  onToggleExport: () => store.toggleExport(item),
                ),
              ),
            ],
            if (modelItems.isNotEmpty) ...[
              if (sprites.isNotEmpty) const SizedBox(height: 20),
              _SectionHeader(
                title: 'Модели (${modelItems.length})',
                hint: 'Двойной клик по плитке — просмотр модели с анимациями',
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: gridDelegate,
                itemCount: modelItems.length,
                itemBuilder: (context, i) {
                  final entry = modelItems[i];
                  return Model3dTile(
                    entry: entry,
                    isSelected: entry.name == selectedModel?.name,
                    onTap: () => _selectModel(entry.name),
                    onOpen: () => _openViewer(entry),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statusBar(BuildContext context) {
    final theme = Theme.of(context);
    final items = store.items;
    final modified = items.where((i) => i.isModified).length;
    final selected = store.selectedCount;
    final modelCount = models.items.length;
    final counts = items.isEmpty
        ? 'Моделей: $modelCount'
        : modelCount > 0
            ? 'Файлов: ${items.length}  •  Моделей: $modelCount'
                '  •  Изменено: $modified  •  Выбрано: $selected'
            : 'Файлов: ${items.length}  •  Изменено: $modified'
                '  •  Выбрано: $selected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(counts, style: theme.textTheme.bodySmall),
          ),
          if (items.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: selected == 0 ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text('Удалить ($selected)'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: selected == 0 ? null : _export,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text('Экспорт ($selected)'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool? allSelected;
  final VoidCallback? onToggle;
  final String? hint;
  const _SectionHeader({
    required this.title,
    this.allSelected,
    this.onToggle,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onToggle != null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: onToggle,
                icon: Icon(
                  allSelected! ? Icons.deselect : Icons.select_all,
                  size: 16,
                ),
                label: Text(allSelected! ? 'Снять выбор' : 'Выбрать все'),
              ),
          ],
        ),
        if (hint != null)
          Text(
            hint!,
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          ),
      ],
    );
  }
}

/// A non-scrolling grid of one resource family (inside the section list).
class _SectionGrid extends StatelessWidget {
  final SliverGridDelegateWithFixedCrossAxisCount delegate;
  final List<ResourceItem> items;
  final Widget Function(ResourceItem item) onTile;
  const _SectionGrid({
    required this.delegate,
    required this.items,
    required this.onTile,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: delegate,
      itemCount: items.length,
      itemBuilder: (context, i) => onTile(items[i]),
    );
  }
}

/// The import-family dialog: «Текстура (textures/)» / «Спрайт (sprites/)».
/// Pops with the chosen family, or null on cancel.
class FamilyPickDialog extends StatefulWidget {
  const FamilyPickDialog({super.key});

  @override
  State<FamilyPickDialog> createState() => _FamilyPickDialogState();
}

class _FamilyPickDialogState extends State<FamilyPickDialog> {
  String _family = 'texture';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: const Text(
        'Семейство импортируемых файлов',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Все выбранные файлы попадут в одну папку проекта:',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'texture',
                label: Text('Текстура'),
                icon: Icon(Icons.grid_on, size: 16),
              ),
              ButtonSegment(
                value: 'sprite',
                label: Text('Спрайт'),
                icon: Icon(Icons.image, size: 16),
              ),
            ],
            selected: {_family},
            onSelectionChanged: (s) => setState(() => _family = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _family == 'sprite'
                ? 'Папка sprites/ — billboard-объекты (стоят лицом к камере)'
                : 'Папка textures/ — тайлинг на гранях моделей',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _family),
          child: const Text('Импортировать'),
        ),
      ],
    );
  }
}
