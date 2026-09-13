import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/resource_item.dart';
import '../../processing/background_remover.dart';
import '../../processing/image_ops.dart';
import '../../services/resource_store.dart';
import 'checkerboard_image.dart';

class ResourceEditorPanel extends StatefulWidget {
  const ResourceEditorPanel({super.key, required this.item, required this.store});

  final ResourceItem item;
  final ResourceStore store;

  @override
  State<ResourceEditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<ResourceEditorPanel> {
  late double _tolerance;
  late RgbColor _bg;
  bool _showOriginal = false;
  Uint8List? _liveBytes;
  Timer? _debounce;

  /// How the scale presets/custom size treat the aspect ratio.
  ResourceScaleMode _scaleMode = ResourceScaleMode.stretch;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  late final TextEditingController _padTopCtrl;
  late final TextEditingController _padRightCtrl;
  late final TextEditingController _padBottomCtrl;
  late final TextEditingController _padLeftCtrl;

  ResourceItem get item => widget.item;
  ResourceStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tolerance = item.tolerancePercent;
    _bg = store.detectBackground(item);
    _nameCtrl = TextEditingController(text: item.name);
    _wCtrl = TextEditingController(text: item.width.toString());
    _hCtrl = TextEditingController(text: item.height.toString());
    _padTopCtrl = TextEditingController(text: '0');
    _padRightCtrl = TextEditingController(text: '0');
    _padBottomCtrl = TextEditingController(text: '0');
    _padLeftCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    _padTopCtrl.dispose();
    _padRightCtrl.dispose();
    _padBottomCtrl.dispose();
    _padLeftCtrl.dispose();
    super.dispose();
  }

  Uint8List get _displayBytes => _showOriginal
      ? item.original.bytes
      : (_liveBytes ?? item.snapshot.bytes);

  int get _displayWidth =>
      _showOriginal ? item.original.width : item.snapshot.width;
  int get _displayHeight =>
      _showOriginal ? item.original.height : item.snapshot.height;

  void _scheduleLivePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      try {
        final bytes = store.previewRemoval(
          item: item,
          tolerance: _tolerance,
        );
        setState(() {
          _liveBytes = bytes;
          _showOriginal = false;
        });
      } catch (e) {
        setState(() => _liveBytes = null);
        _notify('Ошибка предпросмотра: $e', isError: true);
      }
    });
  }

  Future<void> _applyRemoval() async {
    _debounce?.cancel();
    await store.applyRemoval(item: item, tolerance: _tolerance);
    if (!mounted) return;
    setState(() {
      _liveBytes = null;
      _showOriginal = false;
    });
    _notify('Фон удалён');
  }

  void _applyScale(int width, int height) {
    if (width <= 0 || height <= 0) return;
    setState(() {
      store.applyScale(
        item: item,
        width: width,
        height: height,
        mode: _scaleMode,
      );
      _liveBytes = null;
      _showOriginal = false;
    });
    _notify('Масштаб: ${item.width}×${item.height}');
  }

  void _applyCustomScale() {
    final w = int.tryParse(_wCtrl.text);
    final h = int.tryParse(_hCtrl.text);
    if (w == null || h == null || w <= 0 || h <= 0) {
      _notify('Укажите корректные размеры', isError: true);
      return;
    }
    _applyScale(w, h);
  }

  static String _alignLabel(AlignTarget target) => switch (target) {
    AlignTarget.top => 'К верху',
    AlignTarget.bottom => 'К низу',
    AlignTarget.left => 'К левому краю',
    AlignTarget.right => 'К правому краю',
    AlignTarget.center => 'По центру',
  };

  static IconData _alignIcon(AlignTarget target) => switch (target) {
    AlignTarget.top => Icons.vertical_align_top,
    AlignTarget.bottom => Icons.vertical_align_bottom,
    AlignTarget.left => Icons.align_horizontal_left,
    AlignTarget.right => Icons.align_horizontal_right,
    AlignTarget.center => Icons.center_focus_strong,
  };

  void _align(AlignTarget target) {
    setState(() {
      store.applyAlign(item: item, target: target);
      _liveBytes = null;
      _showOriginal = false;
    });
    _notify('Выравнивание: ${_alignLabel(target).toLowerCase()}');
  }

  void _applyPadding() {
    final top = int.tryParse(_padTopCtrl.text);
    final right = int.tryParse(_padRightCtrl.text);
    final bottom = int.tryParse(_padBottomCtrl.text);
    final left = int.tryParse(_padLeftCtrl.text);
    final values = [top, right, bottom, left];
    if (values.any((v) => v == null || v < 0)) {
      _notify('Отступы — целые числа от 0 до 1024', isError: true);
      return;
    }
    setState(() {
      store.applyTrimMargins(
        item: item,
        top: top!,
        right: right!,
        bottom: bottom!,
        left: left!,
      );
      _liveBytes = null;
      _showOriginal = false;
    });
    _notify('Отступы применены: ${item.width}×${item.height}');
  }

  Future<void> _rename() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || name == item.name) return;
    final err = await store.rename(item, name);
    if (!mounted) return;
    _notify(err ?? 'Имя: $name', isError: err != null);
    if (err != null) _nameCtrl.text = item.name;
  }

  Future<void> _changeFamily(String family) async {
    await store.setFamily(item, family);
    if (!mounted) return;
    _notify(family == 'sprite' ? 'Семейство: спрайт' : 'Семейство: текстура');
  }

  Future<void> _delete() async {
    final name = item.name;
    await store.delete(item);
    if (!mounted) return;
    _notify('Удалён: $name');
  }

  void _rollback(int index) {
    setState(() {
      store.rollback(item, index);
      _liveBytes = null;
      _showOriginal = false;
    });
  }

  Future<void> _save() async {
    await _rename();
    if (!mounted) return;
    final error = await store.saveItem(item);
    if (!mounted) return;
    _notify(error ?? 'Сохранено: ${item.name}.png', isError: error != null);
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SegmentedButton<bool>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Результат')),
                      ButtonSegment(value: true, label: Text('Оригинал')),
                    ],
                    selected: {_showOriginal},
                    onSelectionChanged: (s) =>
                        setState(() => _showOriginal = s.first),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _preview(theme),
                  const SizedBox(height: 12),
                  _nameCard(theme),
                  const SizedBox(height: 12),
                  _familyCard(theme),
                  const SizedBox(height: 12),
                  _removeBackgroundCard(theme),
                  const SizedBox(height: 12),
                  _alignCard(theme),
                  const SizedBox(height: 12),
                  _padCard(theme),
                  const SizedBox(height: 12),
                  _scaleCard(theme),
                  const SizedBox(height: 12),
                  _historyCard(theme),
                  const SizedBox(height: 12),
                  _saveCard(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    return Container(
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CheckerboardImage(bytes: _displayBytes),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$_displayWidth×$_displayHeight',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
          if (_liveBytes != null)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Предпросмотр',
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: Colors.amber),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nameCard(ThemeData theme) {
    return _Card(
      title: 'Имя файла',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _rename(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _rename, child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _removeBackgroundCard(ThemeData theme) {
    return _Card(
      title: 'Удаление фона',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(_bg.toArgb32()),
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text('Цвет фона: ${_bg.toHex()}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _tolerance,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_tolerance.round()}%',
                  onChanged: (v) {
                    setState(() {
                      _tolerance = v;
                      _showOriginal = false;
                    });
                    _scheduleLivePreview();
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${_tolerance.round()}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _applyRemoval,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Удалить фон'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alignCard(ThemeData theme) {
    return _Card(
      title: 'Выравнивание',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final target in AlignTarget.values)
            ActionChip(
              avatar: Icon(_alignIcon(target), size: 16),
              label: Text(_alignLabel(target)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _align(target),
            ),
        ],
      ),
    );
  }

  Widget _padCard(ThemeData theme) {
    Widget sideField(TextEditingController ctrl, String label) {
      return SizedBox(
        width: 84,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }

    return _Card(
      title: 'Изменить отступы',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Пустые пиксели вокруг содержимого удаляются, '
            'после чего добавляются указанные отступы.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              sideField(_padTopCtrl, 'Сверху'),
              sideField(_padBottomCtrl, 'Снизу'),
              sideField(_padLeftCtrl, 'Слева'),
              sideField(_padRightCtrl, 'Справа'),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _applyPadding,
            icon: const Icon(Icons.crop, size: 18),
            label: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  Widget _scaleCard(ThemeData theme) {
    return _Card(
      title: 'Масштаб (без сглаживания)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ResourceScaleMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: ResourceScaleMode.contain,
                label: Text('Вписать'),
                tooltip: 'Вписать в поле без обрезки',
              ),
              ButtonSegment(
                value: ResourceScaleMode.cover,
                label: Text('Заполнить'),
                tooltip: 'Заполнить поле целиком, обрезать лишнее',
              ),
              ButtonSegment(
                value: ResourceScaleMode.stretch,
                label: Text('Растянуть'),
                tooltip: 'Ровно до поля (пропорции искажаются)',
              ),
            ],
            selected: {_scaleMode},
            onSelectionChanged: (s) =>
                setState(() => _scaleMode = s.first),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final size in ResourceStore.scalePresets)
                ActionChip(
                  label: Text('$size'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applyScale(size, size),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _wCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ширина',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Высота',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _applyCustomScale,
                child: const Text('ОК'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyCard(ThemeData theme) {
    final history = item.history;
    return _Card(
      title: 'История',
      child: Column(
        children: [
          for (var i = 0; i < history.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 12,
                backgroundColor:
                    i == 0 ? theme.colorScheme.primary : null,
                child: i == 0
                    ? Icon(Icons.image,
                        size: 14, color: theme.colorScheme.onPrimary)
                    : Text('$i',
                        style: theme.textTheme.labelSmall),
              ),
              title: Text(
                i == 0
                    ? 'Оригинал'
                    : i == history.length - 1
                        ? 'Текущий'
                        : 'Версия $i',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text('${history[i].width}×${history[i].height}'),
              trailing: i == history.length - 1
                  ? null
                  : TextButton(
                      onPressed: () => _rollback(i),
                      child: const Text('Откатить'),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _familyCard(ThemeData theme) {
    return _Card(
      title: 'Семейство',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
            selected: {item.family},
            onSelectionChanged: (s) => _changeFamily(s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Удалить'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saveCard(ThemeData theme) {
    return _Card(
      title: null,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Сохранить'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _rollback(0),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('К оригиналу'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
