import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

import '../render/engine_material.dart';

/// A compiled `.fmat` slot: one source path with [instances] per-instance
/// copies. Each instance owns its own [MaterialParameters], so per-object
/// uniforms do not leak between simultaneous users (the game caches three
/// copies for up to three enemies).
class FmatSlot {
  const FmatSlot({
    required this.name,
    required this.sourcePath,
    this.instances = 1,
  });

  /// Game-side slot key (e.g. an effect id or a name).
  final String name;

  /// The `.fmat` source path inside the app bundle
  /// (`assets/shaders/fx_glow.fmat`).
  final String sourcePath;

  /// How many independent material instances this slot keeps.
  final int instances;
}

/// Loader signature (injectable for tests); defaults to the fork's
/// [loadFmatMaterial].
typedef FmatLoader = Future<PreprocessedMaterial> Function(String sourcePath);

/// Loads and owns `.fmat` materials for a game/stand: one or more slots, each
/// with a fixed number of per-instance materials, parameters configured at use
/// time, and a hard fallback — a failed slot returns null from [materialFor]
/// so the caller draws its plain sprite instead.
///
/// Hot reload: [PreprocessedMaterial] implements the fork's hot-reloadable
/// contract; `SceneView.reassemble()` refreshes loaded materials in place
/// after the build hook recompiles an edited `.fmat`.
class FmatManager {
  FmatManager({required List<FmatSlot> slots, FmatLoader? loader})
      : _slots = {for (final slot in slots) slot.name: slot},
        _loader = loader ?? loadFmatMaterial;

  final Map<String, FmatSlot> _slots;
  final FmatLoader _loader;
  final Map<String, List<PreprocessedMaterial?>> _materials = {};
  bool _loaded = false;
  bool _ready = false;

  /// True once [load] finished without any slot failing.
  bool get ready => _ready;

  /// Whether [load] has run (regardless of failures).
  bool get loaded => _loaded;

  /// Loads every slot. Failures are caught per slot: the slot stays
  /// unavailable ([materialFor] returns null for it) and [ready] is false.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    var allOk = true;
    for (final slot in _slots.values) {
      final list = <PreprocessedMaterial?>[];
      for (var i = 0; i < slot.instances; i++) {
        try {
          list.add(await _loader(slot.sourcePath));
        } catch (error) {
          debugPrint(
            'FmatManager: ${slot.name} unavailable, falling back: $error',
          );
          allOk = false;
          list.add(null);
        }
      }
      _materials[slot.name] = list;
    }
    _ready = allOk;
  }

  /// The material of slot [name], instance [instance], after applying
  /// [configure] to its parameters; null when the slot is unknown, out of
  /// range or failed to load.
  PreprocessedMaterial? materialFor(
    String name, {
    int instance = 0,
    void Function(MaterialParameters parameters)? configure,
  }) {
    final list = _materials[name];
    if (list == null || instance < 0 || instance >= list.length) return null;
    final material = list[instance];
    if (material == null) return null;
    if (configure != null) configure(material.parameters);
    return material;
  }

  /// The engine-facade variant of [materialFor]: the material arrives as an
  /// [EngineMaterial] and [configure] receives the typed engine parameter
  /// wrapper, so games configure `.fmat` shaders without naming fork types.
  EngineMaterial? engineMaterialFor(
    String name, {
    int instance = 0,
    void Function(EngineMaterialParameters parameters)? configure,
  }) {
    final material = materialFor(
      name,
      instance: instance,
      configure: configure == null
          ? null
          : (parameters) => configure(EngineMaterialParameters(parameters)),
    );
    return material == null ? null : EngineMaterial.wrap(material);
  }

  /// Drops every material; [load] can run again afterwards.
  void dispose() {
    _materials.clear();
    _loaded = false;
    _ready = false;
  }
}
