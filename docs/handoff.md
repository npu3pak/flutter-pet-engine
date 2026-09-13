# Передача контекста: pet_engine_v2 → фаза 5 (очистка старых фасадов)

Дата: 12 сентября 2026. Для нового контекста реализации.
Читать вместе с `AGENTS.md`, `docs/tz.md`, `docs/plan.md` §8, `docs/api.md`.

## 0. Состояние

- Фазы 0–4 выполнены: ядро API, demo со всеми 48 фичами, scene_editor.
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
- `engine`: `analyze` чист, **556 тестов** зелёные.
- `demo`: `analyze` чист, **164 теста** зелёные, все 49 фич открываются;
  замечания владельца bug_38–bug_56 закрыты (журнал
  `demo/visual_tests.json`).
- `scene_editor`: `analyze` чист, **345 тестов** зелёные; визуальные
  проверки вьюпорта — `scene_editor/visual_tests.json` (bug_1–bug_8).
- Форк (`../flutter_scene`) расширен пиксельным режимом
  `LineSegmentsGeometry` и `expandLineSegments` (analyze/тесты зелёные).
- Коммитов нет (правило репозитория) — всё в рабочем дереве.
- Следующее: фаза 5 (очистка старых фасадов), затем финальная приёмка
  владельцем.

## 1. Проверка базлайна

```bash
cd pet_engine_v2/engine
fvm flutter pub get
fvm flutter analyze      # No issues found
fvm flutter test         # 521 тест

cd ../demo
fvm flutter analyze      # No issues found
fvm flutter test         # 163 теста

cd ../scene_editor
fvm flutter analyze      # No issues found
fvm flutter test         # 339 тестов
```

## 2. Что сделано в фазе 4 (scene_editor)

- Каркас `scene_editor/`: macOS/iOS, GPU-флаги и снятая песочница,
  диплинки (`pet-scene-editor`, канал `editor/deeplink`), снимки,
  `AppPaths`/`AppInfo`, `hook/build.dart`, staging `--full`, `tool/deeplink.sh`.
- Документ и undo: `AppState` на `SceneController(mergeStatic: false)`,
  `ProjectStore`/`ResourceStore`/`Model3dStore`, стеки отмены, шаблоны,
  обработка изображений, миграция legacy `chunks/`.
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

## 4. Фаза 5: очистка (следующая работа)

Цель: публичный экспорт `pet_engine_v2` — только API из `docs/api.md`;
старые фасады удалены из кода и экспорта (список — `api.md` §20).

Порядок:

1. Перенести покрытие `engine/test/*` (33 файла импортируют
   `package:pet_engine_v2/pet_engine.dart`) на `pet_engine_v2.dart` или
   внутренние `src/`-пути; ничего не потерять (документ, уровень, частицы,
   навигация, ресурсы, скриншоты).
2. Удалить старый вход `engine/lib/pet_engine.dart` и фасады из `api.md`
   §20 (`GameScene`, `GameNode`, `GameSceneView`, `GameCamera`,
   `FreeCameraController`, `GameViewController`, `EngineScene`,
   `EngineNode`, `EngineMaterial`, `EngineTexture`, `EngineMesh`,
   `EngineGeometry`, `EngineSceneView`, `DynamicWorld`, `DynamicVisual`,
   `ModelRenderer`, `ScreenPicking`, `FmatManager`, `FmatSlot`,
   `BillboardBatch`, `SpriteFieldLayer`, `GroundFogLayer`, `ParticleLayer`,
   `StaticSkybox`, `GameQualitySettings`, `GameFog`, `GameAntiAliasing`,
   `EngineFog`, `EngineAntiAliasing`).
3. Внутренние зависимости v2, которые сегодня живут в этих типах
   (`SceneNode.engine` → `EngineNode`, `SceneController` → `ModelRenderer`,
   `FlyCameraController` → `GameCamera`, `ParticleNode` → `ParticleLayer`/
   `BillboardBatch`, `GameResourceManager`/`TextureCache`), оставить
   внутренними: убрать их из экспорта, но не переписывать рендер целиком.
4. Обновить `docs/migration.md`, `docs/api.md` (§20), `AGENTS.md`, `plan.md`.
5. Проверки: `analyze`/`test` зелёные во всех трёх пакетах; в `demo/lib` и
   `scene_editor/lib` нет старых типов; смоук-визуал demo и редактора.

## 5. Правила

- `AGENTS.md` — рабочая область `pet_games`; `pet_engine_v2` можно менять
  свободно; форк — читать и добавлять хелперы/багфиксы; `pet_engine`,
  игры — только читать; временные файлы — `pet_engine_v2/temp/`.
- Коммиты — только по явной просьбе владельца, сообщения по-русски.
- Документы — источник истины; расхождение → сначала `docs/api.md`, потом
  код.
- Визуальные проверки demo — по `docs/tz.md` §4.10; журнал —
  `demo/visual_tests.json`; редактора — `scene_editor/visual_tests.json`.

## 6. Первые шаги нового контекста

1. `pwd`, `git status`; базлайн (§1).
2. Прочитать `AGENTS.md`, `docs/tz.md`, `docs/plan.md` §8, `docs/api.md`
   §20, этот файл.
3. Составить карту: какие старые тесты что покрывают и куда переезжают;
   начать с переноса тестов, затем удаление фасадов.
