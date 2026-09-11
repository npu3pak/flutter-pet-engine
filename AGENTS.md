# AGENTS.md

`pet_engine_v2` is the next generation of the `pet_engine` game engine with a
Flutter-style public API: `SceneViewport` (widget) + `SceneController`
(controller) + `SceneNode` (live nodes). The old engine lives separately in
`../pet_engine` and is not rewritten. The shared `flutter_scene` fork is a
separate repository at `../flutter_scene`. Documentation and commit messages
are written in Russian; code identifiers are English.

## Layout

- `engine/` — the `pet_engine_v2` package: `model_v1` document, render core,
  level layer, navigation, particles, resources. Public entry point:
  `lib/pet_engine_v2.dart`. Currently it is the v1 code moved over; the new
  API layer (`src/api/`) is added in phase 2.
- `demo/` — the example app (phase 3): the full feature catalog and
  documentation-as-code. Written for junior and mid-level developers: keep
  it clear.
- `scene_editor/` — the scene editor on API v2 (phase 4). Optimization
  matters more than clarity here.
- `docs/` — the knowledge base: `plan.md` (idea and phases), `features.md`
  (feature registry with examples and code references), `architecture.md`,
  `api.md`, `migration.md`, `conventions.md`, `visual_testing.md`, `tz.md`
  (the implementation brief).
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

# fork — outside this repository; fork edits and fork tests are out of scope
```

## Working-directory boundaries

- Work only inside `pet_engine_v2`. Determine the current subdirectory with
  `pwd`; never step outside the repository.
- Do not read or modify sibling directories: `../pet_engine`, `../math_quest`,
  `../mypet-game`, `../flutter_scene`, and others.
- Scratch files go only to `pet_engine_v2/temp/`; `/tmp`, the home directory,
  and files outside the repository are forbidden.
- Information about plugins, dependencies, and third-party libraries
  (including the shared fork) comes from the internet and official docs, not
  from sibling directories.

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
is `docs/tz.md`. Code work for v2 happens in a separate context following
these documents. Final owner acceptance happens after the whole v2 is
complete (engine, docs, demo, scene_editor); old facades are removed after
the demo and editor migrations.
