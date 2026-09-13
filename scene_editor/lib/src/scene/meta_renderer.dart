import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Node-name prefix of markup meta-object nodes (`meta:<id>` for a shape,
/// `meta:<id>:label` for its text bubble). Picking scans node names for
/// these; the id never contains ':'.
const metaNodePrefix = 'meta:';

/// The overlay render layer of the editor's selection/gizmo UI — markup
/// renders in the same always-on-top overlay view (its own depth buffer), so
/// metas are visible «through» the objects. Equals [SceneLayer.overlay].
const metaRenderLayer = SceneLayer.overlay;

/// Radius of the dot sphere of a comment meta («!» shape), world units.
/// The comment anchor (its y) is the dot's center.
const kCommentBallRadius = 0.05;

/// Gap between the dot's top and the «!» stem bottom (was 0.1 → ×1/1.5 →
/// ×0.7).
const kCommentDotGap = 0.1 / 1.5 * 0.7;

/// Radius of the «!» stem at the side facing the dot: the original 2× rod
/// shrunk ×1.5.
const kCommentStemBottomRadius = 0.04 / 1.5;

/// Radius of the «!» stem at the side opposite the dot: the original 4× rod
/// shrunk ×1.5 — the stem still flares from the dot toward the top.
const kCommentStemTopRadius = 0.08 / 1.5;

/// Height of the «!» stem cylinder above the dot (was 0.3, now −20%).
const kCommentStemHeight = 0.3 * 0.8;

/// Height of a marker's pin pole, world units (pole base at the anchor y).
const kMarkerPinHeight = 0.24;

/// Radius of the marker's pin head sphere (sitting on the pole top).
const kMarkerBallRadius = 0.09;

/// Vertical gap between the top of a meta's shape and its bubble bottom
/// (comment/marker). Was 0.28, now ×1/3.
const kMetaBubbleGap = 0.28 / 3;

/// The same gap for the box meta (was 0.34, now ×1/3).
const kBoxBubbleGap = 0.34 / 3;

/// Translucent factor of an occluded meta (a ghost behind a covering
/// object) — the same factor applies to its bubble.
const _ghostAlpha = 0.45;

/// Base opacity of a box meta's translucent fill faces.
const _boxFillAlpha = 0.26;

/// World height of one logical pixel of a text bubble: the 32 px bubble font
/// then reads ~0.09 world units tall (labels were shrunk ×1.5 twice).
const _labelWorldPerPx = 0.0062 / 2.25;

/// Maximum bubble width in world units — long text wraps at this width.
const _labelMaxWorldWidth = 3.4;

/// Logical bubble text width cap (px) — `_labelMaxWorldWidth` at the px
/// scale; doubles as the paragraph layout width.
double get _labelMaxWidthPx => _labelMaxWorldWidth / _labelWorldPerPx;

/// A collapsed bubble keeps at most this many lines (then «…»).
const _labelCollapsedLines = 3;

/// An expanded bubble is capped at this many lines (a runaway comment must
/// not build a world-high wall of text).
const _labelExpandedLines = 16;

/// The meta kind's shape/bubble color (linear RGBA; unlit so the markup
/// never depends on the editor lights).
vm.Vector4 metaColor(String kind) => switch (kind) {
      metaKindMarker => vm.Vector4(0.98, 0.72, 0.2, 1),
      metaKindBox => vm.Vector4(0.34, 0.56, 1.0, 1),
      _ => vm.Vector4(0.3, 0.78, 0.38, 1),
    };

/// sRGB chip background of a bubble of [kind] (same hue as the shape).
ui.Color metaBubbleColor(String kind) => switch (kind) {
      metaKindMarker => const ui.Color(0xFFB26A00),
      metaKindBox => const ui.Color(0xFF1F4FD6),
      _ => const ui.Color(0xFF1E7A2F),
    };

/// The bubble's border (a lighter shade of its fill).
ui.Color metaBubbleBorder(String kind) => switch (kind) {
      metaKindMarker => const ui.Color(0xFFFFD57A),
      metaKindBox => const ui.Color(0xFF8FB0FF),
      _ => const ui.Color(0xFF7FD88F),
    };

/// The text of [meta]'s bubble: markers/boxes show the name (bold) and the
/// comment under it; a comment bubble shows the comment only. Empty string
/// means no bubble.
String metaLabelText(ModelMeta meta) {
  final comment = meta.comment.trim();
  if (meta.kind == metaKindComment) return comment;
  final name = meta.name.trim();
  if (comment.isEmpty) return name;
  return '$name\n$comment';
}

/// Whether [meta] has a text bubble at all.
bool metaHasLabel(ModelMeta meta) => metaLabelText(meta).isNotEmpty;

/// True when a bubble would be truncated while [ModelMeta.collapsed] — long
/// comments collapse by default, short ones never do.
bool metaNeedsCollapse(ModelMeta meta) =>
    meta.kind == metaKindComment && meta.comment.trim().length > 90;

/// World Y of the bottom edge of [meta]'s bubble (above its shape).
double metaBubbleBottomY(ModelMeta meta) => switch (meta.kind) {
      // Comment «!»: dot at y, stem above it across a visible gap.
      metaKindComment => meta.y +
          kCommentBallRadius +
          kCommentDotGap +
          kCommentStemHeight +
          kMetaBubbleGap,
      // Marker pin: pole up to pinH, head sphere (2r) on top.
      metaKindMarker => meta.y +
          kMarkerPinHeight +
          kMarkerBallRadius * 2 +
          kMetaBubbleGap,
      _ => meta.y + meta.dim('h', 1.0) + kBoxBubbleGap,
    };

/// The highest point of [meta]'s shape above its anchor y (world units).
double metaShapeHeight(ModelMeta meta) => switch (meta.kind) {
      metaKindComment =>
        kCommentBallRadius * 2 + kCommentDotGap + kCommentStemHeight,
      metaKindMarker => kMarkerPinHeight + kMarkerBallRadius * 2,
      _ => meta.dim('h', 1.0),
    };

/// The occluders' hit test core — pure, unit-tested without a GPU.
bool anyHitCloserThan(Iterable<SceneHit> hits, double targetDistance) {
  for (final h in hits) {
    if (h.distance < targetDistance - 1e-4) return true;
  }
  return false;
}

/// World-space probe points used to decide whether [meta] is covered by a
/// regular object: samples through the shape's volume plus the bubble's
/// center. Occluded when ANY sample is covered (partial coverage ghosts the
/// whole meta — the standard x-ray approximation).
List<vm.Vector3> metaOcclusionSamples(ModelMeta meta, ModelSize size) {
  final w = chunkWorld(meta.x, meta.z, size.w, size.l);
  final out = <vm.Vector3>[];
  switch (meta.kind) {
    case metaKindComment:
      // Dot center + «!» stem top (across the dot gap).
      out
        ..add(vm.Vector3(w.x, meta.y, w.z))
        ..add(vm.Vector3(
          w.x,
          meta.y + kCommentBallRadius + kCommentDotGap + kCommentStemHeight,
          w.z,
        ));
    case metaKindMarker:
      // Pin: pole base + head sphere center.
      out
        ..add(vm.Vector3(w.x, meta.y + 0.05, w.z))
        ..add(vm.Vector3(w.x, meta.y + kMarkerPinHeight + kMarkerBallRadius, w.z));
    case metaKindBox:
      final hw = meta.dim('w', 1.0) / 2;
      final h = meta.dim('h', 1.0);
      final hd = meta.dim('d', 1.0) / 2;
      for (final dx in [-hw, 0.0, hw]) {
        for (final dz in [-hd, 0.0, hd]) {
          final dy = dx == 0 && dz == 0 ? h / 2 : h * 0.9;
          out.add(vm.Vector3(w.x + dx, meta.y + dy, w.z + dz));
        }
      }
  }
  if (metaHasLabel(meta)) {
    final by = metaBubbleBottomY(meta);
    out.add(vm.Vector3(w.x, by + 0.45, w.z));
  }
  return out;
}

/// Endpoint pairs of a box meta's 12 edges in world space (for a model of
/// [size]). Pure — unit-tested without a GPU.
List<((double, double, double), (double, double, double))> metaBoxEdges(
  ModelMeta meta,
  ModelSize size,
) {
  final w = chunkWorld(meta.x, meta.z, size.w, size.l);
  final hw = meta.dim('w', 1.0) / 2;
  final h = meta.dim('h', 1.0);
  final hd = meta.dim('d', 1.0) / 2;
  vm.Vector3 p(double x, double y, double z) =>
      vm.Vector3(w.x + x, meta.y + y, w.z + z);
  final c = [
    p(-hw, 0, -hd), p(hw, 0, -hd), p(hw, 0, hd), p(-hw, 0, hd),
    p(-hw, h, -hd), p(hw, h, -hd), p(hw, h, hd), p(-hw, h, hd),
  ];
  const pairs = [
    (0, 1), (1, 2), (2, 3), (3, 0),
    (4, 5), (5, 6), (6, 7), (7, 4),
    (0, 4), (1, 5), (2, 6), (3, 7),
  ];
  return [
    for (final (a, b) in pairs)
      ((c[a].x, c[a].y, c[a].z), (c[b].x, c[b].y, c[b].z)),
  ];
}

/// Linear RGBA (the meta palette) as a `dart:ui` sRGB color: the unlit
/// material converts it back to the engine's linear space itself.
ui.Color _uiColor(vm.Vector4 c) => ui.Color.fromARGB(
      (c.w.clamp(0.0, 1.0) * 255).round(),
      (math.pow(c.x.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
      (math.pow(c.y.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
      (math.pow(c.z.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
    );

/// A material whose alpha is animated (occlusion ghosting) without a node
/// rebuild.
class _MetaMaterial {
  final SceneMaterial material;
  final ui.Color baseColor;
  _MetaMaterial(this.material, this.baseColor);

  void apply(double factor) {
    material.color = baseColor.withValues(alpha: baseColor.a * factor);
  }
}

class _BubbleSpec {
  final String key;
  final double widthWorld;
  final double heightWorld;
  _BubbleSpec(this.key, this.widthWorld, this.heightWorld);
}

class _MetaView {
  final ModelMeta meta;
  final List<_MetaMaterial> materials = [];
  final List<SpriteNode> billboards = [];

  String? bubbleKey;
  double bubbleWidthWorld = 0;
  double bubbleHeightWorld = 0;
  bool bubbleAttached = false;
  bool ghost = false;

  _MetaView(this.meta);
}

/// Builds and owns the markup (meta-object) layer of the editor scene.
///
/// Meta geometry renders on the overlay layer — the view with its own depth
/// buffer that composites above the objects — so metas are always visible
/// «through» the regular geometry. Whether a meta is covered is probed per
/// frame with CPU raycasts through the [controller] against the object nodes
/// only; a covered meta (and its bubble) becomes a translucent ghost, so
/// both the meta and the covering object stay readable. Overlapping metas
/// draw in their [ModelMeta.zIndex] order via the materials'
/// [SceneMaterial.blendOrder].
///
/// Text bubbles are rasterized to GPU textures lazily (cached by content),
/// attached live as soon as a texture is ready.
class MetaOverlayLayer {
  /// The controller the layer raycasts through and whose document nodes are
  /// the only possible occluders.
  final SceneController controller;

  final GroupNode root = GroupNode(name: 'meta-overlay');

  final Map<String, SceneTexture> _textures = {};
  final Map<String, Future<SceneTexture?>> _loading = {};
  final Map<String, _BubbleSpec> _specs = {};
  final List<_MetaView> _views = [];
  ModelData? _model;
  double _yaw = 0;
  bool _needsProbe = false;
  bool _disposed = false;

  MetaOverlayLayer({required this.controller});

  bool get hasContent => _views.isNotEmpty;

  /// Clears and rebuilds the markup of [model] (null hides everything).
  /// Textures are cached by content key, so repositions and z-index edits
  /// never re-rasterize bubbles.
  void rebuild(ModelData? model) {
    if (_disposed) return;
    root.removeAll();
    _views.clear();
    _model = model;
    if (model == null) return;
    final usedKeys = <String>{};
    for (final meta in model.metas) {
      if (meta.kind != metaKindComment &&
          meta.kind != metaKindMarker &&
          meta.kind != metaKindBox) {
        continue;
      }
      final view = _buildShape(meta, model.size);
      _views.add(view);
      if (metaHasLabel(meta)) {
        view.bubbleKey = _labelKey(meta);
        usedKeys.add(view.bubbleKey!);
        final spec = _specs[view.bubbleKey];
        if (spec != null) {
          view.bubbleWidthWorld = spec.widthWorld;
          view.bubbleHeightWorld = spec.heightWorld;
          final tex = _textures[view.bubbleKey];
          if (tex != null) view.bubbleAttached = true;
        }
      }
    }
    // Attach ready bubbles; kick off the pending rasterizations.
    for (final view in _views) {
      if (view.bubbleKey != null && view.bubbleAttached) {
        _attachBubbleNode(view, _textures[view.bubbleKey]!);
      } else if (view.bubbleKey != null) {
        _ensureBubbleTexture(view);
      }
    }
    // Drop caches of metas/bubbles that no longer exist.
    _textures.removeWhere((k, tex) {
      if (usedKeys.contains(k)) return false;
      tex.dispose();
      return true;
    });
    _specs.removeWhere((k, _) => !usedKeys.contains(k));
    _needsProbe = true;
  }

  /// Detaches the layer and releases the cached bubble textures. Called when
  /// the owning EditorScene is disposed (the viewport is recreated on every
  /// workspace-tab switch).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    root.removeAll();
    for (final texture in _textures.values) {
      texture.dispose();
    }
    _textures.clear();
    _loading.clear();
    _specs.clear();
    _views.clear();
    _model = null;
  }

  /// Per-frame upkeep: fresh billboard yaw/anchor (positions may track a
  /// drag), then the occlusion probes — only when the camera moved or the
  /// content is new (they are the most expensive part).
  void tick(
    ModelData model,
    double fx,
    double fz,
    vm.Vector3 eye, {
    required bool cameraMoved,
  }) {
    if (_disposed || _views.isEmpty) return;
    _yaw = screenParallelYaw(fx, fz);
    for (final view in _views) {
      for (final b in view.billboards) {
        b
          ..position = _bubbleCenterWorld(view.meta, view.bubbleHeightWorld)
          ..yaw = _yaw;
      }
    }
    if (cameraMoved || _needsProbe) {
      _needsProbe = false;
      _probeGhosts(model, eye);
    }
  }

  // ── occlusion ghosting ───────────────────────────────────────────────

  void _probeGhosts(ModelData model, vm.Vector3 eye) {
    final size = model.size;
    // Only real object surfaces may occlude a meta: grid lines, gizmos,
    // lights and the metas themselves never do. Document objects are
    // `ModelNode` wrappers — skip every other attached node.
    final skip = <String>{
      for (final node in controller.nodesOfType<SceneNode>())
        if (node is! ModelNode) node.id,
    };
    for (final view in _views) {
      var occluded = false;
      for (final target in metaOcclusionSamples(view.meta, size)) {
        final d = (target - eye).length;
        if (d < 1e-6) continue;
        final ray = vm.Ray.originDirection(eye, (target - eye).normalized());
        final hits = controller.raycastAll(
          ray,
          options: RaycastOptions(
            includeInvisible: true,
            skipNodeIds: skip,
          ),
        );
        if (anyHitCloserThan(hits, d)) {
          occluded = true;
          break;
        }
      }
      if (occluded != view.ghost) {
        view.ghost = occluded;
        _applyGhostAlpha(view);
      }
    }
  }

  void _applyGhostAlpha(_MetaView view) {
    final factor = view.ghost ? _ghostAlpha : 1.0;
    for (final m in view.materials) {
      m.apply(factor);
    }
  }

  // ── bubbles ──────────────────────────────────────────────────────────

  String _labelKey(ModelMeta meta) =>
      '${meta.id}:${meta.kind}:${meta.collapsed ? 1 : 0}:'
      '${metaLabelText(meta).hashCode}';

  void _ensureBubbleTexture(_MetaView view) {
    final key = view.bubbleKey;
    if (key == null || _loading.containsKey(key)) return;
    final meta = view.meta;
    final future = _rasterizeBubble(
      meta,
      collapsed: meta.collapsed,
    );
    _loading[key] = future;
    future.then((tex) {
      if (_disposed) {
        tex?.dispose();
        return;
      }
      if (!identical(_loading[key], future)) return; // superseded
      _loading.remove(key);
      if (tex == null) return;
      final spec = _specs[key];
      if (spec == null) return;
      _textures[key] = tex;
      // The view list may have been rebuilt while the rasterization ran —
      // attach to the current view with the same bubble key.
      for (final v in _views) {
        if (v.bubbleKey == key && !v.bubbleAttached) {
          v.bubbleWidthWorld = spec.widthWorld;
          v.bubbleHeightWorld = spec.heightWorld;
          v.bubbleAttached = true;
          _attachBubbleNode(v, tex);
          break;
        }
      }
    });
  }

  /// Rasterizes the bubble chip of [meta]: a rounded plate tinted with the
  /// meta's color, carrying its bold name and/or comment text. Short text
  /// hugs its own width; text wider than the cap wraps at the cap.
  Future<SceneTexture?> _rasterizeBubble(
    ModelMeta meta, {
    required bool collapsed,
  }) async {
    const fontPx = 32.0;
    const padX = 20.0, padY = 12.0, corner = 14.0;
    final kind = meta.kind;
    final text = metaLabelText(meta);
    if (text.isEmpty) return null;
    final maxLines =
        collapsed ? _labelCollapsedLines : _labelExpandedLines;
    final cap = _labelMaxWidthPx;

    /// A paragraph of the bubble's content laid out at [width].
    ui.Paragraph buildContent(double width, {required bool truncate}) {
      final style = ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        fontSize: fontPx,
        maxLines: truncate ? maxLines : null,
        ellipsis: truncate && maxLines < _labelExpandedLines ? '…' : null,
      );
      final builder = ui.ParagraphBuilder(style);
      final hasName = kind != metaKindComment && meta.name.trim().isNotEmpty;
      final hasComment = meta.comment.trim().isNotEmpty;
      if (hasName) {
        builder.pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontWeight: ui.FontWeight.bold,
        ));
        builder.addText(meta.name.trim());
        builder.pop();
        if (hasComment) builder.addText('\n');
      }
      if (hasComment) {
        builder.pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: hasName ? fontPx * 0.9 : fontPx,
        ));
        builder.addText(meta.comment.trim());
        builder.pop();
      }
      final p = builder.build();
      p.layout(ui.ParagraphConstraints(width: width));
      return p;
    }

    // Pass 1: measure the content without wrapping — the widest natural
    // line decides whether the chip hugs the text or wraps at the cap.
    final natural = buildContent(cap * 100, truncate: false);
    if (natural.height <= 0) return null;
    var widest = 0.0;
    for (final l in natural.computeLineMetrics()) {
      if (l.width > widest) widest = l.width;
    }
    final lineCount = natural.computeLineMetrics().length;
    final fitsNoWrap = widest <= cap && lineCount <= maxLines;
    // Pass 2: the displayed paragraph — hugging the text, or wrapped/
    // truncated at the cap.
    final para = fitsNoWrap
        ? natural
        : buildContent(cap, truncate: true);
    final contentWidth =
        fitsNoWrap ? widest : _labelMaxWidthPx;
    final wLogical = contentWidth + padX * 2;
    final hLogical = para.height + padY * 2;
    if (wLogical <= 0 || hLogical <= 0) return null;
    const ss = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(ss);
    final rect = ui.Rect.fromLTWH(0, 0, wLogical, hLogical);
    final rrect = ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(corner));
    canvas.drawRRect(rrect, ui.Paint()..color = metaBubbleColor(kind));
    final border = ui.Paint()
      ..color = metaBubbleBorder(kind)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(rrect, border);
    canvas.drawParagraph(para, ui.Offset(padX, padY));
    final image = await recorder.endRecording().toImage(
          (wLogical * ss).round(),
          (hLogical * ss).round(),
        );
    try {
      final tex = SceneTexture.fromImage(
        image,
        filter: SceneTextureFilter.linear,
      );
      // The upload is asynchronous; wait for it so the decoded image can be
      // released right away (the texture owns the GPU copy from here on).
      await tex.ready;
      _specs[_labelKey(meta)] = _BubbleSpec(
        _labelKey(meta),
        wLogical * _labelWorldPerPx,
        hLogical * _labelWorldPerPx,
      );
      return tex;
    } finally {
      image.dispose();
    }
  }

  void _attachBubbleNode(_MetaView view, SceneTexture tex) {
    final node = SpriteNode(
      name: '$metaNodePrefix${view.meta.id}:label',
      texture: tex,
      width: view.bubbleWidthWorld,
      height: view.bubbleHeightWorld,
      billboard: true,
      layer: SceneLayer.overlay,
    );
    node.material.blendOrder = view.meta.zIndex.toDouble();
    root.add(node);
    final m = _MetaMaterial(node.material, const ui.Color(0xFFFFFFFF));
    view.materials.add(m);
    view.billboards.add(node);
    node
      ..position = _bubbleCenterWorld(view.meta, view.bubbleHeightWorld)
      ..yaw = _yaw;
    _applyGhostAlpha(view);
  }

  vm.Vector3 _anchorWorld(ModelMeta meta) {
    final model = _model;
    if (model == null) return vm.Vector3.zero();
    final w = chunkWorld(meta.x, meta.z, model.size.w, model.size.l);
    return vm.Vector3(w.x, 0, w.z);
  }

  /// World center of the bubble card: the sprite is centered on its own
  /// origin, so the anchor is the bubble's bottom edge plus half its height.
  vm.Vector3 _bubbleCenterWorld(ModelMeta meta, double heightWorld) {
    final w = _anchorWorld(meta);
    return vm.Vector3(w.x, metaBubbleBottomY(meta) + heightWorld / 2, w.z);
  }

  // ── shapes ───────────────────────────────────────────────────────────

  _MetaView _buildShape(ModelMeta meta, ModelSize size) {
    final view = _MetaView(meta);
    final color = metaColor(meta.kind);
    final w = chunkWorld(meta.x, meta.z, size.w, size.l);
    switch (meta.kind) {
      case metaKindComment:
        // A green «!»: a small dot sphere at the anchor and, across a clear
        // gap, a stem flaring from the dot side (2× rod ÷1.5) to the top
        // (4× rod ÷1.5).
        _addShape(
          view,
          SceneGeometry.sphere(radius: kCommentBallRadius),
          color,
          alpha: 1.0,
          anchor: vm.Vector3(w.x, meta.y, w.z),
        );
        _addShape(
          view,
          SceneGeometry.cylinder(
            bottomRadius: kCommentStemBottomRadius,
            topRadius: kCommentStemTopRadius,
            height: kCommentStemHeight,
            radialSegments: 10,
          ),
          color,
          alpha: 1.0,
          anchor: vm.Vector3(
            w.x,
            meta.y + kCommentBallRadius + kCommentDotGap + kCommentStemHeight / 2,
            w.z,
          ),
        );
      case metaKindMarker:
        // A pin: a thin pole from the anchor with a head sphere on top —
        // both in the marker color (no billboards, nothing to tear apart).
        _addShape(
          view,
          SceneGeometry.cylinder(
            bottomRadius: 0.011,
            topRadius: 0.011,
            height: kMarkerPinHeight,
            radialSegments: 8,
          ),
          color,
          alpha: 1.0,
          anchor: vm.Vector3(w.x, meta.y + kMarkerPinHeight / 2, w.z),
        );
        _addShape(
          view,
          SceneGeometry.sphere(radius: kMarkerBallRadius),
          color,
          alpha: 1.0,
          anchor: vm.Vector3(
            w.x,
            meta.y + kMarkerPinHeight + kMarkerBallRadius,
            w.z,
          ),
        );
      case metaKindBox:
        final hw = meta.dim('w', 1.0) / 2;
        final h = meta.dim('h', 1.0);
        final hd = meta.dim('d', 1.0) / 2;
        // Translucent fill.
        _addShape(
          view,
          SceneGeometry.cuboid(vm.Vector3(hw * 2, h, hd * 2)),
          color,
          alpha: _boxFillAlpha,
          anchor: vm.Vector3(w.x, meta.y + h / 2, w.z),
        );
        // Bright edges.
        final pts = <vm.Vector3>[];
        for (final (a, b) in metaBoxEdges(meta, size)) {
          pts
            ..add(vm.Vector3(a.$1, a.$2, a.$3))
            ..add(vm.Vector3(b.$1, b.$2, b.$3));
        }
        _addLineShape(
          view,
          pts,
          color,
          anchor: vm.Vector3.zero(),
        );
    }
    return view;
  }

  _MetaMaterial _addShape(
    _MetaView view,
    SceneGeometry geometry,
    vm.Vector4 color, {
    required double alpha,
    required vm.Vector3 anchor,
  }) {
    final base = _uiColor(color).withValues(alpha: alpha);
    final mat = SceneMaterial.unlit(
      color: base,
      alphaMode: SceneAlphaMode.blend,
      blendOrder: view.meta.zIndex.toDouble(),
    );
    final node = MeshNode(
      name: '$metaNodePrefix${view.meta.id}',
      geometry: geometry,
      material: mat,
      layer: SceneLayer.overlay,
    );
    root.add(node);
    node.transform = vm.Matrix4.translation(anchor);
    final m = _MetaMaterial(mat, base);
    view.materials.add(m);
    return m;
  }

  _MetaMaterial _addLineShape(
    _MetaView view,
    List<vm.Vector3> points,
    vm.Vector4 color, {
    required vm.Vector3 anchor,
  }) {
    final base = _uiColor(color);
    final node = LineNode(
      name: '$metaNodePrefix${view.meta.id}',
      geometry: LineGeometry(points, width: 0.018),
      color: base,
      layer: SceneLayer.overlay,
    );
    node.material
      ..alphaMode = SceneAlphaMode.blend
      ..blendOrder = view.meta.zIndex.toDouble();
    root.add(node);
    node.transform = vm.Matrix4.translation(anchor);
    final m = _MetaMaterial(node.material, base);
    view.materials.add(m);
    return m;
  }
}
