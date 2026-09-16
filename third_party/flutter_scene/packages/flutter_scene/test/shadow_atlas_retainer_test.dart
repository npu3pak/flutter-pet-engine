// ShadowAtlasRetainer probe tests. The retainer's reuse decision is pure
// (GPU-free): it records the exact inputs an atlas was rendered with and
// reports whether the current frame's inputs would produce identical
// content. These tests exercise that decision headlessly, following the
// renderer's call order: beginProbe() -> addCaster() per caster ->
// contentMatches() (fills the probe, reports reuse) -> recordRendered()
// after a render.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_atlas_retainer.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  _StubMaterial({this.masked = false});

  final bool masked;

  @override
  bool get depthAlphaMasked => masked;

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

RenderItem _renderItem({bool masked = false}) => RenderItem(
  geometry: _StubGeometry(),
  material: _StubMaterial(masked: masked),
);

ShadowCascade _cascade(Matrix4 matrix) => ShadowCascade(
  lightSpaceMatrix: matrix,
  splitDistance: 10.0,
  boxSize: 20.0,
);

ShadowAtlasRetainer _retainer() => ShadowAtlasRetainer();

Vector3 _cam = Vector3.zero();

/// Fills and tests the probe for the frame's shadow inputs (no
/// beginProbe — the caller starts a probe before adding casters).
bool _matches(
  ShadowAtlasRetainer retainer, {
  int tileResolution = 1024,
  int totalTiles = 4,
  List<ShadowCascade> cascades = const [],
}) {
  return retainer.contentMatches(
    cameraPosition: _cam,
    tileResolution: tileResolution,
    totalTiles: totalTiles,
    casterFaces: ShadowCasterFaces.front,
    spotFaces: ShadowCasterFaces.front,
    cascades: cascades.isEmpty
        ? [_cascade(Matrix4.identity())]
        : cascades,
    spotMatrices: const [],
  );
}

/// Runs the renderer's per-frame sequence once over [casters]: a fresh probe,
/// the caster walk, the reuse check, and (first frame only) a render record.
void _frame(
  ShadowAtlasRetainer retainer,
  List<RenderItem> casters, {
  bool record = false,
  bool expectReuse = false,
}) {
  retainer.beginProbe();
  for (final caster in casters) {
    retainer.addCaster(caster);
  }
  final reuse = _matches(retainer);
  expect(reuse, expectReuse);
  if (record || reuse) {
    retainer.recordRendered();
  }
}

void main() {
  group('ShadowAtlasRetainer', () {
    test('no recorded content never matches', () {
      final retainer = _retainer();
      retainer.beginProbe();
      expect(_matches(retainer), isFalse);
    });

    test('identical inputs match across frames', () {
      final retainer = _retainer();
      final a = _renderItem();
      final b = _renderItem();
      // Frame 1: nothing recorded, must render.
      _frame(retainer, [a, b], record: true);
      // Frames 2-3: unchanged scene, reuse.
      _frame(retainer, [a, b], expectReuse: true);
      _frame(retainer, [a, b], expectReuse: true);
    });

    test('an empty caster set matches an empty caster set', () {
      final retainer = _retainer();
      _frame(retainer, const [], record: true);
      _frame(retainer, const [], expectReuse: true);
    });

    test('a moved caster invalidates the content', () {
      final retainer = _retainer();
      final item = _renderItem();
      _frame(retainer, [item], record: true);

      item.worldTransform.setTranslationRaw(3.0, 0.0, 0.0);
      _frame(retainer, [item], record: true);

      // And the new position is reused afterwards.
      _frame(retainer, [item], expectReuse: true);
    });

    test('a rotated caster invalidates the content', () {
      final retainer = _retainer();
      final item = _renderItem();
      _frame(retainer, [item], record: true);

      item.worldTransform.rotateY(0.5);
      _frame(retainer, [item], record: true);
      _frame(retainer, [item], expectReuse: true);
    });

    test('a changed caster set invalidates the content', () {
      final retainer = _retainer();
      final a = _renderItem();
      final b = _renderItem();
      _frame(retainer, [a, b], record: true);

      // One caster vanished.
      _frame(retainer, [a], record: true);
      // And both are reused once the set stabilizes.
      _frame(retainer, [a], expectReuse: true);
    });

    test('a changed light basis or atlas layout invalidates', () {
      final retainer = _retainer();
      _frame(retainer, const [], record: true);
      _frame(retainer, const [], expectReuse: true);

      // Tile resolution changed.
      retainer.beginProbe();
      expect(
        retainer.contentMatches(
          cameraPosition: _cam,
          tileResolution: 2048,
          totalTiles: 4,
          casterFaces: ShadowCasterFaces.front,
          spotFaces: ShadowCasterFaces.front,
          cascades: [_cascade(Matrix4.identity())],
          spotMatrices: const [],
        ),
        isFalse,
      );
      retainer.recordRendered();

      // Atlas width changed.
      retainer.beginProbe();
      expect(
        retainer.contentMatches(
          cameraPosition: _cam,
          tileResolution: 2048,
          totalTiles: 6,
          casterFaces: ShadowCasterFaces.front,
          spotFaces: ShadowCasterFaces.front,
          cascades: [_cascade(Matrix4.identity())],
          spotMatrices: const [],
        ),
        isFalse,
      );
      retainer.recordRendered();

      // Camera moved.
      retainer.beginProbe();
      expect(
        retainer.contentMatches(
          cameraPosition: Vector3(1, 0, 0),
          tileResolution: 2048,
          totalTiles: 6,
          casterFaces: ShadowCasterFaces.front,
          spotFaces: ShadowCasterFaces.front,
          cascades: [_cascade(Matrix4.identity())],
          spotMatrices: const [],
        ),
        isFalse,
      );
      retainer.recordRendered();

      // Cascade faces changed.
      retainer.beginProbe();
      expect(
        retainer.contentMatches(
          cameraPosition: Vector3(1, 0, 0),
          tileResolution: 2048,
          totalTiles: 6,
          casterFaces: ShadowCasterFaces.back,
          spotFaces: ShadowCasterFaces.front,
          cascades: [_cascade(Matrix4.identity())],
          spotMatrices: const [],
        ),
        isFalse,
      );
    });

    test('spot matrices are part of the record', () {
      final retainer = _retainer();
      retainer.beginProbe();
      expect(_matches(retainer), isFalse);
      retainer.recordRendered();

      retainer.beginProbe();
      expect(
        retainer.contentMatches(
          cameraPosition: _cam,
          tileResolution: 1024,
          totalTiles: 4,
          casterFaces: ShadowCasterFaces.front,
          spotFaces: ShadowCasterFaces.front,
          cascades: [_cascade(Matrix4.identity())],
          spotMatrices: [Matrix4.translation(Vector3(0, 1, 0))],
        ),
        isFalse,
      );
    });

    test('an alpha-masked caster opts out of reuse', () {
      final retainer = _retainer();
      final item = _renderItem(masked: true);
      retainer.beginProbe();
      retainer.addCaster(item);
      expect(_matches(retainer), isFalse);
      retainer.recordRendered();
      // Still no reuse: the opt-out is recorded with the content.
      expect(_matches(retainer), isFalse);
    });

    test('an instanced caster opts out of reuse', () {
      final retainer = _retainer();
      final item = _renderItem()..instanceTransforms = [Matrix4.identity()];
      retainer.beginProbe();
      retainer.addCaster(item);
      expect(_matches(retainer), isFalse);
      retainer.recordRendered();
      expect(_matches(retainer), isFalse);
    });

    test('one opted-out caster poisons reuse for the whole frame', () {
      final retainer = _retainer();
      final a = _renderItem();
      retainer.beginProbe();
      retainer.addCaster(a);
      retainer.addCaster(_renderItem(masked: true));
      expect(_matches(retainer), isFalse);
      retainer.recordRendered();
      // Reuse stays off even though the plain caster alone would match.
      retainer.beginProbe();
      retainer.addCaster(a);
      expect(_matches(retainer), isFalse);
    });
  });
}
