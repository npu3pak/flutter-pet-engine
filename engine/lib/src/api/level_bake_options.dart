import 'materials/scene_material.dart';

/// Called once per unique material of a baked level after the geometry pass,
/// before the merge — the game applies its material recipes here (the wet
/// look of rain biomes, tinting). [tags] are the element tags that resolved
/// to this material (empty when the element carries none); [sprite] is true
/// only when every contributing element is a billboard sprite.
typedef BakedMaterialHook = void Function(
  SceneMaterial material, {
  required bool sprite,
  required List<String> tags,
});

/// Options of `SceneController.loadLevel`.
class LevelBakeOptions {
  const LevelBakeOptions({this.collectStats = false, this.onMaterial});

  /// Collect bake statistics (a measurement pass; off by default).
  final bool collectStats;

  /// The material recipe hook (see [BakedMaterialHook]).
  final BakedMaterialHook? onMaterial;
}
