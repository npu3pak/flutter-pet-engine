import 'dart:math' as math;

import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

/// Сетка уровня-примера: две комнаты и дверной проём между ними.
const List<String> levelShellRows = [
  '#########',
  '#.......#',
  '#.......#',
  '#####.###',
  '#.......#',
  '#.......#',
  '#########',
];

/// Зазор между соседними телами оболочки: убирает совпадающие грани и
/// мерцание стен. На глаз незаметен (2 мм).
const double kLevelGap = 0.002;

/// Оболочка уровня из клеток: полы и потолки только под открытыми клетками,
/// твёрдые клетки — целыми блоками на всю высоту, стены по границе открытых
/// клеток, дверная перемычка над проходом, окно-спрайт и декор в одной
/// комнате. Все тела разведены зазором [kLevelGap], поэтому совпадающих
/// граней нет (проверяет [countCoincidentFaces]).
ConstructionModel buildLevelShell({
  bool withDecor = true,
  bool withWindow = true,
}) {
  const wallH = 3.0;
  const wallT = 0.12;
  const slabT = 0.04;
  const doorTop = 2.2;
  const gap = kLevelGap;

  final grid = LevelGrid.fromRows(levelShellRows);
  final model = ConstructionModel(id: 'level_shell', name: 'Оболочка уровня');
  model.data.size = ModelSize(w: grid.cols, l: grid.rows, h: 3);

  final floorMat = ModelMaterial(
    type: MaterialType.color,
    color: [96, 112, 96],
  );
  final wallMat = ModelMaterial(
    type: MaterialType.color,
    color: [186, 176, 152],
  );
  final ceilMat = ModelMaterial(type: MaterialType.color, color: [72, 76, 88]);
  final solidMat = ModelMaterial(
    type: MaterialType.color,
    color: [120, 112, 104],
  );
  // Декор первой комнаты: коврик, стол и растение — разные цвета, чтобы их
  // нельзя было перепутать (коврик лежит, мебель и растение стоят).
  final rugMat = ModelMaterial(
    type: MaterialType.color,
    color: [168, 74, 66],
  );
  final tableMat = ModelMaterial(
    type: MaterialType.color,
    color: [150, 104, 62],
  );
  final plantMat = ModelMaterial(
    type: MaterialType.color,
    color: [86, 140, 78],
  );
  final recessMat = ModelMaterial(
    type: MaterialType.color,
    color: [38, 42, 50],
  );

  var id = 0;
  ModelObject block(
    double x,
    double y,
    double z,
    double w,
    double h,
    double d,
    ModelMaterial mat,
    String tag,
  ) => model.add(
    ModelObject(
      id: 'e${id++}',
      name: tag,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      dims: {'w': w, 'h': h, 'd': d},
      material: ModelMaterial.copy(mat),
    ),
    tag: tag,
  );

  final wallInset = gap;
  final floorInset = 2 * gap;

  // Оконный проём в северной стене первой комнаты: открытая клетка (1, 4),
  // за ней твёрдая клетка (0, 4) с тёмной нишей.
  const windowRow = 1;
  const windowCol = 4;
  const windowHalf = 0.4;
  const windowBottom = 0.6;
  const windowTop = 1.4;
  const recessBack = 0.05;

  /// Кубок по границам в координатах модели (для косяков и ниши).
  void solidPiece(
    double minX,
    double maxX,
    double minY,
    double maxY,
    double minZ,
    double maxZ,
    ModelMaterial mat,
    String tag,
  ) => block(
    (minX + maxX) / 2,
    minY,
    (minZ + maxZ) / 2,
    maxX - minX,
    maxY - minY,
    maxZ - minZ,
    mat,
    tag,
  );

  // Твёрдые клетки — целыми блоками; открытые — пол и потолок.
  for (final ((r, c), cell) in grid.cells) {
    if (cell.isSolid) {
      if (r == windowRow - 1 && c == windowCol) {
        // Клетка за окном: вместо целого блока — рамка с нишей, чтобы за
        // проёмом была видна тёмная глубина, а не сплошная стена.
        final blockMinX = c - (1 - 2 * wallInset) / 2;
        final blockMaxX = c + (1 - 2 * wallInset) / 2;
        final blockMinZ = r - (1 - 2 * wallInset) / 2;
        final blockMaxZ = r + (1 - 2 * wallInset) / 2;
        final openMinX = c - windowHalf;
        final openMaxX = c + windowHalf;
        solidPiece(
          blockMinX,
          openMinX - gap,
          gap,
          wallH - gap,
          blockMinZ + recessBack + gap,
          blockMaxZ,
          solidMat,
          'solid',
        );
        solidPiece(
          openMaxX + gap,
          blockMaxX,
          gap,
          wallH - gap,
          blockMinZ + recessBack + gap,
          blockMaxZ,
          solidMat,
          'solid',
        );
        solidPiece(
          openMinX,
          openMaxX,
          gap,
          windowBottom - gap,
          blockMinZ + recessBack + gap,
          blockMaxZ,
          solidMat,
          'solid',
        );
        solidPiece(
          openMinX,
          openMaxX,
          windowTop + gap,
          wallH - gap,
          blockMinZ + recessBack + gap,
          blockMaxZ,
          solidMat,
          'solid',
        );
        solidPiece(
          openMinX,
          openMaxX,
          windowBottom,
          windowTop,
          blockMinZ,
          blockMinZ + recessBack,
          recessMat,
          'window_recess',
        );
      } else {
        block(
          c.toDouble(),
          gap,
          r.toDouble(),
          1 - 2 * wallInset,
          wallH - 2 * gap,
          1 - 2 * wallInset,
          solidMat,
          'solid',
        );
      }
    } else if (cell.isOpen) {
      block(
        c.toDouble(),
        0,
        r.toDouble(),
        1 - 2 * floorInset,
        slabT,
        1 - 2 * floorInset,
        floorMat,
        'floor',
      );
      block(
        c.toDouble(),
        wallH,
        r.toDouble(),
        1 - 2 * floorInset,
        slabT,
        1 - 2 * floorInset,
        ceilMat,
        'ceiling',
      );
    }
  }

  // Стены по границе «открытая клетка — не открытая», с зазором от соседей.
  // Углы подрезаются, чтобы перпендикулярные стены не пересекались
  // (иначе их торцы и низ совпадают и поверхность мерцает).
  void wall(double x, double z, double w, double d) =>
      block(x, slabT + gap, z, w, wallH - slabT - 2 * gap, d, wallMat, 'wall');

  /// Часть стены с заданными границами по X и высоте (для оконного проёма).
  void wallPiece(
    double minX,
    double maxX,
    double z,
    double minY,
    double maxY,
  ) => block(
    (minX + maxX) / 2,
    minY,
    z,
    maxX - minX,
    maxY - minY,
    wallT,
    wallMat,
    'wall',
  );

  bool wallAt(int r, int c, String side) {
    if (grid.tryCellAt(r, c)?.isOpen != true) return false;
    final (dr, dc) = switch (side) {
      'north' => (-1, 0),
      'south' => (1, 0),
      'west' => (0, -1),
      _ => (0, 1),
    };
    return grid.tryCellAt(r + dr, c + dc)?.isOpen != true;
  }

  for (final ((r, c), cell) in grid.cells) {
    if (!cell.isOpen) continue;
    if (wallAt(r, c, 'north')) {
      final x0 = c - 0.5 + (wallAt(r, c, 'west') ? wallT + 2 * gap : 2 * gap);
      final x1 = c + 0.5 - (wallAt(r, c, 'east') ? wallT + 2 * gap : 2 * gap);
      final z = r - 0.5 + wallT / 2 + gap;
      if (r == windowRow && c == windowCol) {
        // Стена с оконным проёмом: косяки, подоконник и перемычка.
        final openMinX = c - windowHalf;
        final openMaxX = c + windowHalf;
        final bottom = slabT + gap;
        final top = wallH - gap;
        wallPiece(x0, openMinX - gap, z, bottom, top);
        wallPiece(openMaxX + gap, x1, z, bottom, top);
        wallPiece(openMinX, openMaxX, z, bottom, windowBottom - gap);
        wallPiece(openMinX, openMaxX, z, windowTop + gap, top);
      } else if (x1 > x0) {
        wall((x0 + x1) / 2, z, x1 - x0, wallT);
      }
    }
    if (wallAt(r, c, 'south')) {
      final x0 = c - 0.5 + (wallAt(r, c, 'west') ? wallT + 2 * gap : 2 * gap);
      final x1 = c + 0.5 - (wallAt(r, c, 'east') ? wallT + 2 * gap : 2 * gap);
      if (x1 > x0) {
        wall((x0 + x1) / 2, r + 0.5 - wallT / 2 - gap, x1 - x0, wallT);
      }
    }
    if (wallAt(r, c, 'west')) {
      final z0 = r - 0.5 + (wallAt(r, c, 'north') ? wallT + 2 * gap : 2 * gap);
      final z1 = r + 0.5 - (wallAt(r, c, 'south') ? wallT + 2 * gap : 2 * gap);
      if (z1 > z0) {
        wall(c - 0.5 + wallT / 2 + gap, (z0 + z1) / 2, wallT, z1 - z0);
      }
    }
    if (wallAt(r, c, 'east')) {
      final z0 = r - 0.5 + (wallAt(r, c, 'north') ? wallT + 2 * gap : 2 * gap);
      final z1 = r + 0.5 - (wallAt(r, c, 'south') ? wallT + 2 * gap : 2 * gap);
      if (z1 > z0) {
        wall(c + 0.5 - wallT / 2 - gap, (z0 + z1) / 2, wallT, z1 - z0);
      }
    }
  }

  // Дверная перемычка над проходом (row 2 → row 3, col 5); по высоте чуть
  // ниже верха стен, чтобы её торцы не совпадали с их верхними гранями.
  block(
    5,
    doorTop,
    2.5,
    1 - 2 * floorInset,
    wallH - doorTop - 2 * gap,
    wallT,
    wallMat,
    'door',
  );

  if (withWindow) {
    // Окно на внутренней стороне северной стены первой комнаты.
    model.add(
      ModelObject(
        id: 'e${id++}',
        name: 'window',
        kind: 'plane',
        x: 4,
        y: 0.6,
        z: 0.5 + wallT + 2 * gap,
        dims: const {'w': 0.8, 'd': 0.8, 'vertical': 1},
        material: ModelMaterial(type: MaterialType.sprite, key: 'window_1.png'),
      ),
      tag: 'window',
    );
  }

  if (withDecor) {
    // Декор одной комнаты (row 1–2): коврик с отступом, стол и растение.
    // Коврик — плоская плитка (h ≈ 0) прямо перед стартовой камерой, стол и
    // растение — вертикальные тела по бокам, чтобы их не путали с ковриком.
    block(4, slabT + gap, 1, 0.7, 0.01, 0.7, rugMat, 'decor');
    block(2, slabT + gap, 1, 0.5, 0.5, 0.5, tableMat, 'decor');
    block(6, slabT + gap, 1, 0.3, 0.7, 0.3, plantMat, 'decor');
    block(2, slabT + gap, 5, 0.6, 0.5, 0.6, tableMat, 'decor');
  }

  return model;
}

/// Число пар совпадающих граней между кубами сцены: 0 означает, что оболочка
/// собрана без наложений (иначе поверхности мерцают).
int countCoincidentFaces(doc.ModelData model) {
  final boxes = [
    for (final object in model.objects)
      if (object.kind == 'cuboid') object,
  ];
  var pairs = 0;
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i];
      final b = boxes[j];
      final (ax0, ay0, az0) = a.minCorner();
      final (ax1, ay1, az1) = a.maxCorner();
      final (bx0, by0, bz0) = b.minCorner();
      final (bx1, by1, bz1) = b.maxCorner();
      final overlapX = _overlap(ax0, ax1, bx0, bx1);
      final overlapY = _overlap(ay0, ay1, by0, by1);
      final overlapZ = _overlap(az0, az1, bz0, bz1);
      if ((_close(ax1, bx0) ||
              _close(ax0, bx1) ||
              _close(ax0, bx0) ||
              _close(ax1, bx1)) &&
          overlapY &&
          overlapZ) {
        pairs++;
      }
      if ((_close(ay1, by0) ||
              _close(ay0, by1) ||
              _close(ay0, by0) ||
              _close(ay1, by1)) &&
          overlapX &&
          overlapZ) {
        pairs++;
      }
      if ((_close(az1, bz0) ||
              _close(az0, bz1) ||
              _close(az0, bz0) ||
              _close(az1, bz1)) &&
          overlapX &&
          overlapY) {
        pairs++;
      }
    }
  }
  return pairs;
}

bool _close(double a, double b) => (a - b).abs() < 1e-6;

bool _overlap(double a0, double a1, double b0, double b1) =>
    math.min(a1, b1) - math.max(a0, b0) > 1e-6;

/// Стресс-уровень: [rows]×[cols] открытых клеток с полом, потолком и стенами
/// по периметру; тела разведены зазором, как в оболочке.
ConstructionModel buildStressLevel({int rows = 100, int cols = 100}) {
  const wallH = 3.0;
  const wallT = 0.12;
  const slabT = 0.04;
  const gap = kLevelGap;
  final model = ConstructionModel(
    id: 'stress_level',
    name: 'Стресс $cols×$rows',
  );
  model.data.size = ModelSize(w: cols, l: rows, h: 3);
  final floorMat = ModelMaterial(
    type: MaterialType.color,
    color: [96, 112, 96],
  );
  final wallMat = ModelMaterial(
    type: MaterialType.color,
    color: [186, 176, 152],
  );
  final ceilMat = ModelMaterial(type: MaterialType.color, color: [72, 76, 88]);

  var id = 0;
  void cuboid(
    double x,
    double y,
    double z,
    double w,
    double h,
    double d,
    ModelMaterial mat,
    String tag,
  ) {
    model.add(
      ModelObject(
        id: 'e${id++}',
        name: tag,
        kind: 'cuboid',
        x: x,
        y: y,
        z: z,
        dims: {'w': w, 'h': h, 'd': d},
        material: ModelMaterial.copy(mat),
      ),
      tag: tag,
    );
  }

  final floorInset = 2 * gap;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      cuboid(
        c.toDouble(),
        0,
        r.toDouble(),
        1 - 2 * floorInset,
        slabT,
        1 - 2 * floorInset,
        floorMat,
        'floor',
      );
      cuboid(
        c.toDouble(),
        wallH,
        r.toDouble(),
        1 - 2 * floorInset,
        slabT,
        1 - 2 * floorInset,
        ceilMat,
        'ceiling',
      );
    }
  }
  void wall(double x, double z, double w, double d) =>
      cuboid(x, slabT + gap, z, w, wallH - slabT - 2 * gap, d, wallMat, 'wall');
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final north = r == 0;
      final south = r == rows - 1;
      final west = c == 0;
      final east = c == cols - 1;
      if (north) {
        final x0 = c - 0.5 + (west ? wallT + 2 * gap : 2 * gap);
        final x1 = c + 0.5 - (east ? wallT + 2 * gap : 2 * gap);
        if (x1 > x0) {
          wall((x0 + x1) / 2, -0.5 + wallT / 2 + gap, x1 - x0, wallT);
        }
      }
      if (south) {
        final x0 = c - 0.5 + (west ? wallT + 2 * gap : 2 * gap);
        final x1 = c + 0.5 - (east ? wallT + 2 * gap : 2 * gap);
        if (x1 > x0) {
          wall((x0 + x1) / 2, rows - 0.5 - wallT / 2 - gap, x1 - x0, wallT);
        }
      }
      if (west) {
        final z0 = r - 0.5 + (north ? wallT + 2 * gap : 2 * gap);
        final z1 = r + 0.5 - (south ? wallT + 2 * gap : 2 * gap);
        if (z1 > z0) {
          wall(-0.5 + wallT / 2 + gap, (z0 + z1) / 2, wallT, z1 - z0);
        }
      }
      if (east) {
        final z0 = r - 0.5 + (north ? wallT + 2 * gap : 2 * gap);
        final z1 = r + 0.5 - (south ? wallT + 2 * gap : 2 * gap);
        if (z1 > z0) {
          wall(cols - 0.5 - wallT / 2 - gap, (z0 + z1) / 2, wallT, z1 - z0);
        }
      }
    }
  }
  return model;
}

/// Сцены проекта, пригодные для ряда домов: непустые и с боксами
/// «непроходимо» (по ним определяется footprint).
List<ModelData> streetHouses(List<ModelData> models) {
  final houses = [
    for (final model in models)
      if (model.objects.isNotEmpty &&
          model.metas.any((meta) => meta.name == metaNameUnpassable))
        model,
  ];
  houses.sort((a, b) => a.id.compareTo(b.id));
  return houses;
}

/// Собирает ряд сцен (kind `model`) через [ScenePlacement]: позиции —
/// грид-точные, стыковка проверяется автоматически. Возвращает null, если
/// сцен нет или их footprint-ы накладываются. Рендер — ссылками на модели
/// каталога проекта.
ConstructionModel? buildSceneRow(
  List<ModelData> scenes, {
  required String id,
  required String name,
}) {
  if (scenes.isEmpty) return null;
  final placements = <ScenePlacement>[];
  var col = 0;
  for (final scene in scenes) {
    final p = ScenePlacement(scene: scene, originRow: 0, originCol: col);
    placements.add(p);
    col += p.footprintCols;
  }
  final layout = SceneLayout(placements);
  if (layout.overlaps.isNotEmpty) return null;

  final model = ConstructionModel(id: id, name: name);
  var maxRows = 0;
  var maxHeight = 1;
  for (final p in placements) {
    maxRows = p.footprintRows > maxRows ? p.footprintRows : maxRows;
    maxHeight = p.scene.size.h > maxHeight ? p.scene.size.h : maxHeight;
  }
  model.data.size = ModelSize(w: col, l: maxRows, h: maxHeight);
  var i = 0;
  for (final p in placements) {
    // kind `model` ставит центр сетки источника в `pos` (docs/model_format.md):
    // чтобы сцена заняла свои клетки из [ScenePlacement], привязка — центр
    // сцены, а не её клетка (0,0).
    model.add(
      ModelObject(
        id: 'scene_${++i}',
        name: p.scene.name,
        kind: modelRefKind,
        x: p.originCol + (p.scene.size.w - 1) / 2,
        y: 0,
        z: p.originRow + (p.scene.size.l - 1) / 2,
        rotY: p.rotY.toDouble(),
        refModelId: p.scene.id,
        refSize: ModelSize.copy(p.scene.size),
      ),
      bake: BakeMode.node,
      tag: 'scene',
    );
  }
  return model;
}

/// Ряд домов-сцен (улицы).
ConstructionModel? buildStreetsRow(List<ModelData> houses) =>
    buildSceneRow(houses, id: 'streets_row', name: 'Улица (дома)');
