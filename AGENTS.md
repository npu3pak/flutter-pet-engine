# AGENTS.md

`pet_engine_v2` is the next generation of the `pet_engine` game engine with a
Flutter-style public API: `SceneViewport` (widget) + `SceneController`
(controller) + `SceneNode` (live nodes). The old engine lives separately in
`../pet_engine` and is not rewritten. The shared `flutter_scene` fork is a
separate repository at `../flutter_scene`. Documentation and commit messages
are written in Russian; code identifiers are English.

## Layout

- `engine/` — the `pet_engine_v2` package: `model_v1` document, render core,
  level layer, navigation, particles, resources. The only public entry point
  is `lib/pet_engine_v2.dart` (since phase 5); the old `pet_engine.dart` and
  the v1 facades are removed. Internal plumbing (`src/`) stays available to
  the package's own tests via `src/` imports.
- `demo/` — the example app (phase 3): the full feature catalog and
  documentation-as-code. Written for junior and mid-level developers: keep
  it clear.
- `scene_editor/` — the scene editor on API v2 (phase 4). Optimization
  matters more than clarity here.
- `docs/` — the knowledge base: `plan.md` (idea and phases), `features.md`
  (feature registry with examples and code references), `architecture.md`,
  `api.md`, `migration.md`, `conventions.md`, `visual_testing.md`, `tz.md`
  (the implementation brief), `handoff.md` (transfer context and the state
  of the phases).
- `projects/` — scene projects and resources (copied from v1).
- `scripts/` — asset staging (`stage_app_assets.dart`), perf scripts.
- `temp/` — the only place for scratch files (not tracked by git).

## Commands

Flutter **master** via FVM (`.fvmrc`); the stable SDK will not resolve.
Always use `fvm`, run package commands from the package directory.

```bash
# engine
cd engine
fvm flutter pub get
fvm flutter analyze
fvm flutter test            # single file: fvm flutter test test/<name>_test.dart

# demo (phase 3): stage assets from the repository root first
fvm dart run scripts/stage_app_assets.dart
cd demo && fvm flutter run -d macos --enable-flutter-gpu --enable-impeller

# fork — the shared path dependency; helpers and bug fixes are allowed
cd ../flutter_scene/packages/flutter_scene && fvm flutter analyze && fvm flutter test
```

## Working-directory boundaries

- The workspace is `pet_games`. `pet_engine_v2` may be read and changed
  freely (add, change, delete).
- `../flutter_scene` (the shared fork) may be read, and may receive helper
  additions and bug fixes. Keep fork analyze and tests green; do not change
  its formats or sacred conventions.
- Other sibling directories (`../pet_engine`, `../math_quest`,
  `../mypet-game`) may be read as references, but never modified.
- Scratch files go only to `pet_engine_v2/temp/`; `/tmp`, the home directory,
  and files outside `pet_games` are forbidden.
- Information about plugins, dependencies, and third-party libraries comes
  from their sources, the internet and official docs.

## Repository boundaries

- The old repository `../pet_engine` is frozen: do not rewrite or refactor
  it. Only path fixes related to the fork move were allowed there.
- Apps (demo, scene_editor) must not import `package:flutter_scene/...`;
  fork types stay inside the engine.
- Changes to formats, rendering, or conventions require updating
  `docs/conventions.md` and tests.
- Commit only when explicitly asked by the owner.

## Things to remember

- Formats: `project_v1`, `model_v1`; legacy chunks are import-only.
- Mirrored X is a sacred convention: never "fix" the lookAt and never strip
  the billboard mirror. Details in `docs/conventions.md`.
- Engine tests read the real `../projects/Pet` project by relative path — run
  them from `engine/`.
- Rendering requires a GPU: tests never render; the viewport must have a
  swappable backend for headless tests.
- Billboard shader varyings must keep their fixed order — otherwise the
  Impeller pipeline breaks.

## Status

Phase 0 (infrastructure) is done (September 11, 2026): the fork is a separate
repository, the engine has been copied, the knowledge base exists. Phase 1
(API design) is done and validated: the feature registry is
`docs/features.md`, the public API is `docs/api.md`, the implementation brief
is `docs/tz.md`.

Phase 2 (core API) is done (September 12, 2026): `lib/pet_engine_v2.dart`
exposes `SceneViewport`/`SceneController`/`SceneNode`, materials, textures,
shaders, geometry, cameras, input, picking, dynamics, mechanism nodes,
document `ModelNode` and `QualityController`. `engine` analyze is clean and
439 tests are green; the journal is `docs/plan.md` §8. Old facades stay
internal until the demo and editor migrations.

Phase 3 (demo) is done (September 12, 2026): the `demo/` app runs all 48
features of the v1 example on API v2, with deeplinks, screenshots, visual
checks and the stress screen. `engine` has 458 green tests, `demo` has 162;
the journal is `docs/plan.md` §8, the defect log is
`demo/visual_tests.json`.

Phase 4 (scene_editor) is done (September 12, 2026): `scene_editor/` is the
v1 editor ported to API v2 — document and undo, panels, viewport with
picking/FaceRef, gizmo, overlays and layers, resources, model viewer and
markup, with deeplinks/screenshots and a visual journal.

Phase 7 (demo defects) is done (September 12, 2026): the owner-reported
defects bug_38–bug_50 are closed — camera input roles, glTF loading state,
shadow settings, quality through `QualityController`, frame-driven
first-person animation, the disposed-controller frame crash behind the
vanishing weather, the `.fmat` effect cycle and the level decor. The journal
is `demo/visual_tests.json`.

Phase 5 (cleanup) is done (September 13, 2026): the old entry
`engine/lib/pet_engine.dart` and the v1 facades (the list in `docs/api.md`
§20) are removed from code; the public export is exactly the API of
`docs/api.md`. Internal plumbing (`EngineNode`, `EngineMaterial`,
`ModelRenderer`, `GameCamera`, `ParticleLayer`/`BillboardBatch`,
`GameResourceManager`, `TextureCache`) remains unexported; the package's
tests import it through `src/` paths, and `TextureCache` was replaced for
consumers by `LevelBaker.planning()`. `engine` has 511 green tests,
`demo` 164, `scene_editor` 349; the journal is `docs/plan.md` §8.

Post-acceptance addition (branch `feature/camera-input-touch-fly`):
`CameraInput` flies on touch with two fingers (the second finger's drag,
`touchFlyDistance`), `FlyCameraController.rightH` is public; the first
consumer is the `mypet-game/pet_demo` migration (branch
`feature/engine-v2`).

Post-acceptance addition (branch `feature/sprite-field-yaw`):
`SpriteFieldNode.screenParallelYaw` exposes the shared yaw of
`SpriteFieldFacing.screenParallel` fields (the v1 `SpriteFieldLayer.update`
capability) so math_quest's grass keeps its one-instanced-batch
camera-facing; the consumer migration is the `math_quest` branch
`feature/engine-v2` (September 13, 2026).

Post-acceptance addition (branch `feature/polyhedra`, September 14, 2026):
the engine is ready for lossless arbitrary geometry — the `polyhedron`
document kind (`PolyMesh`/`PolyFace`/`PolyLoop` with holes and explicit UVs,
`bakePolyhedron`, mesh edit operations, `refreshObjectGeometry`,
`objectWorldMatrix`, `faceLoops`), the runtime `PolyhedronNode`, and the
large-map camera (`configureForExtent`); engine version `0.1.0-dev.3`.
The demo has a ninth group «Многогранники» (54 features, 184 tests) and the
scene editor a full Object/Faces/Vertices editing mode (381 tests); the
WAD converter itself is a separate future task. Backward-compat goldens live
in `engine/test/fixtures/backward_compat/`.
Same branch (September 16, 2026): sprite atlases wrap into rows beyond
`SpriteFieldNode.atlasMaxWidth` / `buildSpriteAtlas(maxWidth:)` (the GPU
texture-width limit), `SpriteFieldLayer` shares composed atlases process-wide
through a bounded LRU cache (`clearSharedAtlasCache`), and unlit
`SceneMaterial` honours `alphaCutoff` (now also a parameter of
`SceneMaterial.unlit` and preserved by `copy()`).

Next: final owner acceptance of the whole v2 (engine, docs, demo,
scene_editor).
