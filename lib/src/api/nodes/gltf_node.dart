import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import '../../render/engine_node.dart';
import '../../services/gltf_asset_store.dart';
import '../../services/texture_alpha.dart';
import 'scene_node.dart';

/// A runtime-imported glTF/GLB resource (the editor's model viewer, dynamic
/// loading). Not tied to the project's `3d_models/` catalog.
///
/// The asset owns a detached master tree; every [GltfNode] clones it, so
/// several nodes can share one imported resource. Loading needs a GPU (the
/// importer builds materials); the surrounding API (node, player, bounds)
/// is headless-friendly.
class GltfAsset {
  GltfAsset._(this._master, this._animations, this.bounds, this.animations);

  final fs.Node _master;
  final List<fs.Animation> _animations;

  /// The asset's world-space bounds in its own frame, or null when the
  /// model reports none (for example skinned meshes).
  final vm.Aabb3? bounds;

  /// The animation descriptors of the asset.
  final List<GltfAnimInfo> animations;

  /// The detached master tree. Plumbing for [GltfNode].
  @internal
  fs.Node get master => _master;

  /// The parsed animations. Plumbing for [AnimationPlayer].
  @internal
  List<fs.Animation> get parsedAnimations => _animations;

  /// Imports glTF/GLB [bytes]. For a `.gltf` document, [siblings] resolves
  /// the referenced URIs (relative paths as written in the document) to
  /// bytes; missing entries resolve to an empty buffer, like a missing file.
  static Future<GltfAsset> fromBytes(
    Uint8List bytes, {
    Map<String, Uint8List> siblings = const {},
  }) async {
    if (_isGlb(bytes)) {
      final node = await fs.Node.fromGlbBytes(bytes);
      return _wrap(node);
    }
    final node = await fs.Node.fromGltfBytes(
      bytes,
      resolveUri: (uri) async => siblings[uri] ?? Uint8List(0),
    );
    await _configureBlend(node, bytes, (uri) async => siblings[uri]);
    return _wrap(node);
  }

  /// Imports a `.glb` file or a `.gltf` document with its sibling files
  /// (`.bin`, textures) resolved relative to the file's folder.
  static Future<GltfAsset> fromFile(File file) async {
    final bytes = await file.readAsBytes();
    if (_isGlb(bytes)) {
      final node = await fs.Node.fromGlbBytes(bytes);
      return _wrap(node);
    }
    final dir = file.parent.path;
    Future<Uint8List?> read(String uri) async {
      final sibling = File('$dir/$uri');
      return sibling.existsSync() ? sibling.readAsBytes() : null;
    }

    final node = await fs.Node.fromGltfBytes(
      bytes,
      resolveUri: (uri) async => await read(uri) ?? Uint8List(0),
    );
    await _configureBlend(node, bytes, read);
    return _wrap(node);
  }

  static bool _isGlb(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x67 &&
      bytes[1] == 0x6C &&
      bytes[2] == 0x54 &&
      bytes[3] == 0x46;

  static GltfAsset _wrap(fs.Node node) {
    final bounds = node.combinedWorldBounds;
    final parsed = node.parsedAnimations;
    return GltfAsset._(
      node,
      parsed,
      bounds,
      [
        for (final a in parsed)
          GltfAnimInfo(
            fullName: a.name,
            shortName: GltfAnimInfo.shortOf(a.name),
            duration: a.endTime,
          ),
      ],
    );
  }

  /// Best-effort alpha reclassification of `BLEND` materials (cut-out
  /// textures must not show their hidden geometry through the body). Never
  /// throws — a failure leaves the imported materials as they are.
  static Future<void> _configureBlend(
    fs.Node node,
    Uint8List gltfBytes,
    Future<Uint8List?> Function(String uri) readImage,
  ) async {
    try {
      await configureGltfBlendMaterials(
        node,
        gltfDoc: jsonDecode(utf8.decode(gltfBytes)) as Map<String, Object?>,
        readImage: readImage,
      );
    } catch (_) {
      // A malformed document or unreadable texture is not fatal here.
    }
  }
}

/// A scene node rendering one [GltfAsset] with its own animation player.
///
/// The node clones the asset's master tree on attach, so the same asset can
/// back several nodes. The fork advances the clips each frame while the node
/// is mounted; the player only drives their state.
class GltfNode extends SceneNode {
  GltfNode.fromAsset(this.asset, {super.id, String? name, super.layer})
    : super(name: name ?? asset.master.name) {
    player = AnimationPlayer(this);
  }

  /// The imported resource.
  final GltfAsset asset;

  /// The animation player of this node (empty when the asset has no clips).
  late final AnimationPlayer player;

  fs.Node? _content;

  @override
  void syncToEngine() {
    if (_content != null) return;
    final content = asset.master.clone();
    _content = content;
    player._attach(content);
    engine.add(EngineNode.wrap(content));
  }

  @override
  vm.Aabb3? get worldBounds {
    final bounds = asset.bounds;
    if (bounds == null) return null;
    final m = globalTransform;
    final min = vm.Vector3(double.infinity, double.infinity, double.infinity);
    final max = vm.Vector3(
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );
    for (var i = 0; i < 8; i++) {
      final corner = vm.Vector3(
        (i & 1) == 0 ? bounds.min.x : bounds.max.x,
        (i & 2) == 0 ? bounds.min.y : bounds.max.y,
        (i & 4) == 0 ? bounds.min.z : bounds.max.z,
      );
      m.transform3(corner);
      min.setValues(
        min.x < corner.x ? min.x : corner.x,
        min.y < corner.y ? min.y : corner.y,
        min.z < corner.z ? min.z : corner.z,
      );
      max.setValues(
        max.x > corner.x ? max.x : corner.x,
        max.y > corner.y ? max.y : corner.y,
        max.z > corner.z ? max.z : corner.z,
      );
    }
    return vm.Aabb3.minMax(min, max);
  }

  @override
  void frameTick(Duration elapsed, double dt) => player._tick(dt);

  @override
  void dispose() {
    player.dispose();
    _content = null;
    super.dispose();
  }
}

/// Full animation control of a [GltfNode]: clip selection, transport,
/// speed, looping, weight and crossfades. The fork advances the clips while
/// the node is mounted; the player owns their state and notifies listeners
/// on every change (including fades).
class AnimationPlayer extends ChangeNotifier {
  /// Creates a player for [node].
  AnimationPlayer(this._node);

  final GltfNode _node;
  final Map<String, fs.AnimationClip> _clips = {};

  String? _current;
  double _speed = 1;
  bool _loop = true;
  double _weight = 0;
  fs.AnimationClip? _fadeFrom;
  fs.AnimationClip? _fadeTo;
  double _fadeDuration = 0;
  double _fadeElapsed = 0;
  bool _lastPlaying = false;

  /// The animation descriptors of the node's asset.
  List<GltfAnimInfo> get clips => _node.asset.animations;

  /// The selected clip (full name), or null for the rest pose.
  String? get current => _current;

  /// Whether the selected clip is currently advancing.
  bool get playing => _clipOf(_current)?.playing ?? false;

  /// The playback speed multiplier of the selected clip.
  double get speed => _speed;

  /// Whether the selected clip loops.
  bool get loop => _loop;

  /// The current blend weight (1 — fully visible; fades interpolate it).
  double get weight => _weight;

  fs.AnimationClip? _clipOf(String? name) =>
      name == null ? null : _clips[name];

  /// Plays [clipFullName] from the start, looping by default. Unknown names
  /// (and '') return to the rest pose.
  void play(String clipFullName, {bool loop = true, double speed = 1}) {
    final clip = _clips[clipFullName];
    if (clip == null) {
      stop();
      return;
    }
    _cancelFade();
    for (final entry in _clips.entries) {
      if (identical(entry.value, clip)) continue;
      entry.value
        ..pause()
        ..weight = 0;
    }
    _current = clipFullName;
    _loop = loop;
    _speed = speed;
    _weight = 1;
    clip
      ..weight = 1
      ..loop = loop
      ..playbackTimeScale = speed
      ..seek(0)
      ..play();
    _lastPlaying = true;
    notifyListeners();
  }

  /// Pauses the selected clip at its current time.
  void pause() {
    _clipOf(_current)?.pause();
    notifyListeners();
  }

  /// Resumes the selected clip.
  void resume() {
    _clipOf(_current)?.play();
    notifyListeners();
  }

  /// Stops playback and returns to the rest pose.
  void stop() {
    final clip = _clipOf(_current);
    if (clip != null) {
      clip
        ..pause()
        ..seek(0)
        ..weight = 0;
    }
    _current = null;
    _weight = 0;
    _cancelFade();
    notifyListeners();
  }

  /// Seeks the selected clip to [seconds].
  void seek(double seconds) {
    _clipOf(_current)?.seek(seconds);
    notifyListeners();
  }

  /// Blends from the current clip to [clipFullName] over [duration].
  void crossFade(
    String clipFullName, {
    Duration duration = const Duration(milliseconds: 250),
  }) {
    final target = _clips[clipFullName];
    if (target == null) return;
    final from = _clipOf(_current);
    if (from == null || identical(from, target)) {
      play(clipFullName, loop: _loop, speed: _speed);
      return;
    }
    _fadeFrom = from;
    _fadeTo = target;
    _fadeDuration = duration.inMicroseconds / 1000000;
    _fadeElapsed = 0;
    target
      ..loop = _loop
      ..playbackTimeScale = _speed
      ..weight = 0
      ..seek(0)
      ..play();
    _current = clipFullName;
    _weight = 0;
    notifyListeners();
  }

  void _cancelFade() {
    final from = _fadeFrom;
    if (from != null) {
      from.weight = 0;
    }
    _fadeFrom = null;
    _fadeTo = null;
    _fadeDuration = 0;
    _fadeElapsed = 0;
  }

  /// Builds the clip instances of a freshly cloned content tree.
  void _attach(fs.Node content) {
    _clips.clear();
    for (final animation in _node.asset.parsedAnimations) {
      final clip = content.createAnimationClip(animation)
        ..weight = 0
        ..loop = true
        ..pause();
      _clips[animation.name] = clip;
    }
    _current = null;
    _weight = 0;
  }

  /// Advances an active crossfade (the fork advances the clips themselves).
  void _tick(double dt) {
    final from = _fadeFrom;
    final to = _fadeTo;
    if (from != null && to != null) {
      _fadeElapsed += dt;
      final t = _fadeDuration <= 0
          ? 1.0
          : (_fadeElapsed / _fadeDuration).clamp(0.0, 1.0);
      from.weight = 1 - t;
      to.weight = t;
      _weight = t;
      if (t >= 1) {
        from
          ..pause()
          ..weight = 0;
        _fadeFrom = null;
        _fadeTo = null;
        _weight = 1;
      }
      notifyListeners();
      return;
    }
    final playing = this.playing;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      notifyListeners();
    }
  }
}
