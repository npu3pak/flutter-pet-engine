import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Node-name prefix of the light-source gizmo nodes (`light:<id>` for the
/// ball, and `light:<id>` again for every arrow part — picking scans the
/// names and never needs to tell parts apart; the id never contains ':').
const lightNodePrefix = 'light:';

/// The overlay render layer of the light-source gizmos («Освещение» mode).
/// Equals [SceneLayer.overlay] (1 << 1): the light markers composite in the
/// always-on-top overlay view with their own depth buffer.
const lightRenderLayer = SceneLayer.overlay;

/// Radius of the marker ball of a light source, world units. The ball's
/// center sits at the source anchor ([ModelLight.x]/[y]/[z] in the model),
/// like the comment ball of a meta.
const kLightBallRadius = 0.09;

/// Directional-light arrow: a thin shaft leaving the ball surface and a
/// cone tip along the light's aim [ModelLight.dir] (world space). All parts
/// are cylinders built along local +Y and rotated by [rotationAlignY].
const kLightArrowShaftLength = 0.3;
const kLightArrowShaftRadius = 0.024;
const kLightArrowConeLength = 0.16;
const kLightArrowConeRadius = 0.07;

/// Distance from the ball center to the shaft's near end.
const kLightArrowGap = 0.1;

/// sRGB → linear gamma for the engine's light/marker colors (light values
/// are linear RGB in the engine).
double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Converts an sRGB 0..1 color to the engine's linear space.
vm.Vector3 srgbToLinear(double r, double g, double b) =>
    vm.Vector3(_linear(r), _linear(g), _linear(b));

/// The world-space aim of [light] (its stored unit vector).
vm.Vector3 lightDirOf(ModelLight light) =>
    vm.Vector3(light.dirX, light.dirY, light.dirZ);

/// Editor-friendly angles of a world aim [dx,dy,dz]: azimuth degrees around
/// +Y measured from +Z toward +X, and elevation degrees above the horizon
/// (negative = aiming down). Pure — unit-tested.
(double azDeg, double elDeg) lightDirToAngles(
    double dx, double dy, double dz) {
  final h = math.sqrt(dx * dx + dz * dz);
  return (
    math.atan2(dx, dz) * 180 / math.pi,
    math.atan2(dy, h) * 180 / math.pi,
  );
}

/// The inverse of [lightDirToAngles]: a unit world aim from azimuth/
/// elevation degrees (azimuth around +Y from +Z, elevation above horizon).
vm.Vector3 lightAnglesToDir(double azDeg, double elDeg) {
  final az = azDeg * math.pi / 180;
  final el = elDeg * math.pi / 180;
  final ce = math.cos(el);
  return vm.Vector3(math.sin(az) * ce, math.sin(el), math.cos(az) * ce);
}

/// A rotation matrix that maps the local +Y axis onto [dir] (the unit
/// direction the arrow must point at). Pure — unit-tested. When [dir] is
/// parallel to ±Y the extra twist about Y is arbitrary but consistent.
vm.Matrix4 rotationAlignY(vm.Vector3 dir) {
  final d = dir.normalized();
  final up = vm.Vector3(0, 1, 0);
  if ((d - up).length < 1e-6) return vm.Matrix4.identity();
  if ((d + up).length < 1e-6) {
    return vm.Matrix4.rotationZ(math.pi);
  }
  // Rodrigues rotation from up to d about axis = up × d. With the unit
  // vectors the cross-product length IS sinθ.
  final axis = up.cross(d).normalized();
  final c = up.dot(d).clamp(-1.0, 1.0);
  final sin = up.cross(d).length;
  final t = 1 - c;
  final (ux, uy, uz) = (axis.x, axis.y, axis.z);
  return vm.Matrix4(
    // Column 1: R·ex
    t * ux * ux + c, t * ux * uy + sin * uz, t * ux * uz - sin * uy, 0,
    // Column 2: R·ey (maps to d when d is unit)
    t * ux * uy - sin * uz, t * uy * uy + c, t * uy * uz + sin * ux, 0,
    // Column 3: R·ez
    t * ux * uz + sin * uy, t * uy * uz - sin * ux, t * uz * uz + c, 0,
    // Column 4
    0, 0, 0, 1,
  );
}

/// The world anchor of [light] (mirrored model cell like every other
/// editor shape: `chunkWorld(x, z, w, l)` puts (0,0) at the model center).
vm.Vector3 lightAnchor(ModelLight light, int modelW, int modelL) {
  final w = chunkWorld(light.x, light.z, modelW, modelL);
  return vm.Vector3(w.x, light.y, w.z);
}

/// Owns the light-source gizmo layer under a root group: a colored ball per
/// source and, for directional lights, an aim arrow along [ModelLight.dir].
/// The shapes are unlit [MeshNode]s on [SceneLayer.overlay] — they never
/// depend on the scene lights and render «through» the objects (their own
/// depth buffer), like the meta markers. Each part node carries the
/// `light:<id>` name so picking finds the source behind any of its parts.
///
/// [sync] refreshes only the sources whose shape or pose changed: a dragged
/// light keeps its nodes and gets a new transform ([sync] with [only] skips
/// every other source entirely).
class LightGizmoLayer {
  final GroupNode root = GroupNode(id: 'light-gizmos');

  /// Part nodes per light id (ball; optionally shaft and cone).
  final Map<String, List<MeshNode>> _views = {};

  bool _disposed = false;

  /// Full rebuild (model/mode/size changes).
  void rebuild(ModelLighting cfg, {required int modelW, required int modelL}) {
    if (_disposed) return;
    root.removeAll();
    _views.clear();
    for (final light in cfg.lights) {
      _views[light.id] = _buildLight(light, modelW, modelL);
    }
  }

  /// Incremental sync: sources with a different part count are rebuilt, the
  /// rest only get fresh transforms and colors; gone sources are removed.
  /// With [only] every other source is left untouched (the live drag).
  void sync(
    ModelLighting cfg, {
    required int modelW,
    required int modelL,
    String? only,
  }) {
    if (_disposed) return;
    final alive = <String>{};
    for (final light in cfg.lights) {
      if (only != null && light.id != only) continue;
      alive.add(light.id);
      final existing = _views[light.id];
      if (existing == null || existing.length != _partCount(light)) {
        _removeLight(light.id);
        _views[light.id] = _buildLight(light, modelW, modelL);
      } else {
        _updateLight(existing, light, modelW, modelL);
      }
    }
    if (only == null) {
      for (final id in _views.keys.toList()) {
        if (!alive.contains(id)) _removeLight(id);
      }
    }
  }

  /// Removes every marker and forgets the views (leaving the mode).
  void clear() {
    root.removeAll();
    _views.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _views.clear();
  }

  int _partCount(ModelLight light) =>
      light.isPoint || lightDirOf(light).length < 1e-6 ? 1 : 3;

  List<MeshNode> _buildLight(ModelLight light, int modelW, int modelL) {
    final nodes = <MeshNode>[];
    final color = _uiColor(light);
    final anchor = lightAnchor(light, modelW, modelL);
    void add(SceneGeometry geometry, vm.Matrix4 transform) {
      final node = _part(light, geometry, color, transform);
      root.add(node);
      nodes.add(node);
    }

    if (light.isPoint || lightDirOf(light).length < 1e-6) {
      add(SceneGeometry.sphere(radius: kLightBallRadius),
          vm.Matrix4.translation(anchor));
      return nodes;
    }
    // Directional: a ball at the anchor and an arrow along the aim. The
    // direction is stored in WORLD coordinates — no mirroring needed.
    final dir = lightDirOf(light);
    final rot = rotationAlignY(dir);
    add(SceneGeometry.sphere(radius: kLightBallRadius),
        vm.Matrix4.translation(anchor));
    add(
      SceneGeometry.cylinder(
        bottomRadius: kLightArrowShaftRadius,
        topRadius: kLightArrowShaftRadius,
        height: kLightArrowShaftLength,
        radialSegments: 10,
      ),
      vm.Matrix4.translation(anchor + dir * _shaftCenter) * rot,
    );
    add(
      SceneGeometry.cylinder(
        bottomRadius: kLightArrowConeRadius,
        topRadius: 0.0,
        height: kLightArrowConeLength,
        radialSegments: 10,
      ),
      vm.Matrix4.translation(anchor + dir * _coneCenter) * rot,
    );
    return nodes;
  }

  void _updateLight(
    List<MeshNode> nodes,
    ModelLight light,
    int modelW,
    int modelL,
  ) {
    final anchor = lightAnchor(light, modelW, modelL);
    final color = _uiColor(light);
    if (nodes.length == 1) {
      nodes[0]
        ..transform = vm.Matrix4.translation(anchor)
        ..material.color = color;
      return;
    }
    final dir = lightDirOf(light);
    final rot = rotationAlignY(dir);
    nodes[0]
      ..transform = vm.Matrix4.translation(anchor)
      ..material.color = color;
    nodes[1]
      ..transform = vm.Matrix4.translation(anchor + dir * _shaftCenter) * rot
      ..material.color = color;
    nodes[2]
      ..transform = vm.Matrix4.translation(anchor + dir * _coneCenter) * rot
      ..material.color = color;
  }

  void _removeLight(String id) {
    final nodes = _views.remove(id);
    if (nodes == null) return;
    for (final node in nodes) {
      root.remove(node);
    }
  }
}

const double _shaftCenter =
    kLightBallRadius + kLightArrowGap + kLightArrowShaftLength / 2;
const double _coneCenter = kLightBallRadius +
    kLightArrowGap +
    kLightArrowShaftLength +
    kLightArrowConeLength / 2;

/// The light's sRGB color 0..1 as a `dart:ui` [Color] (the unlit material
/// converts it to the engine's linear space itself).
Color _uiColor(ModelLight light) => Color.fromARGB(
      255,
      (light.r * 255).round(),
      (light.g * 255).round(),
      (light.b * 255).round(),
    );

MeshNode _part(ModelLight light, SceneGeometry geometry, Color color,
    vm.Matrix4 transform) {
  return MeshNode(
    name: '$lightNodePrefix${light.id}',
    geometry: geometry,
    material: SceneMaterial.unlit(color: color),
    layer: SceneLayer.overlay,
  )..transform = transform;
}
