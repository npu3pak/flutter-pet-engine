# Переход с v1 на v2

Документ описывает, как возможности v1 и форка ложатся на API v2, в каком
порядке переводятся потребители и что происходит со старыми фасадами.

Статус: согласовано в фазе 1, выполнено в фазе 5. Реестр возможностей —
`docs/features.md`, полный API — `docs/api.md`.

## 1. Принципы

- Форматы и содержимое сцен не меняются: `project_v1`, `model_v1`.
- Поведение рендера, уровневого слоя, навигации, частиц и координатных
  конвенций сохраняется.
- Приложения переходят на `SceneController` / `SceneViewport` /
  `SceneNode`; типы форка наружу не выходят.
- Старые репозитории не переписываются, пока v2 не принят. Допустимы
  только инфраструктурные правки, связанные с переездом форка.

## 2. Карта «v1 и форк → v2»

### 2.1. Виджет и кадр

| v1 / форк | v2 | Примечание |
|---|---|---|
| `GameSceneView(game, onTick:)` | `SceneViewport(controller:)` | Виджет сам ведёт кадр и размер |
| `EngineSceneView(scene)` | `SceneViewport(controller:)` | Низкоуровневый вид уходит внутрь |
| `SceneView` (форк) | внутренний | Приложения его не видят |
| `SceneView.viewsBuilder` + `RenderView` | `SceneViewport.views` + `SceneViewSpec` | Виды и слои редактора |
| `kRenderLayerAll`, `kGizmoLayer`, `kGizmoTopLayer` | `SceneLayer.all/overlay/top` | Публичные константы |
| `Node.layers` | `SceneNode.layer` | Битовая маска |
| `GameScene.update(dt)` | `SceneController.update(dt)` | Вызывает вьюпорт |
| ручные `Ticker`/16 мс таймеры | `addFrameListener` | Единый кадр |
| `pixelRatio`, `warmUp` | те же параметры вьюпорта | — |

### 2.2. Сцена, документ, ноды

| v1 / форк | v2 | Примечание |
|---|---|---|
| `GameScene` | `SceneController` | Сессия, документ, ноды, камера |
| `GameNode` | `ModelNode` | Живая нода документа |
| `EngineNode` | `MeshNode` / `GroupNode` / `LightNode` | Наружу не выходит |
| `GameScene.nodes` / `node(id)` | `nodes` / `byId` / `nodesOfType<T>` | Поиск по типу |
| `GameScene.add/remove` | `SceneController.add/remove` | Живые ноды |
| `GameScene.loadModel/loadModelData` | `loadModel` / `loadModelData` | — |
| `GameScene.model` / `modelId` | `model` / `modelId` | — |
| `GameScene.rebuildContent` | `rebuild` | После внешних подмен |
| `GameScene.mountLevel/unmountLevel` | `mountLevel` / `unmountLevel` | Возвращает `LevelNode` |
| `GameNode.setPlacement/setWorldPlacement` | те же методы `ModelNode` | Координаты модели/мира |
| `GameNode.worldPosition/worldBounds` | те же | — |
| `GameNode.playAnimation/animationClips` | `play` / `animationClips` | — |
| `GameNode.setTexture/setColor` | те же методы `ModelNode` | По ключу ресурса |
| `EngineNode.cameraNode` / дети камеры | `SceneController.cameraNode` | Крепление ламп и эффектов к камере |
| `EngineNode.highlightColor` | `SceneNode.highlightColor` | Контур выделения |
| `Node.detach` (форк) | `SceneNode.detach` | Снять со сцены без удаления |
| — | `SceneController.addMeta/addDocumentLight/addGroup` | Явные операции документа (меты, свет, группы) |
| — | `SceneController.revision` | Ревизия пересборки для редактора |
| `ProjectStore` (редактор) | `ProjectStore` (публичный) | Создание/удаление/переименование моделей |
| `Node.fromGltfBytes` (форк) | `GltfAsset.fromBytes/fromFile`, `GltfNode` | Runtime-импорт glTF |
| `AnimationClip` (форк) | `AnimationPlayer` | Пауза, перемотка, цикл, кроссфейд |
| `FmatManager` | `SceneController.shaders` | Библиотека шейдеров |
| `ModelRenderer` | внутренний | Приложения не используют |
| `Node` (форк) | внутренний | — |

### 2.3. Материалы, текстуры, шейдеры

| v1 / форк | v2 | Примечание |
|---|---|---|
| `EngineMaterial` | `SceneMaterial` | PBR/unlit/шейдер |
| `EngineTexture` | `SceneTexture` | asset/bytes/image + фильтры |
| `Texture2D.fromImage` (форк) | `SceneTexture.fromImage` | Подписи редактора |
| `TextureSampling`, `gpu.MinMagFilter` | `SceneTextureFilter` | pixelated/linear |
| `FmatManager`, `FmatSlot` | `ShaderLibrary`, `ShaderMaterial`, `ShaderMaterialInstance` | Схема параметров и экземпляры |
| `EngineMaterialParameters.setFloat/setTexture` | типизированные сеттеры экземпляра | float/int/vector/color/texture |
| `PreprocessedMaterial` (форк) | внутренний | — |
| `BakedMaterialHook(EngineMaterial)` | `LevelBakeOptions.onMaterial(SceneMaterial)` | Теги и признак спрайта |
| `GameScene.setGltfTextureOverride` | `SceneResources.setGltfTextureOverride` | Плюс `rebuild`/событие |
| `configureGltfBlendMaterials` | внутренний | Поведение сохраняется |

### 2.4. Камера

| v1 / форк | v2 | Примечание |
|---|---|---|
| `GameCamera` | `FlyCameraController` | Полёт, орбита, зум, кадрирование |
| `FreeCameraController` | `FlyCameraController` | То же |
| `GameViewController` | `FirstPersonCameraController` | Клетка, анимация шага |
| `EditorScene`-камера | `OrbitCameraController` | Орбита без рывка |
| ручная `Matrix4` (math_quest) | `MatrixCameraController` | Матрица на кадр |
| `NodeCamera`, `PerspectiveProjection` | `CameraProjection` внутри контроллера | Наружу не выходит |
| `GameScene.applyCameraController` | не нужен | Контроллер применяет сам |
| `kFovY`, `zoomMaxDistance` | в `FlyCameraController` | Публично |

### 2.5. Ввод

| v1 / форк | v2 | Примечание |
|---|---|---|
| `Listener` + `Focus` в приложении | `SceneViewport` + `SceneInput` | Единая точка |
| самописный разбор указателей | `CameraInput` | Кнопки, роли, пороги |
| самописный тап (8 px, 300 мс) | `onTap(SceneTapEvent)` | Пороги внутри |
| `onPointerCancel` вручную | `SceneInput.onPointerCancel` | — |
| колесо вручную | `onPointerSignal` | — |
| pan-zoom трекпада | `onPanZoom*` | — |
| клавиатура вручную | `SceneInput.onKey` + `FocusNode` | Не потребляет шорткаты |
| собственные шорткаты | `Shortcuts`/`Actions` приложения | Вьюпорт не мешает |

### 2.6. Динамика и механизмы

| v1 / форк | v2 | Примечание |
|---|---|---|
| `DynamicWorld` | `DynamicNodes` (`controller.dynamics`) | Ноды вместо визуалов |
| `DynamicObject` | `DynamicObject` | Жизненный цикл + трансформа |
| `DynamicVisual`, `SpriteVisual` | `SceneNode`-визуалы | Любая нода |
| `RingVisual` | `RingNode` | Готовый визуал |
| `spawn/despawn/byId/clear` | те же | — |
| keyed-пул вручную (math_quest) | `dynamics.sync(key, entries)` | Без пересоздания |
| `BillboardBatch` | `BillboardBatchNode` | — |
| `SpriteFieldLayer` | `SpriteFieldNode` | — |
| `GroundFogLayer` | `GroundFogNode` | — |
| `ParticleLayer` | `ParticleNode` | Пресеты и поля |
| `StaticSkybox` | `SkyboxNode` + `SkyboxImageLayer` | Небо — нода со слоями (градиент, панорамы, облака, звёзды, солнце/луна) |
| `EngineScene.addPointLight` | `LightNode.point` | — |
| `Node.addComponent` (форк) | `LightNode` | Компоненты внутри |

### 2.7. Попадания и проекция

| v1 / форк | v2 | Примечание |
|---|---|---|
| `Scene.raycastAll` (форк) | `SceneController.raycast/raycastAll` | Без типов форка |
| `SceneRaycastHit` | `SceneHit` | + `face`, `localPoint` |
| `GameScene.picking` | методы контроллера | — |
| `worldToScreen`, `screenRect` | те же | — |
| `Node.name`-парсинг (`obj:`, `face:`) | типизированные ноды | Имена не нужны |
| `includeInvisible`, `where` | `RaycastOptions` | — |

### 2.8. Качество и перф

| v1 | v2 | Примечание |
|---|---|---|
| `GameQualitySettings.recommendedFor` | `QualityPreset.recommendedFor` | Внутри `QualityController` |
| `detectGpuBackend`, `GpuBackend` | те же | Публично |
| `applyQualitySettings` | `QualityController.attach` + `applySettings` | Единая точка |
| `FpsMeter`, `FrameStatsLogger` в приложениях | `FrameStats` контроллера | Замер внутри |
| `DevicePerformance` (Android) | остаётся в приложении | `sustainedPerformance` — подсказка |
| ручные тумблеры качества | `QualitySettings` (get/set) | — |
| динамическая подстройка (нет) | `QualityController.adaptive` | Полная лестница |
| `GameFog`, `EngineFog` | `SceneFog` | Переименование |
| `GameAntiAliasing`, `EngineAntiAliasing` | `SceneAntiAliasing` | Переименование |
| `ModelLighting.shadows/ssao` | `QualitySettings.shadows/ssao` | Источник истины — качество, не документ |
| `GameScene.applyLighting` (автоматически) | `applyLighting()`/`clearLighting()` по явному вызову | Свет документа не навязывается |
| ручной лимит ламп | `QualitySettings.maxPointLights` + `LightNode.importance` | Бюджет сложного света |
| `GameScene.setShadows/setSsao` (мутировали `ModelLighting`) | `SceneController.setShadows/setSsao` (пишут `QualitySettings`) | Документ не меняется |

### 2.9. Ресурсы, уровень, навигация, инструменты

| v1 / форк | v2 | Примечание |
|---|---|---|
| `GameResourceManager` | `SceneResources` | Владеет контроллер; только чтение и кэши |
| `GameResourceManager`, `TextureCache` | внутренние | В публичный экспорт не входят |
| `GameResourceManager.saveModel` | `ProjectStore.saveModel` | Запись моделей — через `controller.project` |
| `ProjectSource` и реализации | без изменений | — |
| `ProjectStore` (редактор) | `ProjectStore` (публичный) | CRUD моделей проекта |
| `LevelLoader/LevelBaker/...` | без изменений | + `controller.loadLevel` |
| `LevelBaker(TextureCache())` | `LevelBaker.planning()` | Чистый план/предпросмотр; запекание ресурсов — `controller.loadLevel` |
| `ScenePlacement/SceneLayout` | без изменений | — |
| `NavigationSource/PathPlanner/PathFollower` | без изменений | Становятся публичными |
| `chunkWorld` и соседние | без изменений | — |
| `captureBoundary` | `SceneViewport.capture` + `saveScreenshot` | Снимок вьюпорта из виджета |
| `petBuildMaterials` | без изменений | — |

## 3. Порядок миграции

1. **demo** — переписывается на v2 в этом репозитории; служит приёмкой
   API: каждая фича выражается без обходных путей.
2. **scene_editor** — переписывается после demo; проверяет редакторский
   профиль (виды, слои, picking, гизмо, отмена).
3. **mypet-game** — выполнено (ветвь `feature/engine-v2` в `mypet-game`).
4. **math_quest** — выполнено (ветвь `feature/engine-v2` в `math_quest`,
   13 сентября 2026): рендер-слой переведён на публичный API, для травы
   добавлен `SpriteFieldNode.screenParallelYaw`; визуальная приёмка —
   снимки 9 биомов против эталона v1 (7 совпадают попиксельно, остальные
   отличаются только фазой анимированного тумана/осадков).

## 4. Судьба старых фасадов

**Решение: удаляем после миграции — выполнено в фазе 5.** Реестр фич
показал, что все возможности четырёх проектов выражаются API v2; отдельный
публичный низкоуровневый доступ не нужен. Список удаляемых типов — раздел 20
`docs/api.md`.

Порядок:

1. Фаза 2: новые типы реализуются; старые фасады остаются в коде как
   внутренняя реализация, к которой обращается новый API.
2. Фаза 3: demo переходит на новый API; старые фасады больше никем не
   используются в demo.
3. Фаза 4: редактор переходит на новый API; старые фасады не используются
   нигде.
4. Фаза 5 (выполнена): старый вход `engine/lib/pet_engine.dart` и фасады
   удалены, экспорт `package:pet_engine/pet_engine.dart` сокращён до
   нового API, документа и механизмов (уровни, навигация, частицы, ресурсы).
   `TextureCache` убран из публичного экспорта: предпросмотр запекания
   создаётся через `LevelBaker.planning()`, тесты внутренних механизмов
   импортируют `src/`-пути самого пакета.

Внутренними (без экспорта) остались `EngineNode`, `EngineMaterial`,
`EngineTexture`, `EngineMesh`, `EngineGeometry`, `ModelRenderer`,
`GameCamera` (под `FlyCameraController`/`FirstPersonCameraController`),
`ParticleLayer`/`BillboardBatch`/`GroundFogLayer`/`SpriteFieldLayer`
(под механизмами-нодами), `GameResourceManager` и `TextureCache` (под
`SceneResources`).

## 5. Карта тестов

| Что проверяем | Откуда тесты | Куда переезжают |
|---|---|---|
| Документ `model_v1`, легаси-чанки | `EN/test/model_*`, `legacy_*` | без изменений |
| Уровневый слой | `EN/test/level_*`, `construction_*`, `meta_queries_*` | без изменений |
| Навигация | `PD/test/pet_move_test.dart` | в `engine/test` (публичный API) |
| Материалы и шейдеры | `EN/test/engine_material_test.dart`, `fmat_manager_test.dart` | новые тесты `SceneMaterial`/`ShaderMaterial`; внутренние `EngineMaterial`/`FmatManager` — через `src/`-импорты (`FmatManager` удалён) |
| Ноды и контроллер | `EN/test/engine_scene_*`, `game_scene_*` | новые тесты `SceneNode`/`SceneController` (`game_scene` удалён) |
| Камеры | `EN/test/game_camera_math_test.dart`, `camera_*` | тесты контроллеров камер; математика `GameCamera` — внутренняя |
| Качество | `EN/test/gpu_backend_test.dart`, `game_quality_test.dart` | + тесты политики `QualityController` (`GameQualitySettings` удалён) |
| Виды и слои | — | новые тесты `SceneViewSpec`/`SceneLayer` |
| Ввод | — | тесты `SceneInput`/`CameraInput` (widget) |
| Скриншоты | `EN/test/screenshot_test.dart` | без изменений |

## 6. Что остаётся в приложениях

- Логика игр: навигация как правило (какие точки проходимы), поведение
  питомца, генерация этажей, боевая система.
- Интерфейс: панели, оверлеи, диплинки, настройки, журналы проверок.
- Редакторские слои: гизмо, отмена действий, мета-рендер, редактор
  изображений, шаблоны.
- Платформенные подсказки: режим стабильной производительности на Android.
