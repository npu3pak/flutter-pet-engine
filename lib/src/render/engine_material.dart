import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'engine_texture.dart';

/// How a material's alpha channel is interpreted (mirrors glTF's alphaMode).
enum EngineAlphaMode { opaque, mask, blend }

/// Opaque handle to a shading material owned by pet_engine.
///
/// Games build materials through the [EngineMaterial.pbr] / [EngineMaterial.unlit]
/// factories and tweak them through the engine setters; the fork material
/// types stay behind this facade. Materials produced by the level baker or an
/// `.fmat` shader arrive through [EngineMaterial.wrap] (engine plumbing).
class EngineMaterial {
  EngineMaterial.wrap(this.raw);

  /// The underlying fork material. Engine-internal plumbing only.
  final Material raw;

  /// A physically based material with image-based lighting.
  factory EngineMaterial.pbr({
    EngineTexture? texture,
    vm.Vector4? color,
    double roughness = 1.0,
    double metallic = 0.0,
    vm.Vector4? emissive,
    EngineAlphaMode alphaMode = EngineAlphaMode.opaque,
    double alphaCutoff = 0.5,
    bool doubleSided = false,
    double fogStartOverride = 0.0,
    double blendOrder = 0.0,
  }) {
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = texture?.raw
      ..baseColorFactor = color ?? vm.Vector4(1, 1, 1, 1)
      ..roughnessFactor = roughness
      ..metallicFactor = metallic
      ..emissiveFactor = emissive ?? vm.Vector4.zero()
      ..alphaMode = _alphaModeOf(alphaMode)
      ..alphaCutoff = alphaCutoff
      ..doubleSided = doubleSided
      ..fogStartOverride = fogStartOverride
      ..blendOrder = blendOrder;
    return EngineMaterial.wrap(material);
  }

  /// A flat-color / textured material ignoring scene lighting.
  factory EngineMaterial.unlit({
    EngineTexture? texture,
    vm.Vector4? color,
    EngineAlphaMode alphaMode = EngineAlphaMode.opaque,
    bool doubleSided = true,
    double blendOrder = 0.0,
  }) {
    final material = UnlitMaterial(colorTexture: texture?.raw)
      ..baseColorFactor = color ?? vm.Vector4(1, 1, 1, 1)
      ..alphaMode = _alphaModeOf(alphaMode)
      ..doubleSided = doubleSided
      ..blendOrder = blendOrder;
    return EngineMaterial.wrap(material);
  }

  /// Whether this material is a physically based (lit) material.
  bool get isPbr => raw is PhysicallyBasedMaterial;

  /// Whether this material is an unlit material.
  bool get isUnlit => raw is UnlitMaterial;

  /// Whether this material is a compiled `.fmat` material (parameters are
  /// available through [parameters]).
  bool get isFmat => raw is PreprocessedMaterial;

  /// The per-instance parameter block of an `.fmat` material, or null for the
  /// built-in materials.
  EngineMaterialParameters? get parameters {
    final material = raw;
    return material is PreprocessedMaterial
        ? EngineMaterialParameters(material.parameters)
        : null;
  }

  /// Linear RGBA base color (PBR: multiplied with the base texture).
  vm.Vector4 get color {
    final material = raw;
    if (material is PhysicallyBasedMaterial) return material.baseColorFactor;
    if (material is UnlitMaterial) return material.baseColorFactor;
    return vm.Vector4(1, 1, 1, 1);
  }

  set color(vm.Vector4 value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      material.baseColorFactor = value;
    } else if (material is UnlitMaterial) {
      material.baseColorFactor = value;
    }
  }

  set texture(EngineTexture? value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      material.baseColorTexture = value?.raw;
    } else if (material is UnlitMaterial) {
      material.baseColorTexture = value?.raw;
    }
  }

  /// The base color texture, or null.
  EngineTexture? get texture {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      final source = material.baseColorTexture;
      return source is Texture2D ? EngineTexture.wrap(source) : null;
    }
    if (material is UnlitMaterial) {
      final source = material.baseColorTexture;
      return source is Texture2D ? EngineTexture.wrap(source) : null;
    }
    return null;
  }

  double get roughness {
    final material = raw;
    return material is PhysicallyBasedMaterial ? material.roughnessFactor : 1.0;
  }

  set roughness(double value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) material.roughnessFactor = value;
  }

  double get metallic {
    final material = raw;
    return material is PhysicallyBasedMaterial ? material.metallicFactor : 0.0;
  }

  set metallic(double value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) material.metallicFactor = value;
  }

  vm.Vector4 get emissive {
    final material = raw;
    return material is PhysicallyBasedMaterial
        ? material.emissiveFactor
        : vm.Vector4.zero();
  }

  set emissive(vm.Vector4 value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) material.emissiveFactor = value;
  }

  EngineAlphaMode get alphaMode {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      return _engineAlphaModeOf(material.alphaMode);
    }
    if (material is UnlitMaterial) {
      return _engineAlphaModeOf(material.alphaMode);
    }
    return EngineAlphaMode.opaque;
  }

  set alphaMode(EngineAlphaMode value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      material.alphaMode = _alphaModeOf(value);
    } else if (material is UnlitMaterial) {
      material.alphaMode = _alphaModeOf(value);
    }
  }

  double get alphaCutoff {
    final material = raw;
    return material is PhysicallyBasedMaterial ? material.alphaCutoff : 0.5;
  }

  set alphaCutoff(double value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) material.alphaCutoff = value;
  }

  bool get doubleSided => raw.doubleSided;

  set doubleSided(bool value) => raw.doubleSided = value;

  double get fogStartOverride {
    final material = raw;
    return material is PhysicallyBasedMaterial ? material.fogStartOverride : 0.0;
  }

  set fogStartOverride(double value) {
    final material = raw;
    if (material is PhysicallyBasedMaterial) {
      material.fogStartOverride = value;
    }
  }

  double get blendOrder => raw.blendOrder;

  set blendOrder(double value) => raw.blendOrder = value;

  set name(String value) => raw.name = value;
}

/// Typed access to an `.fmat` material's uniforms: floats by name plus
/// textures. Games configure effect parameters here without touching the
/// fork's parameter classes.
class EngineMaterialParameters {
  EngineMaterialParameters(this.raw);

  /// Engine-internal plumbing only.
  final MaterialParameters raw;

  void setFloat(String name, double value) => raw.setFloat(name, value);

  void setTexture(String name, EngineTexture texture, {bool nearest = false}) {
    raw.setTexture(
      name,
      texture.raw.sampledTexture!,
      sampler: nearest ? texture.raw.sampledSampler : null,
    );
  }
}

AlphaMode _alphaModeOf(EngineAlphaMode mode) => switch (mode) {
      EngineAlphaMode.opaque => AlphaMode.opaque,
      EngineAlphaMode.mask => AlphaMode.mask,
      EngineAlphaMode.blend => AlphaMode.blend,
    };

EngineAlphaMode _engineAlphaModeOf(AlphaMode mode) => switch (mode) {
      AlphaMode.opaque => EngineAlphaMode.opaque,
      AlphaMode.mask => EngineAlphaMode.mask,
      AlphaMode.blend => EngineAlphaMode.blend,
    };
