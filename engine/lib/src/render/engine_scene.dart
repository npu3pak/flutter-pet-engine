import 'dart:math' as math;
import 'dart:ui' show FilterQuality, Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../camera/game_camera_math.dart';
import '../engine_compat/coords.dart';
import '../level/level_baker.dart';
import 'engine_material.dart';
import 'engine_mesh.dart';
import 'engine_node.dart';

/// Anti-aliasing strategy exposed to games (mirrors the fork's modes).
enum EngineAntiAliasing { none, msaa, fxaa, auto }

/// Distance fog settings applied to an [EngineScene].
class EngineFog {
  const EngineFog({
    required this.color,
    required this.start,
    required this.end,
    this.minOpacity = 0.0,
    this.maxOpacity = 1.0,
  });

  /// Linear RGB fog color (the game transfers it to sRGB for 2D overlays).
  final vm.Vector3 color;
  final double start;
  final double end;
  final double minOpacity;
  final double maxOpacity;
}

/// Initializes the engine's shared static resources (shaders, BRDF LUT).
/// Call once before creating scenes or loading textures; safe to await more
/// than once.
Future<void> initializeEngine() => Scene.initializeStaticResources();

/// The engine's low-level scene facade: a fork scene, camera, settings and
/// content roots behind engine-owned handles. Games build static geometry with
/// [PrimitiveBatch] + [addMesh], place sprites/decals, attach lights, mount
/// baked levels and drive the camera per frame — without naming a single fork
/// type.
class EngineScene {
  EngineScene({
    double fovY = kGameCameraFovY,
    double near = kGameCameraNear,
    double far = kGameCameraFar,
  }) {
    camera = NodeCamera(
      cameraNode.raw,
      PerspectiveProjection(fovRadiansY: fovY, near: near, far: far),
    );
    _scene.add(cameraNode.raw);
  }

  final Scene _scene = Scene();

  /// The underlying fork scene. Engine-internal plumbing only.
  Scene get raw => _scene;

  /// The camera node driven by [updateCamera].
  final EngineNode cameraNode = EngineNode(name: 'camera');

  /// The engine camera (view transform, projection, ray/projection helpers).
  late final NodeCamera camera;

  /// The scene root (all content roots are children of it).
  EngineNode get root => EngineNode.wrap(_scene.root);

  final List<EngineNode> _billboards = [];

  /// Creates and attaches a named content root (grass, weather, ...).
  EngineNode addLayer(String name) {
    final node = EngineNode(name: name);
    _scene.add(node.raw);
    return node;
  }

  /// Removes every root child except the camera (a floor/level teardown).
  void clearContent() {
    final cameraRaw = cameraNode.raw;
    final children = List<Node>.of(_scene.root.children);
    for (final child in children) {
      if (identical(child, cameraRaw)) continue;
      _scene.root.remove(child);
    }
    _billboards.clear();
    unmountLevel();
  }

  // ── settings ─────────────────────────────────────────────────────────

  double get renderScale => _scene.renderScale;
  set renderScale(double value) => _scene.renderScale = value;

  FilterQuality get filterQuality => _scene.filterQuality;
  set filterQuality(FilterQuality value) => _scene.filterQuality = value;

  set antiAliasing(EngineAntiAliasing mode) {
    _scene.antiAliasingMode = switch (mode) {
      EngineAntiAliasing.none => AntiAliasingMode.none,
      EngineAntiAliasing.msaa => AntiAliasingMode.msaa,
      EngineAntiAliasing.fxaa => AntiAliasingMode.fxaa,
      EngineAntiAliasing.auto => AntiAliasingMode.auto,
    };
  }

  /// The anti-aliasing technique that actually runs (resolved against the
  /// backend).
  EngineAntiAliasing get effectiveAntiAliasing =>
      switch (_scene.effectiveAntiAliasingMode) {
        AntiAliasingMode.none => EngineAntiAliasing.none,
        AntiAliasingMode.msaa => EngineAntiAliasing.msaa,
        AntiAliasingMode.fxaa => EngineAntiAliasing.fxaa,
        AntiAliasingMode.auto => EngineAntiAliasing.auto,
      };

  double get environmentIntensity => _scene.environmentIntensity;
  set environmentIntensity(double value) =>
      _scene.environmentIntensity = value;

  /// Applies distance fog (null disables it). Linear mode, no sky/scatter
  /// influence — the game's dungeon look.
  void setFog(EngineFog? fog) {
    final f = _scene.fog;
    if (fog == null) {
      f.enabled = false;
      return;
    }
    f
      ..enabled = true
      ..mode = FogMode.linear
      ..color = fog.color
      ..start = fog.start
      ..end = fog.end
      ..minOpacity = fog.minOpacity
      ..maxOpacity = fog.maxOpacity
      ..skyColorInfluence = 0.0
      ..cutoffDistance = 0.0
      ..heightFalloff = 0.0
      ..sunInScatter = 0.0;
  }

  // ── camera ───────────────────────────────────────────────────────────

  /// Applies the camera node transform for this frame.
  void updateCamera(vm.Matrix4 transform) =>
      cameraNode.raw.localTransform = transform;

  /// The camera's horizontal forward direction (billboard orientation).
  vm.Vector3 get cameraForward {
    final f = camera.forward;
    return vm.Vector3(f.x, 0, f.z).normalized();
  }

  /// The screen-space ray through [position] for a view of [size].
  vm.Ray screenPointToRay(Offset position, Size size) =>
      camera.screenPointToRay(position, size);

  /// Projects a world point to logical-pixel screen coordinates; null at or
  /// behind the camera plane or outside the depth range.
  Offset? worldToScreen(vm.Vector3 world, Size size) =>
      camera.worldToScreen(world, size);

  // ── content ──────────────────────────────────────────────────────────

  /// Attaches [child] under [parent] (or the scene root).
  EngineNode add(EngineNode child, {EngineNode? parent}) {
    (parent ?? root).add(child);
    return child;
  }

  /// Adds a mesh node. [billboard] registers it for per-frame camera-facing
  /// reorientation; [shadowStatic] marks it as a static shadow caster.
  EngineNode addMesh(
    EngineMesh mesh, {
    vm.Matrix4? transform,
    EngineNode? parent,
    bool billboard = false,
    bool shadowStatic = true,
    String name = '',
  }) {
    final node = EngineNode(name: name)..mesh = mesh;
    if (transform != null) node.transform = transform;
    node.shadowStatic = shadowStatic;
    (parent ?? root).add(node);
    if (billboard) registerBillboard(node);
    return node;
  }

  /// Adds a camera-facing vertical sprite quad (mirrored-X, yaw, upright).
  /// [billboard] registers it for per-frame reorientation.
  EngineNode addSprite({
    required vm.Vector3 position,
    required double width,
    required double height,
    required EngineMaterial material,
    double yaw = 0.0,
    bool billboard = false,
    bool shadowStatic = false,
    EngineNode? parent,
    String name = 'sprite',
  }) {
    final geometry = EngineGeometry.wrap(PlaneGeometry(width: width, depth: height));
    final mesh = EngineMesh(geometry, material);
    final node = EngineNode(name: name)
      ..mesh = mesh
      ..transform = spriteTransform(position: position, yaw: yaw);
    node.shadowStatic = shadowStatic;
    (parent ?? root).add(node);
    if (billboard) registerBillboard(node);
    return node;
  }

  /// Adds a wall decal quad (vertical, facing out of the wall side).
  EngineNode addWallDecal({
    required vm.Vector3 position,
    required double width,
    required double height,
    required EngineMaterial material,
    String? wallDir,
    EngineNode? parent,
    String name = 'decal',
  }) {
    final geometry = EngineGeometry.wrap(PlaneGeometry(width: width, depth: height));
    final node = EngineNode(name: name)
      ..mesh = EngineMesh(geometry, material)
      ..transform = wallDecalTransform(
        position: position,
        wallDir: wallDir,
      );
    (parent ?? root).add(node);
    return node;
  }

  /// Adds a horizontal quad just above the floor.
  EngineNode addFloorDecal({
    required double x,
    required double z,
    required double width,
    required double depth,
    required double y,
    required EngineMaterial material,
    EngineNode? parent,
    String name = 'floor-decal',
  }) {
    final geometry = EngineGeometry.wrap(PlaneGeometry(width: width, depth: depth));
    final node = EngineNode(name: name)
      ..mesh = EngineMesh(geometry, material)
      ..transform = vm.Matrix4.translation(vm.Vector3(x, y, z));
    (parent ?? root).add(node);
    return node;
  }

  /// Adds a horizontal quad facing down (ceiling-hung decals).
  EngineNode addCeilingDecal({
    required double x,
    required double z,
    required double width,
    required double depth,
    required double y,
    required EngineMaterial material,
    EngineNode? parent,
    String name = 'ceiling-decal',
  }) {
    final geometry = EngineGeometry.wrap(PlaneGeometry(width: width, depth: depth));
    final node = EngineNode(name: name)
      ..mesh = EngineMesh(geometry, material)
      ..transform = (vm.Matrix4.identity()
        ..translateByVector3(vm.Vector3(x, y, z))
        ..rotateX(math.pi));
    (parent ?? root).add(node);
    return node;
  }

  /// Adds a point light at [position].
  EngineNode addPointLight({
    required vm.Vector3 position,
    required vm.Vector3 color,
    required double intensity,
    required double range,
    EngineNode? parent,
    String name = 'point-light',
  }) {
    final node = EngineNode(name: name)
      ..transform = vm.Matrix4.translation(position);
    node.addPointLight(color: color, intensity: intensity, range: range);
    (parent ?? root).add(node);
    return node;
  }

  // ── billboards ───────────────────────────────────────────────────────

  /// Registers [node] for per-frame camera-facing reorientation.
  void registerBillboard(EngineNode node) {
    if (!_billboards.contains(node)) _billboards.add(node);
  }

  /// Unregisters [node] (call before removing it from the graph).
  void unregisterBillboard(EngineNode node) => _billboards.remove(node);

  /// Reorients every registered billboard and the mounted level's baked
  /// sprites toward the camera (call when the camera yaw changes).
  void reorientBillboards() {
    final forward = cameraForward;
    final yaw = screenParallelYaw(forward.x, forward.z);
    for (final node in _billboards) {
      reorientBillboardNode(node, yaw);
    }
    _levelResult?.reorientBillboards(forward.x, forward.z);
  }

  // ── baked level ──────────────────────────────────────────────────────

  LevelBakeResult? _levelResult;

  /// The mounted baked level, or null.
  LevelBakeResult? get levelResult => _levelResult;

  /// Mounts a baked level under the scene root with an optional offset
  /// (centered engine frame → the game's world frame).
  void mountLevel(LevelBakeResult baked, {vm.Matrix4? offset}) {
    unmountLevel();
    if (offset != null) baked.root.localTransform = offset;
    _scene.root.add(baked.root);
    _levelResult = baked;
  }

  /// Detaches the mounted baked level (the result stays intact).
  void unmountLevel() {
    final root = _levelResult?.root;
    if (root != null && root.parent != null) root.parent!.remove(root);
    _levelResult = null;
  }

  /// The separate node of a mounted baked level by element id, or null.
  EngineNode? levelNode(String id) {
    final node = _levelResult?.nodes[id];
    return node == null ? null : EngineNode.wrap(node);
  }

  // ── lifecycle ────────────────────────────────────────────────────────

  void dispose() {
    _billboards.clear();
    _levelResult = null;
    _scene.removeAll();
  }
}

final _rotateXHalfPi = vm.Matrix4.rotationX(math.pi / 2);

/// The vertical-sprite transform: mirrored X, screen-parallel yaw, unit quad
/// scaled to [width]×[height] — the project's sacred billboard composition.
vm.Matrix4 spriteTransform({
  required vm.Vector3 position,
  required double yaw,
}) {
  return vm.Matrix4.translation(position) *
      vm.Matrix4.diagonal3Values(-1, 1, 1) *
      vm.Matrix4.rotationY(yaw) *
      _rotateXHalfPi;
}

/// Reorients an existing vertical sprite node to a new yaw (billboard facing).
void reorientBillboardNode(EngineNode node, double yaw) {
  final position = node.transform.getTranslation();
  node.transform = spriteTransform(position: position, yaw: yaw);
}

const _wallAngle = <String, double>{
  'n': 0.0,
  's': math.pi,
  'e': -math.pi / 2,
  'w': math.pi / 2,
};

/// The wall-decal transform: mirrored X, wall-side yaw, upright quad.
vm.Matrix4 wallDecalTransform({
  required vm.Vector3 position,
  String? wallDir,
}) {
  final angle = _wallAngle[wallDir] ?? 0.0;
  return vm.Matrix4.translation(position) *
      vm.Matrix4.diagonal3Values(-1, 1, 1) *
      vm.Matrix4.rotationY(angle) *
      _rotateXHalfPi;
}
