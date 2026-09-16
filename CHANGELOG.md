# История изменений pet_engine

Краткий список версий пакета `pet_engine`. Версия записывается в журналы
визуальных проверок приложений. Подробные планы и фазы — в
`../docs/plan.md`.

## 0.1.0-dev.3

- **Редактирование многогранников** — движок закрывает потребности
  сцены-редактора, чтобы она осталась тонкой обёрткой:
  - `PolyMesh`: `addVertexToFace` (вставка в ближайшее ребро контура или
    дырки с интерполяцией UV), `moveVertices`, `rotateVertices`,
    `deleteVertices`, `deleteFaces`, `compact`, `verticesOfFaces`;
  - `objectWorldMatrix` — мировая матрица объекта документа (якорь ·
    поворот · per-axis масштаб), общая для рендера и приложений;
  - `SceneController.refreshObjectGeometry(id)` — пересборка узлов одного
    объекта после правки сети (drag вершин без пересборки всей модели);
    `ModelNode.invalidatePicking()` — сброс кэша pick-партов;
  - `ModelNode.wireframeSegments` для многогранника — точные контуры
    `faceLoops` без диагоналей триангуляции;
  - `PolyBakeResult.applyTo` — применить конверсию к объекту одним вызовом;
    `pruneFaceMaterials` — чистка устаревших материалов граней;
  - многогранник в уровневом слое всегда печётся как `BakeMode.node`.

## 0.1.0-dev.2

- **Вид документа `polyhedron`** — произвольная геометрия для переноса
  сложных карт (в т.ч. 1:1 из WAD) без потерь:
  - `PolyMesh`/`PolyFace`/`PolyLoop`: индексные вершины, плоские грани
    (вогнутые и с дырками), явные UV на контурах;
  - `ModelObject` хранит сеть (`mesh`) и неоднородный масштаб
    (`scaleX/Y/Z`); `model_v1` остаётся аддитивно совместимым, старые виды и
    `round3` не изменены;
  - рендер и пикинг по граням (`FaceRef` с ключом грани), контуры
    `faceLoops`; лимиты `ModelSize` расширены до 16384×16384×4096 для карт
    1:1; точность сети — до 6 знаков.
- **Дружелюбный API**: `PolyMesh.box`, `PolyFace.quad`/`triangle`,
  `bakePolyhedron` (конверсия примитивов и CSG в многогранник),
  `PolyhedronNode` — runtime-узел для прямого рендера `PolyMesh` с
  материалами по граням и пикингом по ключам граней.
- **Камера для крупных сцен**: `FlyCameraController.configureForExtent`,
  динамические потолки `frameModel`; сцены до ~200 единиц диагонали
  сохраняют прежние значения камеры.

## 0.1.0-dev.1

- Пакет переименован в `pet_engine_v2` (16.09.2026 — обратно в `pet_engine`);
  код перенесён из `pet_engine` 0.5.0 (v1) в новый репозиторий (фаза 0).
  Публичный API нового поколения (`SceneViewport`/`SceneController`/
  `SceneNode`) проектируется в фазе 1.
- Общий форк `flutter_scene` вынесен в отдельный репозиторий
  `pet_games/flutter_scene`; path-зависимости v1 и v2 указывают на него.

## 0.5.0

- **Игровой фасад рендера** (`src/render/`): игры больше не импортируют
  vendored-форк и не работают с его типами напрямую.
  - `EngineScene` — низкоуровневая сцена движка: настройки (`renderScale`,
    `filterQuality`, `antiAliasing`, `fog`, `environmentIntensity`), камера
    (`updateCamera`/`cameraForward`/`screenPointToRay`/`worldToScreen`),
    монтирование запечённого уровня (`mountLevel`) и разворот билбордов
    (`reorientBillboards`). `initializeEngine()` — общая инициализация
    статических ресурсов; `EngineSceneView`/`GameSceneView` — движковые
    обёртки `SceneView` (hot-reload `.fmat` сохраняется).
  - `EngineNode`/`EnginePointLight` — узлы, видимость, трансформ, материалы,
    точечный свет; `EngineMaterial`/`EngineMaterialParameters` — PBR/unlit и
    параметры `.fmat`; `EngineTexture` (`fromAsset`/`fromBytes`, пресеты
    фильтрации) и `EngineMesh`/`EngineGeometry`.
  - `PrimitiveBatch` — сборка геометрии: `addGeometry`, `addQuad`,
    `addWallBox` (мировой UV, срезы и пропуск торцов), `addVerticalQuad`,
    `addFacingQuad`, `addTiledPlane`; `packVertices()` для GPU-free тестов.
  - `BakedMaterialHook` теперь принимает `EngineMaterial`.
  - `SpriteFieldLayer` — обобщённый инстанс-спрайт-слой (атлас-флипбук,
    screen-parallel/velocity-stretched, opaque); `attachToNode` у
    `GroundFogLayer`/`ParticleLayer`; `RingVisual` — готовый визуал маркера.
  - `GameScene`: геттеры `renderScale`/`effectiveAntiAliasing`,
    `cameraForward`, `applyCameraController()`, `screenPointToRay()`.
  - `lib/build_hooks.dart` — `petBuildMaterials` для hook-ов игр
    (dataAssetsIfAvailable).
- Игры переведены на фасад: приложения импортируют только
  `package:pet_engine/…`, `flutter_scene` у них — транзитивная зависимость.
  Проверки: analyze/тесты всех пакетов, автотест сцен macOS (`missing=0`,
  фуксия=0), смоук `/fxlab`.

## 0.4.0

- Слой стелющегося (объёмного) тумана — `GroundFogLayer`
  (`src/render/ground_fog_layer.dart`): `GroundFogSprite` (смысловой ключ +
  путь ассета), `FogInstance` (мир-якорное облако) и один инстанс-батч на
  слой. Атлас собирается `prepare()` (загрузчик уровня ждёт его до показа),
  переживает `reset()` — после пересборки этажа батч пересоздаётся из кэша
  без повторной загрузки. `blendOrder`, линейная фильтрация, tint/opacity на
  инстанс. Размещение (какие облака и как плывут) — сторона игры.
- `spriteFrameMap` (`src/render/sprite_atlas.dart`) — отображение смысловых
  ключей спрайтов на ячейки атласа по пути ассета (общий помощник слоёв;
  `ParticleLayer` переведён на него). Исправляет невидимость травы и тумана
  после перехода на движковый `buildSpriteAtlas`.
- `analyzeFrameContent` (`src/visual/screenshot.dart`) — доля пикселей,
  отличных от доминирующего фона: автотест загрузки сцен падает на почти
  пустом кадре (страховка от «сцена перестала рисоваться»).
- `ModelRenderer`: `tag` элемента входит в идентичность материала
  (`resolveMaterial`/`_materialCache`) — игра получает отдельный экземпляр на
  тег (направления стен, кожа), и хук `onMaterial` настраивает каждый
  вариант отдельно; элементы без тега делят материал как раньше.

## 0.3.0

- Фаза 5, подшаг 5.4 (движок): запекание доведено до оболочки и
  сцен-заготовок.
  - `ModelRenderer.elementNodes`/`elementOfNode` — реестр узлов по элементу
    (включая вложенные сцены, csg и glTF); `LevelBakeResult.nodes[id]` для
    многосоставного элемента — обёртка `obj:<id>`, элемент двигается целиком.
  - `bakeModeOf`: спрайты, сцены (`kind model`), glTF и csg без общего
    материала всегда остаются отдельными узлами.
  - Группы merge/batch ключуются по фактическому материалу части — материалы
    по граням и csg больше не сливаются в один `m|none`.
  - `LevelBaker` принимает `gltfCatalog`/`gltfCatalogReady`/`onGltfFootprint`
    (как `ModelRenderer`); `LevelLoader` прокидывает каталог сам.
  - `LevelBakeResult.billboards` и `reorientBillboards(fx, fz)` — запечённые
    спрайты разворачиваются к камере; `GameScene.update` вызывает сам.
  - `LevelLoader.onMaterial` прокидывает хук материалов в запекание (игра
    применяет рецепты вроде wet-вида).
  - `BakedMaterialHook` (`LevelBaker.bake(onMaterial:)`) — каждый уникальный
    материал после геометрии с тегами элементов и признаком спрайта
    (рецепты игры, например wet-вид).
  - `TextureCache.isTextureMissing`/`isSpriteMissing` — синхронная отметка
    потерянного ресурса; запекание рисует фуксию сразу, без серой заглушки.
  - `ModelMaterial.tileScaleU`/`tileScaleV` — раздельный тайлинг по осям
    (стены и листва: один тайл на метр по горизонтали, один на высоту
    стены); необязательные поля `model_v1`, панель редактора обновлена.
- Визуальные снимки как фича движка (`src/visual/screenshot.dart`):
  `captureBoundary` (захват вьюпорта внутри приложения), `saveScreenshot`
  (PNG + карточка), `analyzePlaceholders` (цвета-заглушки).
- Пример: фича `level_loading` получила спрайт и сцену-заготовку — проверка
  узлов-обёрток и билбордов; собственный `captureBoundary` удалён в пользу
  движкового.

## 0.2.0

- Фаза 5, подшаг 5.1: запросы к мета-объектам — `ScenePlacement.metasAtCell/
  metasAtLevel/metasAtWorld/metasNamed` и уровне-
  вые `SceneLayout.metasAt/metasAtWorld/allMetas/metasNamed/metaNames`
  (пары «сцена + мета»). Участвуют только боксы и маркеры; бокс принадлежит
  клетке при пересечении площадей, маркер — по якорю; результат по клетке
  кэшируется. `isCellPassable` не менялся (решение 3.25.2).
- Фаза 5, подшаг 5.2: статический скайбокс — `StaticSkybox` (панорама за
  сценой, прокрутка `staticSkyboxRotation`), предзагрузка `loadSkyboxImage`,
  дымка у горизонта. Пример: фича `skybox_static`; каталог — 47 фич.
- Фаза 5, подшаг 5.3: загрузчик уровня — `LevelLoader` (этапы «проект →
  модели → ресурсы → геометрия → запекание», события прогресса и ошибок),
  `collectModelResources`, `LevelExtraResource`, монтирование
  `GameScene.mountLevel`, готовые текстуры до первой сборки
  (`TextureCache.markTextureReady`/`peek*`), разделение
  `GameResourceManager.openProject`/`openModels`. Пример: фича
  `level_loading` с прогрессом и потерянным ресурсом; каталог — 48 фич.

## 0.1.0+3

- Сцены проекта собираются в ряд через `ScenePlacement` (разметка — боксы
  `unpassable`/`door`, поля `entries`/`front`).
- `GameCamera.frameModel` учитывает ширину модели: широкие ряды сцен
  помещаются в кадр целиком.

## 0.1.0+2

- Скруглённые тела: угловые октанты собраны из четырёх колец — поверхность
  замкнута, «шипы» и сгибы ушли; нормали скруглений и круглых фасеток CSG
  усредняются по совпадающим вершинам; UV углов больше не схлопываются
  (центр октанта клонируется перед преобразованием).
- Форк: `PunctualLightBuffer` переиспользует текстуру при неизменных
  параметрах — мерцание punctual-света ушло; теневой атлас пересоздаётся при
  смене раскладки каскадов, 1–2 каскада больше не читают пустые тексели.
- glTF: BLEND-материалы классифицируются по альфе внешней диффузной текстуры
  (`texture_alpha` перенесён в движок) — cut-out-модели не просвечивают.
- `BuildOps.snapToFace`/`parallelToFace`: необязательная точка нажатия
  (`clickLocal`) — привязка к боку цилиндра, конуса и наклонённого цилиндра.
- `GameNode.worldBounds` — мировой AABB объекта для попадания и оверлеев.

## 0.1.0+1

- Фаза 0: прототип на форке flutter_scene, базовые замеры производительности.
- Фаза 1: единая библиотека flutter_scene, форматы `project_v1` и `model_v1`,
  ресурсы, редактор сцен.
- Фаза 2: нижний уровень движка — динамические объекты (`DynamicWorld`),
  частицы и погода (`ParticleLayer`, `ParticlePresets`), материалы с
  программой для видеокарты (`FmatManager`), попадание по объекту
  (`ScreenPicking`), камеры (свободная и по клеткам), настройки картинки
  (туман, сглаживание, масштаб отрисовки, яркость окружения), тени и SSAO.
- Фаза 3: уровневый слой — клетки и регионы (`LevelGrid`), модель построения
  (`ConstructionModel`), операции размещения (`BuildOps`), размещение сцен
  (`ScenePlacement`), проверки уровня (`LevelValidator`), запекание
  (`LevelBaker`).
- Добавлена константа версии `kPetEngineVersion`.
