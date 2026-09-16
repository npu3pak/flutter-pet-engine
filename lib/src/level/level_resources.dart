import '../models/model_scene.dart';

/// The resource closure of a level model: every texture, sprite, glTF asset
/// and referenced model the scene needs before it can be built (подшаг 5.3).
class ModelResourceClosure {
  const ModelResourceClosure({
    this.textureKeys = const {},
    this.spriteKeys = const {},
    this.gltfNames = const {},
    this.modelIds = const {},
    this.missingModelIds = const {},
  });

  /// Texture keys (file name with extension) used by element/face materials.
  final Set<String> textureKeys;

  /// Sprite keys (file name with extension) used by element/face materials.
  final Set<String> spriteKeys;

  /// glTF catalog names referenced by `gltf` elements.
  final Set<String> gltfNames;

  /// Model ids visited while walking `kind model` references (excluding the
  /// root model itself).
  final Set<String> modelIds;

  /// Referenced model ids the catalog could not resolve.
  final Set<String> missingModelIds;
}

/// Collects the resource closure of [model]: materials of every element and
/// face, `kind model` references (walked recursively through [modelCatalog])
/// and `gltf` references. Pure data, testable without a video card.
ModelResourceClosure collectModelResources(
  ModelData model, {
  ModelData? Function(String id)? modelCatalog,
}) {
  final textureKeys = <String>{};
  final spriteKeys = <String>{};
  final gltfNames = <String>{};
  final modelIds = <String>{};
  final missingModelIds = <String>{};
  final visited = <String>{model.id};

  void addMaterial(ModelMaterial? material) {
    if (material == null) return;
    switch (material.type) {
      case MaterialType.texture:
        if (material.key.isNotEmpty) textureKeys.add(material.key);
      case MaterialType.sprite:
        if (material.key.isNotEmpty) spriteKeys.add(material.key);
      case MaterialType.color:
        break;
    }
  }

  void walk(ModelData data) {
    for (final object in data.objects) {
      addMaterial(object.material);
      for (final material in object.faces.values) {
        addMaterial(material);
      }
      if (object.isGltfRef && object.gltfName.isNotEmpty) {
        gltfNames.add(object.gltfName);
      }
      if (object.isModelRef && object.refModelId.isNotEmpty) {
        final id = object.refModelId;
        if (!visited.add(id)) continue;
        final ref = modelCatalog?.call(id);
        if (ref == null) {
          missingModelIds.add(id);
        } else {
          modelIds.add(id);
          walk(ref);
        }
      }
    }
  }

  walk(model);
  return ModelResourceClosure(
    textureKeys: Set.unmodifiable(textureKeys),
    spriteKeys: Set.unmodifiable(spriteKeys),
    gltfNames: Set.unmodifiable(gltfNames),
    modelIds: Set.unmodifiable(modelIds),
    missingModelIds: Set.unmodifiable(missingModelIds),
  );
}
