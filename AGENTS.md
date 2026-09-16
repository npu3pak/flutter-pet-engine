# AGENTS.md

`pet_engine` is a game engine with a Flutter-style public API:
`SceneViewport` (widget) + `SceneController` (controller) + `SceneNode`
(live nodes). It superseded the old engine (v1), which no longer exists in
this workspace (its history lives on in `npu3pak/flutter-pet-engine`). The
shared `flutter_scene` fork lives inside this checkout at
`third_party/flutter_scene`. Documentation and commit messages are
written in Russian; code identifiers are English.

## Layout

- The repository root **is** the `pet_engine` package: `model_v1` document,
  render core, level layer, navigation, particles, resources. The only
  public entry point is `lib/pet_engine.dart` (since phase 5); the v1-era
  entry and facades are removed. Internal plumbing (`src/`) stays available
  to the package's own tests via `src/` imports.
- `example/` — the example app (phase 3): the full feature catalog and
  documentation-as-code. Written for junior and mid-level developers: keep
  it clear.
- `docs/` — the knowledge base: `plan.md` (idea and phases), `features.md`
  (feature registry with examples and code references), `architecture.md`,
  `api.md`, `migration.md`, `conventions.md`, `visual_testing.md`, `tz.md`
  (the implementation brief), `handoff.md` (transfer context and the state
  of the phases).
- `third_party/flutter_scene` — the shared `flutter_scene` fork (a
  plain folder, no nested repository).
- `example/assets/` — the scene projects (`Pet/`, `House/`) plus shaders;
  the projects are read from the bundle through `AssetProjectSource`.
- `scripts/` — `clean.sh` and the perf tools (`perf/`).
- `temp/` — the only place for scratch files (not tracked by git).

## Commands

Flutter **master** via FVM (`.fvmrc`); the stable SDK will not resolve.
Always use `fvm`, run package commands from the package directory.

```bash
# engine (from the repository root)
fvm flutter pub get
fvm flutter analyze
fvm flutter test            # single file: fvm flutter test test/<name>_test.dart

# example: project sources live in example/assets and are bundled via pubspec
cd example && fvm flutter run -d macos --enable-flutter-gpu --enable-impeller

# fork — the shared path dependency; helpers and bug fixes are allowed
cd third_party/flutter_scene/packages/flutter_scene
fvm flutter analyze && fvm flutter test
```

## Working-directory boundaries

- The workspace is `pet_games`. `pet_engine` may be read and changed
  freely (add, change, delete).
- `third_party/flutter_scene` (the shared fork) may receive helper
  additions and bug fixes. Keep fork analyze and tests green; do not change
  its formats or sacred conventions.
- Other sibling directories (`../mypet-game`) may be read as references,
  but never modified.
- Scratch files go only to `pet_engine/temp/`; `/tmp`, the home directory,
  and files outside `pet_games` are forbidden.
- Information about plugins, dependencies, and third-party libraries comes
  from their sources, the internet and official docs.

## Repository boundaries

- The old v1 repository is gone from the workspace (history: GitHub
  `npu3pak/flutter-pet-engine`); do not resurrect its checkout here.
- Apps (`example` here, `../pet_engine_scene_editor` outside) must not
  import `package:flutter_scene/...`; fork types stay inside the engine.
- Changes to formats, rendering, or conventions require updating
  `docs/conventions.md` and tests.
- Commit only when explicitly asked by the owner.

## Things to remember

- Formats: `project_v1`, `model_v1`.
- Mirrored X is a sacred convention: never "fix" the lookAt and never strip
  the billboard mirror. Details in `docs/conventions.md`.
- Engine tests read the real `example/assets/Pet` project by relative
  path — run them from the repository root.
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

Phase 2 (core API) is done (September 12, 2026): `lib/pet_engine.dart`
exposes `SceneViewport`/`SceneController`/`SceneNode`, materials, textures,
shaders, geometry, cameras, input, picking, dynamics, mechanism nodes,
document `ModelNode` and `QualityController`. `engine` analyze is clean and
439 tests are green; the journal is `docs/plan.md` §8. Old facades stay
internal until the example and editor migrations.

Phase 3 (example app) is done (September 12, 2026): the `example/` app runs
all 48 features of the v1 example on API v2, with deeplinks, screenshots,
visual checks and the stress screen. The engine has 458 green tests, the
example has 162; the journal is `docs/plan.md` §8, the defect log is
`example/visual_tests.json`.

Phase 4 (scene_editor) is done (September 12, 2026): `scene_editor/` is the
v1 editor ported to API v2 — document and undo, panels, viewport with
picking/FaceRef, gizmo, overlays and layers, resources, model viewer and
markup, with deeplinks/screenshots and a visual journal.

Phase 7 (example defects) is done (September 12, 2026): the owner-reported
defects bug_38–bug_50 are closed — camera input roles, glTF loading state,
shadow settings, quality through `QualityController`, frame-driven
first-person animation, the disposed-controller frame crash behind the
vanishing weather, the `.fmat` effect cycle and the level decor. The journal
is `example/visual_tests.json`.

Phase 5 (cleanup) is done (September 13, 2026): the old entry
`lib/pet_engine.dart` and the v1 facades (the list in `docs/api.md` §20)
are removed from code; the public export is exactly the API of
`docs/api.md`. Internal plumbing (`EngineNode`, `EngineMaterial`,
`ModelRenderer`, `GameCamera`, `ParticleLayer`/`BillboardBatch`,
`GameResourceManager`, `TextureCache`) remains unexported; the package's
tests import it through `src/` paths, and `TextureCache` was replaced for
consumers by `LevelBaker.planning()`. The engine has 511 green tests, the
example 164, scene_editor 349; the journal is `docs/plan.md` §8.

Post-acceptance addition (branch `feature/camera-input-touch-fly`):
`CameraInput` flies on touch with two fingers (the second finger's drag,
`touchFlyDistance`), `FlyCameraController.rightH` is public; the first
consumer is the `mypet-game/pet_demo` migration (branch
`feature/engine-v2`).

Post-acceptance addition (branch `feature/sprite-field-yaw`):
`SpriteFieldNode.screenParallelYaw` exposes the shared yaw of
`SpriteFieldFacing.screenParallel` fields (the v1 `SpriteFieldLayer.update`
capability) so instanced grass fields keep their one-instanced-batch
camera-facing (September 13, 2026).

Post-acceptance addition (branch `feature/polyhedra`, September 14, 2026):
the engine is ready for lossless arbitrary geometry — the `polyhedron`
document kind (`PolyMesh`/`PolyFace`/`PolyLoop` with holes and explicit UVs,
`bakePolyhedron`, mesh edit operations, `refreshObjectGeometry`,
`objectWorldMatrix`, `faceLoops`), the runtime `PolyhedronNode`, and the
large-map camera (`configureForExtent`); engine version `0.1.0-dev.3`.
The example has a ninth group «Многогранники» (50 features, 182 tests) and the
scene editor a full Object/Faces/Vertices editing mode (386 tests); the
WAD converter itself is a separate future task. Backward-compat goldens live
in `test/fixtures/backward_compat/`.
Same branch (September 16, 2026): sprite atlases wrap into rows beyond
`SpriteFieldNode.atlasMaxWidth` / `buildSpriteAtlas(maxWidth:)` (the GPU
texture-width limit), `SpriteFieldLayer` shares composed atlases process-wide
through a bounded LRU cache (`clearSharedAtlasCache`), and unlit
`SceneMaterial` honours `alphaCutoff` (now also a parameter of
`SceneMaterial.unlit` and preserved by `copy()`). Also on September 16 the
shared `flutter_scene` fork was moved back into the engine checkout —
`third_party/flutter_scene` (a plain folder, no nested repository).
The scene editor was extracted from the repository to
`../pet_engine_scene_editor` (its history stays in this repository).

Repository restructure (September 16, 2026): the `engine/` package directory
was moved to the repository root — the root now **is** the `pet_engine`
package; `demo/` was renamed to `example/` (Dart package `example`, bundle id
`com.npu3pak.petengine.example`), and dependent projects point at
`../pet_engine` instead of `../pet_engine/engine`.

Next: final owner acceptance of the whole v2 (engine, docs, example,
scene_editor).
