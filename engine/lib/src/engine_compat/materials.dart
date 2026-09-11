import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

/// Material/texture helpers copied from the main game
/// (`lib/engine/impl/texture_store.dart`, `lib/engine/impl/scene_graph.dart`)
/// so model rendering matches the game's PBR look.

/// Nearest-sampling sampler for the editor's model textures.
///
/// `mipmaps: false` — the fork builds a full sRGB mip chain on the main
/// isolate (`Texture2D.fromPixels` downsampling with `math.pow` per texel:
/// ~130ms per 1024² texture, which froze the UI the moment a template model
/// with textures appeared). The editor shows models up close, so the nearest
/// level-0 sampling is visually identical; the game's model textures use the
/// same no-mip sampler (`chunkSampler`), while project textures keep their
/// mipmapped sampler.
const pixelatedSampler = TextureSampling(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  mipFilter: gpu.MipFilter.nearest,
  mipmaps: false,
);

/// PBR material for sprite/texture quads. [alphaMode] defaults to blend
/// (transparent billboards); solid face parts pass mask so they render in
/// the opaque pass with per-fragment depth (no translucent sorting).
PhysicallyBasedMaterial pbrSprite(
  Texture2D tex, {
  double brightness = 1.0,
  double opacity = 1.0,
  bool doubleSided = true,
  AlphaMode alphaMode = AlphaMode.blend,
}) {
  return PhysicallyBasedMaterial()
    ..baseColorTexture = tex
    ..baseColorFactor =
        vm.Vector4(brightness, brightness, brightness, opacity)
    ..roughnessFactor = 1.0
    ..metallicFactor = 0.0
    ..alphaMode = alphaMode
    ..doubleSided = doubleSided;
}

/// PBR material for a flat color fill (no texture). [opacity] < 1 switches
/// to alpha blending (used by the walkability mode's ghosted objects).
PhysicallyBasedMaterial pbrColor(
  vm.Vector3 color, {
  bool doubleSided = true,
  double opacity = 1.0,
}) {
  return PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(color.x, color.y, color.z, opacity)
    ..roughnessFactor = 1.0
    ..metallicFactor = 0.0
    ..alphaMode = opacity < 1.0 ? AlphaMode.blend : AlphaMode.opaque
    ..doubleSided = doubleSided;
}

final _rotateXHalfPi = vm.Matrix4.rotationX(math.pi / 2);

/// A vertical sprite quad — copied from the game's `makeVerticalSprite`.
/// [yaw] is the world-space yaw around Y (billboards: [screenParallelYaw]).
Node makeVerticalSprite({
  required double wx,
  required double wy,
  required double wz,
  required double sx,
  required double sy,
  required Material material,
  double yaw = 0.0,
}) {
  final transform = vm.Matrix4.translation(vm.Vector3(wx, wy, wz)) *
      vm.Matrix4.diagonal3Values(-1, 1, 1) *
      vm.Matrix4.rotationY(yaw) *
      _rotateXHalfPi;
  return Node(
    mesh: Mesh(PlaneGeometry(width: sx, depth: sy), material),
    localTransform: transform,
  );
}

/// Reorients an existing vertical sprite node to a new yaw (billboard facing).
void reorientBillboard(Node node, double yaw) {
  final pos = node.localTransform.getTranslation();
  node.localTransform = vm.Matrix4.translation(pos) *
      vm.Matrix4.diagonal3Values(-1, 1, 1) *
      vm.Matrix4.rotationY(yaw) *
      _rotateXHalfPi;
}
