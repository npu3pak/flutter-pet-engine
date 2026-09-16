// Private fields behind public getters/setters cannot use initializing
// formals in named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene_layer.dart';
import 'scene_node.dart';

/// A light source of the scene: a point light or a directional light.
///
/// The node owns its fork light component; moving or rotating the node moves
/// the light. Point lights are limited by `QualitySettings.maxPointLights`:
/// the engine keeps the sources with the highest [importance] and disables
/// the rest without removing the nodes.
class LightNode extends SceneNode {
  LightNode._({
    super.id,
    super.name,
    super.layer,
    required bool isPoint,
    required Color color,
    required vm.Vector3 linearColor,
    required double intensity,
    required double range,
    required vm.Vector3 direction,
    required bool castsShadow,
    required double importance,
  }) : _isPoint = isPoint,
       _color = color,
       _linearColor = linearColor,
       _intensity = intensity,
       _range = range,
       _direction = direction,
       _castsShadow = castsShadow,
       _importance = importance;

  /// A point light with a [range] (world units, 0 = unlimited).
  factory LightNode.point({
    String? id,
    String name = '',
    int layer = SceneLayer.base,
    Color color = const Color(0xFFFFFFFF),
    double intensity = 1,
    double range = 0,
    double importance = 1,
  }) => LightNode._(
    id: id,
    name: name,
    layer: layer,
    isPoint: true,
    color: color,
    linearColor: _linearOf(color),
    intensity: intensity,
    range: range,
    direction: vm.Vector3(0, -1, 0),
    castsShadow: false,
    importance: importance,
  );

  /// A directional light aimed along [direction] (node-local; the node's
  /// rotation is applied on top, like the fork's component).
  factory LightNode.directional({
    String? id,
    String name = '',
    int layer = SceneLayer.base,
    vm.Vector3? direction,
    Color color = const Color(0xFFFFFFFF),
    double intensity = 1,
    bool castsShadow = false,
    double importance = 1,
  }) => LightNode._(
    id: id,
    name: name,
    layer: layer,
    isPoint: false,
    color: color,
    linearColor: _linearOf(color),
    intensity: intensity,
    range: 0,
    direction: _normalized(direction ?? vm.Vector3(0, -1, 0)),
    castsShadow: castsShadow,
    importance: importance,
  );

  /// A point light from a linear RGB color (the document rig path).
  @internal
  factory LightNode.pointLinear({
    String? id,
    String name = '',
    int layer = SceneLayer.base,
    required vm.Vector3 color,
    double intensity = 1,
    double range = 0,
    double importance = 1,
  }) => LightNode._(
    id: id,
    name: name,
    layer: layer,
    isPoint: true,
    color: _colorOf(color),
    linearColor: color,
    intensity: intensity,
    range: range,
    direction: vm.Vector3(0, -1, 0),
    castsShadow: false,
    importance: importance,
  );

  /// A directional light from a linear RGB color (the document rig path).
  @internal
  factory LightNode.directionalLinear({
    String? id,
    String name = '',
    int layer = SceneLayer.base,
    required vm.Vector3 color,
    vm.Vector3? direction,
    double intensity = 1,
    bool castsShadow = false,
    double importance = 1,
  }) => LightNode._(
    id: id,
    name: name,
    layer: layer,
    isPoint: false,
    color: _colorOf(color),
    linearColor: color,
    intensity: intensity,
    range: 0,
    direction: _normalized(direction ?? vm.Vector3(0, -1, 0)),
    castsShadow: castsShadow,
    importance: importance,
  );

  /// The default engine key light (linear color, as in the v1 rig).
  @internal
  factory LightNode.defaultSun({required bool castsShadow}) =>
      LightNode.directionalLinear(
        id: 'light_default_sun',
        name: 'default-sun',
        color: vm.Vector3(1, 0.96, 0.9),
        direction: vm.Vector3(-0.4, -0.85, -0.35),
        intensity: 2.2,
        castsShadow: castsShadow,
      );

  /// The default camera lamp (linear color, as in the v1 rig).
  @internal
  factory LightNode.defaultCameraLamp() => LightNode.pointLinear(
    id: 'light_default_camera',
    name: 'default-camera-lamp',
    color: vm.Vector3(1, 0.9, 0.8),
    intensity: 4,
    range: 6,
  );

  final bool _isPoint;

  /// Whether this is a point light (otherwise a directional one).
  bool get isPoint => _isPoint;

  /// Whether this is a directional light.
  bool get isDirectional => !_isPoint;

  Color _color;

  /// The sRGB light color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _linearColor = _linearOf(value);
    markChanged();
  }

  vm.Vector3 _linearColor;

  /// The linear RGB color passed to the renderer. Plumbing only.
  @internal
  vm.Vector3 get linearColor => _linearColor;

  double _intensity;

  /// The scalar brightness multiplier.
  double get intensity => _intensity;
  set intensity(double value) {
    if (_intensity == value) return;
    _intensity = value;
    markChanged();
  }

  double _range;

  /// The point-light influence radius (0 = unlimited); ignored by directional
  /// lights.
  double get range => _range;
  set range(double value) {
    if (_range == value) return;
    _range = value;
    markChanged();
  }

  vm.Vector3 _direction;

  /// The directional light aim (node-local, normalized); ignored by point
  /// lights.
  vm.Vector3 get direction => _direction.clone();
  set direction(vm.Vector3 value) {
    final normalized = _normalized(value);
    if (_direction == normalized) return;
    _direction = normalized;
    markChanged();
  }

  bool _castsShadow;

  /// Whether this directional light may cast shadows. The global toggle lives
  /// in `QualitySettings.shadows`; shadows run only when both are true.
  bool get castsShadow => _castsShadow;
  set castsShadow(bool value) {
    if (_castsShadow == value) return;
    _castsShadow = value;
    markChanged();
  }

  double _importance;

  /// The priority of this light when `QualitySettings.maxPointLights` limits
  /// the point-light budget: the highest values stay on.
  double get importance => _importance;
  set importance(double value) {
    if (_importance == value) return;
    _importance = value;
    markChanged();
  }

  // ── quality settings wiring ──────────────────────────────────────────

  bool _settingsShadows = true;
  int _shadowCascades = 4;
  double _shadowDistance = 150;

  /// Applies the global shadow knobs of `QualitySettings`. Plumbing for
  /// `SceneController`.
  @internal
  void applyShadowSettings({
    required bool shadows,
    required int cascades,
    required double distance,
  }) {
    _settingsShadows = shadows;
    _shadowCascades = cascades;
    _shadowDistance = distance;
    _applyShadowToComponent();
  }

  bool _budgetEnabled = true;

  /// Whether the light passes the `maxPointLights` budget. Plumbing for
  /// `SceneController`; always true for directional lights.
  @internal
  bool get budgetEnabled => _budgetEnabled;

  /// Enables or disables this light by the point-light budget. Plumbing.
  @internal
  void setBudgetEnabled(bool value) {
    if (_budgetEnabled == value) return;
    _budgetEnabled = value;
    if (value) {
      _ensureComponent();
    } else {
      _removeComponent();
    }
  }

  /// The point lights that pass [maxPointLights] (-1 = no limit, 0 = none),
  /// the most important first. Pure helper of the controller budget.
  static List<LightNode> selectForBudget(
    List<LightNode> pointLights,
    int maxPointLights,
  ) {
    if (maxPointLights < 0) return List.of(pointLights);
    if (maxPointLights == 0) return const [];
    final sorted = List.of(pointLights)
      ..sort((a, b) => b.importance.compareTo(a.importance));
    return sorted.take(maxPointLights).toList();
  }

  @override
  void syncToEngine() {
    if (!_budgetEnabled) {
      _removeComponent();
      return;
    }
    _ensureComponent();
  }

  void _ensureComponent() {
    final raw = engine.raw;
    if (_isPoint) {
      var component = raw.getComponent<fs.PointLightComponent>();
      if (component == null) {
        component = fs.PointLightComponent(fs.PointLight());
        raw.addComponent(component);
      }
      component.light
        ..color = _linearColor
        ..intensity = _intensity
        ..range = _range;
      return;
    }
    var component = raw.getComponent<fs.DirectionalLightComponent>();
    if (component == null) {
      component = fs.DirectionalLightComponent(fs.DirectionalLight());
      raw.addComponent(component);
    }
    _applyShadowToComponent(component);
  }

  void _removeComponent() {
    final raw = engine.raw;
    if (_isPoint) {
      final component = raw.getComponent<fs.PointLightComponent>();
      if (component != null) raw.removeComponent(component);
      return;
    }
    final component = raw.getComponent<fs.DirectionalLightComponent>();
    if (component != null) raw.removeComponent(component);
  }

  void _applyShadowToComponent([fs.DirectionalLightComponent? component]) {
    if (_isPoint) return;
    final target =
        component ?? engine.raw.getComponent<fs.DirectionalLightComponent>();
    if (target == null) return;
    target.light
      ..direction = _direction
      ..color = _linearColor
      ..intensity = _intensity
      ..castsShadow = _castsShadow && _settingsShadows
      ..shadowCascadeCount = _shadowCascades.clamp(1, 4)
      ..shadowMaxDistance = _shadowDistance;
  }
}

vm.Vector3 _normalized(vm.Vector3 value) {
  final copy = value.clone();
  if (copy.length2 > 1e-18) copy.normalize();
  return copy;
}

vm.Vector3 _linearOf(Color color) => vm.Vector3(
  math.pow(color.r, 2.2).toDouble(),
  math.pow(color.g, 2.2).toDouble(),
  math.pow(color.b, 2.2).toDouble(),
);

Color _colorOf(vm.Vector3 linear) => Color.fromARGB(
  255,
  (math.pow(linear.x.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
  (math.pow(linear.y.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
  (math.pow(linear.z.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
);
