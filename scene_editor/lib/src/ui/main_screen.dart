import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/editor_scene.dart';
import '../state/app_state.dart';
import 'bottom_bars.dart';
import 'editor_viewport.dart';
import 'form_fields.dart';
import 'left_panel.dart';
import 'resources/resource_screen.dart';
import 'right_panel.dart';
import 'unsaved_dialog.dart';

/// The top-level workspace tabs: the resource editor and the 3D editor
/// modes (compose/texture/lighting/markup).
enum WorkspaceTab { resources, compose, texture, lighting, markup }

/// Below this width the editor switches to the drawer layout (iPad
/// portrait / split view); wide screens keep the three-column layout.
const narrowLayoutWidth = 900.0;

bool isNarrowLayout(double maxWidth) => maxWidth < narrowLayoutWidth;

/// The three-column editor: left panel (models/inspector), 3D viewport,
/// right panel (mode-dependent properties).
class MainScreen extends StatefulWidget {
  final AppState app;
  const MainScreen({super.key, required this.app});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double _leftWidth = 350;
  double _rightWidth = 350;

  static const _minLeft = 180.0, _maxLeft = 420.0;
  static const _minRight = 220.0, _maxRight = 480.0;
  static const _minViewport = 240.0;

  WorkspaceTab _tab = WorkspaceTab.compose;

  void _selectTab(WorkspaceTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab != WorkspaceTab.resources) {
      widget.app.setMode(tab == WorkspaceTab.compose
          ? EditorMode.compose
          : tab == WorkspaceTab.texture
              ? EditorMode.texture
              : tab == WorkspaceTab.lighting
                  ? EditorMode.lighting
                  : EditorMode.markup);
    }
  }

  /// Esc for the whole editor screen, cascading: cancel the armed face-snap
  /// operation → drop the markup meta selection → clear the scene selection
  /// (objects, group, faces). Only reachable when no modal is open: dialogs
  /// (`showDialog`) are navigator routes ABOVE MainScreen and consume Esc
  /// themselves (barrier dismiss), so the event never bubbles down here.
  bool _onEditorKey(KeyDownEvent e) {
    final key = e.logicalKey;
    if (key != LogicalKeyboardKey.escape) return false;
    final app = widget.app;
    if (app.faceSnapMode != null) {
      // Esc cancels the armed face-snap operation.
      app.setFaceSnapMode(null);
      return true;
    }
    if (app.mode == EditorMode.markup && app.selectedMetaId != null) {
      // Esc drops the meta selection (the gizmo returns to the objects).
      app.selectMeta(null);
      return true;
    }
    if (app.mode == EditorMode.lighting && app.selectedLightId != null) {
      // Esc drops the light selection (the scene settings panel returns).
      app.selectLight(null);
      return true;
    }
    final hasSelection = app.selectedCount > 0 ||
        app.selectedObjectId != null ||
        app.selectedFaceKey != null ||
        app.selectedGroupId != null ||
        app.selectedMetaId != null ||
        app.selectedLightId != null ||
        app.selectedFaces.isNotEmpty;
    if (hasSelection) {
      // Same clear as a click on empty viewport space: objects, group, faces.
      app.selectMeta(null);
      app.selectLight(null);
      app.selectObject(null);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final model = app.currentModel;
        return LayoutBuilder(
          builder: (context, constraints) {
            // iPad portrait / split-view: panels live in drawers so the
            // viewport gets the whole width; wide screens keep the
            // resizable three-column layout.
            final narrow = isNarrowLayout(constraints.maxWidth);
            return Focus(
              // Workspace-wide key handling: Esc bubbles here from any
              // focused widget below (viewport, panels) unless a modal
              // dialog above the home route consumed it first.
              onKeyEvent: (node, e) {
                if (e is KeyDownEvent) {
                  return _onEditorKey(e)
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored;
                }
                return KeyEventResult.ignored;
              },
              child: Scaffold(
                key: _scaffoldKey,
                backgroundColor: const Color(0xFF20242C),
                drawer: narrow && _tab != WorkspaceTab.resources
                    ? SizedBox(width: 300, child: LeftPanel(app: app))
                    : null,
                endDrawer: narrow && _tab != WorkspaceTab.resources
                    ? SizedBox(width: 320, child: RightPanel(app: app))
                    : null,
                appBar: AppBar(
                  centerTitle: true,
                  leadingWidth: narrow ? 140 : 220,
                  leading: Row(
                    children: [
                      const SizedBox(width: 4),
                      if (narrow && _tab != WorkspaceTab.resources)
                        IconButton(
                          tooltip: 'Модели и объекты',
                          onPressed: () => _scaffoldKey.currentState
                              ?.openDrawer(),
                          icon: const Icon(Icons.menu),
                        ),
                      IconButton(
                        tooltip: 'Другой проект',
                        onPressed: app.project == null
                            ? null
                            : () async {
                                // Closing the project discards unsaved models.
                                if (await confirmUnsavedChanges(context, app)) {
                                  app.closeProject();
                                }
                              },
                        icon: const Icon(Icons.folder_open),
                      ),
                      IconButton(
                        tooltip: 'Сохранить (Cmd+S)',
                        onPressed: model == null ? null : app.saveCurrent,
                        icon: const Icon(Icons.save),
                      ),
                    ],
                  ),
                  title: SegmentedButton<WorkspaceTab>(
                    showSelectedIcon: false,
                    style: appSegmentedStyle(fontSize: 13),
                    segments: const [
                      ButtonSegment(
                        value: WorkspaceTab.resources,
                        label: Text('Ресурсы'),
                        icon: Icon(Icons.image, size: 18),
                      ),
                      ButtonSegment(
                        value: WorkspaceTab.compose,
                        label: Text('Композиция'),
                        icon: Icon(Icons.view_in_ar, size: 18),
                      ),
                      ButtonSegment(
                        value: WorkspaceTab.texture,
                        label: Text('Текстурирование'),
                        icon: Icon(Icons.brush, size: 18),
                      ),
                      ButtonSegment(
                        value: WorkspaceTab.lighting,
                        label: Text('Освещение'),
                        icon: Icon(Icons.lightbulb_outline, size: 18),
                      ),
                      ButtonSegment(
                        value: WorkspaceTab.markup,
                        label: Text('Разметка'),
                        icon: Icon(Icons.flag, size: 18),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => _selectTab(s.first),
                  ),
                  actions: [
                    if (narrow &&
                        model != null &&
                        _tab != WorkspaceTab.resources)
                      IconButton(
                        tooltip: 'Свойства',
                        onPressed: () =>
                            _scaffoldKey.currentState?.openEndDrawer(),
                        icon: const Icon(Icons.tune),
                      ),
                    IconButton(
                      tooltip: 'Отмена (Cmd+Z)',
                      onPressed: app.canUndo ? app.undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Повтор (Cmd+Shift+Z)',
                      onPressed: app.canRedo ? app.redo : null,
                      icon: const Icon(Icons.redo),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: _tab == WorkspaceTab.resources
                    ? ResourceScreen(
                        app: app,
                        store: app.resources,
                        models: app.model3d,
                      )
                    : Column(
                        children: [
                          if (model != null &&
                              (app.mode == EditorMode.compose ||
                                  app.mode == EditorMode.lighting ||
                                  app.mode == EditorMode.markup))
                            TopBar(app: app),
                          Expanded(
                            child: narrow
                                ? EditorViewport(app: app)
                                : _wideLayout(app, model),
                          ),
                          HintBar(app: app),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  /// The desktop three-column row with resizable panels.
  Widget _wideLayout(AppState app, dynamic model) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft = (_maxLeft).clamp(
            _minLeft, constraints.maxWidth - _minRight - _minViewport);
        final maxRight = (_maxRight).clamp(
            _minRight, constraints.maxWidth - _minLeft - _minViewport);
        final leftW = _leftWidth.clamp(_minLeft, maxLeft);
        final rightW = _rightWidth.clamp(_minRight, maxRight);
        return Row(
          children: [
            SizedBox(width: leftW, child: LeftPanel(app: app)),
            _DragHandle(
              onDelta: (d) => setState(
                () => _leftWidth =
                    (_leftWidth + d).clamp(_minLeft, maxLeft).toDouble(),
              ),
            ),
            Expanded(child: EditorViewport(app: app)),
            _DragHandle(
              // The right handle is the right panel's left edge:
              // dragging it left widens the panel, right narrows.
              onDelta: (d) => setState(
                () => _rightWidth =
                    (_rightWidth - d).clamp(_minRight, maxRight).toDouble(),
              ),
            ),
            SizedBox(width: rightW, child: RightPanel(app: app)),
          ],
        );
      },
    );
  }
}

/// Thin draggable divider between panels (resize-left-right cursor).
class _DragHandle extends StatelessWidget {
  final ValueChanged<double> onDelta;
  const _DragHandle({required this.onDelta});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (e) => onDelta(e.delta.dx),
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 2,
              height: double.infinity,
              color: const Color(0xFF3A4250),
            ),
          ),
        ),
      ),
    );
  }
}
