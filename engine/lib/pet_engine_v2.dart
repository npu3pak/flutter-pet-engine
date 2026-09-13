/// Public API of `pet_engine_v2`: the Flutter-style scene layer
/// (`SceneViewport` + `SceneController` + `SceneNode`), the `model_v1`
/// document, and the engine's mechanisms (levels, navigation, particles).
///
/// Applications import only this library; the fork's types stay inside the
/// engine.
library;

export 'models.dart';
export 'src/engine/project_source.dart'
    show
        BundleProjectSource,
        DirectoryProjectSource,
        MutableProjectSource,
        ProjectSource;

export 'src/api/controllers/camera_controller.dart';
export 'src/api/controllers/camera_types.dart';
export 'src/api/controllers/first_person_camera_controller.dart';
export 'src/api/controllers/fly_camera_controller.dart';
export 'src/api/controllers/orbit_camera_controller.dart';
export 'src/api/dynamics/dynamic_nodes.dart';
export 'src/api/geometry/geometry_builder.dart';
export 'src/api/geometry/line_geometry.dart';
export 'src/api/geometry/scene_geometry.dart';
export 'src/api/geometry/wireframe.dart';
export 'src/api/input/camera_input.dart';
export 'src/api/input/scene_input.dart';
export 'src/api/level_bake_options.dart';
export 'src/api/materials/scene_material.dart';
export 'src/api/materials/scene_texture.dart';
export 'src/api/materials/shader_material.dart';
export 'src/api/nodes/group_node.dart';
export 'src/api/nodes/gizmo.dart';
export 'src/api/nodes/gltf_node.dart';
export 'src/api/nodes/light_node.dart';
export 'src/api/nodes/mechanisms.dart';
export 'src/api/nodes/model_node.dart';
export 'src/api/nodes/primitives.dart';
export 'src/api/nodes/scene_node.dart';
export 'src/api/nodes/skybox_node.dart';
export 'src/api/picking.dart' hide intersectGeometry;
export 'src/api/quality/quality_controller.dart';
export 'src/api/quality/quality_settings.dart';
export 'src/api/resources/scene_resources.dart';
export 'src/api/scene_controller.dart';
export 'src/api/scene_fog.dart';
export 'src/api/scene_layer.dart';
export 'src/api/scene_load_status.dart';
export 'src/api/viewport/scene_view_spec.dart';
export 'src/api/viewport/scene_viewport.dart';
export 'src/engine/gpu_backend.dart'
    show GpuBackend, classifyGpuBackend, detectGpuBackend;
export 'src/engine/version.dart' show kPetEngineVersion;
export 'src/engine_compat/coords.dart'
    show
        cellWorld,
        chunkWorld,
        facingAngle,
        modelXFromWorld,
        modelZFromWorld,
        screenParallelYaw;
export 'src/level/build_ops.dart';
export 'src/level/construction_model.dart';
export 'src/level/level_baker.dart'
    show LevelBakePlan, LevelBakeResult, LevelBakeStats, LevelBaker;
export 'src/level/level_grid.dart';
export 'src/level/level_loader.dart'
    show
        LevelExtraResource,
        LevelLoadEvent,
        LevelLoadEventKind,
        LevelLoadResult,
        LevelLoader;
export 'src/level/level_validator.dart';
export 'src/level/scene_placement.dart';
export 'src/navigation/nav_path.dart';
export 'src/navigation/navigation_source.dart';
export 'src/navigation/path_follower.dart';
export 'src/navigation/path_planner.dart';
export 'src/particles/particle_config.dart'
    show ParticleConfig, ParticleDef, ParticleKind;
export 'src/particles/particle_placement.dart' show ParticleField;
export 'src/particles/particle_presets.dart' show ParticlePresets;
export 'src/render/ground_fog_layer.dart' show FogInstance, GroundFogSprite;
export 'src/render/sprite_atlas.dart'
    show SpriteAtlas, buildSpriteAtlas, composeSpriteAtlas, spriteFrameMap;
export 'src/scene/face_snap.dart'
    show faceCenterAt, faceNormalAt, parallelToFaceAngles;
export 'src/scene/model_renderer.dart'
    show
        faceCorners,
        gltfFootprintBox,
        modelRefCubeProxy,
        modelRefFootprintBox,
        objectRotation,
        sourceAnchor,
        spriteBillboardMatrix,
        spriteBillboardRotation,
        unionAabbResolved;
export 'src/render/sprite_field_layer.dart'
    show SpriteFieldFacing, SpriteFieldInstance, SpriteFieldSprite;
export 'src/services/gltf_asset_store.dart' show GltfAnimInfo;
export 'src/services/texture_cache.dart' show TextureCache;
export 'src/skybox/static_skybox.dart' show loadSkyboxImage;
export 'src/visual/screenshot.dart'
    show
        FrameContentReport,
        PlaceholderReport,
        analyzeFrameContent,
        analyzePlaceholders,
        captureBoundary,
        saveScreenshot;
