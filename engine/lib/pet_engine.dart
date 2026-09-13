/// pet_engine — runtime for Scene Editor model scenes.
///
/// Exposes everything a game needs to render and drive `model_v1` scenes:
/// the serializable document ([ModelData] and friends), the renderer glue,
/// the resource manager ([GameResourceManager]) and the scene/node API
/// ([GameScene]/[GameNode]) plus the free-fly camera ([GameCamera]).
///
/// Conventions (sacred, never "fix"): the engine world mirrors model X —
/// see `src/engine_compat/coords.dart` and the renderer flip helpers.
library;

export 'src/camera/animation_type.dart';
export 'src/camera/camera_controller.dart';
export 'src/camera/direction.dart';
export 'src/camera/game_camera_math.dart';
export 'src/dynamic/dynamic_world.dart';
export 'src/dynamic/ring_visual.dart';
export 'src/engine/game_camera.dart';
export 'src/engine/game_quality.dart';
export 'src/engine/game_resource_manager.dart';
export 'src/engine/game_scene.dart';
export 'src/engine/gltf_catalog.dart';
export 'src/engine/gpu_backend.dart';
export 'src/engine/picking.dart';
export 'src/engine/picture_settings.dart';
export 'src/engine/project_source.dart';
export 'src/engine/version.dart';
export 'src/engine_compat/coords.dart';
export 'src/engine_compat/materials.dart';
export 'src/level/build_ops.dart';
export 'src/level/construction_model.dart';
export 'src/level/level_baker.dart';
export 'src/level/level_grid.dart';
export 'src/level/level_loader.dart';
export 'src/level/level_resources.dart';
export 'src/level/level_validator.dart';
export 'src/level/load_status.dart';
export 'src/level/scene_placement.dart';
export 'src/materials/fmat_manager.dart';
export 'src/models/legacy_chunk_converter.dart';
export 'src/models/model3d_entry.dart';
export 'src/models/model_scene.dart';
export 'src/models/scene_loader.dart';
export 'src/navigation/nav_path.dart';
export 'src/navigation/navigation_source.dart';
export 'src/navigation/path_follower.dart';
export 'src/navigation/path_planner.dart';
export 'src/particles/particle_config.dart';
export 'src/particles/particle_layer.dart';
export 'src/particles/particle_placement.dart';
export 'src/particles/particle_presets.dart';
export 'src/render/billboard_batch.dart';
export 'src/render/engine_material.dart';
export 'src/render/engine_mesh.dart';
export 'src/render/engine_node.dart';
export 'src/render/engine_scene.dart';
export 'src/render/engine_texture.dart';
export 'src/render/engine_view.dart';
export 'src/render/ground_fog_layer.dart';
export 'src/render/primitive_batch.dart';
export 'src/render/sprite_atlas.dart';
export 'src/render/sprite_field_layer.dart';
export 'src/render/static_merge.dart';
export 'src/scene/csg.dart';
export 'src/scene/face_snap.dart';
export 'src/scene/model_renderer.dart';
export 'src/scene/rounded_box.dart';
export 'src/services/gltf_asset_store.dart';
export 'src/services/project_store.dart';
export 'src/services/texture_alpha.dart';
export 'src/services/texture_cache.dart';
export 'src/skybox/static_skybox.dart';
export 'src/visual/screenshot.dart';
