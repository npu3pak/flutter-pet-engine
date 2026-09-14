import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/editor_scene.dart';
import '../scene/meta_renderer.dart' show metaNeedsCollapse;
import '../state/app_state.dart';

/// The 3D editing viewport: scene, fly camera (RMB+WASD), picking (LMB),
/// gizmo drag, cursor placement. Owns the overlay [EditorScene].
class EditorViewport extends StatefulWidget {
  final AppState app;

  /// Рендер-бэкенд вьюпорта; в тестах подменяется заглушкой без видеокарты.
  final SceneViewportBackend? backend;

  const EditorViewport({super.key, required this.app, this.backend});

  @override
  State<EditorViewport> createState() => _EditorViewportState();
}

class _EditorViewportState extends State<EditorViewport> {
  late final EditorScene editor;
  final FocusNode _focusNode = FocusNode();
  Offset? _lastPointer;
  Offset? _dragStart;

  /// True when the current gizmo drag is a rotation drag (Alt was held at
  /// pointer-down). Captured at drag start so releasing Alt mid-drag doesn't
  /// switch the semantics under the mouse.
  bool _dragRotate = false;

  /// True when the current gizmo drag moves the selected meta object
  /// (markup mode) instead of regular objects.
  bool _metaDrag = false;

  /// True when the current gizmo drag moves/aims the selected light source
  /// (lighting mode) instead of regular objects/metas.
  bool _lightDrag = false;

  /// True while a named cell-meta brush stroke is in progress (paints on
  /// every pointer move; one undo step on release).
  bool _brushPainting = false;

  /// The last hovered cell under the brush (for the cell highlight).
  (int, int)? _hoverCell;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    editor = EditorScene(app.controller);
    // The editor's fly camera drives the scene camera.
    app.controller.camera = editor.fly;
    app.onFocusObject = editor.focusObject;
    app.onFocusMeta = editor.focusMeta;
    app.onFocusLight = editor.focusLight;
    app.addListener(_onAppChanged);
    _onAppChanged();
  }

  @override
  void dispose() {
    app.onFocusObject = null;
    app.onFocusMeta = null;
    app.onFocusLight = null;
    app.removeListener(_onAppChanged);
    editor.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _lastModelId;
  int _lastRevision = -1;

  void _onAppChanged() {
    if (!mounted) return;
    final model = app.currentModel;
    final modelId = model?.id;
    final revision = app.sceneRevision;
    if (modelId != _lastModelId) {
      _lastModelId = modelId;
      _lastRevision = revision;
      if (model != null) {
        editor.rebuild(model);
        editor.frameModel(model);
      } else {
        editor.rebuildOverlays();
      }
    } else if (revision != _lastRevision) {
      _lastRevision = revision;
      if (model != null) editor.syncDocument(model);
    }
    final texture = app.mode == EditorMode.texture;
    final markup = app.mode == EditorMode.markup;
    final lighting = app.mode == EditorMode.lighting;
    final modeChanged = editor.textureMode != texture ||
        editor.markupMode != markup ||
        editor.lightingMode != lighting;
    editor.textureMode = texture;
    editor.markupMode = markup;
    editor.lightingMode = lighting;
    editor.setMetaSelection(
        app.mode == EditorMode.markup ? app.selectedMetaId : null);
    editor.setLightSelection(
        app.mode == EditorMode.lighting ? app.selectedLightId : null);
    _syncRotateMode();
    editor.setSelection(app.selectedObjectId, faceKey: app.selectedFaceKey);
    editor.syncSelectionIds(app.selectedIds);
    editor.syncFaces(app.selectedFaces);
    editor.syncPolyEdit(
      app.polyEditMode,
      app.selectedVertexIndices,
      app.activeVertexIndex,
      app.selectedFaceKey,
    );
    editor.cursor = vm.Vector3(app.cursorX, app.cursorY, app.cursorZ);
    editor.cellCursor = app.cellBrushArmed;
    editor.setGridVisible(app.gridVisible);
    // Mode changes swap whole layers (meta/light/texture gizmos): rebuild.
    // Everything else is a cheap incremental sync — the drag paths already
    // refreshed the overlays for their revision ([EditorScene.syncDocument]
    // no-ops when the revision was handled).
    if (modeChanged) {
      editor.rebuildOverlays();
    } else {
      editor.syncUiState();
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    _focusNode.requestFocus();
    _lastPointer = e.position;
    if (e.kind == PointerDeviceKind.touch) {
      _onTouchDown(e);
      return;
    }
    if (e.buttons & kSecondaryMouseButton != 0) {
      editor.startFly();
      app.flying.value = true;
      return;
    }
    if (e.buttons & kMiddleMouseButton != 0) {
      editor.startOrbit();
      return;
    }
    if (e.buttons & kPrimaryMouseButton == 0) return;
    _primaryDown(e, deferMiss: false);
  }

  /// The LMB picking/drag logic, shared by mouse and touch. With
  /// [deferMiss] a click on empty space does NOT clear the selection here —
  /// the touch layer clears it on tap-up instead (so a drag on empty space
  /// orbits the camera without losing the selection). Returns false when
  /// the press was a deferred miss.
  bool _primaryDown(PointerDownEvent e, {required bool deferMiss}) {
    // Armed face snap («Перенести к грани» / «Параллельно грани»): the
    // click applies the operation to the selected object — picking and the
    // gizmo are bypassed. A non-face click cancels the armed mode.
    final snapMode = app.faceSnapMode;
    if (snapMode != null && app.mode == EditorMode.compose) {
      // The click passes through the SELECTED object: after «Параллельно
      // грани» it lies ON the target face and would swallow the raycast —
      // the snap must attach to the face of another object behind it.
      final snapPick = editor.pickFace(
        e.localPosition,
        context.size ?? Size.zero,
        skipObjectIds: app.selectedIds,
      );
      if (snapPick != null) {
        final (id, faceKey, worldPoint) = snapPick;
        if (faceKey != null) {
          app.applyFaceSnap(
            snapMode,
            id,
            faceKey,
            worldPoint,
            billboardYaw:
                screenParallelYaw(editor.forwardH.x, editor.forwardH.z),
          );
          return true;
        }
      }
      app.setFaceSnapMode(null);
      return true;
    }
    final size = context.size ?? Size.zero;
    final shift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed;
    // Armed vertex insertion (polyhedron, vertices submode): the click lands
    // the vertex on the face under the cursor; picking/gizmo are bypassed.
    if (app.mode == EditorMode.compose &&
        app.polyAddVertexArmed &&
        app.polyEditMode == PolyEditMode.vertices) {
      _addPolyVertexAt(e.localPosition);
      return true;
    }
    final isMarkup = app.mode == EditorMode.markup;
    final isLighting = app.mode == EditorMode.lighting;
    // Named cell-meta brush: paints a 1×1 box at the cell under the pointer;
    // dragging paints a stroke (one undo step per stroke).
    if (isMarkup && app.cellBrushArmed) {
      final cell = _cellUnderPointer(e.localPosition);
      if (cell != null) {
        app.beginCellStroke();
        app.paintCellMeta(app.cellBrushName, cell.$1, cell.$2);
        _brushPainting = true;
        return true;
      }
    }
    // Lighting mode: the light-source markers take the pick FIRST — their
    // shapes are the click targets. Object picking is disabled entirely in
    // this mode (the scene knobs and sources are what it edits).
    final lightPick = isLighting ? editor.pickLight(e.localPosition, size) : null;
    if (lightPick != null) {
      final isDouble = _isDoubleClick(lightPick);
      app.selectLight(lightPick);
      if (isDouble) {
        app.requestFocusLight(lightPick);
      }
      return true;
    }
    // Markup mode: metas take the pick FIRST — their shapes and bubbles
    // are the click targets (objects stay reachable as a fallback).
    final metaPick = isMarkup ? editor.pickMeta(e.localPosition, size) : null;
    if (metaPick != null) {
      final (metaId, isBubble) = metaPick;
      final meta = app.currentModel?.metaById(metaId);
      if (meta != null) {
        final isDouble = _isDoubleClick(metaId);
        app.selectMeta(metaId);
        // A single click on the BUBBLE expands/collapses it (callout
        // style); double-click keeps the focus behavior. Short bubbles
        // never collapse, so they do not toggle either.
        if (isBubble && !isDouble) {
          if (meta.collapsed || metaNeedsCollapse(meta)) {
            app.toggleMetaCollapsed(metaId);
          }
        }
        if (isDouble) {
          app.requestFocusMeta(metaId);
        }
        return true;
      }
    }
    // Object/face picking FIRST: a double-click must be detected even when
    // the second click lands on the gizmo (its invisible fat hit zones would
    // otherwise swallow it and start a drag instead of focusing).
    final pick = isLighting ? null : editor.pick(e.localPosition, size);
    if (pick != null && _isDoubleClick(pick.$1)) {
      // Select the clicked object/face and focus the camera on it.
      final (id, faceKey) = pick;
      if (isMarkup) app.selectMeta(null);
      if (app.mode == EditorMode.texture &&
          app.texSubmode == TexSubmode.faces) {
        app.selectFace(id, faceKey ?? '+z');
      } else {
        app.selectObject(id);
      }
      app.requestFocusObject(id);
      return true;
    }
    // Gizmo drag — compose/markup/lighting only (texturing has its own
    // interaction). The engine owns the handles and the hit test (screen
    // tolerance, priority over the scene); Alt/Option (or the TopBar toggle)
    // swaps the translate gizmo for the rotate gizmo.
    final free =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final gizmoHit = app.mode == EditorMode.compose ||
            isMarkup ||
            isLighting
        ? app.controller.beginGizmoDrag(e.localPosition)
        : null;
    if (gizmoHit != null) {
      final rotate = gizmoHit.gizmo.mode == GizmoMode.rotate;
      _dragRotate = rotate;
      final metaDrag = isMarkup && app.selectedMetaId != null;
      final lightDrag = isLighting && app.selectedLightId != null;
      _metaDrag = metaDrag;
      _lightDrag = lightDrag;
      editor.gizmoSnap = free ? 0 : app.snapStep;
      editor.gizmoSnapDeg = free ? 0 : kRotateSnapDeg;
      if (rotate && lightDrag) {
        editor.beginLightRotateDrag();
      } else if (rotate) {
        editor.beginRotateDrag();
      } else if (metaDrag) {
        editor.beginMetaDrag();
      } else if (lightDrag) {
        editor.beginLightDrag();
      } else {
        editor.beginGizmoDrag();
      }
      if (lightDrag) {
        app.beginLightGizmoDrag();
      } else if (metaDrag) {
        app.beginMetaGizmoDrag();
      } else {
        app.beginGizmoDrag();
      }
      _dragStart = e.localPosition;
      return true;
    }
    if (pick != null) {
      final (id, faceKey) = pick;
      if (isMarkup) app.selectMeta(null);
      // A csg result has no per-face surfaces: any click selects the whole
      // result object even in the faces submode.
      final isCsg = app.currentModel?.objectById(id)?.isCsg == true;
      if (app.mode == EditorMode.compose &&
          app.polyEditMode == PolyEditMode.faces) {
        final obj = app.currentModel?.objectById(id);
        if (obj != null && obj.isPolyhedron) {
          app.selectFace(id, faceKey ?? facesOf(obj).first, shift: shift);
          return true;
        }
      }
      if (app.mode == EditorMode.compose &&
          app.polyEditMode == PolyEditMode.vertices) {
        final obj = app.selectedObject();
        if (obj != null && obj.isPolyhedron) {
          final index = editor.pickPolyVertex(obj, e.localPosition);
          if (index != null) {
            app.selectPolyVertex(index, shift: shift);
            return true;
          }
        }
      }
      if (app.mode == EditorMode.texture &&
          app.texSubmode == TexSubmode.faces &&
          !isCsg) {
        app.selectFace(id, faceKey ?? '+z', shift: shift);
      } else if (shift) {
        app.selectObject(id, shift: true);
      } else {
        app.selectObject(id);
      }
      return true;
    }
    // Miss.
    if (deferMiss) return false;
    // Without shift — clear; with shift — keep the group.
    app.selectMeta(null);
    app.selectLight(null);
    app.selectObject(null, shift: shift);
    _lastClickTime = null;
    _lastClickObject = null;
    return true;
  }

  DateTime? _lastClickTime;
  String? _lastClickObject;

  /// Вставляет вершину в грань выбранного многогранника под нажатием:
  /// луч попадает в грань, мировая точка переводится в локальную рамку сети
  /// и отдаётся состоянию (одна команда undo).
  void _addPolyVertexAt(Offset position) {
    final model = app.currentModel;
    final obj = app.selectedObject();
    if (model == null || obj?.mesh == null) return;
    final targetId = obj!.id;
    final ray = app.controller.screenPointToRay(position);
    final hits = app.controller.raycastAll(
      ray,
      options: RaycastOptions(
        where: (node) => node is ModelNode && node.object.id == targetId,
      ),
    );
    for (final hit in hits) {
      final face = hit.face;
      if (hit.node is! ModelNode || face == null) continue;
      final matrix = objectWorldMatrix(model, obj);
      final inverse = vm.Matrix4.identity()..copyInverse(matrix);
      final local = inverse.transform3(hit.worldPoint);
      app.addPolyVertex(face.key, local);
      return;
    }
  }

  bool _isDoubleClick(String id) {
    final now = DateTime.now();
    // The standard Flutter double-tap window (kDoubleTapTimeout).
    final isDouble = _lastClickObject == id &&
        _lastClickTime != null &&
        now.difference(_lastClickTime!) < kDoubleTapTimeout;
    _lastClickTime = now;
    _lastClickObject = id;
    return isDouble;
  }

  // ── touch gestures (iPad) ────────────────────────────────────────────
  //
  // 1 finger on empty space = orbit (selection clears only on a tap without
  // movement); 2 fingers = pan + pinch zoom. Object/gizmo drags work like
  // the mouse. Desktop (mouse/trackpad) behavior is unchanged.

  final Map<int, Offset> _touches = {};
  bool _touchTapPending = false;
  Offset? _touchStart;
  double _pinchLastDist = 0;
  Offset _pinchMidLast = Offset.zero;

  void _onTouchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.position;
    if (_touches.length == 2) {
      // A second finger cancels a pending tap and any orbit; pan+pinch arm.
      _touchTapPending = false;
      if (editor.orbiting) editor.stopOrbit();
      if (editor.gizmoAxis != null) _endGizmoDrag();
      final pts = _touches.values.toList();
      _pinchLastDist = (pts[0] - pts[1]).distance;
      _pinchMidLast = (pts[0] + pts[1]) / 2;
      return;
    }
    if (!_primaryDown(e, deferMiss: true)) {
      _touchTapPending = true;
      _touchStart = e.position;
    }
  }

  void _onTouchMove(PointerMoveEvent e) {
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.position;
    if (_touches.length == 2) {
      final pts = _touches.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      final mid = (pts[0] + pts[1]) / 2;
      if (_pinchLastDist > 0 && dist > 0) {
        // ratio < 1 (pinch in) = zoom out → positive scrollZoom delta.
        final ratio = dist / _pinchLastDist;
        editor.scrollZoom((1 - ratio) * 10);
        _pinchLastDist = dist;
      }
      final midDelta = mid - _pinchMidLast;
      _pinchMidLast = mid;
      if (midDelta.dx != 0 || midDelta.dy != 0) {
        editor.panCamera(
          midDelta.dx,
          midDelta.dy,
          viewportHeight: context.size?.height ?? 600,
        );
      }
      _lastPointer = e.position;
      return;
    }
    if (_brushPainting) {
      final cell = _cellUnderPointer(e.localPosition);
      if (cell != null) app.paintCellMeta(app.cellBrushName, cell.$1, cell.$2);
      _lastPointer = e.position;
      return;
    }
    if (_touchTapPending) {
      final moved = (e.position - _touchStart!).distance;
      if (moved > kTouchSlop) {
        _touchTapPending = false;
        editor.startOrbit();
        editor.orbit(e.delta.dx, e.delta.dy);
      }
      _lastPointer = e.position;
      return;
    }
    if (editor.orbiting) {
      editor.orbit(e.delta.dx, e.delta.dy);
      _lastPointer = e.position;
      return;
    }
    _dragGizmo(e);
  }

  void _onTouchUp(PointerUpEvent e) {
    final hadTwo = _touches.length == 2;
    _touches.remove(e.pointer);
    if (_brushPainting && _touches.isEmpty) {
      app.endCellStroke();
      _brushPainting = false;
      return;
    }
    if (_touchTapPending) {
      // A tap on empty space clears the selection (like a mouse click).
      _touchTapPending = false;
      app.selectLight(null);
      app.selectObject(null);
      _lastClickTime = null;
      _lastClickObject = null;
    }
    if (editor.orbiting && _touches.isEmpty) editor.stopOrbit();
    if (hadTwo && _touches.length == 1) {
      _pinchLastDist = 0;
    }
    if (_touches.isEmpty && editor.gizmoAxis != null) _endGizmoDrag();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _onTouchMove(e);
      return;
    }
    if (editor.flying) {
      editor.flyLook(e.delta.dx, e.delta.dy);
      _lastPointer = e.position;
      return;
    }
    if (editor.orbiting) {
      editor.orbit(e.delta.dx, e.delta.dy);
      _lastPointer = e.position;
      return;
    }
    if (_brushPainting) {
      final cell = _cellUnderPointer(e.localPosition);
      if (cell != null) app.paintCellMeta(app.cellBrushName, cell.$1, cell.$2);
      _lastPointer = e.position;
      return;
    }
    _dragGizmo(e);
  }

  /// Shared gizmo drag logic (mouse and touch). The position is queued and
  /// applied once per frame ([EditorScene.flushGizmoDrag]) — high-frequency
  /// pointer events collapse into one transform step per frame.
  void _dragGizmo(PointerMoveEvent e) {
    if (!editor.gizmoDragging || _dragStart == null) return;
    final free =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed;
    editor.gizmoSnap = free ? 0 : app.snapStep;
    editor.gizmoSnapDeg = free ? 0 : kRotateSnapDeg;
    editor.queueGizmoDrag(e.localPosition);
    _lastPointer = e.position;
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.kind == PointerDeviceKind.touch) {
      _onTouchUp(e);
      return;
    }
    if (_brushPainting) {
      app.endCellStroke();
      _brushPainting = false;
      _lastPointer = null;
      return;
    }
    if (editor.flying) {
      editor.stopFly();
      app.flying.value = false;
    }
    if (editor.orbiting) editor.stopOrbit();
    if (editor.gizmoDragging) _endGizmoDrag();
    _lastPointer = null;
    _dragStart = null;
    _dragRotate = false;
    _metaDrag = false;
    _lightDrag = false;
  }

  void _endGizmoDrag() {
    // Apply the final queued pointer position before closing the drag.
    editor.flushGizmoDrag();
    app.controller.endGizmoDrag();
    if (_lightDrag) {
      app.endLightGizmoDrag(action: _dragRotate ? 'Поворот' : 'Перенос');
    } else if (_metaDrag) {
      app.endMetaGizmoDrag(action: 'Перенос');
    } else {
      app.endGizmoDrag(action: _dragRotate ? 'Поворот' : 'Перенос');
    }
    editor.endGizmoDrag();
    editor.rebuildOverlays();
    _dragStart = null;
    _dragRotate = false;
    _metaDrag = false;
    _lightDrag = false;
  }

  void _onPointerCancel(PointerCancelEvent e) {
    // The OS can cancel the pointer stream (window deactivation, gesture
    // preemption): close whatever the pointer started.
    if (e.kind == PointerDeviceKind.touch) {
      _touches.clear();
      _pinchLastDist = 0;
      _touchTapPending = false;
    }
    if (_brushPainting) {
      app.endCellStroke();
      _brushPainting = false;
    }
    if (editor.flying) {
      editor.stopFly();
      app.flying.value = false;
    }
    if (editor.orbiting) editor.stopOrbit();
    if (editor.gizmoDragging) _endGizmoDrag();
    _lastPointer = null;
    _dragStart = null;
    _dragRotate = false;
    _metaDrag = false;
    _lightDrag = false;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      editor.scrollZoom(e.scrollDelta.dy);
    }
  }

  bool get _meta =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  bool _onKeyDown(KeyDownEvent e) {
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
      // Alt/Option swaps the translate gizmo for the rotate gizmo.
      _syncAltMode();
      return true;
    }
    // Esc is handled one level up (MainScreen): modal dialogs are separate
    // navigator routes above it, so Esc here would never fire while one is
    // open. Left ignored so the event bubbles to that handler.
    if (key == LogicalKeyboardKey.keyC) {
      editor.keyDown(0x43, false);
      _placeCursor();
      return true;
    }
    final int? code = _keyCode(key);
    if (code != null) {
      editor.keyDown(code, key == LogicalKeyboardKey.shiftLeft);
      return true;
    }
    if (_meta && key == LogicalKeyboardKey.keyS) {
      app.saveCurrent();
      return true;
    }
    if (_meta && key == LogicalKeyboardKey.keyZ) {
      if (_shift) {
        app.redo();
      } else {
        app.undo();
      }
      return true;
    }
    if (_meta && key == LogicalKeyboardKey.keyY) {
      app.redo();
      return true;
    }
    if (_meta && key == LogicalKeyboardKey.keyD) {
      app.duplicateObject();
      return true;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      // Mode-specific selections take the Del key first: the meta selection
      // in the markup mode, the light source in the lighting mode;
      // otherwise the object selection.
      if (app.mode == EditorMode.markup && app.selectedMetaId != null) {
        final id = app.selectedMetaId!;
        app.selectMeta(null);
        app.deleteMeta(id);
        return true;
      }
      if (app.mode == EditorMode.lighting && app.selectedLightId != null) {
        final id = app.selectedLightId!;
        app.selectLight(null);
        app.deleteLight(id);
        return true;
      }
      if (app.selectedCount > 0) {
        app.deleteSelected();
        return true;
      }
    }
    return false;
  }

  void _onKeyUp(KeyUpEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.altLeft ||
        e.logicalKey == LogicalKeyboardKey.altRight) {
      _syncAltMode();
      return;
    }
    final code = _keyCode(e.logicalKey);
    if (code != null) editor.keyUp(code);
  }

  /// Keeps the gizmo in sync with the Alt/Option key (rotate gizmo while
  /// held) and the TopBar «Режим вращения» toggle — the overlays rebuild so
  /// the swap is visible before any click.
  void _syncAltMode() {
    _syncRotateMode();
    editor.rebuildOverlays();
  }

  /// The rotate gizmo is active when Alt is held OR the TopBar toggle is on.
  void _syncRotateMode() {
    editor.setRotateMode(
        HardwareKeyboard.instance.isAltPressed || app.rotateGizmoMode);
  }

  int? _keyCode(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyA) return 0x41;
    if (key == LogicalKeyboardKey.keyD) return 0x44;
    if (key == LogicalKeyboardKey.keyE) return 0x45;
    if (key == LogicalKeyboardKey.keyQ) return 0x51;
    if (key == LogicalKeyboardKey.keyS) return 0x53;
    if (key == LogicalKeyboardKey.keyW) return 0x57;
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      return 0x21;
    }
    return null;
  }

  /// Places the virtual cursor: ray from the mouse onto the horizontal
  /// plane at the cursor's current height, snapped to [AppState.snapStep].
  void _placeCursor() {
    final last = _lastPointer;
    if (last == null) return;
    final model = app.currentModel;
    if (model == null) return;
    final ray = app.controller.screenPointToRay(last);
    final dir = ray.direction;
    if (dir.y.abs() < 1e-6) return;
    final t = (editor.cursor.y - ray.origin.y) / dir.y;
    if (t < 0) return;
    final p = ray.origin + dir * t;
    // world → model-local (inverse of chunkWorld: world x = −(x − (w−1)/2),
    // world z = z − (l−1)/2).
    final modelX = (model.size.w - 1) / 2 - p.x;
    final modelZ = p.z + (model.size.l - 1) / 2;
    final step = app.snapStep;
    // «Нет» (0) = free placement, no snapping. The snap grid is anchored at
    // the bottom-left cell center, so multiples of the step always land on
    // cell centers (integers for step 1, any model size).
    double snapV(double v) =>
        step > 0 ? (v / step).roundToDouble() * step : v;
    app.setCursor(snapV(modelX), editor.cursor.y, snapV(modelZ));
  }

  /// The model-local grid cell (integer center) under the pointer projected
  /// onto the floor plane, or null when outside the grid.
  (int, int)? _cellUnderPointer(Offset position) {
    final model = app.currentModel;
    if (model == null) return null;
    final ray = app.controller.screenPointToRay(position);
    final dir = ray.direction;
    if (dir.y.abs() < 1e-6) return null;
    final t = -ray.origin.y / dir.y;
    if (t < 0) return null;
    final p = ray.origin + dir * t;
    final modelX = (model.size.w - 1) / 2 - p.x;
    final modelZ = p.z + (model.size.l - 1) / 2;
    final x = modelX.round();
    final z = modelZ.round();
    if (x < 0 || x >= model.size.w || z < 0 || z >= model.size.l) return null;
    return (x, z);
  }

  /// Hover highlight: while the brush is armed, move the virtual cursor to
  /// the hovered cell center (the overlay draws the 1×1 cell square).
  void _onHover(PointerHoverEvent e) {
    if (app.mode != EditorMode.markup || !app.cellBrushArmed) return;
    final cell = _cellUnderPointer(e.localPosition);
    if (cell == _hoverCell) return;
    _hoverCell = cell;
    if (cell == null) return;
    app.setCursor(cell.$1.toDouble(), editor.cursor.y, cell.$2.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, e) {
        // Report handled for consumed keys, otherwise the event escapes to
        // the OS and macOS plays its "unhandled hotkey" beep.
        if (e is KeyDownEvent) {
          return _onKeyDown(e) ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (e is KeyUpEvent) {
          _onKeyUp(e);
          final code = _keyCode(e.logicalKey);
          return code != null ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onHover: _onHover,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: _onPointerSignal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Three views: the main one renders the scene (everything
              // except the editor overlay layers), the overlay renders the
              // selection UI (outline, face highlight, cursor) with its own
              // depth buffer, and the top view renders the gizmo handles —
              // always above the outline, never occluded by the selection
              // lines.
              SceneViewport(
                controller: app.controller,
                views: [
                  SceneViewSpec.main(),
                  SceneViewSpec.overlay(),
                  SceneViewSpec.top(),
                ],
                input: const SceneInput.none(),
                warmUp: false,
                backend: widget.backend,
              ),
              _Hud(app: app),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final AppState app;
  const _Hud({required this.app});

  @override
  Widget build(BuildContext context) {
    final model = app.currentModel;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (model != null)
                Text(
                  '${model.name} — ${model.size.w}×${model.size.l}×${model.size.h}'
                  '${model.dirty ? ' •' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
