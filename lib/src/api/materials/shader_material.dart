import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'scene_texture.dart';

/// The declared type of a `.fmat` shader parameter.
enum ShaderParameterType {
  float,
  int,
  vec2,
  vec3,
  vec4,
  mat4,
  sampler2D,
  samplerCube,
}

/// One declared parameter of a [ShaderMaterial]: name, type and default.
class ShaderParameter {
  const ShaderParameter({
    required this.name,
    required this.type,
    this.defaultValue,
  });

  final String name;
  final ShaderParameterType type;
  final Object? defaultValue;

  @override
  String toString() => 'ShaderParameter($name, ${type.name})';
}

/// Loads a compiled `.fmat` material by source path; injectable for tests.
typedef ShaderMaterialLoader = Future<PreprocessedMaterial> Function(
  String sourcePath,
);

/// A loaded `.fmat` shader: its declared parameter schema and a factory of
/// independent parameter instances.
///
/// One [ShaderMaterialInstance] belongs to one visual object; assigning the
/// same instance to several objects would leak parameter values between them.
class ShaderMaterial {
  ShaderMaterial._({
    required this.name,
    required this.sourcePath,
    required PreprocessedMaterial template,
  }) : _template = template {
    final parsed = _parseSchema(template);
    _schema = parsed.parameters;
    _defaults = parsed.defaults;
  }

  /// The material name (the `.fmat` file stem).
  final String name;

  /// The asset path the material was loaded from.
  final String sourcePath;

  final PreprocessedMaterial _template;
  late final List<ShaderParameter> _schema;
  late final Map<String, Object?> _defaults;

  /// The declared parameters (uniform block first, then samplers).
  List<ShaderParameter> get parameters => List.unmodifiable(_schema);

  /// The engine-internal compiled material. Plumbing only.
  PreprocessedMaterial get raw => _template;

  /// The default value declared for [name], or null.
  Object? defaultValue(String name) => _defaults[name];

  /// Creates an independent instance with its own parameter values.
  ShaderMaterialInstance instance() {
    final material = PreprocessedMaterial(
      fragmentShader: _template.fragmentShader,
      metadata: _template.metadata,
      vertexShaders: _template.vertexShaders,
    );
    return ShaderMaterialInstance._(material, _defaults);
  }

  static ({List<ShaderParameter> parameters, Map<String, Object?> defaults})
  _parseSchema(PreprocessedMaterial material) {
    final out = <ShaderParameter>[];
    final defaults = <String, Object?>{};
    for (final raw in (material.metadata['parameters'] as List?) ?? const []) {
      final entry = (raw as Map).cast<String, Object?>();
      final name = entry['name'] as String?;
      final type = _typeOf(entry['type'] as String?);
      if (name == null || type == null) continue;
      final value = _defaultOf(type, entry['default']);
      defaults[name] = value;
      out.add(ShaderParameter(name: name, type: type, defaultValue: value));
    }
    for (final raw in (material.metadata['samplers'] as List?) ?? const []) {
      final entry = (raw as Map).cast<String, Object?>();
      final name = entry['name'] as String?;
      if (name == null) continue;
      final type = entry['type'] == 'samplerCube'
          ? ShaderParameterType.samplerCube
          : ShaderParameterType.sampler2D;
      defaults[name] = null;
      out.add(ShaderParameter(name: name, type: type));
    }
    return (parameters: out, defaults: defaults);
  }

  static ShaderParameterType? _typeOf(String? token) => switch (token) {
    'float' => ShaderParameterType.float,
    'int' => ShaderParameterType.int,
    'vec2' => ShaderParameterType.vec2,
    'vec3' => ShaderParameterType.vec3,
    'vec4' => ShaderParameterType.vec4,
    'mat4' => ShaderParameterType.mat4,
    'sampler2d' || 'sampler2D' => ShaderParameterType.sampler2D,
    'samplerCube' => ShaderParameterType.samplerCube,
    _ => null,
  };

  static Object? _defaultOf(ShaderParameterType type, Object? raw) {
    if (raw == null) return null;
    if (type == ShaderParameterType.float) {
      return (raw as num).toDouble();
    }
    if (type == ShaderParameterType.int) return (raw as num).toInt();
    if (raw is List) {
      final values = [for (final v in raw) (v as num).toDouble()];
      return switch (type) {
        ShaderParameterType.vec2 when values.length >= 2 => vm.Vector2(
          values[0],
          values[1],
        ),
        ShaderParameterType.vec3 when values.length >= 3 => vm.Vector3(
          values[0],
          values[1],
          values[2],
        ),
        ShaderParameterType.vec4 when values.length >= 4 => vm.Vector4(
          values[0],
          values[1],
          values[2],
          values[3],
        ),
        ShaderParameterType.mat4 when values.length >= 16 =>
          vm.Matrix4.fromList(values.sublist(0, 16)),
        _ => null,
      };
    }
    return null;
  }
}

/// A live parameter block of a [ShaderMaterial]: one visual object's values.
class ShaderMaterialInstance {
  ShaderMaterialInstance._(this.raw, Map<String, Object?> defaults)
    : _defaults = defaults;

  /// The compiled material this instance drives. Plumbing only.
  final PreprocessedMaterial raw;

  final Map<String, Object?> _defaults;

  /// Sets a `float` parameter.
  void setFloat(String name, double value) =>
      raw.parameters.setFloat(name, value);

  /// Sets an `int` parameter.
  void setInt(String name, int value) => raw.parameters.setInt(name, value);

  /// Sets a `vec4` parameter.
  void setVector(String name, vm.Vector4 value) =>
      raw.parameters.setVec4(name, value);

  /// Sets a `vec4` parameter from a [Color] (sRGB-decoded when the parameter
  /// carries a `source_color` hint).
  void setColor(String name, Color value) =>
      raw.parameters.setColor(name, value);

  /// Binds a texture to a sampler parameter. [filter] overrides the texture's
  /// own sampling preset for this binding.
  void setTexture(
    String name,
    SceneTexture texture, {
    SceneTextureFilter? filter,
  }) {
    final gpuTexture = texture.raw;
    if (gpuTexture == null) {
      throw StateError(
        'SceneTexture is not uploaded yet (width ${texture.width}, height '
        '${texture.height}); await SceneTexture.ready before binding it.',
      );
    }
    raw.parameters.setTexture(
      name,
      gpuTexture.gpuTexture,
      sampler: filter == null ? null : _samplingOf(filter).toSamplerOptions(),
    );
  }

  /// The current value of [name]: the last assigned value, otherwise the
  /// declared default (null for samplers).
  Object? get(String name) {
    final assigned = raw.parameters.assignedValues[name];
    if (assigned != null) return assigned;
    return _defaults[name];
  }

  static TextureSampling _samplingOf(SceneTextureFilter filter) =>
      switch (filter) {
        SceneTextureFilter.pixelated => const TextureSampling(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
          mipFilter: gpu.MipFilter.nearest,
        ),
        SceneTextureFilter.linear => const TextureSampling(),
      };
}

/// Loads `.fmat` shaders by asset path and caches the compiled results.
///
/// Failures are isolated per path: [load] returns null and the library keeps
/// working for the other materials.
class ShaderLibrary {
  ShaderLibrary({ShaderMaterialLoader? loader})
    : _loader = loader ?? loadFmatMaterial;

  final ShaderMaterialLoader _loader;
  final Map<String, ShaderMaterial> _materials = {};
  final Set<String> _failed = {};

  /// The loaded materials keyed by their source path.
  Map<String, ShaderMaterial> get materials => Map.unmodifiable(_materials);

  /// The paths that failed to load.
  Set<String> get failures => Set.unmodifiable(_failed);

  /// True when at least one material is loaded and nothing failed.
  bool get isLoaded => _materials.isNotEmpty && _failed.isEmpty;

  /// Loads the `.fmat` at [assetPath] (`assets/shaders/fx_glow.fmat`); returns
  /// the cached material when it was already loaded, or null on failure.
  Future<ShaderMaterial?> load(String assetPath) async {
    final cached = _materials[assetPath];
    if (cached != null) return cached;
    try {
      final raw = await _loader(assetPath);
      final material = ShaderMaterial._(
        name: _stemOf(assetPath),
        sourcePath: assetPath,
        template: raw,
      );
      _materials[assetPath] = material;
      _failed.remove(assetPath);
      return material;
    } catch (error) {
      debugPrint('ShaderLibrary: $assetPath unavailable: $error');
      _failed.add(assetPath);
      return null;
    }
  }

  /// Reloads every previously loaded material (the «перезагрузить» button).
  Future<void> reload() async {
    final paths = _materials.keys.toList();
    _materials.clear();
    _failed.clear();
    for (final path in paths) {
      await load(path);
    }
  }

  /// Drops every loaded material; [load] can run again afterwards.
  void dispose() {
    _materials.clear();
    _failed.clear();
  }

  static String _stemOf(String assetPath) {
    final slash = assetPath.lastIndexOf('/');
    final file = slash >= 0 ? assetPath.substring(slash + 1) : assetPath;
    return file.endsWith('.fmat')
        ? file.substring(0, file.length - '.fmat'.length)
        : file;
  }
}
