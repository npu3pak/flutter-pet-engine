import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

/// Retains the composed shadow atlas across frames so a frame whose shadow
/// inputs are bitwise identical to the last render skips the shadow pass and
/// every view samples the previous content.
///
/// The atlas is a single texture owned here (grown on demand), rendered into
/// in place: `ShadowPass` clears the whole atlas before drawing, so
/// overwriting it every frame is safe, and re-rendering can be skipped when
/// the exact input record matches what the atlas was last rendered with.
///
/// The input record is exact (not a hash): the light/camera parameters as
/// doubles and every visible opaque caster's geometry/material identity and
/// full world transform. Two frames produce the same record only when they
/// would produce identical atlas content, so skipping preserves the rendered
/// image bit for bit. Casters whose depth is not a pure function of those
/// inputs (instanced, skinned, alpha-masked, or vertex-displaced) opt out of
/// reuse and force a render every frame.
class ShadowAtlasRetainer {
  gpu.Texture? _atlas;
  int _atlasWidth = 0;
  int _atlasHeight = 0;

  // Whether [recordRendered] has run at least once (the atlas holds content
  // produced by the recorded inputs).
  bool _hasContent = false;

  // The recorded inputs of the atlas content, compared exactly against the
  // current frame's accumulation buffers ([_params], [_casterInts],
  // [_casterMatrices]) to decide reuse.
  bool _renderedCastersReusable = false;
  List<double>? _renderedParams;
  List<int>? _renderedCasterInts;
  List<double>? _renderedCasterMatrices;

  // Current-frame accumulation buffers, cleared once per view by
  // [beginProbe].
  final List<double> _params = <double>[];
  final List<int> _casterInts = <int>[];
  final List<double> _casterMatrices = <double>[];
  bool _castersReusable = true;

  /// The retained atlas texture, or null before the first shadow render.
  gpu.Texture? get atlas => _atlas;

  /// Starts a fresh probe for one view: clears the accumulation buffers.
  void beginProbe() {
    _params.clear();
    _casterInts.clear();
    _casterMatrices.clear();
    _castersReusable = true;
  }

  /// Records one visible opaque item that can render into the atlas.
  void addCaster(RenderItem item) {
    _casterInts.add(identityHashCode(item.geometry));
    _casterInts.add(identityHashCode(item.material));
    final t = item.worldTransform.storage;
    for (var k = 0; k < 16; k++) {
      _casterMatrices.add(t[k]);
    }
    // Opt-outs: these casters' depth is not a pure function of the recorded
    // inputs (per-instance or per-skeleton transforms, alpha-mask contents,
    // or a material vertex stage that can displace geometry).
    if (item.instanceTransforms != null ||
        item.jointsTexture != null ||
        item.material.depthAlphaMasked ||
        item.material.materialVertexShader('depth') != null) {
      _castersReusable = false;
    }
  }

  /// Whether the atlas already holds content bitwise identical to what a
  /// shadow pass would produce for the given frame inputs.
  ///
  /// The probe is always filled (even when it cannot match, e.g. the first
  /// frame or an opted-out caster), so a following [recordRendered] records
  /// the full input set. Pure and GPU-free: the retained texture is only
  /// read, never allocated, so the reuse decision can be unit tested
  /// headlessly.
  bool contentMatches({
    required Vector3 cameraPosition,
    required int tileResolution,
    required int totalTiles,
    required ShadowCasterFaces casterFaces,
    required ShadowCasterFaces spotFaces,
    required List<ShadowCascade> cascades,
    required List<Matrix4> spotMatrices,
  }) {
    _params.clear();
    _params.add(cameraPosition.x);
    _params.add(cameraPosition.y);
    _params.add(cameraPosition.z);
    _params.add(tileResolution.toDouble());
    _params.add(totalTiles.toDouble());
    _params.add(casterFaces.index.toDouble());
    _params.add(spotFaces.index.toDouble());
    for (final cascade in cascades) {
      final m = cascade.lightSpaceMatrix.storage;
      for (var k = 0; k < 16; k++) {
        _params.add(m[k]);
      }
    }
    for (final matrix in spotMatrices) {
      final m = matrix.storage;
      for (var k = 0; k < 16; k++) {
        _params.add(m[k]);
      }
    }
    return _hasContent &&
        _castersReusable &&
        _renderedCastersReusable &&
        _listsEqualDoubles(_params, _renderedParams) &&
        _listsEqualInts(_casterInts, _renderedCasterInts) &&
        _listsEqualDoubles(_casterMatrices, _renderedCasterMatrices);
  }

  /// Stores the current probe as the atlas content's input record. Call
  /// after a shadow pass was scheduled to render into the retained atlas.
  void recordRendered() {
    _hasContent = true;
    _renderedCastersReusable = _castersReusable;
    _renderedParams = List<double>.of(_params);
    _renderedCasterInts = List<int>.of(_casterInts);
    _renderedCasterMatrices = List<double>.of(_casterMatrices);
  }

  /// Returns the retained atlas, (re)allocated to exactly [width] x [height]
  /// texels. The layout must match the requested tile count: shadow UVs
  /// normalize by the tile count, so a texture wider than the layout would
  /// make the sampler read beyond the rendered tiles (cascades 1–2 read
  /// cleared texels and shadows disappear or shift). The atlas is therefore
  /// recreated on any size change, not only when growing.
  gpu.Texture ensureAtlas(int width, int height) {
    if (atlasNeedsResize(
      currentWidth: _atlasWidth,
      currentHeight: _atlasHeight,
      width: width,
      height: height,
    )) {
      _atlas = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: gpu.PixelFormat.r32Float,
      );
      _atlasWidth = width;
      _atlasHeight = height;
      // A resize invalidates whatever content the old texture held.
      _hasContent = false;
    }
    return _atlas!;
  }

  /// Whether an atlas of [width] x [height] must replace the current one.
  static bool atlasNeedsResize({
    required int currentWidth,
    required int currentHeight,
    required int width,
    required int height,
  }) =>
      currentWidth <= 0 ||
      currentHeight <= 0 ||
      currentWidth != width ||
      currentHeight != height;

  static bool _listsEqualDoubles(List<double>? a, List<double>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _listsEqualInts(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
