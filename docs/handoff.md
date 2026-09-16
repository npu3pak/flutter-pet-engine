# Передача контекста: pet_engine → финальная приёмка (после фазы 5)

Дата: 13 сентября 2026. Для нового контекста реализации.
Читать вместе с `AGENTS.md`, `docs/tz.md`, `docs/plan.md` §8, `docs/api.md`.

## 0. Состояние

- Фазы 0–5 выполнены: ядро API, demo со всеми 49 фичами, scene_editor,
  очистка старых фасадов.
- Обновление 13 сентября (см. `plan.md` §8, разделы «Wireframe…»,
  «Гизмо…», «Спрайты…»):
  - движок: wireframe (грани/объект/сцена, экранная толщина 1 px, шейдер +
    CPU-фолбэк, авто-очистка чужих рамок), гизмо переноса/вращения
    (`GizmoNode`, приоритетный экранный hit-тест, драг мышью и пальцем),
    сетка (`GridNode`), инкрементальный `refreshObjectTransforms`,
    отсечение граней в пикинге, точный пикинг содержимого вставок,
    горизонтальный билборд спрайтов;
  - demo: тумблер wireframe всех сцен (`settings?wireframe=1`) и сцена
    «Гизмо» (49-я фича);
  - редактор: движковые сетка и гизмо (объекты/меты/направленный свет),
    тумблеры wireframe сцены/объекта, диалог несохранённых изменений,
    быстрый драг, исправленные дефекты выделения (кресло, штора,
    CSG-контур, вид снаружи, подпись CSG).
- Фаза 5 (13 сентября 2026, см. `plan.md` §8): старый вход
  `engine/lib/pet_engine.dart` и фасады из `api.md` §20 удалены из кода;
  публичный экспорт — только API `docs/api.md`; 33 теста переведены на
  `pet_engine.dart`/`src/`-импорты; `TextureCache` убран из экспорта,
  для чистого плана забегания добавлен `LevelBaker.planning()`.
- `engine`: `analyze` чист, **511 тестов** зелёные (минус тесты снятых
  фасадов).
- `demo`: `analyze` чист, **164 теста** зелёные, все 49 фич открываются;
  замечания владельца bug_38–bug_60 закрыты (журнал
  `demo/visual_tests.json`).
- `scene_editor`: `analyze` чист, **349 тестов** зелёные; визуальные
  проверки вьюпорта — `scene_editor/visual_tests.json` (bug_1–bug_10).
- Форк (`engine/third_party/flutter_scene`) с пиксельным режимом `LineSegmentsGeometry` и
  `expandLineSegments` (analyze/тесты зелёные).
- Коммиты — по явной просьбе владельца; текущая работа закоммичена
  (c78edee и ранее).
- Обновление после приёмки (ветка `feature/camera-input-touch-fly`):
  `CameraInput` на тач-устройствах умеет полёт двумя пальцами (драг
  второго пальца, параметр `touchFlyDistance`), у `FlyCameraController`
  появился публичный `rightH`; тест — `engine/test/api/camera_test.dart`.
  Первый потребитель — `mypet-game/pet_demo`, переписанный на API v2
  (ветка `feature/engine-v2`), визуальные снимки режима `pet.shots`.
- Обновление 14 сентября (ветка `feature/polyhedra`, см. `plan.md` §8):
  - движок: вид `polyhedron` (сеть с дырками и явными UV), операции
    редактирования сети, `PolyhedronNode`, `bakePolyhedron`,
    `refreshObjectGeometry`, `objectWorldMatrix`, камера крупных карт;
    версия `0.1.0-dev.3`; золотые эталоны совместимости не сдвинулись;
  - demo: девятая группа «Многогранники» (50 фич, 182 теста), журнал
    `demo/visual_tests.json` (bug_61 — магента карты без проекта);
  - scene_editor: режимы «Объект/Грани/Вершины», конверсия примитивов и
    CSG, 1-px выделение, оранжевая рамка, адаптивная сетка, drag вершин
    (381 тест); журнал `scene_editor/visual_tests.json` (bug_11).
  - Числа §1 ниже — исторический базлайн; актуальные: engine 594,
    demo 184, scene_editor 381.
- Следующее: финальная приёмка владельцем (engine, docs, demo,
  scene_editor), затем отдельная ветка конвертера WAD.

## 1. Проверка базлайна

```bash
cd pet_engine/engine
fvm flutter pub get
fvm flutter analyze      # No issues found
fvm flutter test         # 511 тестов

cd ../demo
fvm flutter analyze      # No issues found
fvm flutter test         # 164 теста

cd ../pet_engine_scene_editor
fvm flutter analyze      # No issues found
fvm flutter test         # 349 тестов
```

## 2. Что сделано в фазе 4 (scene_editor)

- Каркас `scene_editor/`: macOS/iOS, GPU-флаги и снятая песочница,
  диплинки (`pet-scene-editor`, канал `editor/deeplink`), снимки,
  `AppPaths`/`AppInfo`, `hook/build.dart`, staging `--full`, `tool/deeplink.sh`.
- Документ и undo: `AppState` на `SceneController(mergeStatic: false)`,
  `ProjectStore`/`ResourceStore`/`Model3dStore`, стеки отмены, шаблоны,
  обработка изображений.
- Вьюпорт: `EditorScene` на видах `main/overlay/top`; сетка, рамка, курсор,
  контуры и грани, гизмо переноса/вращения, picking с `FaceRef`, камера
  `FlyCameraController`, меты и маркеры света.
- Ресурсы и просмотрщик моделей (`GltfAsset`/`GltfNode`/`AnimationPlayer`).
- Панели и разметка: `main_screen`, `left_panel`, `right_panel`,
  `bottom_bars`, диалоги, `entries`/`front`, клеточная кисть.

Закрытие API под редактор (фаза 2, правки `api.md` внесены):

- пикинг документных объектов (`ModelNode.pickParts`, реестр документных
  нод в `SceneController` — `byId`/`nodesOfType`/`nearestNode`);
- размеры `SceneTexture` из ресурсной сессии;
- `GltfAsset`/`GltfNode`/`AnimationPlayer`;
- `SceneResources.gltfEntries`, кэш `gltfBounds` через `onGltfFootprint`;
- `ProjectStore.name/created/lastModelId/resources/loadMeta/saveMeta/
  directory`, `SceneController.createProject`;
- перенесены движковые тесты `csg_test` и `face_snap_test`.

## 3. Замечания demo, закрытые в фазе 7

- `CameraInput`: ПКМ — обзор и полёт, ЛКМ — панорама (`pointerPanButton`).
- `ModelNode.gltfLoading/gltfFailed`, отложенное обновление интерфейса
  demo на изменения контроллера.
- `FirstPersonCameraController.update` ведёт анимацию шага (progress 1 → 0).
- Guard `_disposed` в `SceneController.update` и отложенный `setState` во
  вьюпорте — причина пропадания частиц после переключения сцен.
- Качество demo идёт через `QualityController.apply`.
- Цикл эффектов `.fmat`, однозначный декор `level_shell`, ключи диплинка
  `settings` (`cascades`, `shadowDistance`, `step`).

## 4. Фаза 5: очистка (выполнена 13 сентября 2026)

Цель: публичный экспорт `pet_engine` — только API из `docs/api.md`;
старые фасады удалены из кода и экспорта (список — `api.md` §20).

Что сделано:

1. Покрытие `engine/test/*` (33 файла с
   `package:pet_engine/pet_engine.dart`) переведено на
   `pet_engine.dart` или внутренние `src/`-пути; ничего не потеряно
   (документ, уровень, частицы, навигация, ресурсы, скриншоты).
2. Удалён старый вход `engine/lib/pet_engine.dart` и фасады из `api.md`
   §20 (`GameScene`, `GameNode`, `GameSceneView`, `EngineScene`,
   `EngineSceneView`, `FreeCameraController`, `GameViewController`,
   `DynamicWorld`, `DynamicVisual`, `RingVisual`, `ScreenPicking`,
   `FmatManager`, `FmatSlot`, `GameQualitySettings`, `GameFog`,
   `GameAntiAliasing`, `GamePictureSettings`, `StaticSkybox` и мёртвый
   код вокруг них).
3. Внутренние зависимости v2 (`SceneNode.engine` → `EngineNode`,
   `SceneController` → `ModelRenderer`, `FlyCameraController` →
   `GameCamera`, `ParticleNode` → `ParticleLayer`/`BillboardBatch`,
   `GameResourceManager`/`TextureCache`) остались внутренними: не
   экспортируются, рендер не переписывался. Из публичного экспорта убран
   `TextureCache`, добавлен `LevelBaker.planning()`.
4. Обновлены `docs/migration.md`, `docs/api.md` (§17/§20/§21),
   `AGENTS.md`, `plan.md`.
5. Проверки: `analyze`/`test` зелёные во всех трёх пакетах (engine 511,
   demo 164, scene_editor 349); в `demo/lib` и `scene_editor/lib` старых
   типов нет.

## 5. Правила

- `AGENTS.md` — рабочая область `pet_games`; `pet_engine` можно менять
  свободно; форк — читать и добавлять хелперы/багфиксы; `pet_engine`,
  игры — только читать; временные файлы — `pet_engine/temp/`.
- Коммиты — только по явной просьбе владельца, сообщения по-русски.
- Документы — источник истины; расхождение → сначала `docs/api.md`, потом
  код.
- Визуальные проверки demo — по `docs/tz.md` §4.10; журнал —
  `demo/visual_tests.json`; редактора — `scene_editor/visual_tests.json`.

## 6. Первые шаги нового контекста

1. `pwd`, `git status`; базлайн (§1).
2. Прочитать `AGENTS.md`, `docs/tz.md` (раздел 5, приёмка), `docs/plan.md`
   §5/§8, `docs/api.md`, этот файл.
3. Подготовить финальную приёмку владельцем: прогон demo (все 50 фич,
   визуальные проверки) и scene_editor, сверка документов с фактом.
   Замечания владельца фиксировать в `demo/visual_tests.json` и
   `scene_editor/visual_tests.json`.
