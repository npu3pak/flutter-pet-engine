import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'feature_registry.dart';

/// Палитра сцен-примеров (sRGB).
abstract final class SceneColors {
  static const red = [214, 76, 76];
  static const green = [96, 186, 112];
  static const blue = [86, 132, 214];
  static const orange = [230, 150, 70];
  static const purple = [166, 106, 214];
  static const cyan = [86, 196, 204];
  static const yellow = [222, 196, 88];
  static const gray = [150, 156, 166];
  static const white = [235, 235, 235];
}

/// Объект сцены-примера (короткая обёртка над [doc.ModelObject]).
doc.ModelObject sceneObject({
  required String id,
  required String name,
  required String kind,
  double x = 0,
  double y = 0,
  double z = 0,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
  Map<String, num>? dims,
  doc.ModelMaterial? material,
  Map<String, doc.ModelMaterial>? faces,
  String? tag,
  String? op,
  List<String>? operands,
  String refModelId = '',
  double scale = 1,
  doc.ModelSize? refSize,
  String gltfName = '',
  List<double>? gltfBounds,
  String anim = '',
}) {
  return doc.ModelObject(
    id: id,
    name: name,
    kind: kind,
    x: x,
    y: y,
    z: z,
    rotX: rotX,
    rotY: rotY,
    rotZ: rotZ,
    dims: dims,
    material: material,
    faces: faces,
    tag: tag,
    op: op,
    operands: operands,
    refModelId: refModelId,
    scale: scale,
    refSize: refSize,
    gltfName: gltfName,
    gltfBounds: gltfBounds,
    anim: anim,
  );
}

/// Цветовой материал.
doc.ModelMaterial colorMat(List<int> rgb, {String side = 'outer'}) =>
    doc.ModelMaterial(
      type: doc.MaterialType.color,
      color: List.of(rgb),
      side: side,
    );

/// Материал с текстурой из `textures/` (ключ с расширением файла).
doc.ModelMaterial textureMat(
  String key, {
  String stretch = 'stretch',
  double tileScale = 1,
  int uvDir = 0,
  bool flipX = false,
  bool flipY = false,
  String side = 'outer',
}) => doc.ModelMaterial(
  type: doc.MaterialType.texture,
  key: key,
  stretch: stretch,
  tileScale: tileScale,
  uvDir: uvDir,
  flipX: flipX,
  flipY: flipY,
  side: side,
);

/// Материал со спрайтом из `sprites/` (ключ с расширением файла).
doc.ModelMaterial spriteMat(
  String key, {
  int uvDir = 0,
  bool flipX = false,
  bool flipY = false,
  String side = 'outer',
}) => doc.ModelMaterial(
  type: doc.MaterialType.sprite,
  key: key,
  uvDir: uvDir,
  flipX: flipX,
  flipY: flipY,
  side: side,
);

/// Первая текстура проекта с именем, начинающимся на [prefix] (ключ с
/// расширением `.png`); [fallback] — если проект не открыт.
String pickTexture(
  FeatureBuildContext context,
  String prefix, {
  String fallback = 'wallpaper_beige.png',
}) {
  for (final key in context.textureKeys) {
    if (key.startsWith(prefix)) return '$key.png';
  }
  return fallback;
}

/// Первый спрайт проекта с именем, начинающимся на [prefix].
String pickSprite(
  FeatureBuildContext context,
  String prefix, {
  String fallback = 'window_1.png',
}) {
  for (final key in context.spriteKeys) {
    if (key.startsWith(prefix)) return '$key.png';
  }
  return fallback;
}

/// Первый ключ спрайта проекта с именем, начинающимся на [prefix]
/// (с расширением `.png`); null, если проект не открыт.
String? projectSpriteKey(SceneResources? project, String prefix) {
  if (project == null) return null;
  for (final key in project.spriteKeys) {
    if (key.startsWith(prefix)) return '$key.png';
  }
  if (project.spriteKeys.isEmpty) return null;
  return '${project.spriteKeys.first}.png';
}

/// Создаёт отдельный корень фичи в сцене — для объектов, которые фича
/// добавляет сама (пакеты спрайтов, эффекты). При смене фичи управление
/// снимает корень через [detachFeatureRoot].
GroupNode attachFeatureRoot(SceneController controller, String name) {
  final root = GroupNode(name: name);
  controller.add(root);
  return root;
}

/// Убирает корень фичи из сцены.
void detachFeatureRoot(SceneNode root) {
  root.remove();
}

/// Переводит точку из координат модели в мировые: мир зеркалит X модели и
/// сдвигает X/Z на половину сетки. Нужно панелям, которые добавляют
/// содержимое (спрайты, динамические объекты) прямо в сцену.
vm.Vector3 featureWorldPoint(
  SceneController? controller,
  double x,
  double y,
  double z,
) {
  final size = controller?.model?.size;
  if (size == null) return vm.Vector3(x, y, z);
  final world = chunkWorld(x, z, size.w, size.l);
  return vm.Vector3(world.x, y, world.z);
}

/// Клетка камеры (row, column) по клетке модели (r, c): мир зеркалит X и
/// сдвигает X/Z, поэтому row = r − originZ, column = c − originX. Без
/// [startCell] берётся центр сцены.
(int, int) cameraCellFor(SceneController? controller, (int, int)? startCell) {
  final size = controller?.model?.size;
  final originX = size == null ? 0.0 : (size.w - 1) / 2;
  final originZ = size == null ? 0.0 : (size.l - 1) / 2;
  final modelRow = startCell?.$1.toDouble() ?? originZ;
  final modelColumn = startCell?.$2.toDouble() ?? originX;
  return ((modelRow - originZ).round(), (modelColumn - originX).round());
}
