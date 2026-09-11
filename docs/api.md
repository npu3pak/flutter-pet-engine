# Публичный API pet_engine_v2

Документ описывает новый API движка целиком: типы, их обязанности и примеры
использования. API выведен из реестра фич (`docs/features.md`): каждая
возможность четырёх проектов должна выражаться перечисленными здесь
средствами.

Статус: согласовано в фазе 1; реализация — фаза 2. Имена типов и сигнатуры
могут уточняться при реализации, но состав возможностей фиксирован.

## 1. Принципы

1. **Пара «виджет + контроллер».** Приложение создаёт контроллеры и
   помещает `SceneViewport` в дерево виджетов. Виджет сам владеет кадром,
   размером и вводом.
2. **Несколько контроллеров.** `SceneController` отвечает за сцену и ноды,
   `CameraController` — за камеру, `QualityController` — за качество и
   производительность. Их можно создавать и подключать независимо.
3. **Нода — живой объект.** Появление объекта — добавление ноды, удаление —
   `node.remove()`. Нода хранит актуальные параметры и сразу отражает их в
   сцене.
4. **Типизированные ноды.** Закрытый набор примитивов; общий базовый класс
   отвечает за жизнь ноды, наследники — за параметры.
5. **Никаких типов форка наружу.** Приложения не импортируют
   `package:flutter_scene/...`. Всё, что было нужно редактору и играм,
   выражено движковыми типами.
6. **Шейдеры — рантайм.** `model_v1` не меняется; шейдер назначается ноде
   кодом и не сохраняется в документ.
7. **Проверяемость без GPU.** Логика отделена от рендера; у вьюпорта есть
   подменяемый бэкенд для тестов.

## 2. Виджет `SceneViewport`

```dart
class SceneViewport extends StatefulWidget {
  const SceneViewport({
    super.key,
    required this.controller,       // сцена
    this.views,                     // виды и слои; null — один полный вид
    this.input,                     // обработчик ввода; null — CameraInput
    this.overlayBuilder,            // 2D-оверлеи поверх сцены
    this.backgroundBuilder,         // 2D-фон под сценой (например, небо)
    this.loadingBuilder,            // индикатор загрузки
    this.onTap,                     // тап по сцене
    this.onDoubleTap,               // двойной тап
    this.autoTick = true,           // выключение для ручного кадра
    this.pixelRatio,                // масштаб целевой текстуры
    this.warmUp = false,            // прогрев пайплайнов
    this.focusNode,                 // узел фокуса для клавиатуры
    this.autofocus = true,          // забирать фокус при появлении
  });
}
```

Обязанности виджета:

1. **Размер.** Сообщает контроллеру фактический размер вьюпорта до первого
   кадра; при изменении обновляет.
2. **Кадр.** Раз в кадр вызывает `controller.update(dt)` и перерисовывает
   сцену. Порядок внутри кадра фиксирован: камера → динамика → разворот
   билбордов → подписчики кадра.
3. **Ввод.** Передаёт события указателя, колеса, наведения и клавиатуры
   обработчику `SceneInput`; по умолчанию это `CameraInput`.
4. **Оверлеи и фон.** Рисует 2D-виджеты поверх и под сценой; оверлеи
   получают события раньше сцены.
5. **Загрузка.** Пока `controller.status` не готов, показывает
   `loadingBuilder`.
6. **Жизненный цикл.** Виджет не владеет контроллером и не освобождает
   его; контроллер живёт столько, сколько нужно приложению.
7. **Снимок.** `Future<Uint8List> capture({double? pixelRatio})` отдаёт PNG
   содержимого вьюпорта для визуального тестирования; `pixelRatio` по
   умолчанию — значение вьюпорта, затем `devicePixelRatio` (раздел 18).

Пример:

```dart
SceneViewport(
  controller: controller,
  loadingBuilder: (context, status) => Center(child: Text(status.label)),
  overlayBuilder: (context, size) => const FpsOverlay(),
);
```

## 3. Виды и слои

Редактору нужны три вида одной сцены с раздельной глубиной: сцена, оверлеи,
верхний слой гизмо. Остальным потребителям достаточно одного вида.

```dart
abstract final class SceneLayer {
  static const int base = 1 << 0;      // слой по умолчанию
  static const int overlay = 1 << 1;   // контуры, подписи, сетка
  static const int top = 1 << 2;       // гизмо поверх всего
  static const int all = 0xFFFFFFFF;
}

class SceneViewSpec {
  const SceneViewSpec({required this.layerMask, this.order = 0, this.camera});

  factory SceneViewSpec.main({CameraController? camera});   // всё, кроме overlay/top
  factory SceneViewSpec.overlay({CameraController? camera}); // SceneLayer.overlay
  factory SceneViewSpec.top({CameraController? camera});     // SceneLayer.top
  factory SceneViewSpec.layer(int layerMask, {int order = 0, CameraController? camera});

  final int layerMask;
  final int order;                 // меньше — раньше; больше — поверх
  final CameraController? camera;  // null — активная камера контроллера
}
```

У ноды есть `layer` (битовая маска, по умолчанию `SceneLayer.base`).
Без параметра `views` вьюпорт создаёт один вид со всеми слоями.

Пример редактора:

```dart
SceneViewport(
  controller: editor,
  views: [
    SceneViewSpec.main(),
    SceneViewSpec.overlay(),
    SceneViewSpec.top(),
  ],
);

final contour = editor.add(LineNode(geometry: contourGeometry, color: Colors.blue))
  ..layer = SceneLayer.overlay;
final gizmo = editor.add(MeshNode(geometry: arrowGeometry, material: gizmoMaterial))
  ..layer = SceneLayer.top;
```

## 4. Контроллер сцены `SceneController`

```dart
class SceneController extends ChangeNotifier {
  SceneController({bool mergeStatic = true});

  // ── сессия и ресурсы ────────────────────────────────────────────────
  Future<void> open(ProjectSource source);       // проект, модели, каталоги
  Future<void> openProject();                    // повторно: project.json и каталоги
  Future<void> openModels();                     // повторно: models/*.json
  Future<bool> loadModel(String id);             // модель из каталога
  void loadModelData(ModelData data, {String? id}); // готовая модель
  void unloadModel();
  void reloadResources();                        // сброс кэшей текстур/glTF
  void rebuild();                                // пересборка контента, ++revision
  SceneLoadStatus get status;
  SceneResources? get resources;
  ProjectStore get project;                      // модели проекта (создание и т.п.)
  ShaderLibrary get shaders;                     // .fmat-материалы
  ModelData? get model;
  String? get modelId;
  int get revision;                              // растёт при каждой пересборке
  bool get mergeStatic;

  // ── документ ────────────────────────────────────────────────────────
  ModelNode addObject(ModelObject object);       // добавить в документ и сцену
  void removeObject(ModelObject object);         // убрать из документа и сцены
  ModelNode? objectNode(String objectId);
  ModelMeta? addMeta(ModelMeta meta);
  void removeMeta(ModelMeta meta);
  ModelLight? addDocumentLight(ModelLight light);
  void removeDocumentLight(ModelLight light);
  ModelGroup? addGroup(ModelGroup group);
  void removeGroup(ModelGroup group);

  // ── ноды ────────────────────────────────────────────────────────────
  List<SceneNode> get nodes;                     // корневые ноды контроллера
  T add<T extends SceneNode>(T node);
  void remove(SceneNode node);
  SceneNode? byId(String id);
  Iterable<T> nodesOfType<T extends SceneNode>();

  // ── камера и вьюпорт ────────────────────────────────────────────────
  CameraController get camera;
  set camera(CameraController value);
  SceneNode get cameraNode;                      // узел камеры; к нему крепятся ноды
  Size get viewportSize;
  double get pixelRatio;

  // ── кадр ────────────────────────────────────────────────────────────
  void update(double dt);
  void addFrameListener(SceneFrameListener listener);
  void removeFrameListener(SceneFrameListener listener);

  // ── настройки картинки ──────────────────────────────────────────────
  QualitySettings get settings;
  QualityController? get quality;                // подключённый контроллер качества
  void applySettings(QualitySettings settings);
  void setShadows(bool enabled);   // меняет QualitySettings и применяет; документ не трогает
  void setSsao(bool enabled);      // то же
  void setShadowCascades(int count);
  void setShadowDistance(double distance);
  void setRenderScale(double scale, {FilterQuality? filterQuality});
  void setAntiAliasing(SceneAntiAliasing mode);
  void setEnvironmentIntensity(double value);
  void setFog(SceneFog? fog);
  void applyLighting();                          // построить свет документа
  void clearLighting();                          // снять построенный свет

  // геттеры для интерфейса
  double get renderScale;
  SceneAntiAliasing get effectiveAntiAliasing;
  int? get shadowCascades;
  double? get shadowDistance;
  double get environmentIntensity;
  SceneFog? get fog;

  // ── попадания и проекция ────────────────────────────────────────────
  SceneHit? raycast(Offset screenPoint, {RaycastOptions options});
  SceneHit? raycastRay(Ray ray, {RaycastOptions options});
  List<SceneHit> raycastAll(Ray ray, {RaycastOptions options});
  Offset? worldToScreen(Vector3 worldPoint);
  Rect? screenRect(Aabb3 worldBounds);
  Ray screenPointToRay(Offset screenPoint);
  SceneNode? nearestNode(Offset screenPoint, {double maxDistance = 140});

  // ── уровни ──────────────────────────────────────────────────────────
  Future<LevelLoadResult> loadLevel(
    ConstructionModel model, {
    List<LevelExtraResource> extraResources = const [],
    LevelBakeOptions? options,
  });
  LevelNode mountLevel(LevelBakeResult baked, {Matrix4? offset});
  void unmountLevel();
  LevelNode? get level;

  // ── небо ────────────────────────────────────────────────────────────
  SkyboxNode? get skybox;                        // активное небо сцены

  // ── динамика ────────────────────────────────────────────────────────
  DynamicNodes get dynamics;

  // ── прочее ──────────────────────────────────────────────────────────
  void reorientBillboards();
  void dispose();
}
```

Пояснения:

- `open` асинхронный: читает `project.json`, модели, каталоги и glTF.
  Прогресс и ошибки — в `status`.
- `loadModel`/`loadModelData` строят содержимое сцены синхронно; тяжёлые
  glTF-ресурсы доезжают асинхронно, ноды обновляются сами (см. A6).
- `addObject`/`removeObject`, `addMeta`/`removeMeta`,
  `addDocumentLight`/`removeDocumentLight`, `addGroup`/`removeGroup` меняют
  документ и сцену синхронно — на этом редактор строит отмену действий.
  Остальные поля документа можно править напрямую, затем звать `rebuild()`.
- `revision` увеличивается при каждой пересборке; редактор по нему решает,
  нужно ли обновлять вьюпорт.
- `update` вызывает вьюпорт; при `autoTick: false` приложение зовёт само.
- `raycast` возвращает `SceneHit` без типов форка.
- `applyLighting`/`clearLighting` вызываются только явно (см. раздел 5.5).
- `shaders` — библиотека `.fmat`; `project` — операции над моделями проекта
  (раздел 16).
- `project` — канонический путь записи моделей (`createModel`, `saveModel`,
  `deleteModel`, `renameModel`); `resources` — только чтение и кэши.

## 5. Ноды

### 5.1. Базовая нода

```dart
abstract class SceneNode extends ChangeNotifier {
  SceneNode({String? id, String name = '', int layer = SceneLayer.base});

  String get id;
  String get name;
  set name(String value);
  int get layer;                    // битовая маска вида
  set layer(int value);

  bool get inScene;                 // подключена ли к сцене
  SceneController? get scene;
  SceneNode? get parent;
  List<SceneNode> get children;

  bool visible;
  double opacity;
  Vector4? highlightColor;          // контур выделения, null — нет

  Matrix4 get transform;
  set transform(Matrix4 value);
  Vector3 get position;
  set position(Vector3 value);
  Vector3 get rotation;             // радианы, XYZ
  set rotation(Vector3 value);
  Vector3 get scale;
  set scale(Vector3 value);
  Aabb3? get worldBounds;           // мировые габариты, если их можно вычислить

  SceneMaterial get material;
  set material(SceneMaterial value);

  void detach();                    // снять со сцены, нода остаётся живой
  void remove();                    // отключить и освободить
  void dispose();
}
```

### 5.2. Примитивы и группы

```dart
class GroupNode extends SceneNode {
  GroupNode({String? id, String name = ''});
  void add(SceneNode child);
  void remove(SceneNode child);
  void removeAll();
}

class BoxNode extends SceneNode {
  BoxNode({
    String? id,
    Vector3? size,                  // размеры бруса
    double roundR = 0,              // радиус скругления
    int roundSegments = 0,          // сегментов скругления
    SceneMaterial? material,
  });
  Vector3 size;
  double roundR;
  int roundSegments;
}

class PlaneNode extends SceneNode {
  PlaneNode({
    String? id,
    required double width,
    required double depth,
    bool vertical = false,          // вертикальная или горизонтальная
    SceneMaterial? material,
  });
}

class MeshNode extends SceneNode {
  MeshNode({String? id, required SceneGeometry geometry, SceneMaterial? material});
  SceneGeometry get geometry;
  set geometry(SceneGeometry value);   // замена геометрии у живой ноды
  void addPart(SceneGeometry geometry, SceneMaterial material); // многоматериальный
  List<MeshPart> get parts;
}

class SpriteNode extends SceneNode {
  SpriteNode({
    String? id,
    SceneTexture? texture,
    double width = 1,
    double height = 1,
    double yaw = 0,
    bool billboard = false,         // разворачивать к камере каждый кадр
    SpriteOrientation orientation = SpriteOrientation.vertical,
  });
  SceneTexture? texture;
  double width;
  double height;
  double yaw;
  bool billboard;
}

class LineNode extends SceneNode {
  LineNode({String? id, required LineGeometry geometry, Color color = Colors.white, double width = 0.01});
}

class RingNode extends SceneNode {
  RingNode({String? id, double radius = 0.3, double thickness = 0.05, Color color = Colors.white});
  double radius;
  double thickness;
  Color color;
}

class LightNode extends SceneNode {
  LightNode.point({String? id, Color color = Colors.white, double intensity = 1, double range = 0, double importance = 1});
  LightNode.directional({String? id, Vector3? direction, Color color = Colors.white, double intensity = 1, bool castsShadow = false, double importance = 1});

  Color color;
  double intensity;
  double range;                     // только точечный
  Vector3 direction;                // только направленный
  bool castsShadow;                 // только направленный
  double importance;                // приоритет при ограничении числа ламп
}
```

### 5.3. Нода документа `ModelNode`

```dart
class ModelNode extends SceneNode {
  String get kind;                  // 'gltf' или вид объекта документа
  ModelObject get object;           // живой объект документа
  ModelData get model;

  double get x; double get y; double get z; double get rotY; // координаты модели
  Vector3 get worldPosition;
  Aabb3 get worldBounds;

  void setPlacement({double? x, double? y, double? z, double? rotY});
  void setWorldPlacement({double? x, double? z, double? rotY});

  // glTF
  String get gltfName;
  Aabb3? get gltfBounds;            // габариты ресурса, когда он загружен
  List<GltfAnimInfo> get animationClips;
  String get animation;
  void play(String clipFullName);   // '' — стойка

  // материалы
  List<FaceRef> get faces;
  void setFaceMaterial(String faceKey, SceneMaterial? material);
  void setTexture(String key, {String? faceKey, bool fromSprites = false});
  void setColor(Color color, {String? faceKey});
}
```

### 5.4. Механизмы-ноды

```dart
class ParticleNode extends SceneNode {
  ParticleNode({required ParticleConfig config, required ParticleField field, double intensity = 1, bool enabled = true});
  ParticleConfig config;
  ParticleField field;
  double intensity;
  bool enabled;
  Vector3 windDirection;
  Vector3? focus;                   // точка/клетка игрока: от неё считается плотность
}

class SpriteFieldNode extends SceneNode {
  SpriteFieldNode({required List<SpriteFieldSprite> sprites, required int capacity, SpriteFieldFacing facing = SpriteFieldFacing.screenParallel, bool opaque = false});
  Future<void> prepare();           // сборка атласа до первого кадра
  void update(List<SpriteFieldInstance> instances);
  void reset();                     // очистка без потери атласа
}

class GroundFogNode extends SceneNode {
  GroundFogNode({required List<GroundFogSprite> sprites, required int capacity, int blendOrder = 0});
  Future<void> prepare();
  void update(List<FogInstance> instances, {Color? tint});
  void reset();
}

class BillboardBatchNode extends SceneNode {
  BillboardBatchNode({required int capacity, SpriteAtlas? atlas, BillboardFacing facing = BillboardFacing.spherical, SpriteBlendMode blendMode = SpriteBlendMode.opaque, int blendOrder = 0});
  void setInstance({required Vector3 center, required double width, required double height, double rotation = 0, int frame = 0, Vector3? velocity, Color? color});
  void commit();
}

class SkyboxNode extends SceneNode {
  SkyboxNode({String? id, Color backgroundColor = const Color(0xFF000000)});
  Color backgroundColor;            // фон, когда слоёв нет
  bool followCamera;                // поворот за камерой
  double rotation;                  // дополнительный поворот 0..1 (север = 1/8)
  List<SkyboxLayer> get layers;     // порядок отрисовки снизу вверх
  void addLayer(SkyboxLayer layer);
  void removeLayer(SkyboxLayer layer);
}

sealed class SkyboxLayer {
  bool visible;
  double opacity;
}

class SkyboxColorLayer extends SkyboxLayer {  // вертикальный градиент
  SkyboxColorLayer({required Color topColor, required Color bottomColor});
  Color topColor;
  Color bottomColor;
}

class SkyboxImageLayer extends SkyboxLayer {  // панорама (бывший StaticSkybox)
  SkyboxImageLayer({required ui.Image image, double offset = 0, bool tile = true, Color? fogColor, double fogStrength = 0});
  ui.Image image;
  double offset;
  bool tile;
  Color? fogColor;
  double fogStrength;
}

class SkyboxCloudsLayer extends SkyboxLayer {
  SkyboxCloudsLayer({required SceneTexture texture, double scale = 1, double speed = 0.01, double coverage = 0.5, Color color = Colors.white});
  SceneTexture texture;
  double scale;
  double speed;
  double coverage;
  Color color;
}

class SkyboxStarsLayer extends SkyboxLayer {
  SkyboxStarsLayer({int count = 300, double brightness = 1});
  int count;
  double brightness;
}

class SkyboxBodyLayer extends SkyboxLayer {   // солнце или луна
  SkyboxBodyLayer({required Vector3 direction, double size = 1, Color color = Colors.white, bool moon = false, double glow = 0.5});
  Vector3 direction;
  double size;
  Color color;
  bool moon;
  double glow;
}

class LevelNode extends GroupNode {
  LevelBakeResult get result;
  SceneNode? nodeFor(String elementId);
}
```

### 5.5. Свет

```dart
// Свет строится из документа только по явному вызову:
controller.applyLighting();   // ModelLighting → LightNode (или дефолтный риг)
controller.clearLighting();   // снять построенный свет

// Свои источники:
final lamp = controller.add(
  LightNode.point(color: Colors.orange, intensity: 2, range: 6, importance: 0.5),
);
```

- Документ (`ModelLighting`) хранит художественный свет: источники, цвет,
  интенсивность, радиус, направление, ambient.
- Тумблеры теней и SSAO берутся не из документа, а из `QualitySettings`
  (раздел 15).
- `LightNode.importance` задаёт приоритет: при ограничении
  `QualitySettings.maxPointLights` движок оставляет самые важные точечные
  источники, остальные выключает, не удаляя ноды.
- Направленные источники и ambient под ограничение не попадают.
- `SceneController.cameraNode` позволяет привязать лампу игрока к камере.
- Тумблеры `setShadows`/`setSsao` пишут в `QualitySettings` (источник
  истины) и применяют их. Поля `ModelLighting.shadows/ssao` остаются
  художественной подсказкой и используются только для начального
  заполнения настроек в редакторе.

### 5.6. Небо

- Небо — нода сцены (`SkyboxNode`); вьюпорт рисует её фоновым проходом за
  сценой: фон → градиент → панорамы → облака → звёзды → солнце/луна.
  Сцена перекрывает небо, поэтому пещеры и интерьеры выглядят правильно.
- По умолчанию узел пуст: только `backgroundColor`.
- Примеры: день — градиент + облака + солнце; ночь — градиент + звёзды +
  луна; город — две панорамы + облака; природа — панорама + солнце.
- `loadSkyboxImage(bytes)` превращает PNG/JPEG в `ui.Image` для
  `SkyboxImageLayer`.
- `SceneController.skybox` — активное небо сцены.

### 5.7. Анимации

```dart
class AnimationPlayer extends ChangeNotifier {
  AnimationPlayer(ModelNode node);
  List<GltfAnimInfo> get clips;
  String? get current;
  bool get playing;
  double get speed;
  bool get loop;
  double get weight;
  void play(String clipFullName, {bool loop = true, double speed = 1});
  void pause();
  void resume();
  void stop();                      // стойка
  void seek(double seconds);
  void crossFade(String clipFullName, {Duration duration = const Duration(milliseconds: 250)});
}
```

- `ModelNode.play` — короткая форма для одной анимации; `AnimationPlayer` —
  полное управление (пауза, перемотка, скорость, цикл, кроссфейд), нужное
  просмотрщику моделей.
- Временем владеет контроллер: он обновляет проигрыватели в кадре.

### 5.8. glTF во время выполнения

```dart
class GltfAsset {
  static Future<GltfAsset> fromBytes(Uint8List bytes, {Map<String, Uint8List> siblings = const {}});
  static Future<GltfAsset> fromFile(File file);  // .glb или .gltf с соседями
  Aabb3 get bounds;
  List<GltfAnimInfo> get animations;
}

class GltfNode extends SceneNode {
  GltfNode.fromAsset(GltfAsset asset);
  GltfAsset get asset;
  AnimationPlayer get player;
  Aabb3 get worldBounds;
}
```

- `GltfAsset` — runtime-импорт (просмотрщик редактора, динамическая
  загрузка), не связан с каталогом `3d_models`.
- `GltfNode` — нода такого ресурса с собственным проигрывателем анимаций.
- Ссылки на glTF из документа остаются `ModelNode` (`gltfName`,
  `animationClips`, `play`).

## 6. Материалы `SceneMaterial`

```dart
class SceneMaterial extends ChangeNotifier {
  SceneMaterial.pbr({
    SceneTexture? texture,
    Color color = Colors.white,
    double roughness = 1,
    double metallic = 0,
    SceneAlphaMode alphaMode = SceneAlphaMode.opaque,
    double alphaCutoff = 0.5,
    bool doubleSided = false,
    Color? emissive,
    double? fogStartOverride,
    double blendOrder = 0,
  });

  SceneMaterial.unlit({
    SceneTexture? texture,
    Color color = Colors.white,
    SceneAlphaMode alphaMode = SceneAlphaMode.opaque,
    bool doubleSided = false,
    double blendOrder = 0,
  });

  SceneMaterial.shader(ShaderMaterialInstance shader);

  // общие свойства
  SceneTexture? texture;
  Color color;
  SceneAlphaMode alphaMode;
  double alphaCutoff;
  bool doubleSided;
  double blendOrder;

  // только PBR
  double roughness;
  double metallic;
  Color? emissive;
  double? fogStartOverride;

  // шейдер
  ShaderMaterialInstance? get shader;

  bool get isPbr;
  bool get isUnlit;
  bool get isShader;
}

enum SceneAlphaMode { opaque, mask, blend }
```

Для UV-параметров документа (направление, отражение, тайлинг, сторона)
используются поля `ModelMaterial` — они остаются в документе; `ModelNode`
применяет их при сборке.

## 7. Шейдеры

Шейдеры — рантайм-возможность. `model_v1` не меняется: сцена, сохранённая
редактором, шейдер не несёт. Шейдер загружается по пути `.fmat`, схема
параметров объявлена в самом файле; значения задаются по имени.

```dart
class ShaderMaterial {
  String get name;
  List<ShaderParameter> get parameters;   // имя, тип, значение по умолчанию
  ShaderMaterialInstance instance();      // независимая копия параметров
}

class ShaderMaterialInstance {
  void setFloat(String name, double value);
  void setInt(String name, int value);
  void setVector(String name, Vector4 value);
  void setColor(String name, Color value);   // sRGB → linear
  void setTexture(String name, SceneTexture texture, {SceneTextureFilter? filter});
  Object? get(String name);
}

class ShaderParameter {
  String get name;
  ShaderParameterType get type;   // float/int/vec2/vec3/vec4/mat4/sampler2D/samplerCube
  Object? get defaultValue;
}
```

Загрузка:

```dart
class ShaderLibrary {
  Future<ShaderMaterial?> load(String assetPath); // assets/shaders/fx_glow.fmat
  bool get isLoaded;
  Future<void> reload();            // перечитать .fmat (кнопка «перезагрузить»)
  void dispose();
}
// controller.shaders.load('assets/shaders/fx_glow.fmat');
```

Назначение:

```dart
final glow = await controller.shaders.load('assets/shaders/fx_glow.fmat');
final fx = glow!.instance()
  ..setFloat('u_time', 0)
  ..setTexture('base_color_texture', spriteTexture, filter: SceneTextureFilter.pixelated);
sprite.material = SceneMaterial.shader(fx);

// каждый кадр:
controller.addFrameListener((elapsed, dt) => fx.setFloat('u_time', elapsed.inMilliseconds / 1000));
```

Правила:

- один экземпляр параметров — один визуальный объект; чтобы параметры не
  протекали, на каждого врага/эффект создаётся свой `instance()`;
- горячая перезагрузка встроена: явно заданные значения сохраняются по
  имени и типу;
- `shading_model`, `blending`, `culling` берутся из метаданных шейдера;
  `color`/`texture` у шейдерного материала не используются;
- per-face шейдеры не поддерживаются: per-face остаются цвет и текстура
  документа.

## 8. Текстуры `SceneTexture`

```dart
class SceneTexture {
  static Future<SceneTexture> fromAsset(String assetPath, {SceneTextureFilter filter = SceneTextureFilter.pixelated});
  static Future<SceneTexture> fromBytes(Uint8List bytes, {SceneTextureFilter filter = SceneTextureFilter.pixelated});
  static SceneTexture fromImage(ui.Image image, {SceneTextureFilter filter = SceneTextureFilter.pixelated});

  int get width;
  int get height;
}

enum SceneTextureFilter { pixelated, linear }
```

Текстуры проекта резолвятся по ключу через ресурсную сессию:
`resources.texture('wallpaper_beige.png')`, `resources.sprite('window_4.png')`.

Формат ключей:

- списки `textureKeys`/`spriteKeys` содержат имена файлов **без**
  расширения (стемы), как в v1;
- резолвер `resources.texture(key)`/`sprite(key)`, `peekTexture`/`peekSprite`
  и `ModelNode.setTexture(key)` принимают канонический ключ документа —
  имя файла с расширением (`wallpaper_beige.png`, `window_4.png`); стем без
  расширения тоже допускается, расширение `.png` подставляется;
- в документе `ModelMaterial.key` всегда хранится с расширением.

## 9. Геометрия

```dart
class SceneGeometry {
  static SceneGeometry cuboid(Vector3 size);
  static SceneGeometry plane({required double width, required double depth});
  static SceneGeometry cylinder({required double bottomRadius, double topRadius = 0, required double height, int radialSegments = 16});
  static SceneGeometry cone({required double radius, required double height, int radialSegments = 16});
  static SceneGeometry sphere({required double radius, int segments = 16});
  static SceneGeometry roundedBox({required Vector3 size, required double radius, required int segments});
  static SceneGeometry trapezoid({required double bottomWidth, required double topWidth, required double height, required double depth});
  static SceneGeometry ring({required double radius, required double tubeRadius, int segments = 24});
}

class GeometryBuilder {
  GeometryBuilder({bool deduplicate = false});

  void addGeometry(SceneGeometry geometry, Matrix4 transform);
  void addTiledPlane({required double x, required double z, required double width, required double depth, required double y, double tileSize = 1});
  void addQuad({required Vector3 a, required Vector3 b, required Vector3 c, required Vector3 d, Vector4? color});
  void addWallBox({required Vector3 min, required Vector3 max});
  void addVerticalQuad({required Vector3 center, required double width, required double height, required double yaw});
  void addFacingQuad({required Vector3 center, required double width, required double height, required String facing});

  int get vertexCount;
  void addVertex(Vector3 position);
  void addTriangle(int a, int b, int c);
  void setNormal(Vector3 normal);
  void setTexCoord(double u, double v);

  SceneGeometry build();
}

class LineGeometry {
  LineGeometry(List<Vector3> segments, {double width = 0.01});
}
```

## 10. Камеры

```dart
abstract class CameraController extends ChangeNotifier {
  CameraProjection get projection;
  Vector3 get forwardH;             // горизонтальное направление для билбордов
  void update(double dt);
}

class FlyCameraController implements CameraController {
  FlyCameraController();

  Vector3 eye;
  double yaw;
  double pitch;

  void lookAt(Vector3 target);
  void frameModel(ModelData model);
  void frameBounds(Aabb3 bounds);
  void focusNode(SceneNode node);

  void flyStep(double dt, {bool shift = false});
  void flyLook(double dx, double dy);
  void startFly();
  void stopFly();
  void keyDown(int logicalKey, {bool shift = false});
  void keyUp(int logicalKey);

  void startOrbit(Vector3 pivot);
  void orbit(double dx, double dy);
  void stopOrbit();
  void pan(double dx, double dy, {required Vector3 focus, required double viewportHeight});
  void scrollZoom(double delta, {Vector3? focus, double? maxDistance});

  static double zoomMaxDistance(int w, int l, int h);
  static const double fovY;
}

class FirstPersonCameraController implements CameraController {
  FirstPersonCameraController({Direction facing = Direction.north, int row = 0, int column = 0, double y = 0.5});

  Direction facing;
  int row;
  int column;
  double y;
  AnimationType animation;
  double moveProgress;              // 0..1
}

class OrbitCameraController implements CameraController {
  OrbitCameraController({Vector3? target, double distance = 10, double yaw = 0, double pitch = 0.45});

  Vector3 target;
  double distance;
  double yaw;
  double pitch;

  void startFromCurrent();          // начать без рывка
  void orbit(double dx, double dy);
  void pan(double dx, double dy);
  void zoom(double delta);
  void frameBounds(Aabb3 bounds);
  void focusNode(SceneNode node);
}

class MatrixCameraController implements CameraController {
  MatrixCameraController({double fovY = kFovY, double near = 0.05, double far = 300});

  Matrix4 matrix;                   // задаётся каждый кадр приложением
  double fovY; double near; double far;
}
```

## 11. Ввод

```dart
class SceneViewportInfo {
  Size get size;
  double get pixelRatio;
  SceneController get controller;
  CameraController get camera;
}

class SceneInput {
  const SceneInput();
  const SceneInput.none();          // отключить стандартный ввод

  void onPointerDown(PointerDownEvent event, SceneViewportInfo info);
  void onPointerMove(PointerMoveEvent event, SceneViewportInfo info);
  void onPointerUp(PointerUpEvent event, SceneViewportInfo info);
  void onPointerCancel(PointerCancelEvent event, SceneViewportInfo info);
  void onPointerSignal(PointerSignalEvent event, SceneViewportInfo info);
  void onPanZoomStart(PointerPanZoomStartEvent event, SceneViewportInfo info);
  void onPanZoomUpdate(PointerPanZoomUpdateEvent event, SceneViewportInfo info);
  void onPanZoomEnd(PointerPanZoomEndEvent event, SceneViewportInfo info);
  void onHover(PointerHoverEvent event, SceneViewportInfo info);
  KeyEventResult onKey(FocusNode node, KeyEvent event, SceneViewportInfo info);
}

class CameraInput extends SceneInput {
  CameraInput({
    this.pointerLookButton = kSecondaryButton,
    this.pointerFlyButton = kPrimaryButton,
    this.tapSlop = 8,
    this.tapTimeout = const Duration(milliseconds: 300),
    this.lookSensitivity = 0.005,
    this.keyFlyCodes = const {0x57, 0x41, 0x53, 0x44, 0x45, 0x51},
  });
}
```

Правила вьюпорта:

- события указателя приходят как есть; роли («первый смотрит, второй летит»)
  реализует `CameraInput`;
- тап формируется вьюпортом и приходит в `onTap`; приложение не считает
  пороги само;
- клавиатура не потребляется: вьюпорт возвращает `KeyEventResult.ignored`,
  если ввод не обработал событие, чтобы работали шорткаты приложения;
- оверлеи получают события раньше сцены;
- приложение может передать свой `SceneInput` или `SceneInput.none()` и
  обрабатывать события собственным `Listener` вокруг вьюпорта.

```dart
class SceneTapEvent {
  Offset get screenPosition;
  Size get viewportSize;
  int get buttons;
  bool get isPrimary;
  Ray get ray;
}
```

## 12. Кадр и подписки

```dart
typedef SceneFrameListener = void Function(Duration elapsed, double deltaSeconds);

controller.addFrameListener((elapsed, dt) {
  // логика игры после обновления движка
});
```

Порядок внутри кадра: `camera.update` → `dynamics.update` → разворот
билбордов → подписчики кадра → перерисовка. При `autoTick: false` кадр
ведёт приложение: `controller.update(dt)`.

## 13. Динамика `DynamicNodes`

```dart
typedef DynamicTick = void Function(DynamicObject object, double dt);
typedef DynamicEvent = void Function(DynamicObject object);
typedef SceneNodeBuilder = SceneNode Function();

class DynamicNodes {
  DynamicObject spawn({
    required String id,
    required SceneNode node,
    Vector3? position,
    double rotationY = 0,
    Duration? lifetime,
    int layer = 0,
    Object? userData,
    DynamicTick? onUpdate,
    DynamicEvent? onFinished,
    DynamicEvent? onEnteredFrame,
  });

  DynamicObject? byId(String id);
  void despawn(DynamicObject object);
  void clear();
  Iterable<DynamicObject> get objects;
  int get aliveCount;

  // синхронизация набора без пересоздания: обновляет по id, добавляет
  // недостающие, удаляет исчезнувшие
  void sync(String key, Iterable<DynamicEntry> entries);
}

class DynamicEntry {
  const DynamicEntry({
    required this.id,
    this.node,                     // готовая нода (разовое добавление)
    this.builder,                  // фабрика ноды (пул: нода переиспользуется)
    this.position,
    this.rotationY = 0,
    this.lifetime,
    this.layer = 0,
    this.userData,
    this.onUpdate,                 // зовётся и для уже существующих нод
  });
}

class DynamicObject {
  String get id;
  SceneNode get node;
  double get ageSeconds;
  Duration? lifetime;
  Duration? get remaining;         // до конца жизни, null — бессрочно
  double get remainingFactor;      // 1 → 0, удобно для затухания
  Vector3 get position;
  double get rotationY;
  Object? userData;
  bool get alive;
  void despawn();
}
```

Пример (маркер цели из pet_demo):

```dart
final marker = controller.dynamics.spawn(
  id: 'target',
  node: RingNode(radius: 0.3, color: Colors.cyan),
  position: Vector3(x, 0.07, z),
  lifetime: const Duration(milliseconds: 2500),
  onUpdate: (object, dt) => object.node.opacity = object.remainingFactor,
);
```

Пример (пул врагов из math_quest: `builder` переиспользует ноды,
`onUpdate` меняет материал у существующих, не пересоздавая их):

```dart
controller.dynamics.sync('enemies', [
  for (final enemy in frame.enemies)
    DynamicEntry(
      id: 'enemy:${enemy.index}',
      builder: () => SpriteNode(texture: enemyTexture(enemy.kind), billboard: true),
      position: enemy.worldPosition,
      userData: enemy,
      onUpdate: (object, dt) => object.node.material = enemyMaterial(enemy),
    ),
]);
```

## 14. Попадания и проекция

```dart
class RaycastOptions {
  const RaycastOptions({
    this.includeInvisible = false,
    this.skipNodeIds = const {},
    this.where,
    this.nearest = true,
  });
  final bool includeInvisible;
  final Set<String> skipNodeIds;
  final bool Function(SceneNode node)? where;
  final bool nearest;
}

class SceneHit {
  SceneNode get node;
  FaceRef? get face;
  double get distance;
  Vector3 get worldPoint;
  Vector3 get localPoint;
  Vector3? get worldNormal;
}

class FaceRef {
  String get key;
  ModelNode get node;
  ModelMaterial? get material;      // документный материал грани
}
```

Материал грани — документный (`ModelMaterial`); рантайм-подмена материала
грани выполняется через `ModelNode.setFaceMaterial`.

Примеры:

```dart
// выбрать врага тапом
final hit = controller.raycast(tap.screenPosition, options: const RaycastOptions(where: isEnemy));
// выделить грань в редакторе
final faceHit = controller.raycast(position, options: RaycastOptions(skipNodeIds: selectedIds));
// спроецировать подписи
final screen = controller.worldToScreen(node.worldPosition);
```

## 15. Контроллер качества `QualityController`

```dart
class QualityController extends ChangeNotifier {
  QualityController({
    QualitySettings? floor,
    QualitySettings? ceiling,
    double targetFps = 60,
    bool adaptive = true,
    QualityPolicy policy = const QualityPolicy(),
  });

  Future<void> initialize();        // определение бэкенда и возможностей
  GpuBackend get backend;
  DeviceCapabilities get capabilities;

  QualitySettings get settings;
  void apply(QualitySettings settings);   // ручная установка (адаптация пауза)
  void applyPreset(QualityPreset preset);

  bool get adaptive;
  set adaptive(bool value);
  FrameStats get stats;
  Stream<QualityChange> get changes;

  void attach(SceneController scene);
  void reportFrame(Duration frameTime);
  void pauseAdaptation(Object reason);
  void resumeAdaptation(Object reason);
  void dispose();
}

class QualitySettings {
  final double renderScale;
  final bool ssao;
  final bool shadows;
  final int shadowCascades;
  final double shadowDistance;
  final SceneAntiAliasing antiAliasing;
  final FilterQuality filterQuality;
  final int maxPointLights;          // -1 — без ограничения; 0 — выключить лампы
  final bool sustainedPerformance;   // подсказка приложению
  QualitySettings copyWith({...});
}

enum QualityPreset { low, medium, high, auto }
// QualityPreset.recommendedFor(backend, capabilities) — рекомендованный
// пресет, как GameQualitySettings.recommendedFor в v1.

class QualityPolicy {
  const QualityPolicy({
    this.window = const Duration(seconds: 2),
    this.cooldown = const Duration(seconds: 3),
    this.downscaleFpsFactor = 0.9,
    this.upscaleFpsFactor = 1.15,
    this.upscaleHold = const Duration(seconds: 3),
    this.steps = QualityStep.fullLadder,
  });
}

class FrameStats {
  double get fps;
  Duration get averageFrameTime;
  Duration get p95FrameTime;
  Duration? get averageRasterTime;
  int get jankFrames;
}

class QualityChange {
  QualitySettings get from;
  QualitySettings get to;
  String get reason;
}
```

Поведение:

- замер: `FrameTiming` (build/raster/jank) и кадры вьюпорта
  (`reportFrame`);
- лестница шагов по умолчанию:
  `renderScale → antiAliasing → maxPointLights → ssao → shadows/cascades`,
  один шаг за раз, с паузой между изменениями; порядок настраивается через
  `QualityPolicy.steps`;
- `maxPointLights` — «отключение сложного света»: движок оставляет самые
  важные точечные источники (`LightNode.importance`), остальные выключает;
- гистерезис: понижение быстрее, повышение медленнее;
- пол и потолок: `floor`/`ceiling`;
- пауза на загрузку, скриншоты, замеры (`pauseAdaptation(reason)`);
- `sustainedPerformance` — только подсказка; платформенный канал применяет
  приложение.

Связка с вьюпортом: `attach(scene)` запоминает контроллер качества в сцене
(`scene.quality`); вьюпорт, у которого сцена с подключённым контроллером
качества, сам передаёт длительности кадров. Приложение может звать
`reportFrame` и вручную.

Пример:

```dart
final quality = QualityController();
await quality.initialize();
quality.attach(controller);   // controller.quality == quality

SceneViewport(controller: controller); // кадры попадают в quality

quality.applyPreset(QualityPreset.auto);
```

## 16. Ресурсы, документ и загрузка

```dart
class SceneResources {
  String get projectName;
  bool get writable;
  List<String> get modelIds;
  ModelData? model(String id);
  List<String> get textureKeys;
  List<String> get spriteKeys;
  List<String> get loadErrors;
  Model3dEntry? gltfEntry(String name);

  Future<Uint8List?> readBytes(String relativePath);
  // запись модели — через controller.project.saveModel
  Future<SceneTexture?> texture(String key);   // textures/
  Future<SceneTexture?> sprite(String key);    // sprites/
  SceneTexture? peekTexture(String key);       // готовое, без загрузки
  SceneTexture? peekSprite(String key);

  void setGltfTextureOverride(String name, Map<String, Uint8List> overrides);
  void clearGltfTextureOverride(String name);
  void invalidate();
  Future<void> reload();
}

class ProjectStore {
  List<String> get modelIds;
  ModelData createModel({String? id, String? name});
  Future<void> saveModel(ModelData model);
  Future<void> deleteModel(String id);
  Future<void> renameModel(String id, String newId);
}
// controller.project — операции над моделями проекта (редактор).

enum SceneLoadPhase { idle, project, models, resources, geometry, bake, ready, error }

class SceneLoadStatus {
  SceneLoadPhase get phase;
  double get fraction;              // 0..1
  String get label;
  List<SceneLoadError> get errors;
  bool get isReady;
  bool get hasError;
}

class SceneLoadError {
  String get resource;
  String get reason;
}
```

Типы документа `ModelData`, `ModelObject`, `ModelMaterial`, `ModelMeta`,
`ModelLight`, `ModelLighting`, `ModelGroup`, `ModelSize`, `ModelSide`
остаются публичными без изменений (экспорт `package:pet_engine_v2/models.dart`).

### 16.1. Владение и освобождение

- Контроллер владеет: ресурсной сессией (`SceneResources`), библиотекой
  шейдеров, динамикой, уровнем, камерой, светом, построенным
  `applyLighting`, и нодами, добавленными через `add`.
- `SceneController.dispose()` останавливает кадр, снимает свет и уровень,
  очищает динамику, освобождает ресурсы и шейдеры. Текстуры и материалы,
  созданные приложением, контроллер не трогает — их освобождает владелец.
- `SceneNode.detach()` — нода остаётся живой (`inScene = false`), владеет
  ею приложение; повторный `controller.add(node)` возвращает её на сцену.
  `SceneNode.remove()` — отключает и освобождает ноду.
- `dynamics.despawn` возвращает ноду в пул (не освобождает);
  `dynamics.clear()` отправляет в пул все объекты; пул освобождается в
  `dispose`.
- `SceneViewport` контроллером не владеет. Порядок завершения: убрать
  вьюпорт из дерева, затем `controller.dispose()`.
- `SceneResources`, `ProjectStore` и `ShaderLibrary` принадлежат контроллеру
  и отдельно не освобождаются.

## 17. Уровневый слой и навигация

Публичные механизмы переносятся без изменений поведения:

- **Уровень:** `LevelGrid`, `LevelCell`, `LevelRegion`, `LevelOpening`,
  `ConstructionModel`, `BuildOps`, `LevelValidator`, `LevelIssue`,
  `LevelBaker`, `LevelBakePlan`, `LevelBakeOptions`, `LevelBakeResult`,
  `LevelLoader`, `LevelLoadResult`, `LevelExtraResource`, `LevelLoadEvent`,
  `ScenePlacement`, `SceneLayout`, `metaKind*`, `metaName*`.
- **Навигация:** `NavigationSource`, `BoxMarkupNavigation`, `PathPlanner`,
  `PathFollower`, `NavPath`.
- **Частицы:** `ParticleConfig`, `ParticlePresets`, `ParticleField`.
- **Координаты:** `chunkWorld`, `cellWorld`, `modelXFromWorld`,
  `modelZFromWorld`, `facingAngle`, `screenParallelYaw`.

### 17.1. Определения типов, переносимых из v1

```dart
class SceneFog {                     // бывший GameFog
  const SceneFog({required Color color, double start = 0, double end = 200, double minOpacity = 0, double maxOpacity = 1});
}

enum SceneAntiAliasing { none, msaa, fxaa, auto }   // бывший GameAntiAliasing

class CameraProjection {
  CameraProjection({required double fovY, double near = 0.05, double far = 300});
  double fovY; double near; double far;
}

enum Direction { north, east, south, west }
enum AnimationType { none, step, turn }
enum SpriteOrientation { vertical, floor, ceiling, wall }
enum BillboardFacing { spherical, axisLocked, velocityStretched, screenParallel }
enum SpriteBlendMode { opaque, alpha, additive }
enum SpriteFieldFacing { spherical, screenParallel, velocityStretched }

class GltfAnimInfo {
  GltfAnimInfo({required this.fullName, required this.shortName, required this.duration});
  String fullName; String shortName; double duration;
  static String shortOf(String name);
}

class ParticleDef { /* спрайт частицы: key, assetPath, weight — как в v1 */ }
enum ParticleKind { /* как в v1 */ }

class ParticleConfig {
  ParticleConfig({
    required ParticleKind kind,
    required List<ParticleDef> sprites,
    int maxPerCell = 8, int fullDensityRings = 2, int viewRadius = 12,
    double spawnChance = 1.0, double bottomY = -0.8, double topY = 6.5,
    double fallSpeedMin = 0, double fallSpeedMax = 0,
    double swayAmp = 0, double swayFreq = 0, double windSpeed = 0,
    double slantDrift = 0, double opacity = 1.0, double rotationSpin = 0,
    double velocityStretch = 0, bool crisp = true, bool additive = false,
    int blendOrder = 0, Vector3? windDirection, Vector3? color,
  });
  ParticleConfig withIntensity(double intensity);
}

class ParticlePresets {
  static ParticleConfig get streetRain;
  static ParticleConfig get passSnow;
  static ParticleConfig get passWind;
  static ParticleConfig get caveWindStreak;
  static ParticleConfig get caveWindGlint;
}

class ParticleField {
  ParticleField({required int rows, required int columns, Vector3? origin, bool Function(int row, int column)? allowsCell, int seed = 0});
}

class SpriteFieldSprite {
  const SpriteFieldSprite({required String key, required String assetPath});
}
class SpriteFieldInstance {
  const SpriteFieldInstance({required String spriteKey, required double x, required double y, required double z, required double width, required double height, double rotation = 0, Vector4? color, Vector3? velocity});
}
class GroundFogSprite {
  const GroundFogSprite({required String key, required String assetPath});
}
class FogInstance {
  const FogInstance({required String spriteKey, required double x, required double y, required double z, required double width, required double height, double rotation = 0, double opacity = 1});
}

class SpriteAtlas { /* кадры, число колонок/строк, фильтрация */ }
SceneTexture buildSpriteAtlas(List<ui.Image> frames, {int columns = 1});

class LevelExtraResource {
  LevelExtraResource(String label, Future<void> Function() load);
}
typedef BakedMaterialHook = void Function(SceneMaterial material, {required bool sprite, required List<String> tags});
class LevelBakeOptions {
  const LevelBakeOptions({bool collectStats = false, BakedMaterialHook? onMaterial});
}
class LevelLoadResult {
  LevelBakeResult? get baked;
  List<SceneLoadError> get errors;
  Duration get elapsed;
  bool get hasErrors;
}
enum LevelLoadEventKind { started, progress, finished }
class LevelLoadEvent {
  LevelLoadEventKind get kind;
  SceneLoadPhase get phase;
  double get fraction;
  String get label;
  LevelLoadResult? get result;
}
```

### 17.2. Хелперы документа и геометрии

Переносятся как публичные функции; нужны редактору для привязки к граням,
контуров выделения, csg и габаритов:

- `faceNormalAt(object, faceKey)`, `faceCenterAt(object, faceKey)`,
  `parallelToFaceAngles(object, faceKey)`, `faceCorners(object, faceKey)`;
- `objectRotation(object)`, `sourceAnchor(object)`,
  `unionAabbResolved(...)`, `gltfFootprintBox(...)`,
  `modelRefCubeProxy(...)`;
- `facesOf(object)`, `csgLeavesOf(object)`, `moveExpansion(...)`.

Пример загрузки уровня (math_quest):

```dart
final result = await controller.loadLevel(
  floorModel,
  extraResources: [
    LevelExtraResource('трава и туман', () async {
      await grass.prepare();
      await fog.prepare();
    }),
  ],
  options: LevelBakeOptions(onMaterial: applyFloorMaterial),
);
if (result.baked != null) {
  controller.mountLevel(result.baked!, offset: floorModelMountOffset(floorModel.data));
}
```

## 18. Инструменты

- **Скриншоты:** `SceneViewport.capture({double? pixelRatio})` возвращает
  PNG (`Future<Uint8List>`) содержимого вьюпорта; `pixelRatio` по умолчанию —
  значение вьюпорта, затем `devicePixelRatio`. Плюс `saveScreenshot`,
  `analyzePlaceholders`, `analyzeFrameContent`, `PlaceholderReport`,
  `FrameContentReport` — как в v1.
- **Build-hook:** `petBuildMaterials` из `package:pet_engine_v2/build_hooks.dart`.
- **Диплинки:** остаются в приложениях, движок не участвует.

## 19. Примеры для четырёх проектов

### demo

```dart
final controller = SceneController();
await controller.open(source);
await controller.loadModelData(feature.build(context), id: feature.id);
controller.camera = FlyCameraController()..frameModel(controller.model!);

SceneViewport(
  controller: controller,
  input: CameraInput(),
  overlayBuilder: (context, size) => feature.overlay?.call(context),
  onTap: (tap) => feature.handleTap(tap),
);
controller.addFrameListener((elapsed, dt) => feature.tick(dt));
```

### scene_editor

```dart
final controller = SceneController(mergeStatic: false);
await controller.open(projectSource);
await controller.loadModelData(appState.model!);

SceneViewport(
  controller: controller,
  views: [SceneViewSpec.main(), SceneViewSpec.overlay(), SceneViewSpec.top()],
  input: EditorInput(appState),
);

final hit = controller.raycast(position, options: RaycastOptions(skipNodeIds: appState.selectedIds));
if (hit?.face != null) appState.selectFace(hit!.node.id, hit.face!.key);
```

### pet_demo

```dart
final cat = controller.nodesOfType<ModelNode>().firstWhere((node) => node.gltfName == 'cat');
final navigation = BoxMarkupNavigation.fromModel(controller.model!, radius: 0.2);
final planner = PathPlanner(navigation, step: 0.1);
final follower = PathFollower(source: navigation, position: ..., heading: ...);

controller.addFrameListener((elapsed, dt) {
  follower.update(dt);
  cat.setWorldPlacement(x: follower.position.x, z: follower.position.y, rotY: petRotYFromHeading(follower.heading));
});
```

### math_quest

```dart
final controller = SceneController(mergeStatic: true);
final custom = MatrixCameraController(fovY: 75 * pi / 180, near: 0.05, far: 50);
controller.camera = custom;
controller.addFrameListener((elapsed, dt) {
  custom.matrix = cameraNodeTransformAnimated(...);
});
controller.dynamics.sync('enemies', ...);
```

## 20. Что удаляется после миграции

После перевода demo и редактора на этот API старые фасады удаляются из
публичного экспорта, а затем из кода: `GameScene`, `GameNode`,
`GameSceneView`, `GameCamera`, `FreeCameraController`, `GameViewController`,
`EngineScene`, `EngineNode`, `EngineMaterial`, `EngineTexture`,
`EngineMesh`, `EngineGeometry`, `EngineSceneView`, `DynamicWorld`,
`DynamicVisual`, `ModelRenderer`, `ScreenPicking`, `FmatManager`,
`FmatSlot`, `BillboardBatch`, `SpriteFieldLayer`, `GroundFogLayer`,
`ParticleLayer`, `StaticSkybox`, `GameQualitySettings`, `GameFog`,
`GameAntiAliasing`, `EngineFog`, `EngineAntiAliasing`. Их место занимают
типы из этого документа:

| Удаляется | Заменяется |
|---|---|
| `StaticSkybox` | `SkyboxNode` + `SkyboxImageLayer` |
| `GameQualitySettings` | `QualitySettings` / `QualityPreset` |
| `GameFog`, `EngineFog` | `SceneFog` |
| `GameAntiAliasing`, `EngineAntiAliasing` | `SceneAntiAliasing` |
| `FreeCameraController`, `GameViewController` | `FlyCameraController`, `FirstPersonCameraController` |
| `BillboardBatch`, `SpriteFieldLayer`, `GroundFogLayer`, `ParticleLayer` | `BillboardBatchNode`, `SpriteFieldNode`, `GroundFogNode`, `ParticleNode` |

Таблица соответствий целиком — `docs/migration.md`.

## 21. Детали, уточняемые при реализации

1. Имя ресурсной сессии (`SceneResources`) и остаётся ли
   `GameResourceManager` как внутренний тип.
2. Точные сигнатуры `GeometryBuilder` (полный набор операций) и
   `LineGeometry`.
3. Состав `DeviceCapabilities` (ядра, память, платформа) и способ его
   определения.
4. Политика адаптации качества по умолчанию (пороговые значения) —
   уточняется тестами на реальных устройствах.
5. Форма `SceneViewSpec` при нескольких камерах (пока одна активная
   камера на контроллер).
6. Точные формулы слоёв неба (проекция солнца/луны, покрытие облаков) —
   уточняются на demo.
