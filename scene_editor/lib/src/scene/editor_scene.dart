import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../services/app_log.dart';
import 'geometry_utils.dart';
import 'light_renderer.dart';
import 'meta_renderer.dart';

/// World-space grid line pairs for a model of [w]×[l] cells, with the
/// origin at the model center (world x = −column).
List<(double, double, double)> gridLinePoints(int w, int l) {
  final pts = <(double, double, double)>[];
  final hw = w / 2, hl = l / 2;
  for (var c = -hw; c <= hw; c += 1) {
    final x = -c; // world x = -column
    pts.add((x, 0, -hl));
    pts.add((x, 0, hl));
  }
  for (var r = -hl; r <= hl; r += 1) {
    pts.add((hw, 0, r));
    pts.add((-hw, 0, r));
  }
  return pts;
}

/// The object's true edges in world space (endpoint pairs), rotation-aware
/// (Rz·Rx·Ry — the renderer's matrix) and per kind: cuboid/trapezoid get
/// their 12 edges, cylinders two rings plus verticals, planes and sprites
/// their quad outline. A model instance ([modelRefKind]) resolves its
/// content recursively through [modelOf] (its nested instances, csg leaves
/// and, for missing sources, the fuchsia cube footprint). [billboardYaw] is
/// the sprite billboard's screen-parallel yaw at rebuild time.
List<((double, double, double), (double, double, double))> objectEdgeSegments(
  ModelObject obj, {
  required double billboardYaw,
  double originX = 0,
  double originZ = 0,
  ModelData? Function(String id)? modelOf,
}) {
  final out = <((double, double, double), (double, double, double))>[];
  // World anchor of the object (mirrored chunkWorld translation); sprite
  // billboards additionally carry the −X mirror of reorientBillboards.
  final anchor = vm.Vector3(-(obj.x - originX), obj.y, obj.z - originZ);
  final base = obj.kind == 'sprite'
      ? spriteBillboardMatrix(anchor, billboardYaw)
      : vm.Matrix4.translation(anchor) * objectRotation(obj);
  if (obj.isGltfRef) {
    // A glTF/GLB instance outlines its cached footprint box (the fitted
    // local bounds) resolved under the instance transform — the same box a
    // missing resource renders as a fuchsia cube. Real silhouette edges of
    // the imported content are not available CPU-side.
    final m =
        base * vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
    _appendShapeEdges(out, gltfFootprintBox(obj), m, billboardYaw);
    return out;
  }
  if (obj.isModelRef) {
    // The instance chain maps the referenced model's local space to world:
    // its own anchor first, then the whole chain for nested content.
    final m = base * vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
    final target = modelOf?.call(obj.refModelId);
    if (target == null) {
      _appendShapeEdges(out, modelRefFootprintBox(obj), m, billboardYaw);
    } else {
      _collectContentEdges(
        out,
        target,
        m,
        billboardYaw,
        modelOf,
        <String>{target.id},
      );
    }
    return out;
  }
  _appendShapeEdges(out, obj, base, billboardYaw);
  return out;
}

void _appendEdge(List<((double, double, double), (double, double, double))> out,
    vm.Vector3 a, vm.Vector3 b) {
  out.add(((a.x, a.y, a.z), (b.x, b.y, b.z)));
}

/// The edges of a single (possibly nested) object whose anchor-relative
/// offsets map to the world through [m]. Covers the renderer's primitive
/// kinds; csg results have no own edges ([modelRefKind] handled elsewhere).
void _appendShapeEdges(
  List<((double, double, double), (double, double, double))> out,
  ModelObject obj,
  vm.Matrix4 m,
  double billboardYaw,
) {
  vm.Vector3 w(double lx, double ly, double lz) =>
      (m * objectScale(obj)).transform3(vm.Vector3(lx, ly, lz));

  switch (obj.kind) {
    case 'cuboid':
      final wd = obj.dim('w', 1), h = obj.dim('h', 1), d = obj.dim('d', 1);
      final hx = wd / 2, hz = d / 2;
      final c = [
        w(-hx, 0, -hz), w(hx, 0, -hz), w(hx, 0, hz), w(-hx, 0, hz),
        w(-hx, h, -hz), w(hx, h, -hz), w(hx, h, hz), w(-hx, h, hz),
      ];
      const pairs = [
        (0, 1), (1, 2), (2, 3), (3, 0), // bottom
        (4, 5), (5, 6), (6, 7), (7, 4), // top
        (0, 4), (1, 5), (2, 6), (3, 7), // verticals
      ];
      for (final (a, b) in pairs) {
        _appendEdge(out, c[a], c[b]);
      }
    case 'trapezoid':
      final bw = obj.dim('bottomW', 1), bd = obj.dim('bottomD', 1);
      final tw = obj.dim('topW', bw), td = obj.dim('topD', bd);
      final h = obj.dim('h', 0.5);
      final b = [
        w(-bw / 2, 0, -bd / 2), w(bw / 2, 0, -bd / 2),
        w(bw / 2, 0, bd / 2), w(-bw / 2, 0, bd / 2),
      ];
      final t = [
        w(-tw / 2, h, -td / 2), w(tw / 2, h, -td / 2),
        w(tw / 2, h, td / 2), w(-tw / 2, h, td / 2),
      ];
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        _appendEdge(out, b[i], b[j]);
        _appendEdge(out, t[i], t[j]);
        _appendEdge(out, b[i], t[i]);
      }
    case 'cylinder':
      final bottomR = obj.dim('bottomR', 0.25);
      final topR = obj.dim('topR', bottomR);
      final h = obj.dim('h', 1);
      const n = 16;
      final bot = [
        for (var i = 0; i < n; i++)
          w(bottomR * math.cos(2 * math.pi * i / n), 0,
              bottomR * math.sin(2 * math.pi * i / n)),
      ];
      final top = [
        for (var i = 0; i < n; i++)
          w(topR * math.cos(2 * math.pi * i / n), h,
              topR * math.sin(2 * math.pi * i / n)),
      ];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        _appendEdge(out, bot[i], bot[j]);
        _appendEdge(out, top[i], top[j]);
      }
      _appendEdge(out, bot[0], top[0]);
      _appendEdge(out, bot[n ~/ 2], top[n ~/ 2]);
    case 'plane':
      final wd = obj.dim('w', 1), d = obj.dim('d', 1);
      final c = obj.flag('vertical')
          ? [
              w(-wd / 2, 0, 0), w(wd / 2, 0, 0),
              w(wd / 2, d, 0), w(-wd / 2, d, 0),
            ]
          : [
              w(-wd / 2, 0, d / 2), w(wd / 2, 0, d / 2),
              w(wd / 2, 0, -d / 2), w(-wd / 2, 0, -d / 2),
            ];
      for (var i = 0; i < 4; i++) {
        _appendEdge(out, c[i], c[(i + 1) % 4]);
      }
    case 'sprite':
      final wd = obj.dim('w', 1), h = obj.dim('h', 1);
      final c = [
        w(-wd / 2, 0, 0), w(wd / 2, 0, 0),
        w(wd / 2, h, 0), w(-wd / 2, h, 0),
      ];
      for (var i = 0; i < 4; i++) {
        _appendEdge(out, c[i], c[(i + 1) % 4]);
      }
    case polyhedronKind:
      // Рёбра многогранника — контуры его граней (внешние и дырки), без
      // диагоналей триангуляции.
      final mesh = obj.mesh;
      if (mesh == null) return;
      for (final face in mesh.faces) {
        for (final loop in [face.outer, ...face.holes]) {
          final count = loop.vertices.length;
          if (count < 2) continue;
          for (var i = 0; i < count; i++) {
            final a = mesh.vertices[loop.vertices[i]];
            final b = mesh.vertices[loop.vertices[(i + 1) % count]];
            _appendEdge(out, w(a.x, a.y, a.z), w(b.x, b.y, b.z));
          }
        }
      }
  }
}

/// Recursively collects the world edges of every visible object of [src]
/// (a model placed as an instance), including its nested instances, csg
/// leaves and fuchsia placeholders for missing sources. [m] maps the
/// source model's STANDALONE frame (its grid centered and X-mirrored
/// through [chunkWorld]) into the world — content objects are anchored via
/// [sourceAnchor] of [src]'s grid, exactly like the renderer's
/// `_buildNestedScene`, so the outline hugs the rendered instance.
void _collectContentEdges(
  List<((double, double, double), (double, double, double))> out,
  ModelData src,
  vm.Matrix4 m,
  double billboardYaw,
  ModelData? Function(String id)? modelOf,
  Set<String> guard,
) {
  for (final obj in src.visibleObjects()) {
    final anchor = sourceAnchor(src.size.w, src.size.l, obj);
    if (obj.isCsg) {
      for (final leaf in src.csgLeavesOf(obj.id)) {
        final la = sourceAnchor(src.size.w, src.size.l, leaf);
        final om = m * vm.Matrix4.translation(la) * objectRotation(leaf);
        _appendShapeEdges(out, leaf, om, billboardYaw);
      }
      continue;
    }
    if (obj.isModelRef) {
      final inner = modelOf?.call(obj.refModelId);
      final chain = m *
          vm.Matrix4.translation(anchor) *
          objectRotation(obj) *
          vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
      if (inner == null) {
        // A missing inner source outlines its footprint cube at the
        // source-anchored cell, like the renderer's placeholder.
        _appendShapeEdges(out, modelRefFootprintBox(obj), chain, billboardYaw);
      } else if (guard.add(inner.id)) {
        _collectContentEdges(out, inner, chain, billboardYaw, modelOf, guard);
        guard.remove(inner.id);
      }
      continue;
    }
    if (obj.isGltfRef) {
      // A gltf instance outlines its footprint box at the source-anchored
      // cell (the box is centered on the anchor, like the renderer places
      // its content).
      final chain = m *
          vm.Matrix4.translation(anchor) *
          objectRotation(obj) *
          vm.Matrix4.diagonal3Values(obj.scale, obj.scale, obj.scale);
      _appendShapeEdges(out, gltfFootprintBox(obj), chain, billboardYaw);
      continue;
    }
    final rot = obj.kind == 'sprite'
        ? vm.Matrix4.diagonal3Values(-1, 1, 1) *
            vm.Matrix4.rotationY(billboardYaw)
        : objectRotation(obj);
    final om = m * vm.Matrix4.translation(anchor) * rot;
    _appendShapeEdges(out, obj, om, billboardYaw);
  }
}

/// The rotate gizmo's default snap step (degrees); Shift/Ctrl = free.
const kRotateSnapDeg = 5.0;

enum EditorMode { compose, texture, lighting, markup }

/// Texture-mode submode: click picks whole objects or individual faces.
enum TexSubmode { objects, faces }

/// Правка выбранного многогранника: весь объект, его грани или вершины.
/// По умолчанию всегда [object] — в грани/вершины переходят явно.
enum PolyEditMode { object, faces, vertices }

/// Шаг адаптивной сетки: легаси-модели (≤ 64 клеток) сохраняют клетку 1,
/// крупные карты 1:1 удваивают шаг, пока число линий на ось не станет ≤ 64.
double adaptiveGridCell(int w, int l) {
  final span = math.max(w, l);
  var cell = 1.0;
  while (span / cell > 64) {
    cell *= 2;
  }
  return cell;
}

/// Owns the editor's overlay world: grid/frame/cursor/selection, the
/// transform gizmo, meta-object overlays, light-source markers and picking.
/// The document itself is rendered by the [SceneController]; this class
/// mirrors the AppState selection and rebuilds the overlay nodes.
class EditorScene {
  EditorScene(this.controller) {
    controller.add(overlays);
    overlays.add(selectionOverlay);
    controller.add(metaOverlay.root);
    controller.add(lightGizmoRoot);
    metaOverlay.root.layer = SceneLayer.overlay;
    overlays.layer = SceneLayer.overlay;
    selectionOverlay.layer = SceneLayer.overlay;
    lightGizmoRoot.layer = SceneLayer.overlay;
    // The translate/rotate handles come from the engine: constant screen
    // size, top layer, depth-independent hit priority over the scene.
    moveGizmo = controller.addGizmo(
      GizmoNode(
        id: 'editor-gizmo-move',
        mode: GizmoMode.translate,
        anchor: vm.Vector3.zero(),
      ),
    );
    rotateGizmo = controller.addGizmo(
      GizmoNode(
        id: 'editor-gizmo-rotate',
        mode: GizmoMode.rotate,
        anchor: vm.Vector3.zero(),
      ),
    );
    moveGizmo.visible = false;
    rotateGizmo.visible = false;
    moveGizmo.onDrag = _onGizmoMove;
    rotateGizmo.onDrag = _onGizmoRotate;
    _frameListener = (elapsed, dt) => update(dt);
    controller.addFrameListener(_frameListener);
  }

  /// The scene controller: document nodes, camera, picking.
  final SceneController controller;

  /// The engine translate gizmo of the editor (objects, metas, lights).
  late final GizmoNode moveGizmo;

  /// The engine rotate gizmo of the editor (objects, directional lights).
  late final GizmoNode rotateGizmo;

  /// The fly camera of the editor (fly/orbit/zoom/focus).
  final FlyCameraController fly = FlyCameraController();

  late final SceneFrameListener _frameListener;

  /// Overlay root: grid, frame, cursor, selection, gizmo handles.
  final GroupNode overlays = GroupNode(id: 'editor-overlays');

  /// Selection layer inside [overlays]: outline + face highlight. Rebuilt
  /// per frame when a billboard sprite is selected (its yaw follows the
  /// camera), so it stays a separate child node.
  final GroupNode selectionOverlay = GroupNode(id: 'editor-selection');

  /// The markup (meta-object) layer of the «Разметка» mode. Rendered on the
  /// overlay layer: metas always composite above the objects and only real
  /// object surfaces can occlude them (their CPU probe excludes the grid,
  /// gizmos and other metas).
  late final MetaOverlayLayer metaOverlay = MetaOverlayLayer(
    controller: controller,
  );

  /// The layout-independent light gizmos; all their nodes are managed by
  /// this layer.
  late final LightGizmoLayer lightGizmos = LightGizmoLayer();

  /// The root group of the light gizmos (the layer owns the nodes).
  GroupNode get lightGizmoRoot => lightGizmos.root;

  /// True while the editor is in the texture mode: the gizmo is hidden and
  /// face selection drives the outlines.
  bool textureMode = false;

  /// True in the «Разметка» mode: the meta layer is visible and selectable,
  /// and a selected meta gets the move gizmo.
  bool markupMode = false;

  /// True in the «Освещение» mode: the light-source markers are visible and
  /// selectable, and a selected source gets the move gizmo (directional
  /// sources the rotate gizmo too — it aims the light).
  bool lightingMode = false;

  /// True when the Alt/Option key is held: the translate gizmo is replaced
  /// by the rotate gizmo (rings), and gizmo drags rotate the selection.
  bool rotateMode = false;

  void setRotateMode(bool v) => rotateMode = v;

  /// True when the rotate gizmo is the active one AND the selection has at
  /// least one rotatable object: csg nodes have no own orientation (their
  /// leaves are moved as a whole, and spinning them around their own axes
  /// would break the result) — the move gizmo stays for them, sprites too.
  bool get rotationActive =>
      rotateMode &&
      controller.model != null &&
      controller.model!.moveExpansion(selectedIds).isNotEmpty &&
      selectedObjects(controller.model!).every(
          (o) => o.kind != 'sprite' && o.kind != 'csg');

  /// Mirrors the AppState's selected light source id while in the lighting
  /// mode (the caller rebuilds the overlays).
  String? selectedLightId;

  void setLightSelection(String? id) => selectedLightId = id;

  ModelLight? selectedLight(ModelData model) {
    final id = selectedLightId;
    if (id == null) return null;
    return model.lighting.lightById(id);
  }

  /// True when the rotate gizmo would aim a selected directional light:
  /// the Alt/Option state comes via [rotateMode] like the object gizmo.
  bool get lightRotateActive {
    if (!lightingMode || !rotateMode) return false;
    final model = controller.model;
    final light = model == null ? null : selectedLight(model);
    return light != null && light.isDirectional;
  }

  /// Selected faces ('id:faceKey') in the faces submode.
  final Set<String> faceSelection = {};

  /// Правка многогранника: режим, выбранные вершины и активные элементы —
  /// зеркало состояния AppState для подсветки и гизмо.
  PolyEditMode polyEditMode = PolyEditMode.object;
  final Set<int> vertexSelection = {};
  int? activeVertexIndex;
  String? activeFaceKey;

  /// Fired when an overlay-affecting change happens (selection, cursor,
  /// camera-ready state) — the viewport rebuilds overlays.
  void Function()? onChanged;

  ModelData? _resolveInstance(String id) => controller.resources?.model(id);

  // ── camera (delegates to the engine's fly camera) ────────────────────

  vm.Vector3 get eye => fly.eye;
  set eye(vm.Vector3 value) => fly.eye = value;

  double get yaw => fly.yaw;
  set yaw(double value) => fly.yaw = value;

  double get pitch => fly.pitch;
  set pitch(double value) => fly.pitch = value;

  /// Horizontal part of the camera's forward (view) direction.
  vm.Vector3 get forwardH => fly.forwardH;

  /// The camera's full view direction.
  vm.Vector3 get forward {
    final s = math.sin(yaw), c = math.cos(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    return vm.Vector3(s * cp, -sp, c * cp);
  }

  /// Horizontal part of the camera's local +X (screen-right). Pure helper
  /// kept public for tests.
  static vm.Vector3 horizontalRight(double yaw) {
    final s = math.sin(yaw), c = math.cos(yaw);
    return vm.Vector3(c, 0, -s).normalized();
  }

  vm.Vector3 get rightH => horizontalRight(yaw);

  void frameModel(ModelData model) {
    final w = model.size.w, l = model.size.l, h = model.size.h;
    // Камера готова к крупным картам 1:1: клип-плоскости и скорость полёта
    // масштабируются; для легаси-габаритов значения не меняются.
    fly.configureForExtent(math.sqrt((w * w + l * l + h * h).toDouble()));
    // The model center: cell-center coords ((w−1)/2, (l−1)/2) map to
    // world (0,0,0) — the model stays centered in the view.
    final center = chunkWorld((w - 1) / 2, (l - 1) / 2, w, l);
    // Stand on the +Z side of the model looking toward −Z (yaw = π), so the
    // model's +Z axis (the blue gizmo handle) points at the user. Camera
    // height scales with both model height and length so the whole model
    // stays in frame at a fixed 0.5 rad (~29°) downward pitch. Wide rows
    // need backing away too (vertical fov 55°, viewport is wider than tall).
    final span = math.max(l.toDouble(), w * 0.8);
    final dist = span * 0.9 + 3;
    final height = math.max(2.5, h * 1.2 + 2);
    var y = height.clamp(2.5, math.max(60.0, height)).toDouble();
    y = math
        .max(y, span * 0.55)
        .clamp(2.5, math.max(120.0, span * 0.55))
        .toDouble();
    fly.eye = vm.Vector3(center.x, y, center.z + dist);
    fly.yaw = math.pi;
    fly.pitch = 0.5;
    onChanged?.call();
  }

  void startFly() => fly.startFly();

  void stopFly() => fly.stopFly();

  void keyDown(int logicalKey, bool shift) =>
      fly.keyDown(logicalKey, shift: shift);

  void keyUp(int logicalKey) => fly.keyUp(logicalKey);

  bool get flying => fly.flying;

  void flyLook(double dx, double dy) => fly.flyLook(dx, dy);

  bool _orbiting = false;
  bool get orbiting => _orbiting;

  void startOrbit() {
    _orbiting = true;
    fly.startOrbit(_focusPoint());
  }

  void stopOrbit() {
    _orbiting = false;
    fly.stopOrbit();
  }

  void orbit(double dx, double dy) => fly.orbit(dx, dy);

  void panCamera(double dx, double dy, {required double viewportHeight}) =>
      fly.pan(dx, dy, focus: _focusPoint(), viewportHeight: viewportHeight);

  void scrollZoom(double delta) {
    final size = controller.model?.size;
    // Крупные карты (1:1) требуют большего потолка отдаления; для
    // легаси-моделей максимум не меньше прежнего (расчёт по 64×64×32).
    final maxDistance = size == null
        ? FlyCameraController.zoomMaxDistance(64, 64, 32)
        : math.max(
            FlyCameraController.zoomMaxDistance(64, 64, 32),
            FlyCameraController.zoomMaxDistance(size.w, size.l, size.h),
          );
    fly.scrollZoom(delta, focus: _zoomFocus(), maxDistance: maxDistance);
  }

  /// Per-frame upkeep after the controller's own frame: deduplicated gizmo
  /// drag, meta bubbles and occlusion ghosts, plus the billboard selection
  /// outline.
  void update(double dt) {
    // Apply the coalesced gizmo drag once per frame (pointer events arrive
    // much faster than frames; the gizmo computes absolute deltas from the
    // drag start, so only the last position matters).
    flushGizmoDrag();
    if (dt > 0.05) {
      logStage(
        'editor',
        'slow frame ${(dt * 1000).round()}ms'
            '${flying ? ' (flying)' : ''}',
      );
    }
    final model = controller.model;
    if (markupMode && model != null && model.metas.isNotEmpty) {
      final f = forwardH;
      final moved = _cameraMoved();
      metaOverlay.tick(model, f.x, f.z, eye, cameraMoved: moved);
    }
    // Billboard sprites face the camera per frame, so their selection
    // outline must follow the yaw while the camera turns. The selection is
    // cached: the outline is only rebuilt when the yaw actually changed.
    if (_selectionBillboards) {
      final model = controller.model;
      if (model != null) {
        final yaw = screenParallelYaw(forwardH.x, forwardH.z);
        if ((yaw - _selectionYaw).abs() > 1e-6) {
          _selectionDirty = true;
          _refreshSelection(model, force: true);
        }
      }
    }
  }

  double _lastProbeYaw = double.nan;
  double _lastProbePitch = double.nan;
  vm.Vector3 _lastProbeEye = vm.Vector3(0, 0, 0);
  bool _probeArmed = true;

  /// Whether the camera moved since the last occlusion probe. The probe
  /// also re-runs right after a meta/object edit (a scene-revision rebuild
  /// arms it via [armMetaProbe]).
  bool _cameraMoved() {
    final moved = _probeArmed ||
        (eye - _lastProbeEye).length2 > 1e-8 ||
        yaw != _lastProbeYaw ||
        pitch != _lastProbePitch;
    _lastProbeEye = vm.Vector3.copy(eye);
    _lastProbeYaw = yaw;
    _lastProbePitch = pitch;
    _probeArmed = false;
    return moved;
  }

  /// Re-probes the meta occlusion on the next tick (after any structural
  /// change: a meta or object move can cover/uncover another meta).
  void armMetaProbe() => _probeArmed = true;

  // ── coalesced gizmo drag ─────────────────────────────────────────────

  ui.Offset? _pendingGizmoDrag;

  /// Queues the latest gizmo pointer position; the drag is applied once per
  /// frame by [flushGizmoDrag].
  void queueGizmoDrag(ui.Offset point) => _pendingGizmoDrag = point;

  /// Applies the queued gizmo drag immediately (frame tick and drag end).
  void flushGizmoDrag() {
    final point = _pendingGizmoDrag;
    if (point == null) return;
    _pendingGizmoDrag = null;
    controller.updateGizmoDrag(point);
  }

  bool get _selectionHasBillboard {
    final model = controller.model;
    if (model == null) return false;
    for (final o in selectedObjects(model)) {
      if (o.kind == 'sprite') return true;
      if (o.isModelRef &&
          _contentHasBillboards(o.refModelId, <String>{o.refModelId})) {
        return true;
      }
    }
    return false;
  }

  /// Whether the model [id] (an instance source) contains any billboard
  /// sprite, recursively (their outline yaw follows the camera per frame).
  bool _contentHasBillboards(String id, Set<String> guard) {
    final m = _resolveInstance(id);
    if (m == null) return false;
    for (final o in m.objects) {
      if (o.isCsg) continue; // operands render through the result only
      if (o.isModelRef) {
        if (guard.add(o.refModelId) &&
            _contentHasBillboards(o.refModelId, guard)) {
          return true;
        }
        continue;
      }
      if (o.kind == 'sprite') return true;
    }
    return false;
  }

  vm.Vector3 _focusPoint() {
    final model = controller.model;
    if (model == null) return vm.Vector3.zero();
    final objs = model.moveExpansion(selectedIds);
    if (objs.isNotEmpty) {
      return groupAnchor(model);
    }
    return vm.Vector3.zero();
  }

  vm.Vector3 _zoomFocus() {
    final model = controller.model;
    if (model == null) return vm.Vector3.zero();
    final objs = model.moveExpansion(selectedIds);
    if (objs.isEmpty) {
      return vm.Vector3(0, model.size.h / 2, 0);
    }
    return groupAnchor(model);
  }

  /// Moves the camera to look at [obj] (the double-click focus).
  void focusObject(ModelObject obj) {
    final model = controller.model;
    if (model == null) return;
    fly.lookAt(_anchorWorld(obj, model));
    onChanged?.call();
  }

  /// Moves the camera to look at [meta] (the «Разметка» double-click focus).
  void focusMeta(ModelMeta meta) {
    final model = controller.model;
    if (model == null) return;
    final top = meta.kind == metaKindBox
        ? meta.y + meta.dim('h', 1.0)
        : metaBubbleBottomY(meta);
    final w = chunkWorld(meta.x, meta.z, model.size.w, model.size.l);
    fly.lookAt(vm.Vector3(w.x, (meta.y + top) / 2, w.z));
    onChanged?.call();
  }

  /// Moves the camera to look at [light] (the «Освещение» double-click
  /// focus).
  void focusLight(ModelLight light) {
    final model = controller.model;
    if (model == null) return;
    fly.lookAt(lightAnchorWorld(light, model));
    onChanged?.call();
  }

  // ── selection ────────────────────────────────────────────────────────

  String? selectedObjectId;
  String? selectedFaceKey; // only in texture mode
  final Set<String> selectedIds = {};
  String? gizmoAxis; // 'x' | 'y' | 'z' while dragging
  vm.Vector3 cursor = vm.Vector3.zero(); // model-local, origin = model center

  /// When true the cursor overlay also draws the 1×1 cell square under the
  /// cursor — the named cell-meta brush highlight.
  bool cellCursor = false;

  ModelObject? selectedObject(ModelData model) {
    if (selectedObjectId == null) return null;
    for (final o in model.objects) {
      if (o.id == selectedObjectId) return o;
    }
    return null;
  }

  /// All selected objects in model order.
  List<ModelObject> selectedObjects(ModelData model) => [
        for (final o in model.objects)
          if (selectedIds.contains(o.id)) o,
      ];

  /// World position of the group anchor: the union AABB center for a group,
  /// otherwise the single object's base-center anchor. Csg nodes expand to
  /// their leaves (they carry no own geometry); model instances contribute
  /// their resolved content bounds.
  vm.Vector3 groupAnchor(ModelData model) {
    final objs = model.moveExpansion(selectedIds);
    if (objs.length < 2) {
      if (objs.isEmpty) {
        final obj = selectedObject(model);
        return obj == null ? vm.Vector3.zero() : _anchorWorld(obj, model);
      }
      return _anchorWorld(objs.first, model);
    }
    final (minX, minY, minZ, maxX, maxY, maxZ) = unionAabbResolved(
      objs,
      modelOf: (id) => _resolveInstance(id),
    );
    final w = chunkWorld(
        (minX + maxX) / 2, (minZ + maxZ) / 2, model.size.w, model.size.l);
    return vm.Vector3(w.x, (minY + maxY) / 2, w.z);
  }

  void setSelection(String? objectId, {String? faceKey}) {
    selectedObjectId = objectId;
    selectedFaceKey = faceKey;
    selectedIds
      ..clear()
      ..addAll(objectId == null ? const [] : [objectId]);
    _selectionDirty = true;
    onChanged?.call();
  }

  void syncSelectionIds(Set<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    _selectionDirty = true;
    onChanged?.call();
  }

  void syncFaces(Set<String> faces) {
    faceSelection
      ..clear()
      ..addAll(faces);
    _selectionDirty = true;
    onChanged?.call();
  }

  /// Синхронизирует режим правки многогранника и его подвыделения.
  void syncPolyEdit(
    PolyEditMode mode,
    Set<int> vertices,
    int? activeVertex,
    String? activeFace,
  ) {
    polyEditMode = mode;
    vertexSelection
      ..clear()
      ..addAll(vertices);
    activeVertexIndex = activeVertex;
    activeFaceKey = activeFace;
    _selectionDirty = true;
    onChanged?.call();
  }

  // ── picking ──────────────────────────────────────────────────────────

  /// Raycast for a pickable object/face node; returns (objectId, faceKey).
  (String, String?)? pick(ui.Offset pos, ui.Size size) {
    final p = pickFace(pos, size);
    return p == null ? null : (p.$1, p.$2);
  }

  /// Raycast for a pickable document object plus the world-space hit point
  /// (used by the face-snap tools: the cylinder side's normal and position
  /// depend on the click angle). [skipObjectIds] skips those objects' faces
  /// — the armed snap passes the selection, so the click passes THROUGH the
  /// selected object (which lies on the target face after «Параллельно
  /// грани») to the face behind it.
  ///
  /// In the texture mode model instances and glTF/GLB instances are
  /// unpickable: their content is not editable here (no faces, no material
  /// of their own), and a stray whole-object pick would leak into the
  /// face/submode selection.
  (String, String?, vm.Vector3)? pickFace(
    ui.Offset pos,
    ui.Size size, {
    Set<String>? skipObjectIds,
  }) {
    final ray = controller.screenPointToRay(pos);
    final hits = controller.raycastAll(
      ray,
      options: RaycastOptions(
        skipNodeIds: skipObjectIds ?? const {},
        where: (node) => node is ModelNode,
      ),
    );
    for (final h in hits) {
      if (h.node is! ModelNode) continue;
      final node = h.node as ModelNode;
      if (textureMode &&
          (node.object.isModelRef || node.object.isGltfRef)) {
        continue;
      }
      return (node.object.id, h.face?.key, h.worldPoint);
    }
    return null;
  }

  /// Индекс ближайшей к экранной точке вершины многогранника (радиус в
  /// пикселях). Чистая математика поверх worldToScreen — тестируется
  /// headless.
  int? pickPolyVertex(ModelObject obj, ui.Offset pos, {double radius = 12}) {
    final model = controller.model;
    final mesh = obj.mesh;
    if (model == null || mesh == null) return null;
    final matrix = objectWorldMatrix(model, obj);
    int? best;
    var bestDistance = radius * radius;
    for (var i = 0; i < mesh.vertices.length; i++) {
      final screen = controller.worldToScreen(
        matrix.transform3(mesh.vertices[i].clone()),
      );
      if (screen == null) continue;
      final distance = (screen - pos).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// Raycast for a meta-object node; returns (metaId, isBubble). The bubble
  /// nodes are pickable too — a click on the text toggles the collapse.
  (String, bool)? pickMeta(ui.Offset pos, ui.Size size) {
    final ray = controller.screenPointToRay(pos);
    final hits = controller.raycastAll(
      ray,
      options: RaycastOptions(
        where: (node) => node.name.startsWith(metaNodePrefix),
      ),
    );
    for (final h in hits) {
      final name = h.node.name;
      if (!name.startsWith(metaNodePrefix)) continue;
      final rest = name.substring(metaNodePrefix.length);
      final i = rest.indexOf(':');
      final id = i > 0 ? rest.substring(0, i) : rest;
      if (id.isEmpty) continue;
      return (id, i > 0);
    }
    return null;
  }

  /// Raycast for a light-source gizmo node; returns the source id (every
  /// marker part carries the `light:<id>` name — ball and arrow alike).
  String? pickLight(ui.Offset pos, ui.Size size) {
    final ray = controller.screenPointToRay(pos);
    final hits = controller.raycastAll(
      ray,
      options: RaycastOptions(
        where: (node) => node.name.startsWith(lightNodePrefix),
      ),
    );
    for (final h in hits) {
      final name = h.node.name;
      if (!name.startsWith(lightNodePrefix)) continue;
      final id = name.substring(lightNodePrefix.length);
      if (id.isEmpty) continue;
      return id;
    }
    return null;
  }

  // ── gizmo drag state ─────────────────────────────────────────────────
  //
  // The engine owns the handles, the hit test and the raw deltas
  // (`GizmoNode.onDrag`); the editor snapshots the selection at the drag
  // start and applies the (snapped) absolute deltas to the document. World
  // X is mirrored: world +X = model −x.

  /// What the active gizmo drag edits.
  String? _gizmoTarget; // 'object' | 'meta' | 'light'

  /// Translate snap step (model units) captured at the drag start.
  double gizmoSnap = 0;

  /// Rotate snap step (degrees) captured at the drag start.
  double gizmoSnapDeg = kRotateSnapDeg;

  /// Per-object model-local start positions at grab time (group drag).
  final Map<String, vm.Vector3> _gizmoStartPositions = {};

  /// Per-object model-local start rotations at grab time (group drag).
  final Map<String, (double, double, double)> _gizmoStartRotations = {};

  /// Снимок вершин многогранника на старте drag (локальные координаты).
  Map<int, vm.Vector3>? _polyStartVertices;

  /// Локальный пивот поворота выбранных вершин.
  vm.Vector3? _polyLocalPivot;

  vm.Vector3? _metaStartPos;
  vm.Vector3? _lightStartPos;
  vm.Vector3? _lightStartDir;

  /// Whether a gizmo drag is in progress.
  bool get gizmoDragging => _gizmoTarget != null;

  /// Starts an object translate drag: snapshots the expanded selection.
  void beginGizmoDrag() {
    final model = controller.model;
    final objs = model?.moveExpansion(selectedIds);
    if (model == null || objs == null || objs.isEmpty) return;
    if (_beginPolyDrag(objs.first)) return;
    _gizmoTarget = 'object';
    _gizmoStartPositions
      ..clear()
      ..addEntries([
        for (final o in objs) MapEntry(o.id, vm.Vector3(o.x, o.y, o.z)),
      ]);
  }

  /// Начинает drag вершин многогранника (перевод или поворот): снимок
  /// вершин и локальный пивот для поворота. Возвращает false, когда правка
  /// многогранника не активна.
  bool _beginPolyDrag(ModelObject obj) {
    if (!obj.isPolyhedron || polyEditMode == PolyEditMode.object) return false;
    final indices = _polySelectionVertices(obj);
    final mesh = obj.mesh;
    if (mesh == null || indices.isEmpty) return false;
    _gizmoTarget = 'poly';
    _polyStartVertices = {
      for (final i in indices)
        if (i >= 0 && i < mesh.vertices.length) i: mesh.vertices[i].clone(),
    };
    var pivot = vm.Vector3.zero();
    for (final v in _polyStartVertices!.values) {
      pivot += v;
    }
    _polyLocalPivot = pivot / _polyStartVertices!.length.toDouble();
    return true;
  }

  /// Starts an object rotate drag: snapshots the expanded selection (csg
  /// results rotate their leaves; hidden operands fall back to a rebuild).
  void beginRotateDrag() {
    final model = controller.model;
    final objs = model?.moveExpansion(selectedIds);
    if (model == null || objs == null || objs.isEmpty) return;
    if (_beginPolyDrag(objs.first)) return;
    _gizmoTarget = 'object';
    _gizmoStartRotations
      ..clear()
      ..addEntries([
        for (final o in objs) MapEntry(o.id, (o.rotX, o.rotY, o.rotZ)),
      ]);
  }

  /// Starts a meta translate drag: snapshots the meta position.
  void beginMetaDrag() {
    final model = controller.model;
    final meta = model == null ? null : selectedMeta(model);
    if (model == null || meta == null) return;
    _gizmoTarget = 'meta';
    _metaStartPos = vm.Vector3(meta.x, meta.y, meta.z);
  }

  /// Starts a light translate drag: snapshots the light position.
  void beginLightDrag() {
    final model = controller.model;
    final light = model == null ? null : selectedLight(model);
    if (model == null || light == null) return;
    _gizmoTarget = 'light';
    _lightStartPos = vm.Vector3(light.x, light.y, light.z);
  }

  /// Starts a directional-light aim drag: snapshots the aim direction.
  void beginLightRotateDrag() {
    final model = controller.model;
    final light = model == null ? null : selectedLight(model);
    if (model == null || light == null || !light.isDirectional) return;
    _gizmoTarget = 'light';
    _lightStartDir = lightDirOf(light);
  }

  void endGizmoDrag() {
    _gizmoTarget = null;
    _gizmoStartPositions.clear();
    _gizmoStartRotations.clear();
    _polyStartVertices = null;
    _polyLocalPivot = null;
    _metaStartPos = null;
    _lightStartPos = null;
    _lightStartDir = null;
  }

  /// The engine translate delta: world +X → model −x, y/z pass through.
  vm.Vector3 _modelDelta(vm.Vector3 world) =>
      vm.Vector3(-world.x, world.y, world.z);

  double _snapV(double v) =>
      gizmoSnap > 0 ? (v / gizmoSnap).roundToDouble() * gizmoSnap : v;

  double _snapDeg(double v) =>
      gizmoSnapDeg > 0
          ? (v / gizmoSnapDeg).roundToDouble() * gizmoSnapDeg
          : v;

  void _onGizmoMove(GizmoDragEvent event) {
    final model = controller.model;
    final world = event.translation;
    if (model == null || world == null) return;
    final delta = _modelDelta(world);
    switch (_gizmoTarget) {
      case 'meta':
        _moveMeta(model, delta);
      case 'light':
        _moveLight(model, delta);
      case 'poly':
        _movePolyVertices(model, world);
      default:
        _moveObjects(model, world);
    }
  }

  void _onGizmoRotate(GizmoDragEvent event) {
    final model = controller.model;
    final angle = event.rotation;
    if (model == null || angle == null) return;
    final deg = _snapDeg(angle * 180 / math.pi);
    if (deg.abs() < 1e-6) return;
    if (_gizmoTarget == 'light') {
      _aimLight(model, event.axis, deg);
      return;
    }
    if (_gizmoTarget == 'poly') {
      _rotatePolyVertices(model, event.axis, deg);
      return;
    }
    _rotateObjects(model, event.axis, deg);
  }

  /// Сдвиг выбранных вершин многогранника. Вершины живут в локальной рамке
  /// объекта (`world = anchor + R·S·local`), поэтому мировая дельта
  /// переводится в локальную через `(R·S)⁻¹` — зеркало X сидит только в
  /// якоре и локальные координаты не инвертирует. Дельта снапится в мире,
  /// к снимку прибавляется абсолютно (повторные события не накапливаются).
  void _movePolyVertices(ModelData model, vm.Vector3 world) {
    final obj = selectedObject(model);
    final mesh = obj?.mesh;
    final start = _polyStartVertices;
    if (obj == null || mesh == null || start == null) return;
    final snapped = vm.Vector3(
      _snapDelta(world.x),
      _snapDelta(world.y),
      _snapDelta(world.z),
    );
    final step = _polyLocalDelta(obj, snapped);
    for (final e in start.entries) {
      mesh.vertices[e.key] = e.value + step;
    }
    _syncAfterPolyGeometry(model, obj);
  }

  /// Локальная дельта, соответствующая мировой: `(R·S)⁻¹ · Δworld`.
  vm.Vector3 _polyLocalDelta(ModelObject obj, vm.Vector3 world) {
    final basis = objectRotation(obj) * objectScale(obj);
    final inverse = vm.Matrix4.identity()..copyInverse(basis);
    return inverse.transform3(world);
  }

  /// Поворот выбранных вершин вокруг локального пивота. Мировая ось гизмо
  /// переводится в локальную `(R·S)⁻¹ · axis` (детерминант положителен —
  /// угол сохраняется), поэтому знак не инвертируется.
  void _rotatePolyVertices(ModelData model, GizmoAxis axis, double deg) {
    final obj = selectedObject(model);
    final mesh = obj?.mesh;
    final start = _polyStartVertices;
    final pivot = _polyLocalPivot;
    if (obj == null || mesh == null || start == null || pivot == null) return;
    final basis = objectRotation(obj) * objectScale(obj);
    final inverse = vm.Matrix4.identity()..copyInverse(basis);
    final modelAxis = inverse.transform3(gizmoAxisDirection(axis));
    if (modelAxis.length2 < 1e-18) return;
    final rotation = vm.Quaternion.axisAngle(
      modelAxis.normalized(),
      deg * math.pi / 180,
    );
    for (final e in start.entries) {
      final offset = e.value - pivot;
      offset.applyQuaternion(rotation);
      mesh.vertices[e.key] = pivot + offset;
    }
    _syncAfterPolyGeometry(model, obj);
  }

  double _snapDelta(double v) =>
      gizmoSnap > 0 ? (v / gizmoSnap).roundToDouble() * gizmoSnap : v;

  /// Обновляет геометрию объекта и оверлеи после правки вершин (точечная
  /// пересборка узлов, без полного rebuild документа).
  void _syncAfterPolyGeometry(ModelData model, ModelObject obj) {
    controller.refreshObjectGeometry(obj.id);
    _selectionDirty = true;
    _refreshSelection(model, force: true);
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
    _overlayRevision = controller.revision;
  }

  /// Moves the selected objects by the gizmo's world translation. The
  /// document is snapped, then the render nodes are shifted by the ACTUAL
  /// snapped step: solids recompute, baked content (model/gltf instances,
  /// CSG results, rounded cuboids, sprites) gets the translation prepended
  /// without a scene rebuild — dragging furniture no longer rebuilds the
  /// whole model every pointer move.
  void _moveObjects(ModelData model, vm.Vector3 world) {
    final delta = _modelDelta(world);
    final translated = <String, vm.Vector3>{};
    for (final o in model.moveExpansion(selectedIds)) {
      final start = _gizmoStartPositions[o.id];
      if (start == null) continue;
      final prev = vm.Vector3(o.x, o.y, o.z);
      o.x = _snapV(start.x + delta.x);
      o.y = _snapV(start.y + delta.y).clamp(-4096.0, 4096.0);
      o.z = _snapV(start.z + delta.z);
      final step = vm.Vector3(o.x - prev.x, o.y - prev.y, o.z - prev.z);
      if (step.length2 > 1e-18) {
        // World +X = model −x.
        translated[o.id] = vm.Vector3(-step.x, step.y, step.z);
      }
    }
    // A csg result's nodes are registered under the operation id while the
    // document moves its operands: shift the result by the first leaf's step.
    for (final id in selectedIds) {
      if (translated.containsKey(id)) continue;
      final leaves = model.csgLeavesOf(id);
      if (leaves.isEmpty) continue;
      final step = translated[leaves.first.id];
      if (step != null) translated[id] = step;
    }
    if (translated.isEmpty) return; // snapped back to the same spot
    vm.Vector3? common;
    var mixed = false;
    for (final step in translated.values) {
      if (common == null) {
        common = step;
      } else if ((common - step).length2 > 1e-18) {
        mixed = true;
        break;
      }
    }
    controller.refreshObjectTransforms(translated: translated);
    _syncAfterObjectTransform(uniformStep: mixed ? null : common);
  }

  /// Rotates the selected objects by the gizmo angle. The document gets the
  /// snapped absolute rotation; the render nodes then receive the ACTUAL
  /// model-space step per element (`R_new · R_old⁻¹`) without a scene
  /// rebuild — solids, model/gltf instances and rounded cuboids all rotate
  /// live. A hidden csg operand has no nodes of its own, so a selection that
  /// expands to one falls back to a full rebuild.
  void _rotateObjects(ModelData model, GizmoAxis axis, double deg) {
    // World +X = model −x: a positive world-X rotation is a negative model
    // rotX (the old editor's X handle pointed world −X).
    final signed = axis == GizmoAxis.x ? -deg : deg;
    final rotated = <String, vm.Matrix4>{};
    var needsRebuild = false;
    for (final o in model.moveExpansion(selectedIds)) {
      if (o.kind == 'sprite') continue;
      final start = _gizmoStartRotations[o.id];
      if (start == null) continue;
      if (model.csgParentOf(o.id) != null) needsRebuild = true;
      final before = objectRotation(o);
      switch (axis) {
        case GizmoAxis.x:
          o.rotX = (start.$1 + signed) % 360;
        case GizmoAxis.y:
          o.rotY = (start.$2 + signed) % 360;
        case GizmoAxis.z:
          o.rotZ = (start.$3 + signed) % 360;
      }
      rotated[o.id] = objectRotation(o) * (before.clone()..invert());
    }
    if (needsRebuild) {
      rebuildObjects();
      return;
    }
    controller.refreshObjectTransforms(rotated: rotated);
    _selectionDirty = true;
    _syncAfterObjectTransform();
  }

  void _moveMeta(ModelData model, vm.Vector3 delta) {
    final meta = selectedMeta(model);
    final start = _metaStartPos;
    if (meta == null || start == null) return;
    meta.x = _snapV(start.x + delta.x);
    meta.y = _snapV(start.y + delta.y).clamp(0.0, 64.0);
    meta.z = _snapV(start.z + delta.z);
    _syncAfterMetaMove();
  }

  void _moveLight(ModelData model, vm.Vector3 delta) {
    final light = selectedLight(model);
    final start = _lightStartPos;
    if (light == null || start == null) return;
    light.x = _snapV(start.x + delta.x);
    light.y = _snapV(start.y + delta.y).clamp(0.0, 64.0);
    light.z = _snapV(start.z + delta.z);
    _updateLightNode(model, light.id);
    _syncAfterLightMove(model);
  }

  void _aimLight(ModelData model, GizmoAxis axis, double deg) {
    final light = selectedLight(model);
    final startDir = _lightStartDir;
    if (light == null || !light.isDirectional || startDir == null) return;
    final axisDir = gizmoAxisDirection(axis);
    final dir = vm.Quaternion.axisAngle(axisDir, deg * math.pi / 180)
        .rotate(startDir)
        .normalized();
    light.dirX = dir.x;
    light.dirY = dir.y;
    light.dirZ = dir.z;
    _updateLightNode(model, light.id);
    _syncAfterLightMove(model);
  }

  vm.Vector3 _anchorWorld(ModelObject obj, ModelData model) {
    final w = chunkWorld(obj.x, obj.z, model.size.w, model.size.l);
    return vm.Vector3(w.x, obj.y, w.z);
  }

  // ── meta objects (Разметка) ──────────────────────────────────────────

  /// Mirrors the AppState's selected meta id while in the markup mode (the
  /// caller rebuilds the overlays — the gizmo moves to the meta's anchor).
  String? selectedMetaId;

  void setMetaSelection(String? id) {
    selectedMetaId = id;
  }

  ModelMeta? selectedMeta(ModelData model) {
    final id = selectedMetaId;
    if (id == null) return null;
    return model.metaById(id);
  }

  /// World anchor of [meta] (its model anchor point, like objects).
  vm.Vector3 metaAnchor(ModelMeta meta, ModelData model) {
    final w = chunkWorld(meta.x, meta.z, model.size.w, model.size.l);
    return vm.Vector3(w.x, meta.y, w.z);
  }

  /// Whether the gizmo currently drives the selected meta object instead of
  /// the selected objects.
  bool get metaGizmoActive {
    final model = controller.model;
    return markupMode && model != null && selectedMeta(model) != null;
  }

  // ── light sources (Освещение) ────────────────────────────────────────

  /// The world anchor of [light] (its mirrored model position).
  vm.Vector3 lightAnchorWorld(ModelLight light, ModelData model) =>
      lightAnchor(light, model.size.w, model.size.l);

  /// Whether the gizmo currently drives the selected light source instead
  /// of the selected objects/metas.
  bool get lightGizmoActive {
    final model = controller.model;
    return lightingMode && model != null && selectedLight(model) != null;
  }

  // ── light rig: default editor lights vs the model's config ───────────

  /// Applies the model's lighting config to the scene: the document's own
  /// light sources, or the engine's default rig when the config is default
  /// (the legacy look). Called on every full model rebuild; light gizmo
  /// drags re-apply it live.
  void _applyLighting(ModelData model) {
    final cfg = model.lighting;
    final customized = !cfg.isDefault;
    // Тени и SSAO — настройки качества сцены (документ лишь художественная
    // подсказка): тумблеры режима «Освещение» должны менять картинку.
    controller.setShadows(customized && cfg.shadows);
    controller.setSsao(customized && cfg.ssao);
    controller.applyLighting();
    controller.setEnvironmentIntensity(customized ? cfg.ambient : 1.0);
  }

  /// Rebuilds one light's engine node (live gizmo drags: a point light
  /// follows its anchor, a directional light re-aims).
  void _updateLightNode(ModelData model, String id) {
    controller.applyLighting();
  }

  // ── scene rebuilds ───────────────────────────────────────────────────

  void rebuildObjects() {
    controller.rebuild();
    rebuildOverlays();
  }

  void rebuild(ModelData model) {
    armMetaProbe();
    _applyLighting(model);
    rebuildOverlays();
  }

  /// Public overlay rebuild (grid, frame, arrows, selection, cursor, gizmo):
  /// the slow path for model/mode changes. Drags use the targeted syncs.
  void rebuildOverlays() => _rebuildOverlays();

  /// The controller revision already reflected by the overlays; lets the
  /// viewport skip the full rebuild when a drag path synced it itself.
  int _overlayRevision = -1;

  /// Full overlay refresh after an external scene revision (undo, resource
  /// reload, property edit). No-op when the drag syncs already handled it.
  void syncDocument(ModelData model) {
    if (controller.revision == _overlayRevision) return;
    rebuild(model);
  }

  /// Cheap UI-state sync for AppState notifications that do not change the
  /// scene revision (selection, cursor, brush, gizmo mode): the cursor, the
  /// dirty selection outline and the gizmo anchor. The grid, frame, meta and
  /// light layers stay untouched.
  void syncUiState() {
    final model = controller.model;
    if (model == null) return;
    _syncCursor(model);
    _refreshSelection(model);
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
  }

  void _rebuildOverlays() {
    final model = controller.model;
    if (model == null) {
      _removeOverlayNode(_gridNode);
      _gridNode = null;
      _removeOverlayNode(_frameNode);
      _frameNode = null;
      _removeOverlayNode(_cursorCross);
      _cursorCross = null;
      _removeOverlayNode(_cursorCell);
      _cursorCell = null;
      for (final node in _selectionNodes) {
        selectionOverlay.remove(node);
      }
      _selectionNodes.clear();
      _selectionDirty = true;
      metaOverlay.rebuild(null);
      lightGizmos.clear();
      moveGizmo.visible = false;
      rotateGizmo.visible = false;
      _overlayRevision = controller.revision;
      return;
    }
    _syncGrid(model);
    _syncFrame(model);
    _syncCursor(model);
    _selectionDirty = true;
    _refreshSelection(model, force: true);
    // Markup meta-objects are visible only in the «Разметка» mode.
    metaOverlay.rebuild(markupMode ? model : null);
    _rebuildLightGizmos(model);
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
    _overlayRevision = controller.revision;
  }

  // ── incremental overlay syncs ────────────────────────────────────────

  /// Cached overlay nodes; rebuilt only when their model/size key changes.
  GridNode? _gridNode;
  int? _gridW;
  int? _gridL;
  double? _gridCell;
  LineNode? _frameNode;
  int? _frameW;
  int? _frameH;
  int? _frameL;
  LineNode? _cursorCross;
  LineNode? _cursorCell;
  int? _cursorW;
  int? _cursorL;

  /// The persistent selection overlay nodes (outline segments and vertex
  /// markers); empty when nothing is selected.
  final List<LineNode> _selectionNodes = [];

  /// Whether the outline/selection metadata must be rebuilt on the next sync.
  bool _selectionDirty = true;

  /// Whether the current selection contains billboards (their outline yaw
  /// follows the camera per frame). Recomputed on selection changes only.
  bool _selectionBillboards = false;

  /// Camera yaw the current outline was built with.
  double _selectionYaw = double.nan;

  void _removeOverlayNode(SceneNode? node) {
    if (node != null) overlays.remove(node);
  }

  /// Whether the ground grid overlay is shown (the bottom bar toggle).
  bool gridVisible = true;

  /// Shows or hides the ground grid: only the node's visibility flips, no
  /// rebuild happens; the flag survives later grid rebuilds.
  void setGridVisible(bool visible) {
    gridVisible = visible;
    _gridNode?.visible = visible;
  }

  void _syncGrid(ModelData model) {
    // Адаптивная клетка: легаси-сетка (≤ 64) остаётся единичной; у карт 1:1
    // шаг удваивается, чтобы число линий не росло с размером карты.
    final cell = adaptiveGridCell(model.size.w, model.size.l);
    if (_gridNode != null &&
        _gridW == model.size.w &&
        _gridL == model.size.l &&
        _gridCell == cell) {
      return;
    }
    _removeOverlayNode(_gridNode);
    // The engine grid: 1-px constant screen lines on the overlay layer.
    final node = GridNode(
      width: model.size.w.toDouble(),
      depth: model.size.l.toDouble(),
      cell: cell,
      lineWidthPx: 1.0,
      color: const Color(0xFF737380),
    );
    node.visible = gridVisible;
    node.layer = SceneLayer.overlay;
    overlays.add(node);
    _gridNode = node;
    _gridW = model.size.w;
    _gridL = model.size.l;
    _gridCell = cell;
  }

  void _syncFrame(ModelData model) {
    final w = model.size.w, l = model.size.l, h = model.size.h;
    if (_frameNode != null && _frameW == w && _frameL == l && _frameH == h) {
      return;
    }
    _removeOverlayNode(_frameNode);
    // Origin is the model center: the frame box is centered at world (0,0,0).
    // Рамка уровня — 1 пиксель и оранжевая (выделение объектов — жёлтое).
    final node = wireframeBox(
      vm.Vector3(0, h / 2, 0),
      vm.Vector3(w.toDouble(), h.toDouble(), l.toDouble()),
      color: vm.Vector4(1, 0.54, 0, 1),
    );
    node.widthPx = 1;
    node.layer = SceneLayer.overlay;
    overlays.add(node);
    _frameNode = node;
    _frameW = w;
    _frameH = h;
    _frameL = l;
  }

  void _syncCursor(ModelData model) {
    if (_cursorCross == null ||
        _cursorW != model.size.w ||
        _cursorL != model.size.l) {
      _removeOverlayNode(_cursorCross);
      _removeOverlayNode(_cursorCell);
      _cursorCross = null;
      _cursorCell = null;
      // Local geometry; the node transform carries the world position.
      const r = 0.35;
      final cross = <(double, double, double)>[
        (-r, 0, 0), (r, 0, 0),
        (0, 0, -r), (0, 0, r),
        (0, 0, 0), (0, r, 0),
      ];
      final crossNode = LineNode(
        geometry: lineSegments(cross, width: 0.012),
        color: const Color(0xFF66CCFF),
      );
      crossNode.layer = SceneLayer.overlay;
      overlays.add(crossNode);
      _cursorCross = crossNode;
      _cursorW = model.size.w;
      _cursorL = model.size.l;
    }
    // The cell brush highlight exists only while the brush is armed.
    if (cellCursor && _cursorCell == null) {
      const h = 0.5;
      final square = <(double, double, double)>[
        (-h, 0, -h), (h, 0, -h),
        (h, 0, -h), (h, 0, h),
        (h, 0, h), (-h, 0, h),
        (-h, 0, h), (-h, 0, -h),
      ];
      final cellNode = LineNode(
        geometry: lineSegments(square, width: 0.02),
        color: const Color(0xFF66CCFF),
      );
      cellNode.layer = SceneLayer.overlay;
      overlays.add(cellNode);
      _cursorCell = cellNode;
    } else if (!cellCursor && _cursorCell != null) {
      overlays.remove(_cursorCell!);
      _cursorCell = null;
    }
    final p = chunkWorld(cursor.x, cursor.z, model.size.w, model.size.l);
    _cursorCross!.transform =
        vm.Matrix4.translation(vm.Vector3(p.x, cursor.y, p.z));
    if (cellCursor && _cursorCell != null) {
      final cx = cursor.x.roundToDouble(), cz = cursor.z.roundToDouble();
      final c = chunkWorld(cx, cz, model.size.w, model.size.l);
      _cursorCell!.transform =
          vm.Matrix4.translation(vm.Vector3(c.x, cursor.y + 0.02, c.z));
    }
  }

  void _rebuildLightGizmos(ModelData model) {
    // Light-source gizmos are visible only in the «Освещение» mode (and
    // while its scene knob «показывать гизмо» is on).
    if (lightingMode && model.lighting.gizmos) {
      lightGizmos.rebuild(model.lighting,
          modelW: model.size.w, modelL: model.size.l);
    } else {
      lightGizmos.clear();
    }
  }

  /// Rebuilds the selection outline when it is dirty (selection, mode,
  /// rotation) or forced. A pure translation drag shifts the cached nodes
  /// instead (see [_syncAfterObjectTransform]).
  void _refreshSelection(ModelData model, {bool force = false}) {
    if (!force && !_selectionDirty) return;
    final recomputeBillboards = _selectionDirty;
    final objs = selectedObjects(model);
    for (final node in _selectionNodes) {
      selectionOverlay.remove(node);
    }
    _selectionNodes.clear();
    if (objs.isNotEmpty) {
      _selectionNodes.addAll(_buildSelectionNodes(model, objs));
      for (final node in _selectionNodes) {
        selectionOverlay.add(node);
      }
    }
    if (recomputeBillboards) _selectionBillboards = _selectionHasBillboard;
    _selectionDirty = false;
    _selectionYaw = screenParallelYaw(forwardH.x, forwardH.z);
  }

  /// Builds the selection overlay nodes: the active face yellow, the rest of
  /// the face group cyan, object outlines yellow, and — in the vertices
  /// submode — cross markers for every vertex of the edited polyhedron
  /// (active yellow, group cyan, the rest translucent white). Everything is
  /// drawn with 1-pixel screen width.
  List<LineNode> _buildSelectionNodes(ModelData model, List<ModelObject> objs) {
    const activeColor = Color(0xFFFFD91A);
    const groupColor = Color(0xFF35D0FF);
    final yaw = screenParallelYaw(forwardH.x, forwardH.z);
    final originX = (model.size.w - 1) / 2;
    final originZ = (model.size.l - 1) / 2;
    final nodes = <LineNode>[];
    final faceEdit = textureMode || polyEditMode == PolyEditMode.faces;
    if (faceEdit && faceSelection.isNotEmpty) {
      final active = <(double, double, double)>[];
      final group = <(double, double, double)>[];
      for (final key in faceSelection) {
        final target = _isActiveFace(key) ? active : group;
        for (final (a, b) in faceEdgeSegments(
          model,
          key,
          originX,
          originZ,
          billboardYaw: yaw,
        )) {
          target
            ..add(a)
            ..add(b);
        }
      }
      if (active.isNotEmpty) nodes.add(_outlineNode(active, activeColor));
      if (group.isNotEmpty) nodes.add(_outlineNode(group, groupColor));
    } else {
      final pts = <(double, double, double)>[];
      for (final obj in objs) {
        if (obj.isCsg) {
          // The evaluated result, not the raw operands.
          final edges =
              controller.objectNode(obj.id)?.edges() ?? const <vm.Vector3>[];
          for (var i = 0; i + 1 < edges.length; i += 2) {
            final a = edges[i];
            final b = edges[i + 1];
            pts
              ..add((a.x, a.y, a.z))
              ..add((b.x, b.y, b.z));
          }
          continue;
        }
        for (final (a, b) in objectEdgeSegments(
          obj,
          billboardYaw: yaw,
          originX: originX,
          originZ: originZ,
          modelOf: (id) => _resolveInstance(id),
        )) {
          pts
            ..add(a)
            ..add(b);
        }
      }
      if (pts.isNotEmpty) nodes.add(_outlineNode(pts, activeColor));
    }
    // Vertices submode: markers over the outlines (all vertices visible).
    if (polyEditMode == PolyEditMode.vertices && objs.length == 1) {
      nodes.addAll(_buildVertexMarkers(model, objs.first));
    }
    return nodes;
  }

  bool _isActiveFace(String key) {
    final face = activeFaceKey;
    final obj = selectedObjectId;
    return face != null && obj != null && key == '$obj:$face';
  }

  LineNode _outlineNode(
    List<(double, double, double)> points,
    Color color, {
    double widthPx = 1,
  }) {
    final node = LineNode(
      geometry: lineSegments(points, widthPx: widthPx),
      color: color,
    );
    node.layer = SceneLayer.overlay;
    return node;
  }

  /// Крестики вершин многогранника: активная — жёлтая, выбранные в группе —
  /// голубые, остальные — белые. Крестики яркие и чуть крупнее линий
  /// выделения (3 % диагонали сети, 1.6–2 px), иначе теряются на сцене.
  List<LineNode> _buildVertexMarkers(ModelData model, ModelObject obj) {
    final mesh = obj.mesh;
    if (mesh == null) return const [];
    final matrix = objectWorldMatrix(model, obj);
    final bounds = mesh.vertexBounds;
    final diag = bounds == null ? 1.0 : (bounds.$2 - bounds.$1).length;
    final m = (diag * 0.03).clamp(0.03, 0.6);
    final normal = <(double, double, double)>[];
    final group = <(double, double, double)>[];
    final active = <(double, double, double)>[];
    void cross(List<(double, double, double)> out, vm.Vector3 p) {
      out
        ..add((p.x - m, p.y, p.z))
        ..add((p.x + m, p.y, p.z))
        ..add((p.x, p.y - m, p.z))
        ..add((p.x, p.y + m, p.z))
        ..add((p.x, p.y, p.z - m))
        ..add((p.x, p.y, p.z + m));
    }

    for (var i = 0; i < mesh.vertices.length; i++) {
      final world = matrix.transform3(mesh.vertices[i].clone());
      if (vertexSelection.contains(i)) {
        cross(i == activeVertexIndex ? active : group, world);
      } else {
        cross(normal, world);
      }
    }
    return [
      if (normal.isNotEmpty)
        _outlineNode(normal, const Color(0xE6FFFFFF), widthPx: 1.6),
      if (group.isNotEmpty)
        _outlineNode(group, const Color(0xFF35D0FF), widthPx: 2),
      if (active.isNotEmpty)
        _outlineNode(active, const Color(0xFFFFD91A), widthPx: 2),
    ];
  }

  /// Мировая точка якоря гизмо для правки многогранника: центроид выбранных
  /// вершин (в режиме вершин) или вершин выбранных граней (в режиме граней).
  /// null — правка не активна, гизмо ставится обычным [groupAnchor].
  vm.Vector3? polySelectionAnchor(ModelData model, ModelObject obj) {
    if (!obj.isPolyhedron || polyEditMode == PolyEditMode.object) return null;
    final indices = _polySelectionVertices(obj);
    final mesh = obj.mesh;
    if (mesh == null || indices.isEmpty) return null;
    var sum = vm.Vector3.zero();
    for (final i in indices) {
      if (i < 0 || i >= mesh.vertices.length) continue;
      sum += mesh.vertices[i];
    }
    return objectWorldMatrix(model, obj)
        .transform3(sum / indices.length.toDouble());
  }

  /// Индексы вершин текущего подвыделения многогранника: сами вершины или
  /// вершины выбранных граней.
  Set<int> _polySelectionVertices(ModelObject obj) {
    if (polyEditMode == PolyEditMode.vertices) return vertexSelection;
    final mesh = obj.mesh;
    if (mesh == null) return const {};
    final prefix = '${obj.id}:';
    final keys = [
      for (final key in faceSelection)
        if (key.startsWith(prefix)) key.substring(prefix.length),
    ];
    return mesh.verticesOfFaces(keys);
  }

  /// Публичный доступ к вершинам подвыделения (drag гизмо).
  Set<int> polySelectionVertices(ModelObject obj) =>
      _polySelectionVertices(obj);

  /// Syncs the overlays after a move/rotate drag step: the outline shifts
  /// with a uniform translation (rebuilt otherwise) and the gizmo follows
  /// the group anchor. The grid/frame/cursor/meta/light layers are untouched.
  void _syncAfterObjectTransform({vm.Vector3? uniformStep}) {
    final model = controller.model;
    if (model == null) return;
    final nodes = List<LineNode>.of(_selectionNodes);
    if (!_selectionDirty && nodes.isNotEmpty && uniformStep != null) {
      for (final node in nodes) {
        node.transform = vm.Matrix4.translation(uniformStep) * node.transform;
      }
    } else {
      _selectionDirty = true;
      _refreshSelection(model, force: true);
    }
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
    _overlayRevision = controller.revision;
  }

  /// Syncs the meta layer after a meta drag step: only the dragged meta's
  /// nodes get fresh transforms (the other metas stay cached); the grid,
  /// frame, selection and light overlays are untouched.
  void _syncAfterMetaMove() {
    final model = controller.model;
    if (model == null) return;
    armMetaProbe();
    if (markupMode) metaOverlay.sync(model);
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
    _overlayRevision = controller.revision;
  }

  /// Syncs the light-source gizmos after a light drag step: only the dragged
  /// source's nodes get fresh transforms (the others stay).
  void _syncAfterLightMove(ModelData model) {
    if (lightingMode && model.lighting.gizmos) {
      lightGizmos.sync(model.lighting,
          modelW: model.size.w, modelL: model.size.l, only: selectedLightId);
    }
    _syncGizmo(
      model,
      selectedObjects(model),
      selectedMeta(model),
      selectedLight(model),
    );
    _overlayRevision = controller.revision;
  }

  /// Shows the engine gizmos on the current selection: objects in compose
  /// mode, the selected meta in markup, the selected light in lighting
  /// (directional lights get the rotate gizmo in the rotate mode).
  void _syncGizmo(
    ModelData model,
    List<ModelObject> objs,
    ModelMeta? metaSel,
    ModelLight? lightSel,
  ) {
    var rotate = false;
    vm.Vector3? anchor;
    if (!textureMode) {
      if (lightingMode && lightSel != null) {
        anchor = lightAnchorWorld(lightSel, model);
        rotate = lightSel.isDirectional && rotateMode;
      } else if (markupMode && metaSel != null) {
        anchor = metaAnchor(metaSel, model);
      } else if (objs.isNotEmpty) {
        // Правка многогранника: гизмо стоит на центроиде выбранных
        // граней/вершин; в режиме «объект» — как раньше, на якоре.
        anchor = polySelectionAnchor(model, objs.first) ?? groupAnchor(model);
        rotate = rotationActive;
      }
    }
    final visible = anchor != null;
    moveGizmo.visible = visible && !rotate;
    rotateGizmo.visible = visible && rotate;
    if (anchor != null) {
      moveGizmo.anchor = anchor;
      rotateGizmo.anchor = anchor;
    }
  }

  void dispose() {
    controller.removeFrameListener(_frameListener);
    // The viewport is recreated on every workspace-tab switch, while the
    // controller lives on: every node this scene attached to it must go, or
    // the old overlays stay rendered (frozen at the previous model) and the
    // next EditorScene mounts a second set on top.
    moveGizmo.onDrag = null;
    rotateGizmo.onDrag = null;
    controller.removeGizmo(moveGizmo);
    controller.removeGizmo(rotateGizmo);
    controller.remove(selectionOverlay);
    controller.remove(overlays);
    controller.remove(lightGizmoRoot);
    lightGizmos.dispose();
    controller.remove(metaOverlay.root);
    metaOverlay.dispose();
  }
}

/// Edge outline for one selected face ('id:faceKey'): 4 edges for flat
/// faces (the TRUE corners — the sloped silhouette for trapezoids), ring
/// edges for the cylinder caps, two rings for the cylinder side. Corners
/// rotate with the object (sprites follow the billboard yaw). Pure.
List<((double, double, double), (double, double, double))> faceEdgeSegments(
  ModelData model,
  String key,
  double originX,
  double originZ, {
  required double billboardYaw,
}) {
  final i = key.indexOf(':');
  if (i <= 0) return const [];
  final id = key.substring(0, i);
  final faceKey = key.substring(i + 1);
  final obj = model.objects.where((o) => o.id == id).firstOrNull;
  if (obj == null) return const [];

  // Многогранник: контуры выбранной грани (внешний + дырки) ровно в мировой
  // рамке рендера.
  if (obj.isPolyhedron) {
    final mesh = obj.mesh;
    final face = mesh?.faceByKey(faceKey);
    if (mesh == null || face == null) return const [];
    final matrix = objectWorldMatrix(model, obj);
    final out = <((double, double, double), (double, double, double))>[];
    for (final loop in [face.outer, ...face.holes]) {
      final count = loop.vertices.length;
      if (count < 2) continue;
      for (var i = 0; i < count; i++) {
        final a = matrix.transform3(mesh.vertices[loop.vertices[i]].clone());
        final b = matrix
            .transform3(mesh.vertices[loop.vertices[(i + 1) % count]].clone());
        out.add(((a.x, a.y, a.z), (b.x, b.y, b.z)));
      }
    }
    return out;
  }

  // Flat faces rotate with the object (sprites: the billboard yaw) — the
  // same convention as objectEdgeSegments, so the outline follows the
  // actually-rendered face. Solids use the full Rz·Rx·Ry matrix.
  final rot = obj.kind == 'sprite'
      ? vm.Matrix4.diagonal3Values(-1, 1, 1) *
          vm.Matrix4.rotationY(billboardYaw)
      : objectRotation(obj);
  // World-space anchor; the rotation applies to the LOCAL offset in the
  // world (like the render's translation(anchor)·rotation), so the outline
  // never mirrors the rendered face. Sprite billboards render with a −X
  // mirror (reorientBillboards), so their offsets mirror too.
  vm.Vector3 toWorld(double lx, double ly, double lz) {
    final r = rot.transform3(vm.Vector3(lx - obj.x, ly - obj.y, lz - obj.z));
    return vm.Vector3(
      -(obj.x - originX) + r.x,
      obj.y + r.y,
      obj.z - originZ + r.z,
    );
  }

  final out = <((double, double, double), (double, double, double))>[];
  void edge(vm.Vector3 a, vm.Vector3 b) {
    out.add(((a.x, a.y, a.z), (b.x, b.y, b.z)));
  }

  // Cylinder: caps are rings, the side is bounded by two rings.
  if (obj.kind == 'cylinder') {
    final h = obj.dim('h', 1);
    var r = faceKey == '-y'
        ? obj.dim('bottomR', 0.25)
        : obj.dim('topR', 0);
    if (faceKey == 'side') r = obj.dim('bottomR', 0.25);
    final ringY = faceKey == '-y'
        ? 0.0
        : faceKey == '+y'
            ? h
            : 0.0;
    List<vm.Vector3> ring(double y, double radius) => [
          for (var a = 0; a < 16; a++)
            toWorld(
              obj.x + radius * math.cos(2 * math.pi * a / 16),
              y,
              obj.z + radius * math.sin(2 * math.pi * a / 16),
            ),
        ];
    final rings = [
      ring(obj.y + ringY, r),
      if (faceKey == 'side') ring(obj.y + h, obj.dim('topR', 0)),
    ];
    for (final ring in rings) {
      for (var a = 0; a < ring.length; a++) {
        edge(ring[a], ring[(a + 1) % ring.length]);
      }
    }
    return out;
  }

  // Flat faces: the TRUE corners of the face, rotated around the anchor.
  final corners = faceCorners(obj, faceKey);
  if (corners.isEmpty) return const [];
  // The corner helpers are object-local (centered on the object origin);
  // lift them to model coords so the anchor rotation keeps the position.
  final world = [
    for (final c in corners)
      toWorld(obj.x + c.x, obj.y + c.y, obj.z + c.z),
  ];
  for (var a = 0; a < 4; a++) {
    edge(world[a], world[(a + 1) % 4]);
  }
  return out;
}
