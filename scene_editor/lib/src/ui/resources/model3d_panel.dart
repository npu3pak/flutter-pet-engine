import 'package:flutter/material.dart';

import '../../services/model3d_store.dart';
import '../../state/app_state.dart';
import '../form_fields.dart' show SectionTitle;
import 'package:pet_engine/pet_engine.dart';

/// The right-side panel for a selected model in the «Ресурсы» tab:
/// read-only info (format, size, entry file) plus rename / delete and the
/// «Открыть просмотрщик» action (also reachable by double-clicking the
/// tile). Images have [ResourceEditorPanel]; models are immutable copies,
/// so this panel is intentionally minimal.
class Model3dPanel extends StatefulWidget {
  const Model3dPanel({
    super.key,
    required this.entry,
    required this.store,
    required this.onOpen,
    this.onRenamed,
    this.app,
  });

  final Model3dEntry entry;
  final Model3dStore store;
  final VoidCallback onOpen;

  /// Called with the new catalog name after a successful rename, so the
  /// parent keeps the selection on the renamed model.
  final ValueChanged<String>? onRenamed;

  /// Optional AppState: when present, rename/delete route through it (scene
  /// references are repointed on a rename; the delete warns about models
  /// using the resource and the viewport drops the instance to fuchsia
  /// cubes). Without it the panel works on the raw store only.
  final AppState? app;

  @override
  State<Model3dPanel> createState() => _Model3dPanelState();
}

class _Model3dPanelState extends State<Model3dPanel> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.entry.name,
  );

  @override
  void didUpdateWidget(Model3dPanel old) {
    super.didUpdateWidget(old);
    if (old.entry.name != widget.entry.name) {
      _nameCtrl.text = widget.entry.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Model3dEntry get entry => widget.entry;

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

  void _rename() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || name == entry.name) return;
    final app = widget.app;
    final err = app == null
        ? widget.store.rename(entry.name, name)
        : app.renameGltfResource(entry.name, name);
    _notify(err ?? 'Имя: $name', isError: err != null);
    if (err != null) {
      _nameCtrl.text = entry.name;
    } else {
      widget.onRenamed?.call(name);
    }
  }

  Future<void> _delete() async {
    final app = widget.app;
    // gltf instances of the scenes keep their references after a delete —
    // they render as fuchsia cubes; warn the user which scenes are affected.
    final users =
        app == null ? const <String>[] : app.modelsUsingGltf(entry.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF262B34),
        title: const Text(
          'Удалить модель?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '«${entry.name}» будет удалена с диска навсегда '
              '${entry.isFolder ? 'вместе со всей папкой (bin, текстуры, license).' : '.'}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (users.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Модель используется в моделях: ${users.join(', ')}. '
                'На местах её вставок останется куб фуксии.',
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 13,
                ),
              ),
            ],
          ],
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
    final err = app == null
        ? widget.store.delete(entry.name)
        : app.deleteGltfResource(entry.name);
    _notify(err ?? 'Удалена: ${entry.name}', isError: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.view_in_ar,
                  size: 18,
                  color: Color(0xFFF2A93B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onOpen,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Открыть просмотрщик'),
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Формат', value: _formatLabel()),
            const SizedBox(height: 6),
            _InfoRow(label: 'Размер на диске', value: entry.sizeLabel),
            const SizedBox(height: 6),
            _InfoRow(label: 'Файл модели', value: entry.entryFileName),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF3A4250), height: 1),
            const SizedBox(height: 14),
            SectionTitle('Имя'),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _rename(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _rename,
                  child: const Text('Переименовать'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Удалить'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Модель копируется в 3d_models/ проекта целиком — '
              'переименование перемещает ${entry.isFolder ? 'папку' : 'файл'} '
              'на диске.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLabel() => entry.isFolder
      ? 'glTF (папка: .gltf + .bin + текстуры)'
      : 'GLB (один файл)';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
