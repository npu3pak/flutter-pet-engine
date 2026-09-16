import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Общие помощники группы «Многогранники».
///
/// Здесь показаны два способа собрать [PolyMesh] своими руками:
/// - [extrudeProfile] — призма из плоского профиля (вогнутый контур тоже
///   подходит: грани могут быть n-угольными);
/// - [plateWithHole] — плита с прямоугольным отверстием (у грани есть
///   `holes`).
///
/// Конвенции движка, которые важно соблюдать при ручной сборке:
/// - внешний контур грани обходится ПРОТИВ часовой стрелки, если смотреть
///   на грань снаружи (тогда нормаль Ньюэлла смотрит наружу);
/// - вершины общие: соседние грани ссылаются на одни и те же индексы;
/// - отверстие — отдельный контур в `PolyFace.holes`, его ориентацию
///   триангулятор приводит сам.

/// Объект документа с многогранником в локальной рамке: y = 0 — основание,
/// x/z центрируются так, как их задал автор сети.
doc.ModelObject polyhedronObject({
  required String id,
  required String name,
  required PolyMesh mesh,
  double x = 0,
  double y = 0,
  double z = 0,
  double rotY = 0,
  doc.ModelMaterial? material,
  Map<String, doc.ModelMaterial>? faces,
}) =>
    doc.ModelObject(
      id: id,
      name: name,
      kind: doc.polyhedronKind,
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      mesh: mesh,
      material: material,
      faces: faces,
    );

/// Призма: плоский профиль [profile] (точки (x, z)) вытянут вверх на
/// [height]. Профиль задаётся обходом, при котором наружная нормаль нижней
/// грани смотрит вниз, а боковые грани — наружу; в примерах это обход
/// «по часовой стрелке, если смотреть сверху».
///
/// Грань `+y` — верх (обратный обход профиля), `-y` — низ, боковые грани —
/// `side_0`, `side_1`, … (по одному n-угольнику на ребро профиля).
PolyMesh extrudeProfile({
  required List<vm.Vector2> profile,
  required double height,
}) {
  final count = profile.length;
  final vertices = <vm.Vector3>[
    for (final p in profile) vm.Vector3(p.x, 0, p.y),
    for (final p in profile) vm.Vector3(p.x, height, p.y),
  ];
  return PolyMesh(
    vertices: vertices,
    faces: [
      // Низ: профиль как задан — нормаль смотрит вниз.
      PolyFace(
        key: '-y',
        outer: PolyLoop(vertices: [for (var i = 0; i < count; i++) i]),
      ),
      // Верх: обратный обход — нормаль смотрит вверх.
      PolyFace(
        key: '+y',
        outer: PolyLoop(
          vertices: [for (var i = count - 1; i >= 0; i--) count + i],
        ),
      ),
      // Боковые стенки: (низ_i, верх_i, верх_след, низ_след).
      for (var i = 0; i < count; i++)
        PolyFace(
          key: 'side_$i',
          outer: PolyLoop(
            vertices: [
              i,
              count + i,
              count + (i + 1) % count,
              (i + 1) % count,
            ],
          ),
        ),
    ],
  );
}

/// Плита [width]×[depth] толщиной [thickness] с прямоугольным отверстием
/// [holeWidth]×[holeDepth] по центру. Верх и низ — грани с `holes`, стенки
/// отверстия — отдельные четырёхугольные грани `hole_0`…, наружные стенки —
/// `outer_0`…. Локальная рамка: основание на y = 0, центр в (0, 0).
PolyMesh plateWithHole({
  required double width,
  required double depth,
  required double thickness,
  required double holeWidth,
  required double holeDepth,
}) {
  final hx = width / 2, hz = depth / 2;
  final ix = holeWidth / 2, iz = holeDepth / 2;
  final vertices = <vm.Vector3>[
    // 0..3 — внешний контур, низ.
    vm.Vector3(-hx, 0, -hz),
    vm.Vector3(hx, 0, -hz),
    vm.Vector3(hx, 0, hz),
    vm.Vector3(-hx, 0, hz),
    // 4..7 — внешний контур, верх.
    vm.Vector3(-hx, thickness, -hz),
    vm.Vector3(hx, thickness, -hz),
    vm.Vector3(hx, thickness, hz),
    vm.Vector3(-hx, thickness, hz),
    // 8..11 — контур отверстия, низ.
    vm.Vector3(-ix, 0, -iz),
    vm.Vector3(ix, 0, -iz),
    vm.Vector3(ix, 0, iz),
    vm.Vector3(-ix, 0, iz),
    // 12..15 — контур отверстия, верх.
    vm.Vector3(-ix, thickness, -iz),
    vm.Vector3(ix, thickness, -iz),
    vm.Vector3(ix, thickness, iz),
    vm.Vector3(-ix, thickness, iz),
  ];
  return PolyMesh(
    vertices: vertices,
    faces: [
      PolyFace(
        key: '-y',
        outer: PolyLoop(vertices: const [0, 1, 2, 3]),
        holes: [PolyLoop(vertices: const [8, 9, 10, 11])],
      ),
      PolyFace(
        key: '+y',
        outer: PolyLoop(vertices: const [7, 6, 5, 4]),
        holes: [PolyLoop(vertices: const [12, 13, 14, 15])],
      ),
      // Наружные стенки.
      for (var i = 0; i < 4; i++)
        PolyFace(
          key: 'outer_$i',
          outer: PolyLoop(
            vertices: [i, 4 + i, 4 + (i + 1) % 4, (i + 1) % 4],
          ),
        ),
      // Стенки отверстия: обход обратный, чтобы нормаль смотрела внутрь
      // отверстия (наружу от материала).
      for (var i = 0; i < 4; i++)
        PolyFace(
          key: 'hole_$i',
          outer: PolyLoop(
            vertices: [8 + i, 8 + (i + 1) % 4, 12 + (i + 1) % 4, 12 + i],
          ),
        ),
    ],
  );
}
