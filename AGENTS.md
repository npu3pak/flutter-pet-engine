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
  public entry point is `lib/pet_engine.dart`; the v1-era entry and facades
  are removed. Internal plumbing (`src/`) stays available to the package's
  own tests via `src/` imports.
- `example/` — the example app: the full feature catalog and
  documentation-as-code. Written for junior and mid-level developers: keep
  it clear.
- `docs/` — the knowledge base: `api.md` (public API contract),
  `architecture.md`, `features.md` (feature registry), `conventions.md`
  (sacred conventions), `visual_testing.md`, `perf_journal.md`.
- `third_party/flutter_scene` — the shared `flutter_scene` fork (a
  plain folder, no nested repository).
- `example/assets/` — the scene projects (`Pet/`, `House/`) plus shaders;
  the projects are read from the bundle through `AssetProjectSource`.
- `scripts/` — `clean.sh` and the perf tools (`perf/`).
- `temp/` — the only place for scratch files (not tracked by git).
- `CHANGELOG.md` — version history and feature chronology.

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
- Apps (the `example` here) must not import `package:flutter_scene/...`;
  fork types stay inside the engine.
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

The v2 engine is feature-complete (the contract is `docs/api.md`):
`SceneViewport`/`SceneController`/`SceneNode`, materials, textures and
shaders, geometry, cameras, input, picking, dynamics and mechanism nodes,
document `ModelNode`, `QualityController`, the level layer and navigation,
particles, skybox, and polyhedron geometry (`0.1.0-dev.3`). Analyze is
clean, 585 engine tests and 182 example tests are green; the example defect
log is `example/visual_tests.json`. The public export is exactly the API of
`docs/api.md`: the v1 facades are removed (phase 5), internal plumbing stays
unexported and is tested via `src/` imports.

Repository restructure (September 16, 2026): the `engine/` package directory
was moved to the repository root — the root is the `pet_engine` package;
`demo/` was renamed to `example/` (Dart package `example`, bundle id
`com.npu3pak.petengine.example`); dependent projects point at
`../pet_engine`.

Feature chronology and release history — `CHANGELOG.md`. Next: final owner
acceptance of the whole v2 (engine, docs, example).
