import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../scene/editor_scene.dart';
import '../state/app_state.dart';
import 'form_fields.dart';
import 'gltf_ref_dialog.dart';
import 'model_ref_dialog.dart';
import 'resource_picker.dart';

/// Top toolbar below the app bar (composition mode): the virtual cursor
/// X/Y/Z fields, the snap step, and the primitive add buttons.
class TopBar extends StatelessWidget {
  final AppState app;
  const TopBar({super.key, required this.app});

  static const _tools = [
    (kind: 'cuboid', label: 'Кубоид', icon: Icons.crop_square),
    (kind: 'trapezoid', label: 'Трапеция', icon: Icons.filter_tilt_shift),
    (kind: 'cylinder', label: 'Цилиндр', icon: Icons.crop_landscape),
    (kind: 'cone', label: 'Конус', icon: Icons.change_history),
    (kind: 'plane', label: 'Плоскость', icon: Icons.crop_16_9),
    (kind: 'sprite', label: 'Спрайт', icon: Icons.image),
    (kind: 'polyhedron', label: 'Многогранник', icon: Icons.polyline),
  ];

  /// Meta tools of the «Разметка» mode (meta objects appear at the cursor).
  static const _metaTools = [
    (kind: 'comment', label: 'Комментарий', icon: Icons.chat_bubble_outline),
    (kind: 'marker', label: 'Маркер', icon: Icons.flag_outlined),
    (kind: 'box', label: 'Бокс', icon: Icons.crop_free),
  ];

  /// Light-source tools of the «Освещение» mode (sources appear at the
  /// cursor).
  static const _lightTools = [
    (kind: 'point', label: 'Точечный', icon: Icons.lightbulb_outline),
    (kind: 'directional', label: 'Направленный', icon: Icons.light_mode),
  ];

  double get _fieldStep => app.snapStep <= 0 ? 0.05 : app.snapStep;

  /// Sprites need a resource key, so the button asks for one first.
  Future<void> _addSprite(BuildContext context) async {
    final dir = app.project?.directory;
    if (dir == null) return;
    var sprites = [
      for (final item in app.resources.items)
        if (item.family == 'sprite') '${item.name}.png',
    ];
    if (sprites.isEmpty) {
      sprites = [
        for (final key
            in app.controller.resources?.spriteKeys ?? const <String>[])
          '$key.png',
      ];
    }
    final key = await pickSpriteDialog(
      context,
      sprites: sprites,
      rootDir: '${dir.path}/sprites',
    );
    if (key == null) return;
    app.addObject('sprite', spriteKey: key);
  }

  void _addTool(BuildContext context, ({String kind, String label, IconData icon}) t) {
    if (t.kind == 'sprite') {
      _addSprite(context);
    } else {
      app.addObject(t.kind);
    }
  }

  /// The «Модель» tool: asks which project model to place «as is» at the
  /// cursor (an instance — edited in its own model, replaced not edited).
  Future<void> _addModelRef(BuildContext context) async {
    final id = await pickModelDialog(context, app);
    if (id == null) return;
    app.addModelRef(id);
  }

  /// The «GLB/GLTF» tool: asks which imported `3d_models/` resource to place
  /// «as is» at the cursor (an instance — scaled/rotated as one, animated by
  /// one of its glTF animations, replaced not edited).
  Future<void> _addGltfRef(BuildContext context) async {
    final name = await pickGltfDialog(context, app);
    if (name == null) return;
    app.addGltfRef(name);
  }

  /// Whether any model of the project may be inserted into the current
  /// scene (something besides the scene itself, without reference cycles).
  bool _hasInsertableModels() {
    final store = app.project;
    final container = app.currentModelId;
    if (store == null || container == null) return false;
    return store.modelIds.any((id) => app.canInsertModel(container, id));
  }

  /// Whether any glTF/GLB resource of the project's `3d_models/` catalog may
  /// be inserted (the catalog exists and its scan has settled).
  bool _hasGltfResources() {
    if (app.project == null) return false;
    final gltf = app.model3d;
    return gltf.scanned && gltf.items.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final markup = app.mode == EditorMode.markup;
    final lighting = app.mode == EditorMode.lighting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF262B34),
        border: Border(bottom: BorderSide(color: Color(0xFF3A4250))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On narrow screens (iPad portrait) the row scrolls horizontally;
          // the flex centering of the tool buttons only works when the
          // width is bounded.
          final tight = constraints.maxWidth >= 1000;
          final row = Row(
            children: [
              const Text(
                'Курсор',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
              for (final (key, value) in [
                ('X', app.cursorX),
                ('Y', app.cursorY),
                ('Z', app.cursorZ),
              ])
                SizedBox(
                  width: 112,
                  child: DoubleField(
                    initial: value,
                    step: _fieldStep,
                    onChanged: (v) {
                      final x = key == 'X' ? v : app.cursorX;
                      final y = key == 'Y' ? v : app.cursorY;
                      final z = key == 'Z' ? v : app.cursorZ;
                      app.setCursor(x, y, z);
                    },
                  ),
                ),
              if (tight)
                Expanded(
                  child: Center(
                    child: _centerButtons(context, markup, lighting),
                  ),
                )
              else ...[
                const SizedBox(width: 24),
                _centerButtons(context, markup, lighting),
              ],
              const Text(
                'Шаг',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
              // ClipRRect: the built-in segment dividers render a couple px
              // taller than the dense control and stick out top/bottom.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SegmentedButton<double>(
                  showSelectedIcon: false,
                  style: appSegmentedStyle(),
                  segments: const [
                    ButtonSegment(value: 0.0, label: Text('Нет')),
                    ButtonSegment(value: 0.1, label: Text('0.1')),
                    ButtonSegment(value: 0.25, label: Text('0.25')),
                    ButtonSegment(value: 0.5, label: Text('0.5')),
                    ButtonSegment(value: 1.0, label: Text('1')),
                  ],
                  selected: {app.snapStep},
                  onSelectionChanged: (s) => app.setSnapStep(s.first),
                ),
              ),
              const SizedBox(width: 12),
              // «Режим вращения» — the Alt/Option equivalent for touch.
              IconButton(
                tooltip: 'Режим вращения (Alt/Option)',
                onPressed: app.toggleRotateMode,
                icon: Icon(
                  app.rotateGizmoMode ? Icons.rotate_left : Icons.rotate_right,
                  size: 18,
                ),
                color: app.rotateGizmoMode
                    ? const Color(0xFF4C9BE8)
                    : Colors.white54,
                style: IconButton.styleFrom(
                  backgroundColor: app.rotateGizmoMode
                      ? const Color(0x334C9BE8)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              // Wireframe всей сцены: рёбра всех объектов движковым оверлеем.
              IconButton(
                tooltip: 'Wireframe всей сцены',
                onPressed: () => app.setWireframe(!app.wireframeEnabled),
                icon: Icon(
                  app.wireframeEnabled ? Icons.grid_on : Icons.grid_off,
                  size: 18,
                ),
                color: app.wireframeEnabled
                    ? const Color(0xFFE53935)
                    : Colors.white54,
                style: IconButton.styleFrom(
                  backgroundColor: app.wireframeEnabled
                      ? const Color(0x33E53935)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          );
          return tight
              ? row
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: row,
                );
        },
      ),
    );
  }

  /// The center tool buttons of the current mode: the lighting sources, the
  /// markup metas, or the compose primitives.
  Widget _centerButtons(BuildContext context, bool markup, bool lighting) {
    if (lighting) return _lightButtons();
    return markup ? _markupButtons() : _toolButtons(context);
  }

  /// The «Разметка» meta tools: Комментарий / Маркер / Бокс. They add a
  /// meta-object at the virtual cursor, like the primitives in compose.
  Widget _markupButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final t in _metaTools)
          Tooltip(
            message: 'Добавить ${t.label.toLowerCase()} в курсор',
            child: FilledButton.tonalIcon(
              onPressed: () => app.addMeta(t.kind),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: Icon(t.icon, size: 15),
              label: Text(
                t.label,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  /// The «Освещение» light-source tools: Точечный / Направленный. They add
  /// a light source at the virtual cursor.
  Widget _lightButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final t in _lightTools)
          Tooltip(
            message: 'Добавить ${t.label.toLowerCase()} свет в курсор',
            child: FilledButton.tonalIcon(
              onPressed: () => app.addLight(t.kind),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: Icon(t.icon, size: 15),
              label: Text(
                t.label,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toolButtons(BuildContext context) {
    final canInsert = _hasInsertableModels();
    final hasGltf = _hasGltfResources();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final t in _tools)
          Tooltip(
            message: 'Добавить ${t.label.toLowerCase()} в курсор',
            child: FilledButton.tonalIcon(
              onPressed: () => _addTool(context, t),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: Icon(t.icon, size: 15),
              label: Text(
                t.label,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        Tooltip(
          message: canInsert
              ? 'Вставить модель проекта в курсор'
              : 'Нет моделей для вставки — создайте и сохраните модель-деталь',
          child: FilledButton.tonalIcon(
            onPressed: canInsert ? () => _addModelRef(context) : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.view_in_ar, size: 15),
            label: const Text(
              'Модель',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
        Tooltip(
          message: hasGltf
              ? 'Вставить GLB/GLTF из ресурсов в курсор'
              : 'Нет импортированных GLB/GLTF — добавьте модель во вкладке «Ресурсы»',
          child: FilledButton.tonalIcon(
            onPressed: hasGltf ? () => _addGltfRef(context) : null,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.animation, size: 15),
            label: const Text(
              'GLB/GLTF',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

/// Narrow full-width bar at the very bottom of the screen with contextual
/// hotkey hints. Context: fly mode > active gizmo drag > selection >
/// texture mode > plain compose.
class HintBar extends StatelessWidget {
  final AppState app;
  const HintBar({super.key, required this.app});

  String _hints() {
    final model = app.currentModel;
    if (model == null) return '';
    final touch = defaultTargetPlatform == TargetPlatform.iOS;
    if (app.mode == EditorMode.markup) {
      final meta = app.selectedMetaId != null;
      final base = touch
          ? 'Тап по мета-объекту — выбор · клик по подписи — раскрыть/схлопнуть'
          : 'ЛКМ — выбрать мета-объект · клик по подписи — раскрыть/схлопнуть'
              ' · C — курсор · Del — удалить мета · Cmd+Z — отмена'
              ' · Cmd+S — сохранить';
      if (!meta) {
        return base + (touch
            ? ' · инструменты добавляют мета в курсор'
            : ' · инструменты выше добавляют мета в курсор');
      }
      return base +
          (touch
              ? ' · гизмо двигает мета'
              : ' · гизмо двигает мета · 2×клик — фокус камеры');
    }
    if (app.mode == EditorMode.lighting) {
      final light = app.selectedLightId != null;
      final base = touch
          ? 'Тап по источнику — выбор · без выбора — настройки сцены справа'
          : 'ЛКМ — выбрать источник · без выбора — настройки освещения сцены'
              ' справа · C — курсор · Del — удалить источник · Cmd+Z — отмена'
              ' · Cmd+S — сохранить';
      if (!light) {
        return base;
      }
      return base +
          (touch
              ? ' · гизмо двигает источник'
              : ' · гизмо двигает источник · Alt/кнопка вращения поворачивает'
                  ' направленный · 2×клик — фокус камеры');
    }
    if (app.mode == EditorMode.compose) {
      if (app.selectedCount > 0) {
        return touch
            ? 'Тап — выбор · 2×тап — фокус камеры · Cmd+D — дублировать'
                ' · Del — удалить · Cmd+Z — отмена'
            : 'ЛКМ — выбор · 2×клик — фокус камеры · Shift+ЛКМ — мультивыбор'
                ' · Cmd+D — дублировать · Del — удалить · Cmd+Z — отмена';
      }
      return touch
          ? 'Палец на пустом месте — вращение · 2 пальца — панорама · '
              'пинч — зум · тап — выбор'
          : 'ЛКМ — выбор · ПКМ — полёт · СКМ — вращение · C — курсор'
              ' · Del — удалить · Cmd+D — дублировать · Cmd+Z — отмена · Cmd+S — сохранить';
    }
    return touch
        ? 'Тап по объекту/грани — выбор · Cmd+Z — отмена · Cmd+S — сохранить'
        : 'ЛКМ — выбрать грань · Cmd+Z — отмена · Cmd+S — сохранить';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.flying,
      builder: (context, flying, _) {
        final text = flying
            ? 'WASD — движение · Q/E — вниз/вверх · Shift — быстрее · отпустить ПКМ — выход'
            : _hints();
        return Container(
          width: double.infinity,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFF1B1F26),
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}
