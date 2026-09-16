import 'dart:convert';

import 'package:vector_math/vector_math.dart' as vm;

import '../models/model_scene.dart';
import '../models/scene_loader.dart';
import 'build_ops.dart';

/// How a construction element is turned into render content by the level
/// baker:
/// - [merge] — baked into the shared per-material static mesh (the default);
/// - [batch] — grouped with identical elements (same shape + material) into
///   one batch, transforms baked in (true GPU instancing is phase 6);
/// - [node] — kept as a separate node so the game can move/replace it at
///   runtime without a content rebuild.
enum BakeMode { merge, batch, node }

/// The bake mode of an element (`bake` in JSON; absent = [BakeMode.merge]).
///
/// Kinds that cannot be merged are always [BakeMode.node], regardless of the
/// stored hint: sprites must stay camera-facing, model/gltf instances render
/// as recursive content, a csg without a whole-result material emits
/// several per-face material groups, and a polyhedron's batch key cannot
/// distinguish different meshes (each one stays a node).
BakeMode bakeModeOf(ModelObject obj) {
  if (obj.kind == 'sprite' ||
      obj.kind == polyhedronKind ||
      obj.isModelRef ||
      obj.isGltfRef ||
      (obj.isCsg && obj.material == null)) {
    return BakeMode.node;
  }
  return switch (obj.bake) {
    'batch' => BakeMode.batch,
    'node' => BakeMode.node,
    _ => BakeMode.merge,
  };
}

/// Writes [mode] into the element's serialized `bake` hint (merge = null).
void setBakeMode(ModelObject obj, BakeMode mode) {
  obj.bake = mode == BakeMode.merge ? null : mode.name;
}

/// The level layer's construction model: a thin
/// wrapper over the `model_v1` document whose elements carry the optional
/// `bake`/`tag` hints. Statics are built here and baked into the scene;
/// dynamic objects never pass through it.
///
/// The wrapper adds nothing to the format — [ModelData] already round-trips
/// elements, ids and bounds, and `bake`/`tag` are optional object fields.
class ConstructionModel {
  final ModelData data;

  ConstructionModel({
    String id = 'level',
    String name = '',
    ModelSize? size,
    List<ModelObject>? objects,
    List<ModelGroup>? groups,
    List<ModelMeta>? metas,
  }) : data = ModelData(
          id: id,
          name: name,
          size: size,
          objects: objects,
          groups: groups,
          metas: metas,
        );

  /// Wraps an existing document (no copy — the model is the source of truth).
  ConstructionModel.wrap(this.data);

  String get id => data.id;
  String get name => data.name;
  ModelSize get size => data.size;
  List<ModelObject> get elements => data.objects;

  /// Adds [object] as an element with the given bake mode/tag and returns it.
  /// The model takes ownership: [bake]/[tag] are written onto [object] and
  /// the same instance is stored — do not reuse it in another model.
  ModelObject add(
    ModelObject object, {
    BakeMode bake = BakeMode.merge,
    String? tag,
  }) {
    setBakeMode(object, bake);
    object.tag = tag;
    data.objects.add(object);
    return object;
  }

  void addAll(Iterable<ModelObject> objects, {BakeMode bake = BakeMode.merge}) {
    for (final o in objects) {
      add(o, bake: bake);
    }
  }

  ModelObject? byId(String id) => data.objectById(id);

  bool remove(String id) {
    final before = data.objects.length;
    data.objects.removeWhere((o) => o.id == id);
    return data.objects.length != before;
  }

  void clear() => data.objects.clear();

  /// Model-local AABB of the element [id] (rotation included), or null.
  (vm.Vector3 min, vm.Vector3 max)? boundsOf(String id) {
    final o = byId(id);
    return o == null ? null : objectBounds(o);
  }

  /// Model-local AABB of every element (null when empty).
  (vm.Vector3 min, vm.Vector3 max)? get bounds {
    if (data.objects.isEmpty) return null;
    var lo = vm.Vector3(double.infinity, double.infinity, double.infinity);
    var hi = vm.Vector3(
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    );
    for (final o in data.objects) {
      final (bLo, bHi) = objectBounds(o);
      lo = vm.Vector3(
        bLo.x < lo.x ? bLo.x : lo.x,
        bLo.y < lo.y ? bLo.y : lo.y,
        bLo.z < lo.z ? bLo.z : lo.z,
      );
      hi = vm.Vector3(
        bHi.x > hi.x ? bHi.x : hi.x,
        bHi.y > hi.y ? bHi.y : hi.y,
        bHi.z > hi.z ? bHi.z : hi.z,
      );
    }
    return (lo, hi);
  }

  Map<String, Object> toJson() => data.toJson();

  String toJsonString() => jsonEncode(toJson());

  factory ConstructionModel.fromJson(String jsonStr, {required String id}) =>
      ConstructionModel.wrap(loadModelData(jsonStr, id: id));
}
