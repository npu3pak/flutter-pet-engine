// Private fields behind public getters/setters cannot use initializing
// formals in named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../render/engine_material.dart';
import '../../render/engine_texture.dart';
import 'scene_texture.dart';
import 'shader_material.dart';

/// How a material's alpha channel is interpreted (mirrors glTF's alphaMode).
enum SceneAlphaMode { opaque, mask, blend }

enum _MaterialKind { pbr, unlit, shader }

/// A live material of the new API: color, texture, PBR/unlit parameters, or a
/// `.fmat` shader instance.
///
/// The material is a [ChangeNotifier]: attached nodes re-apply it as soon as
/// it changes, and the GPU material is built lazily so materials can be
/// constructed without a rendering device.
class SceneMaterial extends ChangeNotifier {
  /// A physically based material with image-based lighting.
  SceneMaterial.pbr({
    SceneTexture? texture,
    Color color = const Color(0xFFFFFFFF),
    double roughness = 1.0,
    double metallic = 0.0,
    SceneAlphaMode alphaMode = SceneAlphaMode.opaque,
    double alphaCutoff = 0.5,
    bool doubleSided = false,
    Color? emissive,
    double? fogStartOverride,
    double blendOrder = 0.0,
  }) : _kind = _MaterialKind.pbr,
       _texture = texture,
       _color = color,
       _roughness = roughness,
       _metallic = metallic,
       _alphaMode = alphaMode,
       _alphaCutoff = alphaCutoff,
       _doubleSided = doubleSided,
       _emissive = emissive,
       _fogStartOverride = fogStartOverride,
       _blendOrder = blendOrder {
    _texture?.addListener(_onTextureChanged);
  }

  /// A flat-color / textured material ignoring scene lighting.
  SceneMaterial.unlit({
    SceneTexture? texture,
    Color color = const Color(0xFFFFFFFF),
    SceneAlphaMode alphaMode = SceneAlphaMode.opaque,
    bool doubleSided = false,
    double blendOrder = 0.0,
  }) : _kind = _MaterialKind.unlit,
       _texture = texture,
       _color = color,
       _roughness = 1.0,
       _metallic = 0.0,
       _alphaMode = alphaMode,
       _alphaCutoff = 0.5,
       _doubleSided = doubleSided,
       _emissive = null,
       _fogStartOverride = null,
       _blendOrder = blendOrder {
    _texture?.addListener(_onTextureChanged);
  }

  /// A material driven by a [ShaderMaterialInstance] (a `.fmat` shader).
  SceneMaterial.shader(ShaderMaterialInstance shader)
    : _kind = _MaterialKind.shader,
      _texture = null,
      _color = const Color(0xFFFFFFFF),
      _roughness = 1.0,
      _metallic = 0.0,
      _alphaMode = SceneAlphaMode.opaque,
      _alphaCutoff = 0.5,
      _doubleSided = false,
      _emissive = null,
      _fogStartOverride = null,
      _blendOrder = 0.0,
      _shader = shader;

  /// Wraps an already-built engine material (the level bake hook path).
  /// Plumbing only: parameters are read from the wrapped material and writes
  /// go through to it.
  @internal
  SceneMaterial.fromEngine(EngineMaterial material)
    : _kind = material.isFmat
          ? _MaterialKind.shader
          : material.isUnlit
          ? _MaterialKind.unlit
          : _MaterialKind.pbr,
      _texture = material.texture == null
          ? null
          : SceneTexture.fromGpu(material.texture!.raw),
      _color = _colorOf(material.color),
      _roughness = material.roughness,
      _metallic = material.metallic,
      _alphaMode = _alphaModeOfEngine(material.alphaMode),
      _alphaCutoff = material.alphaCutoff,
      _doubleSided = material.doubleSided,
      _emissive = null,
      _fogStartOverride = material.fogStartOverride,
      _blendOrder = material.blendOrder {
    _wrapped = material;
    _raw = material.raw;
  }

  final _MaterialKind _kind;

  EngineMaterial? _wrapped;

  SceneTexture? _texture;

  /// The base color texture, or null.
  SceneTexture? get texture => _texture;
  set texture(SceneTexture? value) {
    if (identical(_texture, value)) return;
    _texture?.removeListener(_onTextureChanged);
    _texture = value;
    _texture?.addListener(_onTextureChanged);
    _apply();
  }

  Color _color;

  /// The base color (sRGB).
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    _apply();
  }

  SceneAlphaMode _alphaMode;

  /// Alpha handling: opaque, alpha-mask with [alphaCutoff], or blended.
  SceneAlphaMode get alphaMode => _alphaMode;
  set alphaMode(SceneAlphaMode value) {
    if (_alphaMode == value) return;
    _alphaMode = value;
    _apply();
  }

  double _alphaCutoff;

  /// The mask threshold when [alphaMode] is [SceneAlphaMode.mask].
  double get alphaCutoff => _alphaCutoff;
  set alphaCutoff(double value) {
    if (_alphaCutoff == value) return;
    _alphaCutoff = value;
    _apply();
  }

  bool _doubleSided;

  /// Whether both faces render (otherwise back faces are culled).
  bool get doubleSided => _doubleSided;
  set doubleSided(bool value) {
    if (_doubleSided == value) return;
    _doubleSided = value;
    _apply();
  }

  double _blendOrder;

  /// Sort order within the translucent pass.
  double get blendOrder => _blendOrder;
  set blendOrder(double value) {
    if (_blendOrder == value) return;
    _blendOrder = value;
    _apply();
  }

  double _roughness;

  /// Surface roughness (PBR only).
  double get roughness => _roughness;
  set roughness(double value) {
    if (_roughness == value) return;
    _roughness = value;
    _apply();
  }

  double _metallic;

  /// Metalness (PBR only).
  double get metallic => _metallic;
  set metallic(double value) {
    if (_metallic == value) return;
    _metallic = value;
    _apply();
  }

  Color? _emissive;

  /// Emissive tint (PBR only), or null for none.
  Color? get emissive => _emissive;
  set emissive(Color? value) {
    if (_emissive == value) return;
    _emissive = value;
    _apply();
  }

  double? _fogStartOverride;

  /// Fog distance override (PBR only), or null for the scene fog.
  double? get fogStartOverride => _fogStartOverride;
  set fogStartOverride(double? value) {
    if (_fogStartOverride == value) return;
    _fogStartOverride = value;
    _apply();
  }

  ShaderMaterialInstance? _shader;

  /// The shader instance when this is a shader material, else null.
  ShaderMaterialInstance? get shader => _shader;

  /// Whether this is a physically based (lit) material.
  bool get isPbr => _kind == _MaterialKind.pbr;

  /// Whether this is an unlit material.
  bool get isUnlit => _kind == _MaterialKind.unlit;

  /// Whether this is a `.fmat` shader material.
  bool get isShader => _kind == _MaterialKind.shader;

  Material? _raw;

  /// The compiled material used for rendering. Plumbing only; built lazily so
  /// headless tests never touch a rendering device.
  Material get raw {
    final existing = _raw;
    if (existing != null) return existing;
    final built = _build();
    _raw = built;
    return built;
  }

  Material _build() {
    switch (_kind) {
      case _MaterialKind.shader:
        return _shader!.raw;
      case _MaterialKind.unlit:
        final material = UnlitMaterial(colorTexture: _texture?.raw)
          ..baseColorFactor = _linear(_color)
          ..alphaMode = _alphaModeOf(_alphaMode)
          ..doubleSided = _doubleSided
          ..blendOrder = _blendOrder;
        return material;
      case _MaterialKind.pbr:
        final material = PhysicallyBasedMaterial()
          ..baseColorFactor = _linear(_color)
          ..roughnessFactor = _roughness
          ..metallicFactor = _metallic
          ..emissiveFactor = _emissive == null
              ? vm.Vector4.zero()
              : _linear(_emissive!)
          ..alphaMode = _alphaModeOf(_alphaMode)
          ..alphaCutoff = _alphaCutoff
          ..doubleSided = _doubleSided
          ..fogStartOverride = _fogStartOverride ?? 0.0
          ..blendOrder = _blendOrder;
        final texture = _texture?.raw;
        if (texture != null) material.baseColorTexture = texture;
        return material;
    }
  }

  void _onTextureChanged() => _apply();

  /// Creates a detached copy of this material with the same parameters.
  /// Plumbing for per-node opacity; the copy builds its own GPU material.
  @internal
  SceneMaterial copy() {
    final wrapped = _wrapped;
    if (wrapped != null && _kind == _MaterialKind.shader) {
      return SceneMaterial.fromEngine(wrapped);
    }
    return switch (_kind) {
      _MaterialKind.pbr => SceneMaterial.pbr(
        texture: _texture,
        color: _color,
        roughness: _roughness,
        metallic: _metallic,
        alphaMode: _alphaMode,
        alphaCutoff: _alphaCutoff,
        doubleSided: _doubleSided,
        emissive: _emissive,
        fogStartOverride: _fogStartOverride,
        blendOrder: _blendOrder,
      ),
      _MaterialKind.unlit => SceneMaterial.unlit(
        texture: _texture,
        color: _color,
        alphaMode: _alphaMode,
        doubleSided: _doubleSided,
        blendOrder: _blendOrder,
      ),
      _MaterialKind.shader => SceneMaterial.shader(_shader!),
    };
  }

  /// Re-applies the stored parameters to the compiled material (when it was
  /// already built) and notifies listeners.
  void _apply() {
    final wrapped = _wrapped;
    if (wrapped != null) {
      wrapped
        ..color = _linear(_color)
        ..roughness = _roughness
        ..metallic = _metallic
        ..alphaMode = _engineAlphaModeOf(_alphaMode)
        ..alphaCutoff = _alphaCutoff
        ..doubleSided = _doubleSided
        ..blendOrder = _blendOrder
        ..fogStartOverride = _fogStartOverride ?? 0.0;
      if (_emissive != null) wrapped.emissive = _linear(_emissive!);
      final texture = _texture?.raw;
      if (texture is Texture2D) {
        wrapped.texture = EngineTexture.wrap(texture);
      }
      notifyListeners();
      return;
    }
    final material = _raw;
    if (material != null) {
      switch (_kind) {
        case _MaterialKind.shader:
          break;
        case _MaterialKind.unlit:
          final unlit = material as UnlitMaterial;
          unlit.baseColorFactor = _linear(_color);
          unlit.baseColorTexture = _texture?.raw;
          unlit.alphaMode = _alphaModeOf(_alphaMode);
          unlit.doubleSided = _doubleSided;
          unlit.blendOrder = _blendOrder;
        case _MaterialKind.pbr:
          final pbr = material as PhysicallyBasedMaterial;
          pbr.baseColorFactor = _linear(_color);
          pbr.baseColorTexture = _texture?.raw;
          pbr.roughnessFactor = _roughness;
          pbr.metallicFactor = _metallic;
          pbr.emissiveFactor = _emissive == null
              ? vm.Vector4.zero()
              : _linear(_emissive!);
          pbr.alphaMode = _alphaModeOf(_alphaMode);
          pbr.alphaCutoff = _alphaCutoff;
          pbr.doubleSided = _doubleSided;
          pbr.fogStartOverride = _fogStartOverride ?? 0.0;
          pbr.blendOrder = _blendOrder;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _texture?.removeListener(_onTextureChanged);
    super.dispose();
  }
}

/// sRGB → linear (the engine's `pow(c, 2.2)` conversion).
vm.Vector4 _linear(Color color) => vm.Vector4(
  math.pow(color.r, 2.2).toDouble(),
  math.pow(color.g, 2.2).toDouble(),
  math.pow(color.b, 2.2).toDouble(),
  color.a,
);

AlphaMode _alphaModeOf(SceneAlphaMode mode) => switch (mode) {
  SceneAlphaMode.opaque => AlphaMode.opaque,
  SceneAlphaMode.mask => AlphaMode.mask,
  SceneAlphaMode.blend => AlphaMode.blend,
};

/// Linear RGBA (the engine's material color) → sRGB [Color].
Color _colorOf(vm.Vector4 linear) => Color.fromARGB(
  (linear.w.clamp(0.0, 1.0) * 255).round(),
  (math.pow(linear.x.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
  (math.pow(linear.y.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
  (math.pow(linear.z.clamp(0.0, 1.0), 1 / 2.2) * 255).round(),
);

SceneAlphaMode _alphaModeOfEngine(EngineAlphaMode mode) => switch (mode) {
  EngineAlphaMode.opaque => SceneAlphaMode.opaque,
  EngineAlphaMode.mask => SceneAlphaMode.mask,
  EngineAlphaMode.blend => SceneAlphaMode.blend,
};

EngineAlphaMode _engineAlphaModeOf(SceneAlphaMode mode) => switch (mode) {
  SceneAlphaMode.opaque => EngineAlphaMode.opaque,
  SceneAlphaMode.mask => EngineAlphaMode.mask,
  SceneAlphaMode.blend => EngineAlphaMode.blend,
};
