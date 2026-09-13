# План развития pet_engine_v2

Документ фиксирует идею нового движка, её интерпретацию командой и принятый
план работ. Написан так, чтобы через год его можно было прочитать с нуля и
понять, что и зачем делалось.

Дата фиксации: 11 сентября 2026.
Статус: фаза 0 выполнена; фаза 1 (проектирование API) выполнена, документы
`docs/features.md` и `docs/api.md` согласованы и прошли валидацию; код фазы 2
пишется в отдельном контексте по этим документам. Задание для контекста
реализации — `docs/tz.md`; итоговая приёмка владельцем — после завершения
всего v2 (движок, документация, demo, scene_editor).

## 1. Идея владельца (записано с его слов)

> pet_engine сейчас не имеет удобного API, привычного Flutter-пользователям.
> Давай его создадим и перейдём на него.
>
> К чему привыкли пользователи Flutter: **widget + controller**.
>
> В нашем случае виджет — это **viewport**: то, что будет встраиваться в
> дерево виджетов, самостоятельно определять ресайз, делать себе тики, так
> что внешнее приложение не переживает насчёт этого.
>
> Контроллеров может быть несколько. Например, один управляет камерой.
> Второй управляет нодами сцены. Чтобы объект появился — добавляем ноду на
> сцену, чтобы исчез — удаляем ноду.
>
> Нода — какой-то из поддерживаемых нами примитивов, очевидно. У неё признак,
> на сцене ли она, и её параметры. К каким-то нодам можно применить шейдеры.
> К каким-то применить новую раскраску. В объекте ноды всегда его актуальные
> данные, которые сейчас в сцене.
>
> Моя схема очевидно слишком наивна, но у нас три проекта, которые позволят
> подобрать такую же простую и понятную, но не наивную схему:
> `math_quest`, `mypet-game`, `pet_engine/engine/example`.
>
> (Позже добавлено) Более того, есть четвёртый проект:
> `pet_engine/tools/scene_editor`.

Уточнения владельца, данные при обсуждении плана:

- Новый код живёт в `pet_engine_v2` в корне рабочего каталога. Внутри —
  подкаталоги: `docs` (единая база знаний), `engine` (код движка),
  `scene_editor` (переписанный редактор сцен на новом движке), `demo`
  (переписанный `pet_engine/engine/example` на новом движке).
- Старый движок и старые проекты сейчас не переписываем. Сначала делаем
  связку `docs + engine + demo`, потом на ней переделываем `scene_editor` в
  каталоге v2. Проектируем так, чтобы покрыть нужды всех четырёх проектов.
  Когда закончим — отдельно пересаживаем на v2 сначала `mypet-game`, потом
  `math_quest`.
- Новый движок пишем, не ломая старые проекты. Старые фасады
  (`GameScene`, `GameSceneView`, `EngineSceneView`) удаляются после миграции
  demo и редактора; до этого остаются внутренней реализацией (решение фазы 1,
  раздел 7).
- Форма нод — иерархия типизированных нод.
- Редактор — полный перевод на новый API.
- Публичные имена: `SceneViewport`, `SceneController`, `SceneNode`.
- `pet_engine_v2` — отдельный git-репозиторий; имя пакета движка —
  `pet_engine_v2`.
- Форк `flutter_scene` переезжает в `pet_games/flutter_scene` и становится
  отдельным git-репозиторием, общим для v1, v2 и всех проектов. В финале
  переносим его внутрь `pet_engine_v2`.
- Ассеты (`projects/`) копируются в v2.
- `docs` v2 — новая единая база знаний; консолидируем ключевые документы.
  Старые документы не помечаем архивами: они текущие, а v2 — следующее
  поколение.
- Объём demo: полный каталог фич example (48) плюс новый `scene_editor`,
  построенный на новом понятном API. Смысл: «Можно построить сцену
  приложением, а можно через API. Возможности должны быть те же, но в API
  чуть больше, например шейдеры есть».
- demo — приложение для отладки, тестирования и документирования кодом; код
  должен быть максимально понятен джунам и младшим мидлам. `scene_editor` —
  утилита, где критична оптимизация, а не наглядность. Общего между demo и
  scene_editor нет, кроме движка.
- Текст всех документов пишем без сленга — так, чтобы через год и человек, и
  агент с ходу поняли, о чём речь.

## 2. Что это значит: интерпретация команды

### 2.1. Пара «виджет + контроллер»

Новый публичный API — это, в первую очередь, два типа:

- **`SceneViewport`** — виджет. Встраивается в дерево виджетов приложения,
  сам следит за своими размерами (ресайз), сам ведёт покадровое обновление
  (тик), сам передаёт сцене размер вьюпорта и события ввода. Приложение не
  обязано знать, когда и как перерисовывать сцену.
- **`SceneController`** — контроллер. Владеет сценой, ресурсами, нодами и
  состоянием загрузки; предоставляет приложению методы и живые объекты,
  через которые оно меняет сцену.

Приложение создаёт контроллер, загружает в него проект и модель, помещает
`SceneViewport(controller: ...)` в дерево виджетов — и дальше работает только
с нодами и контроллерами.

### 2.2. Несколько контроллеров

Контроллеров действительно несколько, и они делят ответственность:

- `SceneController` — сцена и ноды: добавление, удаление, поиск, материалы,
  покадровое обновление, ресурсы, настройки картинки, статус загрузки.
- `CameraController` (интерфейс уже существует в v1) — камера: свободный
  полёт, первый план, орбита, фиксированная точка. `SceneController`
  предоставляет активный контроллер камеры и умеет его менять.
- Дополнительные контроллеры ввода/слоёв/оверлеев — по мере надобности
  потребителей.

### 2.3. Нода — живой объект

Нода — это не описание и не команда. Нода — это живой объект сцены:

- знает, находится ли она сейчас на сцене (`inScene`), и через какие сцену и
  контроллер она к ней подключена;
- хранит свои актуальные параметры (положение, размер, материал, цвет,
  текстуру, состояние анимации);
- изменение параметров ноды сразу отражается на сцене (при необходимости —
  на следующем кадре, без «пересборки документа»);
- добавление ноды на сцену делает объект видимым, удаление — убирает.

Это отличается от v1, где параллельно существуют `EngineNode` (обёртка над
узлом графа форка) и `GameNode` (обёртка над объектом документа `ModelData`).
В v2 нода — единая точка правды о текущем состоянии объекта.

### 2.4. Иерархия типизированных нод

Поддерживаемые примитивы — закрытый, но расширяемый набор. Общий базовый
класс `SceneNode` отвечает за жизнь ноды (сцена, видимость, трансформация,
удаление, уведомление об изменениях). Наследники добавляют параметры
конкретного примитива:

- `GroupNode` — узел-контейнер для иерархии;
- `BoxNode`, `PlaneNode` — параметрические примитивы;
- `SpriteNode` — вертикальная карточка/спрайт с текстурой;
- `MeshNode` — произвольная геометрия (композиции игры);
- `ModelNode` — объект документа `model_v1` (сцена), включая glTF-инстансы;
- `LightNode` — источник света;
- `ParticleNode`, `SpriteFieldNode`, `GroundFogNode`, `SkyboxNode` —
  механизмы движка, доступные как ноды.

Материал ноды — отдельный живой объект: цвет, текстура, параметры шейдера
(`.fmat`). «К каким-то нодам можно применить шейдеры» — значит, что тип ноды
и её материал определяют, какие операции доступны; неподдерживаемая операция
не должна молча ломать сцену.

### 2.5. «Не наивно»: урок четырёх потребителей

Четыре проекта уже решают реальные задачи, и API обязан их покрыть:

| Проект | Что требует |
|---|---|
| `pet_engine/engine/example` | 48 фич: сцены, камеры, динамика, частицы, уровни, погода, проекция, шейдеры. Полный каталог — приёмка API. |
| `mypet-game/pet_demo` | Простая игра: одна сцена, движение glTF-персонажа по маршруту, анимации, маркер цели, смена текстур, качество. |
| `math_quest` | Сырая геометрия, процедурные этажи, пул динамических объектов, запечённые уровни, трава/туман/погода, своя математика камеры и попаданий. |
| `pet_engine/tools/scene_editor` | Документ и undo, picking (в том числе по граням), гизмо, оверлеи, несколько слоёв рендера, ресурсы, шаблоны. |

Отсюда два профиля использования одного API:

1. **Простой** — demo и игры: создать контроллер, загрузить модель, добавить
   ноды, подписаться на кадр. Код должен читаться без пояснений.
2. **Оптимизированный** — редактор и тяжёлые игры: те же понятия, но с
   доступом к слоям, произвольной геометрии, raycast, переиспользованию
   буферов. Наглядность здесь уступает производительности.

API должен быть надмножеством возможностей редактора: если редактор умеет
что-то строить, то же самое должно быть доступно программно (в том числе
шейдеры).

### 2.6. Что остаётся от v1

v1 не выбрасывается: форматы (`project_v1`, `model_v1`), рендер-ядро,
уровневый слой, навигация, частицы, конвенции координат переносятся в
v2/engine и переиспользуются. Меняется публичный слой: вместо `GameScene` /
`GameSceneView` / `GameNode` появляется пара `SceneController` /
`SceneViewport` и иерархия `SceneNode`. Судьба старых фасадов решается на
фазе проектирования API: если они не нужны — удаляем, если нужны как
низкоуровневый доступ — оставляем.

## 3. Границы и правила

- Старые репозитории (`pet_engine`, `mypet-game`, `math_quest`) в этой
  работе не переписываются. Допустимы только инфраструктурные правки,
  связанные с переездом форка (пути зависимостей и замки пакетов).
- Общий форк `flutter_scene` живёт отдельно в `pet_games/flutter_scene` и
  подключается по относительному пути.
- Временные файлы — только в `temp/` соответствующего репозитория.
- Коммиты — только по явной просьбе владельца. Сообщения коммитов — на
  русском языке.
- Документы и сообщения коммитов — на русском; идентификаторы в коде — на
  английском.

## 4. Структура репозитория

```
pet_games/
├── flutter_scene/                    # общий форк, отдельный git-репозиторий
│   └── packages/flutter_scene
├── pet_engine/                       # v1, заморожен (только path-правки форка)
├── pet_engine_v2/                    # новый репозиторий, git main
│   ├── AGENTS.md  README.md  .fvmrc
│   ├── docs/                         # единая база знаний v2
│   ├── engine/                       # пакет pet_engine_v2
│   ├── demo/                         # приложение-пример (все 48 фич)
│   ├── scene_editor/                 # редактор сцен на API v2
│   ├── projects/                     # проекты сцен и ресурсы (копия)
│   ├── scripts/                      # staging, perf, служебные скрипты
│   └── temp/                         # временные файлы (в git не попадает)
├── mypet-game/  math_quest/          # не трогаем до отдельной миграции
```

## 5. Фазы

### Фаза 0. Инфраструктура (выполнена 11 сентября 2026)

1. Форк вынесен в отдельный репозиторий `pet_games/flutter_scene` с
   сохранением истории; из `pet_engine` удалён. В форк добавлен `.fvmrc`
   (`master`), иначе FVM в новом репозитории молча не запускает команды.
2. Path-зависимости форка переподключены в `pet_engine/engine`,
   `pet_engine/engine/example`, `pet_engine/tools/scene_editor`; в играх
   обновлены замки пакетов.
3. Создан репозиторий `pet_engine_v2` (git, `.fvmrc`, `.gitignore`).
4. В `pet_engine_v2/engine` перенесён код v1-движка; пакет переименован в
   `pet_engine_v2`; скопированы `projects/` и `scripts/`.
5. Заведена база знаний `pet_engine_v2/docs` (этот документ и спутники).

Результаты проверок после переезда (все зелёные):

| Пакет | `analyze` | Тесты |
|---|---|---|
| `pet_engine/engine` | чисто | 317 |
| `pet_engine/engine/example` | чисто | 168 |
| `pet_engine/tools/scene_editor` | чисто | 454 |
| `math_quest` | чисто | 938 |
| `mypet-game/pet_demo` | чисто | 12 |
| `flutter_scene/packages/flutter_scene` | — | 1050 (+29 пропущено) |
| `pet_engine_v2/engine` | чисто | 317 |

Коммиты в новых и старых репозиториях не делались: по правилу они
выполняются только по явной просьбе владельца.

### Фаза 1. Проектирование API (выполнена 11 сентября 2026)

Сначала составлен полный реестр возможностей четырёх проектов
(`docs/features.md`): каждая фича с описанием, примерами использования и
ссылками на код. Реестр показал, что именно не покрывал исходный проект API:
навигация, линейная геометрия, текстуры из изображений, батч спрайтов,
виды и слои, скриншоты, единый контроллер качества.

Затем реестр превращён в публичный API (`docs/api.md`): виджет
`SceneViewport`, контроллеры `SceneController`/`CameraController`/
`QualityController`, иерархия `SceneNode`, материалы и шейдеры, ввод,
попадания, уровневый слой, навигация, примеры для четырёх проектов.

Итоговые документы фазы:

- `docs/features.md` — реестр фич (источник требований);
- `docs/api.md` — публичный API (результат проектирования);
- `docs/migration.md` — карта «v1 и форк → v2», порядок миграции;
- `docs/architecture.md`, `docs/conventions.md` — устройство и конвенции.

Решения, принятые в фазе 1:

1. **Шейдеры — только рантайм.** Формат `model_v1` не меняется; шейдер
   назначается ноде кодом (`ShaderMaterial` + экземпляр параметров).
2. **Редакторские виды — декларативный список** (`SceneViewport.views`,
   `SceneViewSpec`, `SceneLayer`); по умолчанию один полный вид.
3. **Контроллер качества** — отдельный `QualityController`: замер
   `FrameTiming` и кадров вьюпорта, определение бэкенда, полная лестница
   адаптации (`renderScale → AA → SSAO → тени/каскады`) с гистерезисом,
   полом и потолком.
4. **Старые фасады удаляются после миграции** demo и редактора; до этого
   остаются внутренней реализацией. Публичного доступа к типам форка нет.
5. **`SceneInput`** описан по фактическому использованию: указатели и
   кнопки, роли двух пальцев, тап с порогами, колесо и трекпад, наведение,
   клавиатура без перехвата шорткатов, приоритет оверлеев.

### Фаза 2. Ядро API в engine

Последовательные подшаги, каждый с тестами:

1. `SceneNode` и иерархия примитивов; материалы и шейдеры;
   подключение/отключение/удаление.
2. `SceneController`: сессия, ресурсы, загрузка модели, реестр нод, камера,
   покадровое обновление, настройки, статус, сохранение.
3. `SceneViewport`: тик через механизм рендера, ресайз, ввод, оверлеи,
   индикатор загрузки; тестовый шов, позволяющий проверять логику без
   видеокарты.
4. Камеры: свободная, первый план, орбита, матричная; ввод.
5. Попадания и проекция без типов форка; виды и слои.
6. Динамика: ноды с временем жизни, пул, синхронизация набора; частицы,
   трава, туман, небо, батч.
7. Документ: добавление и удаление объектов модели через ноды, пригодное для
   undo; сохранение.
8. `QualityController`: замер, пресеты, полная лестница адаптации.
9. Приёмка: `analyze`/`test` зелёные, GPU-free тесты, smoke-фичи demo на
   новом API.

### Фаза 3. demo

- Перенос всех 48 фич примера; код — эталон использования API для
  разработчиков.
- Сохраняем визуальное тестирование, диплинки, снимки, измерения
  производительности.
- Приёмка агента: все фичи открываются, визуальные самопроверки на macOS по
  ходу работы (`docs/tz.md`, раздел 4.10), в `demo/lib` нет импортов
  `flutter_scene`.
- Итоговая приёмка владельцем — после завершения всего v2 (раздел 5 `tz.md`).

### Фаза 4. scene_editor

- Полный перевод редактора: документ и undo, панели, вьюпорт с picking,
  гизмо, оверлеями и слоями, ресурсы, просмотр моделей, разметка.
- Потребности редактора, не покрытые API, возвращаются в фазу 2.
- Приёмка агента: портированные тесты зелёные, визуальная проверка,
  паритет возможностей со старым редактором.
- Итоговая приёмка владельцем — после завершения всего v2 (раздел 5 `tz.md`).

### Фаза 5. Завершение

- Очистка (входит в объём): удаление старых фасадов из кода и публичного
  экспорта после миграции demo и редактора (список — `docs/api.md`,
  раздел 20).

Вне текущего объёма (отдельные работы позже):

- перенос форка в `pet_engine_v2`, вывод старого движка;
- миграция `mypet-game`, затем `math_quest`.

## 6. Проверка

- `fvm flutter analyze` и `fvm flutter test` во всех пакетах.
- Логика, не требующая видеокарты, покрывается модульными тестами; для
  виджета вьюпорта предусматривается подменяемый бэкенд.
- Интерактивная проверка — macOS и физические устройства; методика — в
  `docs/visual_testing.md`.
- Перед миграцией игр — визуальные прогоны по всем биомам.

## 7. Решения по итогам фазы 1 и валидации API

Открытые вопросы фазы 1 закрыты:

1. **Старые фасады** (`GameScene`, `GameSceneView`, `EngineSceneView`,
   `GameNode` и прочие) удаляются после миграции demo и редактора; до этого
   остаются внутренней реализацией. Полный список — `docs/api.md`, раздел 20.
2. **Низкоуровневые потребности редактора** выражены движковыми типами:
   `SceneViewSpec`/`SceneLayer`, `LineNode`/`LineGeometry`,
   `SceneTexture.fromImage`, `RaycastOptions`, `ModelNode.faces`, хелперы
   документа и геометрии (раздел 17.2 `api.md`); отдельного доступа к форку
   не остаётся.
3. **Шейдеры** — только рантайм (`ShaderMaterial`/`ShaderMaterialInstance`),
   доступ через `SceneController.shaders`.
4. **Контроллер качества** — `QualityController` с полной лестницей
   адаптации и замером через `FrameTiming` и кадры вьюпорта.
5. **Виды и слои** — декларативный список видов у вьюпорта.

Дополнения после валидации API (сверка `features.md` с `api.md`, 24 пробела
закрыты; список — `features.md`, раздел «Валидация API»):

6. **Свет** применяется только по явному вызову (`applyLighting`/
   `clearLighting`); тумблеры теней и SSAO — из `QualitySettings`; сложный
   свет ограничивается бюджетом `QualitySettings.maxPointLights` с
   приоритетом `LightNode.importance`.
7. **Небо** — нода `SkyboxNode` со слоями (фон, градиент, панорамы,
   облака, звёзды, солнце/луна); рисуется фоновым проходом за сценой;
   `StaticSkybox` заменяется `SkyboxImageLayer`.
8. **Документ** редактируется явными операциями
   (`addMeta/addDocumentLight/addGroup` и парные `remove*`) плюс прямой
   правкой полей и `rebuild()`.
9. **Переименования**: `AnimationPlayer`, `SceneAntiAliasing`, `SceneFog`;
   `ProjectStore`, `AnimationPlayer`, `GltfAsset`, `RingNode` и прочие
   добавлены в API.

Детали, уточняемые при реализации (не влияют на состав API): имя ресурсной
сессии, полный набор операций `GeometryBuilder`, состав
`DeviceCapabilities`, пороги политики качества, формулы слоёв неба. Список —
`docs/api.md`, раздел 21.

Реализация кода v2 ведётся в отдельном контексте; этот документ и
спутники — единственный источник требований для неё. Порядок работ, объём
и приёмка — в `docs/tz.md`.

## 8. Журнал реализации (фаза 2)

### Подшаг 1. Ноды, материалы, геометрия (12 сентября 2026)

Сделано:

- Новый публичный вход `engine/lib/pet_engine_v2.dart`; новый слой
  `engine/lib/src/api/`.
- `SceneNode` (id, имя, слой, `inScene`, parent/children,
  transform/position/rotation/scale, visible/opacity/highlightColor,
  material, worldBounds, detach/remove/dispose) и внутренний шов
  `SceneNodeHost`, который реализует будущий `SceneController`.
- Ноды: `GroupNode`, `BoxNode`, `PlaneNode`, `MeshNode` (+`MeshPart`),
  `SpriteNode`, `LineNode`, `RingNode`; `SceneLayer`.
- Материалы: `SceneMaterial` (pbr/unlit/shader), `SceneTexture` (ленивая
  GPU-загрузка, `fromImage/Asset/Bytes`), `ShaderMaterial`/
  `ShaderMaterialInstance`/`ShaderParameter` + `ShaderLibrary` (схема
  параметров из sidecar `.fmat`).
- Геометрия: `SceneGeometry` (cuboid/plane/cylinder/cone/sphere/roundedBox/
  trapezoid/ring + annulus), `GeometryBuilder` (transform-bake, мировые UV,
  стены), `LineGeometry`.
- Форк: добавлены геттеры `PreprocessedMaterial.metadata`/
  `vertexShaders`; экспортированы чистые генераторы примитивов
  (`PrimitiveArrays`, `build*Arrays`). Analyze форка чист.
- Тесты `engine/test/api/*` (39); analyze чист, тесты зелёные:
  356 (317 базовых + 39 новых).

Решения:

- Геометрия хранит чистые CPU-данные (`MeshData`) и поднимает GPU лениво —
  отсюда GPU-free тесты и измерение габаритов без видеокарты.
- `roundedBox`/`trapezoid` собираются из документных csg-полигонов (та же
  математика, что у рендера) и центрируются по Y.
- Виндинг: треугольники намотаны так, что правая тройка смотрит внутрь,
  нормаль — наружу (правило форка).
- `GroupNode.remove(child)` совмещён с `SceneNode.remove()` (необязательный
  аргумент): в `api.md` у обоих методов одно имя.
- `SceneNode.scene` появится в подшаге 2 вместе с `SceneController`; пока
  нода знает только внутренний `host`.

Отклонение от `AGENTS.md` (по разрешению владельца): общий форк читается и
дополняется хелперами; правки — только совместимые, тесты и analyze форка
зелёные.

### Подшаг 2. Контроллер сцены (12 сентября 2026)

Сделано:

- `SceneController` (`ChangeNotifier` + `SceneNodeHost`): реестр нод
  (`add/remove/byId/nodesOfType`), камера (`camera`, `cameraNode`), кадр
  (`update`, `addFrameListener`, `reorientBillboards`), размер вьюпорта,
  ревизия (`revision`, `rebuild`).
- Сессия: `open/openProject/openModels/loadModel/loadModelData/unloadModel/
  reloadResources`; `SceneResources` (модели, каталоги, чтение, текстуры
  через `SceneTexture.fromGpu`, glTF-оверрайды, инвалидация);
  `ProjectStore` (create/save/delete/rename) с необязательной
  возможностью `MutableProjectSource` (у `DirectoryProjectSource` есть,
  кастомные источники не ломаются).
- `SceneLoadStatus`/`SceneLoadError`/`SceneLoadPhase`; ошибки загрузки не
  фатальны и попадают в статус.
- `CameraController` (интерфейс) и `MatrixCameraController`; `SceneNode.scene`
  теперь возвращает контроллер.
- Внутренняя привязка рендера: ленивая `ensureRenderScene()` (fork `Scene`
  создаётся только при подключении вьюпорта), `renderCamera`, синхронизация
  мешей нод с проверкой идентичности (без пересборки на смену трансформа).

### Подшаг 3. Вьюпорт (12 сентября 2026)

Сделано:

- `SceneViewport` (виджет) + `SceneViewportState`: размер и pixelRatio
  сообщаются контроллеру, тик через `Ticker`, `autoTick`, оверлеи, фон,
  индикатор загрузки, тап/двойной тап с порогами, клавиатурный фокус,
  `capture`.
- `SceneViewSpec` (main/overlay/top/layer) и `SceneLayer`; подменяемый
  `SceneViewportBackend`: боевой `ForkSceneViewportBackend` (fork
  `SceneView` + `RepaintBoundary` + `captureBoundary`) и фейковый в тестах —
  GPU-free widget-тесты.
- `SceneInput`/`SceneViewportInfo`/`SceneTapEvent` (луч из камеры);
  `initializeEngine()`.
- Тесты: 59 в `engine/test/api` (всего 376, analyze чист).

Открыто до следующих подшагов: `CameraInput` (подшаг 4), raycast/проекция
(подшаг 5), динамика и механизмы (6), документ и `ModelNode` (7), качество
(8).

### Подшаг 4. Камеры и ввод (12 сентября 2026)

Сделано:

- `FlyCameraController` (полёт, обзор, орбита, панорама, зум, кадрирование
  модели/габаритов/ноды) поверх v1-математики `GameCamera`;
- `FirstPersonCameraController` (клетка, направление, анимации шага/поворота,
  покачивание) поверх `gameCameraNodeTransformAnimated`;
- `OrbitCameraController` (цель, дистанция, орбита, панорама, зум,
  кадрирование);
- `Direction`/`AnimationType` — полный набор (правка внесена в `api.md`
  §17.1: `stepForward/stepBackward/strafeLeft/strafeRight/turnLeft/turnRight`);
- `CameraInput` (роли кнопок мыши и двух пальцев, колесо, WASD/QE,
  клавиатура не потребляет чужие шорткаты); вьюпорт по умолчанию использует
  его;
- `SceneController` применяет матрицу любой из встроенных камер к
  `cameraNode`.
- Тесты: 15 в `test/api/camera_test.dart`; всего 391, analyze чист.

### Подшаг 5. Попадания и проекция (12 сентября 2026)

Сделано:

- `SceneHit`, `FaceRef`, `RaycastOptions`;
- `SceneController.screenPointToRay/worldToScreen/screenRect/raycast/
  raycastRay/raycastAll/nearestNode`;
- CPU-луч по треугольникам геометрии (`intersectGeometry` + AABB-пре-тест) —
  без видеокарты; нормаль разворачивается к лучу;
- фильтры `includeInvisible`, `skipNodeIds`, `where`, порядок «ближний
  первым»; у нод появился внутренний `pickGeometries`;
- `FaceRef` заполняется для `ModelNode` в подшаге 7.
- Тесты: 10 в `test/api/picking_test.dart`; всего 401, analyze чист.

### Подшаг 6. Динамика и небо (12 сентября 2026)

Сделано:

- `DynamicNodes`/`DynamicObject`/`DynamicEntry`: `spawn/despawn/clear/
  byId/objects/aliveCount/update`, время жизни, `remainingFactor`,
  `onUpdate/onFinished/onEnteredFrame`, пул нод и `sync(key, entries)` без
  пересоздания неизменившихся объектов;
- `SceneController.dynamics` и вызов `dynamics.update(dt)` в кадре;
- `SkyboxNode` и слои (`SkyboxColorLayer`, `SkyboxImageLayer`,
  `SkyboxCloudsLayer`, `SkyboxStarsLayer`, `SkyboxBodyLayer`);
  `SceneController.skybox`;
- в `api.md` исправлены две коллизии имён: `AnimationType` (полный набор) и
  `SkyboxNode.skyRotation` (не конфликтует с `SceneNode.rotation`).
- Тесты: 8 в `test/api/dynamics_test.dart`; всего 409, analyze чист.

Осталось по фазе 2 (следующий контекст):

- подшаг 6 (продолжение): ноды-механизмы `ParticleNode`, `SpriteFieldNode`,
  `GroundFogNode`, `BillboardBatchNode`, `LevelNode` (обёртки v1-слоёв) и
  фоновый проход неба во вьюпорте;
- подшаг 7: документ (`addObject/addMeta/addDocumentLight/addGroup` + remove,
  грани, csg, `ModelNode`, сохранение, undo-совместимость);
- подшаг 8: `QualityController`;
- подшаг 9: приёмка ядра и smoke-фичи demo.

Открытые уточнения API (из анализа demo/editor) уже частично закрыты
(`initializeEngine`, `AnimationType`, `skyRotation`); остальные (`ambient`,
`ParticleNode.prepare`/фокус, прогресс `loadLevel`, undo-совместимость) — в
соответствующих подшагах.

### Подшаг 6 (продолжение). Механизмы-ноды (12 сентября 2026)

Сделано:

- `ParticleNode` (погода/частицы): конфиг, поле, интенсивность, фокус,
  `prepare()`, автоперепаковка в кадре; `SpriteFieldNode` (трава/декор),
  `GroundFogNode` (туман), `BillboardBatchNode` (собственные инстансы,
  `setInstance`/`commit`), `LevelNode` (`result`, `nodeFor`);
- в API введены собственные `BillboardFacing`/`SpriteBlendMode` (типы форка
  наружу не выходят), `SceneNode.frameTick` и общий тик механизмов в
  `SceneController.update`;
- в `api.md` уточнено: `BillboardBatchNode.atlas` — `SceneTexture`.
- Тесты: 7 в `test/api/mechanisms_test.dart`.

### Подшаг 7. Документ и `ModelNode` (12 сентября 2026)

Сделано:

- `SceneController`: `addObject/removeObject/objectNode`, `addMeta/removeMeta`,
  `addDocumentLight/removeDocumentLight`, `addGroup/removeGroup`; ревизия и
  пересборка документа; `rebuild()` пересобирает `ModelRenderer`, когда
  рендер-сцена существует;
- ленивая привязка рендера: `ensureRenderScene()` создаёт `ModelRenderer` из
  ресурсной сессии, монтирует корень документа и текущую модель;
- `ModelNode`: координаты модели (`x/y/z/rotY`), `worldPosition`,
  `worldBounds`, `setPlacement/setWorldPlacement` (живое обновление glTF),
  glTF (`gltfName`, `gltfBounds`, `animationClips`, `animation`, `play`),
  материалы (`faces`, `setFaceMaterial` через runtime-оверрайды рендера,
  `setTexture`, `setColor`);
- `ModelRenderer.materialOverrides` — рантайм-подмена материалов граней без
  изменения документа;
- Тесты: 8 в `test/api/model_node_test.dart`.

### Подшаг 8. `QualityController` (12 сентября 2026)

Сделано:

- `QualitySettings` (renderScale, SSAO, тени/каскады/дистанция, AA, фильтр,
  бюджет ламп, подсказка sustained performance), `QualityPreset`
  (`low/medium/high/auto` + `recommendedFor`), `QualityPolicy`,
  `QualityStep.fullLadder`, `FrameStats`, `QualityChange`,
  `DeviceCapabilities`, `SceneAntiAliasing`, `SceneFog`;
- `QualityController`: замер (`reportFrame` с инъекцией времён), лестница
  понижения/повышения с гистерезисом, cooldown, `upscaleHold`, пол/потолок,
  пауза адаптации, поток изменений, `attach(scene)`;
- `SceneController`: `settings`, `applySettings`, `setShadows/setSsao/
  setShadowCascades/setShadowDistance/setRenderScale/setAntiAliasing/
  setEnvironmentIntensity/setFog`, геттеры для интерфейса; применение к
  рендер-сцене (AA, renderScale, фильтр, SSAO, туман, окружение);
- Тесты: 15 в `test/api/quality_test.dart`.

### Подшаг 9. Приёмка ядра (12 сентября 2026)

- `fvm flutter analyze` — чисто; `fvm flutter test` — **439 тестов** зелёные
  (317 базовых + 122 новых в `engine/test/api/`); форк: analyze чисто,
  1050 тестов зелёные (29 skip).
- Публичный вход `lib/pet_engine_v2.dart` собирает новый API, документ и
  механизмы; старые фасады не тронуты и остаются внутренней реализацией.
- GPU-free правило соблюдено: тесты не создают fork `Scene`; у вьюпорта
  подменяемый бэкенд; геометрия, материалы и пикинг проверяются на CPU.
- Smoke-фичи demo на новом API откладываются до появления demo (фаза 3):
  без приложения их не на чем запускать.

Итог: ядро API фазы 2 готово. Дальше — фаза 3 (demo: инфраструктура и все
48 фич), затем фаза 4 (редактор) и фаза 5 (очистка).

### Фаза 3, подготовка. Закрытие блокеров API (12 сентября 2026)

Сделано:

- **Свет.** `LightNode` (point/directional) с живым форк-компонентом,
  `SceneController.applyLighting`/`clearLighting` (источники документа или
  дефолтный риг «солнце + лампа камеры»), теневые настройки и каскады из
  `QualitySettings`, бюджет `maxPointLights` по `importance`; ambient
  документа — стартовое значение `environmentIntensity` только при
  нестандартном освещении. Тесты `engine/test/api/light_test.dart`.
- **Небо.** 2D-фон `SkyboxBackground` под сценой вьюпорта: градиент,
  панорама (tile/offset/дымка), облака, звёзды, солнце/луна; прокрутка за
  камерой (FirstPerson — по facing/animation, остальные — по forward);
  экспорт `loadSkyboxImage`. Тесты `engine/test/api/skybox_test.dart`.
- **Прозрачность и линии.** `SceneNode.opacity` применяется per-node копией
  материала (общий материал не заражается), `LineGeometry.width` и
  `LineNode.width` стали живыми. Тесты в `test/api/scene_node_test.dart`.
- **Уровни.** `SceneLoadPhase`/`SceneLoadError` переехали в
  `src/level/load_status.dart` (ре-экспорт из `api/scene_load_status.dart`),
  `LevelLoadEvent.stage` → `phase`, `LevelBakeOptions`/`BakedMaterialHook` с
  `SceneMaterial`, `SceneController.loadLevel/mountLevel/unmountLevel/level`,
  реориентация билбордов уровня в кадре. Экспортированы уровневый слой,
  `TextureCache`, `SpriteAtlas`/`buildSpriteAtlas`, координатные хелперы и
  навигация. Тесты `engine/test/api/level_test.dart`.

Отклонения:

- `LineNode` принимает `double? width` (ширина живёт в `LineGeometry`), а не
  `double width = 0.01` — иначе конструктор перетирал бы ширину геометрии;
  `api.md` §5.2 обновлён.
- `SceneController.loadLevel` получил необязательный `@internal LevelBaker`
  — шов для GPU-free тестов; в публичном контракте не значится.

Проверки: `analyze` чист, **458 тестов** зелёные (439 + 19 новых).
Дальше — каркас demo и 48 фич (фаза 3).

### Фаза 3. demo (12 сентября 2026)

Сделано:

- **Каркас приложения** `demo/`: `flutter create` (macOS/iOS/Android),
  `initializeEngine`, диплинк-мосты macOS/iOS (схема `pet-engine-example`,
  канал `example/deeplink`), GPU-флаги и снятие песочницы macOS,
  `hook/build.dart` на `petBuildMaterials`, staging в
  `demo/assets/pet_project`.
- **Инфраструктура**: `AppPaths`/`AppInfo`/`deeplink`/`screenshot_saver`,
  perf-логи, журнал визуальных проверок, `ProjectSource`-источники,
  `app_shell` (три панели, режимы, очередь команд, сервис-расширение),
  `SettingsPanel` на `QualityController`, стресс-экран на
  `SceneController.loadLevel`, навигация по клеткам на
  `FirstPersonCameraController` (свободная камера — на `CameraInput`).
- **Хост сцены** `DemoSceneHost` на `SceneController`/`SceneViewport` с
  подменяемым бэкендом вьюпорта; все 48 фич восьми групп перенесены и
  открываются; `analyze`/`test` demo зелёные (**162 теста**).
- **Визуальные проверки** на macOS по tz §4.10: снимки всех групп через
  `capture` + `saveScreenshot`, замечания — в `demo/visual_tests.json`
  (`note`/`fixed`, вердикт `ok` — владелец).

Найденные и исправленные дефекты движка (журнал `demo/visual_tests.json`):

- `ensureRenderScene` создавал группу document через `attachToHost` и
  прерывал построение рендер-сцены `notifyListeners` во время build;
- `unlinkChild` отвязывал поддерево до `engine.remove` — исключение при
  смене фичи;
- не было подписки на `onTextureReady`/`gltfAssets` — текстуры не
  появлялись после асинхронной загрузки;
- поддеревья нод не синхронизировались при создании рендер-сцены
  (частицы не рисовались) — добавлен `_syncSubtree`;
- `ParticlePresets` ссылались на ассеты старого пакета;
- `BillboardBatchNode` не применял смену режимов и повторно добавлял узел;
- `DynamicNodes.update` не применял позицию `onUpdate` к ноде;
- `LevelNode` повторно добавлял корень уровня;
- добавлены `SceneResources.models`, `BillboardBatchNode.flipbookColumns/Rows`,
  экспорт хелперов §17.2 и `SceneLoadPhaseLabel`.

Отложено (зафиксировано в `api.md` §21): пикинг документных объектов лучом
(`raycast` видит только API-ноды; для demo цели сделаны `BoxNode`), размеры
`SceneTexture.fromGpu`.


### Фаза 4. scene_editor (12 сентября 2026)

Сделано:

- **Каркас** `scene_editor/`: macOS/iOS, GPU-флаги и снятая песочница,
  диплинки (`pet-scene-editor`, канал `editor/deeplink`), снимки,
  `AppPaths`/`AppInfo`, `hook/build.dart`, staging `--full` для iPad,
  `tool/deeplink.sh`.
- **Документ и undo**: `AppState` на `SceneController(mergeStatic: false)`,
  `ProjectStore`/`ResourceStore`/`Model3dStore`, стеки отмены на модель,
  шаблоны дома/комнаты, обработка изображений, сохранение и миграция
  legacy `chunks/`.
- **Вьюпорт**: `EditorScene` на видах `main/overlay/top`; сетка, рамка,
  курсор, контуры и подсветка граней, гизмо переноса/вращения, picking с
  `FaceRef`, камера `FlyCameraController`, меты и маркеры света.
- **Ресурсы и просмотрщик**: вкладка «Ресурсы» с редактором изображений;
  просмотр моделей на `GltfAsset`/`GltfNode`/`AnimationPlayer` и
  `OrbitCameraController`.
- **Панели и разметка**: `main_screen`, `left_panel`, `right_panel`,
  `bottom_bars`, диалоги; `entries`/`front`, клеточная кисть, `ScenePlacement`.
- **Проверки**: `analyze` чист, **339 тестов** зелёные; визуальные снимки
  macOS (вьюпорт, выделение и гизмо, освещение и маркер источника, меты,
  текстурирование) — журнал `scene_editor/visual_tests.json`.

Закрытие API под редактор (до/во время порта):

- пикинг документных объектов: `ModelNode.pickParts` (грани примитивов,
  `side`/крышки цилиндра, `round` скруглений, CSG целиком, прокси-боксы
  вставок) и реестр документных нод в `SceneController`
  (`byId`/`nodesOfType`/`nearestNode`);
- размеры `SceneTexture` из ресурсной сессии (`TextureCache` хранит размер
  декода);
- `GltfAsset`/`GltfNode`/`AnimationPlayer` (§5.7–5.8 `api.md`);
- `SceneResources.gltfEntries`, кэш `gltfBounds` через `onGltfFootprint`;
- мета проекта: `ProjectStore.name/created/lastModelId/resources/loadMeta/
  saveMeta`, `SceneController.createProject`, `ProjectStore.directory`;
- перенесены движковые тесты `csg_test` и `face_snap_test`; всего в
  `engine` **516 тестов**.

### Фаза 7. Закрытие замечаний demo (12 сентября 2026)

Владелец прошёл demo и оставил 13 открытых замечаний
(`demo/visual_tests.json`, bug_38–bug_50). Исправлено:

- **Навигация (bug_38).** `CameraInput`: ПКМ — обзор и полёт (WASD/QE),
  ЛКМ — панорама, колесо — зум; новый параметр `pointerPanButton`.
- **Анимации glTF (bug_39).** `ModelNode.gltfLoading/gltfFailed`; панель
  показывает «загружается», хост demo отложенно обновляет интерфейс на
  изменения контроллера.
- **Тени (bug_40).** Прогон снимков с `cascades=1/2/4` и
  `shadowDistance=2/10`; добавлены ключи диплинка `settings`.
- **Дальность лампы (bug_41).** Пятно точечного света меняется, тени даёт
  солнце; пояснение в панели уточнено.
- **Качество (bug_42).** Хост demo применяет настройки через
  `QualityController.apply` — единый источник истины.
- **Камера по клеткам (bug_43).** Анимацию ведёт
  `FirstPersonCameraController.update` (progress 1 → 0); `CellNavController`
  только задаёт цель.
- **Погода и частицы (bug_44–48).** Причина: старый `SceneViewport` тикал
  disposed-контроллер, `SceneController.update` падал на камерной ноде и
  прерывал кадр (частицы не обновлялись). Guard `_disposed` в `update` и
  отложенный `setState` во вьюпорте; цикл из 9 переключений снова
  показывает погоду.
- **Цикл .fmat (bug_49).** Переключатель «Циклически менять эффект»:
  свечение ↔ пикселизация раз в 3 секунды.
- **Декор уровня (bug_50).** Коврик — плоская плитка перед стартовой
  камерой, стол и растение — вертикальные тела по бокам, разные цвета.
- **Автополёт (bug_51).** `GameCamera._moveStep` двигал камеру вперёд при
  активном полёте даже без клавиш; теперь полёт — только режим и обзор,
  движение — WASD/QE. Регрессионный тест в `engine/test/api/camera_test.dart`.

Проверки: `engine` 521 тест, `demo` 163, `scene_editor` 339; analyze чист;
снимки в `temp/screenshots`, журнал — `demo/visual_tests.json`.

### Аудит scene_editor после приёмки demo (12 сентября 2026)

Проверка редактора на классы дефектов demo и собственные ошибки порта:

- **Обновление панелей.** `AppState` слушает `SceneController` и будит
  интерфейс при росте ревизии (догрузка текстур/glTF): список анимаций
  модели появляется сам. Гейт по ревизии обязателен — оверлеи вьюпорта
  тоже уведомляют контроллер, без него получалось бы зацикливание.
- **Тени.** `EditorScene._applyLighting` пишет `cfg.shadows`/`cfg.ssao`
  в `QualitySettings` сцены: тумблеры режима «Освещение» теперь меняют
  картинку, а не только документ.
- **glTF-панель.** «Загружается»/«Не удалось загрузить» через
  `ModelNode.gltfLoading/gltfFailed`.
- **Вьюпорт.** Тесты `test/editor_viewport_test.dart`: ПКМ-обзор и полёт
  WASD, ЛКМ не летит, гизмо переноса двигает объект, тумблеры тени/SSAO
  доходят до качества; удалён мёртвый код кэша footprint (движок кэширует
  `gltfBounds` сам).

Проверки: `scene_editor` 342 теста, analyze чист; снимки —
`scene_editor/visual_tests.json` (bug_2).

### Замечание bug_52: направление ветра (12 сентября 2026)

Метки компаса в «Параметрах частиц» переводились в мировые оси без учёта
зеркала X (`chunkWorld`): восток модели — world −X. Наклон и снос шли
против выбранной стороны. Направление вынесено в `windDirectionFor()`
(восток → −X, запад → +X), добавлен тест, параметры диплинка
`wind`/`windSpeed`/`density` для визуальных прогонов.

### Отладка scene_editor: краш оверлеев и file_picker (13 сентября 2026)

Первая порция замечаний владельца (`scene_editor/visual_tests.json`,
bug_3–bug_4):

- **Краш при загрузке (bug_3).** `Exception: Child is not attached to this
  node` в `EditorScene._rebuildOverlays` после догрузки текстур/glTF.
  Причина: `SceneController.onNodeDetached` снимал engine-ноду у всех
  потомков отвязываемого поддерева — зеркало движка расходилось с
  API-деревом, и следующий `unlinkChild` падал. Исправлено: отвязка только
  у корней рендер-сцены (`node.parent == null`), `EngineNode.remove` стал
  идемпотентным, `selectionOverlay` чистится до `overlays.removeAll()`.
  Регрессии — `engine/test/api/scene_controller_test.dart`,
  `scene_editor/test/editor_viewport_test.dart`.
- **file_picker на macOS (bug_4).** `ENTITLEMENT_NOT_FOUND` при выборе
  папки: file_picker 11 проверяет user-selected entitlements даже при
  выключенной песочнице. На старте вызывается
  `FilePicker.skipEntitlementsChecks()` — штатный API плагина для
  не-sandbox приложений; тест
  `scene_editor/test/file_picker_entitlements_test.dart`.

Проверки: `engine` 522 теста, `demo` 164, `scene_editor` 344; analyze чист;
смоук редактора на macOS (model_2 с выделением, догрузка текстур/glTF,
смена режимов «Освещение»/«Текстурирование» и моделей) — без исключений.

### Wireframe и экранная толщина линий (13 сентября 2026)

Сделано:

- **Форк.** `LineSegmentsGeometry` получил пиксельный режим (`pixelWidth` +
  `pixelScale`): вершинный шейдер разворачивает ленту на постоянное число
  пикселей независимо от дистанции (неиспользуемые слоты `FrameInfo.params`,
  формат блока не менялся). Добавлена чистая CPU-функция
  `expandLineSegments` (полилинии для Windows/Linux и отладочного режима).
- **Движок.** `LineWidthBackend` (`shader` на macOS/iOS/iPadOS/Android,
  `polyline` на Windows/Linux, принудительно — параметром `initializeEngine`
  или define `PET_LINE_WIDTH_BACKEND=polyline`); `LineGeometry`/`LineNode`
  получили `widthPx` (по умолчанию в хелперах 3 px). `WireframeStyle`
  (толщина, цвет, `throughGeometry`, угол склейки) и API wireframe на трёх
  уровнях: `SceneNode.wireframe`, `ModelNode.setFaceWireframe`, сцена —
  `SceneController.setWireframe`; рёбра берутся из CPU-геометрии (для CSG —
  из вычисленного результата), дедуплицируются и рисуются на слое `top`.
  Вьюпорт сам добавляет служебные виды (`overlay`/`top`), когда на слоях
  есть ноды.
- **Исправлено по ходу.** Pick-прокси model-инстансов в world-кадре
  смещался от содержимого (ячейки `modelRefCubeProxy`); добавлен
  `modelRefFootprintBox` — бокс, центрированный на якоре инстанса, как у
  рендера и `unionAabbResolved`; это же чинит промахи выделения по мебели.
  Guard'ы `_disposed` в колбэках контроллера убрали падения
  «SceneController used after being disposed» при асинхронной догрузке фичи
  или уровня после смены сцены.
- **Demo.** Тумблер «Wireframe всей сцены» в панели настроек, ключ диплинка
  `settings?wireframe=1`, признак в метаданных снимков; визуальный прогон
  всех 48 сцен (`temp/screenshots/wf_*`, журнал `demo/visual_tests.json`
  bug_53).
- **Документация.** `docs/api.md` §9.1 (толщина линий и wireframe), §3
  (авто-виды), §4/§5.1/§5.3.

Проверки: форк — analyze чист, 1057 тестов; `engine` — analyze чист,
534 теста; `demo` — analyze чист, 164 теста; `scene_editor` — 344.

### Гизмо, сетка и отладка выделения (13 сентября 2026)

Сделано:

- **Движок: гизмо.** `GizmoMode`/`GizmoAxis`/`GizmoStyle`/`GizmoHit`/
  `GizmoDragEvent`, `GizmoNode` (перенос — стрелки, вращение — кольца) с
  постоянным экранным размером (линия 3 px, стрелка/радиус 96 px, кончик
  18 px), слоем `top` и видимостью сквозь сцену. `SceneController`:
  `addGizmo`/`removeGizmo`/`hitGizmo` (приоритет над сценой без учёта
  глубины), `beginGizmoDrag`/`updateGizmoDrag`/`endGizmoDrag`; дельты
  приходят в `onDrag`, при заданном `target` нода трансформируется сама.
  Чистые хелперы драга (`axisDragDelta`, `planeHit`,
  `signedAngleAroundAxis`, `rotationDragDelta`) экспортированы.
- **Движок: сетка.** `GridNode` — пиксельные линии на слое `overlay`;
  редактор строит сетку им.
- **Demo: сцена «Гизмо»** (49-я фича): оба гизмо одновременно, драг мышью и
  пальцем; в demo проброшен перехват указателя фичей
  (`FeatureContext.setPointerHandlers`), при драге камера не конфликтует.
- **Отладка выделения (движок + редактор).**
  - pick-прокси model-инстансов выровнен с содержимым
    (`modelRefFootprintBox`), починены и outline, и плейсхолдер, и wireframe;
  - спрайты пикаются по живому билборд-йо, а не по авторскому `rotY`;
  - пикинг учитывает отсечение граней (`RaycastOptions.respectCulling`,
    сторона из материала): невидимые потолок/стены/небо не перехватывают
    луч (баг «выделение не работает за границей сцены»);
  - контур выделения CSG рисует вычисленный результат
    (`ModelNode.edges()`), а не сырые операнды (баг «выделение не совпадает
    изнутри»);
  - исправлена подпись операции CSG в правой панели (печаталась `Closure`).
- **Редактор: wireframe.** Тумблер «Wireframe всей сцены» в верхней панели
  и переключатель объекта в свойствах; ключ диплинка `settings?wireframe=1`.
- **Производительность.** `ModelRenderer.updateObjectTransforms` +
  `SceneController.refreshObjectTransforms` — драг солидных объектов
  обновляет только трансформы (без пересборки геометрии); для
  CSG/скруглений/вставок/спрайтов остаётся полный `rebuild`.
- **Несохранённые изменения.** `AppState.hasUnsavedChanges`/`saveAll`,
  диалог «Сохранить / Не сохранять / Отмена» на открытие и создание
  проекта, создание модели и шаблон; новые/дублированные модели помечаются
  dirty; диплинки (визуальные прогоны) по-прежнему отбрасывают правки.

Проверки: `engine` — analyze чист, 548 тестов; `demo` — 164;
`scene_editor` — 348; визуальные снимки редактора (кресло, штора, CSG,
wireframe сцены, сетка движка) — `temp/screenshots`, журнал
`scene_editor/visual_tests.json`.

Осталось по редактору: перевести собственный гизмо переноса/вращения
редактора на движковый `GizmoNode` (сейчас движковый гизмо используется в
demo; редактор показывает свой — с той же математикой, вынесенной в
движок).

### Wireframe: чужие рамки, следование и толщина (13 сентября 2026)

Замечания владельца (`scene_editor/visual_tests.json` bug_7):

- **Рамки от других сцен.** Документные `ModelNode` виртуальны (без host),
  поэтому их `dispose` не доходил до `_dropNodeWireframe` и линии прошлых
  сцен копились в `_wireframeNodes`/группе `wireframes`. `_refreshWireframes`
  теперь удаляет из трекинга и сцены все id, которых нет среди текущих нод
  (тест «switching models drops the previous wireframes»).
- **Следование за объектами.** Пересборка wireframe добавлена в
  `refreshObjectTransforms` (быстрый драг) и `ModelNode.setPlacement`
  (живой glTF).
- **Толщина.** Дефолт `WireframeStyle.thickness` снижен с 3 до 1 px
  (demo/editor наследуют); `docs/api.md` обновлён.
- **Выделение в редакторе.** Прокси model-инстанса сужен с полного грида
  источника (3×3 = 1.8 world) до world-AABB фактического содержимого
  (`worldContentBounds`): бокс кресла больше не торчит сквозь стену и не
  перехватывает клики. Pet-лучи (`engine/test/api/pet_picking_test.dart`):
  клик по левой шторе → штора, по разделителю → окно, по стене у кресла →
  стена, по креслу → кресло. Снимки `fin_*` — без чужих рамок.

Проверки: `engine` — analyze чист, 554 теста; `demo` — 164;
`scene_editor` — 348.

### Спрайты, точный пикинг и гизмо редактора (13 сентября 2026)

Замечания владельца (`scene_editor/visual_tests.json` bug_8,
`demo/visual_tests.json` bug_56):

- **Спрайты.** `SceneController.reorientBillboards` не вызывал
  `ModelRenderer.reorientBillboards`, поэтому документные спрайты (и
  вложенные во вставки) стояли на авторском `rotY`; вызов восстановлен.
  Ориентация вынесена в общий хелпер `spriteBillboardMatrix`
  (рендер, пик-геометрия, контур редактора) — горизонтальный билборд по
  священной конвенции. Тест `engine/test/api/sprite_billboard_test.dart`.
- **Точный пикинг вставок.** Model-инстансы пикаются рекурсивными частями
  фактического содержимого (примитивы, CSG/скругления, вложенные ссылки,
  glTF-бокс, спрайты с живым yaw) вместо AABB-прокси: луч в зазор больше
  не задевает мебель. Pet-лучи: штора → штора, разделитель → окно, стена у
  кресла → стена, кресло → кресло.
- **Гизмо редактора — из движка.** Объекты, меты и направленный свет
  переведены на движковый `GizmoNode` (`onDrag` применяет дельты с шагом,
  один undo-шаг на драг, приоритетный экранный hit-тест); локальные гизмо,
  невидимые зоны захвата и дублирующая математика удалены. Мировое +X
  зеркалится в модельный −x (объекты) и в −rotX (вращение).
- **Deeplink редактора**: `settings?rotate=1` (режим вращения) и выбор
  мет/света по режиму (`mode=lighting select=…`).

Проверки: `engine` — analyze чист, 556 тестов; `demo` — 164;
`scene_editor` — 345; снимки `gizmo_move`/`gizmo_rot2`/`gizmo_light2`/
`gizmo_light_rot`, `sprite_fix`.

### Луч выделения: инверсия позы камеры (13 сентября 2026)

Владелец: выделение в редакторе «всё ещё ненадёжно» (bug_8). Найденная
причина — `SceneController.screenPointToRay` умножал camera-local
направление луча на **обратную** позу камеры
(`view = globalTransform⁻¹; view.rotate3(dir)`). Это верно только для
самообратных поворотов (yaw = 0/π): модели кадрируются с yaw = π, поэтому
«фронтальный» пикинг работал, а после орбиты или фокуса двойным кликом
(`fly.lookAt` даёт произвольный yaw) луч уезжал — вплоть до зеркального
отражения по вертикали, и клики попадали не туда или мимо. Тесты пикинга
использовали только yaw = π/identity, а pet-лучи кастовались вручную
(`raycastRay`), минуя `screenPointToRay`, поэтому регрессия не ловилась.

Исправлено:

- направление поворачивается позой камеры
  (`cameraNode.globalTransform.rotate3`), а не её обратной матрицей;
- `SceneViewport._screenRay` сведён к `controller.screenPointToRay` — одна
  математика для тапов (`SceneTapEvent.ray`) и пикинга, без дубля;
- размер вьюпорта сообщается контроллеру синхронно в layout (без
  post-frame), чтобы между ресайзом и кликом не было кадра устаревшей
  геометрии.

Регрессии: roundtrip `worldToScreen`↔`screenPointToRay` и пикинг с
наклонённой камеры (`engine/test/api/picking_test.dart`,
`engine/test/api/scene_viewport_test.dart`,
`scene_editor/test/editor_scene_test.dart`).

Проверки: `engine` — analyze чист, 560 тестов; `demo` — 164;
`scene_editor` — 346.

### Перф-проход: драг объектов без пересборки сцены (13 сентября 2026)

Владелец: «очень медленно работает обновление сцен при перемещении
объектов». Замер встроенным харнессом (`pet.perf.drag=true`, macOS,
`Pet/model_2`, 24 объекта, 9335 частей) — журнал `docs/perf_journal.md`:
вставка модели, спрайт и glTF пересобирали ВСЮ сцену на каждый шаг драга
(53 мс синхронно, `ModelRenderer.rebuild` 50–120 мс), куб шёл быстрым
путём (0.6 мс). Попутно: CSG во время драга не двигался (операнды
обновлялись, результат перестраивался только на отпускании), а невидимый
гизмо вращения перехватывал клики по оси переноса.

Исправлено:

- **Трансформационный быстрый путь.** `ModelRenderer.updateObjectTransforms`
  принимает `translated: {id: мировой шаг}` и сдвигает ноды элементов без
  геометрии/CSG/материалов; редактор передаёт фактический снапнутый шаг,
  для CSG результат двигается шагом первого операнда; цепочки билбордов
  внутри вставок сдвигаются вместе с нодами.
- **Идемпотентный свет**: `applyLighting` сравнивает подпись конфигурации,
  `setShadows`/`setSsao`/`setEnvironmentIntensity` — no-op при том же
  значении (редактор зовёт их на каждую ревизию).
- **Wireframe** обновляется только по перемещённым элементам.
- **`SceneController.rebuildCount`** — диагностика и регрессионный тест
  «перенос вставки не пересобирает сцену».
- **`hitGizmo`** не проверяет скрытые гизмо.

Результат: 53.6 → 0.44 мс (вставка), 53.6 → 0.33 (спрайт), 52.9 → 0.34
(glTF), CSG двигается живьём при 0.71 мс; полных пересборок за драг — 0.
Визуальная проверка — снимки `scene_editor/temp/perf_screenshots/`.
Осталось на будущее: поворот «запечённых» видов идёт через полную
пересборку (перенос — нет); коалесинг pointer-событий; инкрементальные
оверлеи.

Проверки: `engine` — analyze чист, 562 теста; `demo` — 164;
`scene_editor` — 347.
