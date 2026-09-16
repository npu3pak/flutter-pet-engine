import 'dart:math' as math;

import 'app_log.dart';
import 'package:pet_engine/pet_engine.dart';

/// Template for the «Комната» («Room») kind of the «По шаблону» button:
/// builds an indoor room model — a hollow box whose four walls carry
/// selectable openings (blank/window/entrance per side) — with a floor and
/// a ceiling slab and optional table/bed furniture. Ported from the
/// chunk_builder's room generator; the game-only parts (meta_pass markers,
/// entries/front/blocked passability) are not part of `model_v1` and are
/// not generated.
///
/// Coordinate conventions (model-local, matching the house template):
/// the origin sits at the CENTER of the bottom-left cell; cell centers land
/// on integers; a cuboid's `pos` is the center of its base at height y and
/// it grows up by `h` (`dims {w, h, d}`); a vertical plane spans y..y+d
/// (0.01 thick) and faces +z locally (rotY turns it).
enum WallType { blank, window, entrance }

extension WallTypeLabel on WallType {
  String get label => switch (this) {
        WallType.blank => 'Глухая',
        WallType.window => 'Окно',
        WallType.entrance => 'Вход',
      };
}

/// The four room walls, labelled for the UI.
enum RoomSide { north, east, south, west }

extension RoomSideLabel on RoomSide {
  String get label => switch (this) {
        RoomSide.north => 'Северная',
        RoomSide.east => 'Восточная',
        RoomSide.south => 'Южная',
        RoomSide.west => 'Западная',
      };
}

/// Asset keys for the template (file names in the project's folders).
/// Empty string = no asset → the element falls back to a default color.
class RoomAssets {
  final String wall; //    textures/ — wall segments
  final String floor; //   textures/ — floor slab
  final String ceiling; // textures/ — ceiling slab
  final String window; //  sprites/  — window planes (mask cutout; empty →
  //                   the opening stays bare — a broken window)
  final String table; //   textures/ — table top + legs
  final String bed; //     textures/ — bed block

  const RoomAssets({
    this.wall = '',
    this.floor = '',
    this.ceiling = '',
    this.window = '',
    this.table = '',
    this.bed = '',
  });
}

// ── Geometry constants (metres) ─────────────────────────────────────────

/// Floor slab thickness (sits on y = 0).
const roomFloorH = 0.06;

/// Ceiling slab thickness.
const roomCeilingH = 0.15;

/// Window opening defaults (width/height of the rectangle cut in the wall,
/// and its bottom above the floor) — overridable per generation.
const roomWindowW = 0.75;
const roomWindowH = 0.7;
const roomWindowSill = 0.5;

// Table: 4 square legs at the sides of a thin top.
const roomTableLeg = 0.06;
const roomTableLegH = 0.68;
const roomTableTopH = 0.05;
const roomTableW = 0.9;
const roomTableD = 0.5;

// Bed: a plain 0.25-high block, 1.0 long.
const roomBedLen = 1.0;
const roomBedW = 0.55;
const roomBedH = 0.25;

/// Builds an indoor room model:
/// - [width]/[depth] are the room's OUTER footprint cells (1..32, min 1 —
///   a corridor). The thin wall panels hug the footprint border from the
///   INSIDE: a panel of [wallThickness] eats that much off the outer edge
///   of the border cells (its inner face sits [wallThickness] from the
///   border), the model is never enlarged to fit the walls;
/// - each wall is one of blank / window (an opening of [windowWidth]×
///   [windowHeight] whose bottom sits [windowSill] above the floor,
///   covered by a mask-cutout window plane when [RoomAssets.window] is
///   set) / entrance (an opening of [doorWidthCells] cells and
///   [doorHeight] height with a header above it when lower than the wall);
/// - a floor slab and a ceiling slab (whole footprint) top the box;
/// - optional table and bed furniture as regular model objects (groups
///   «Стол» / «Кровать»), free to move or delete.
ModelData generateRoomModel({
  required String id,
  required String name,
  required int width,
  required int depth,
  double wallHeight = 2.2,
  double wallThickness = 0.2,
  required Map<RoomSide, WallType> walls,
  double doorHeight = 1.2,
  int doorWidthCells = 1,
  double windowWidth = roomWindowW,
  double windowHeight = roomWindowH,
  double windowSill = roomWindowSill,
  bool table = false,
  bool bed = false,
  RoomAssets assets = const RoomAssets(),
}) {
  assert(width >= 1 && width <= 32, 'width must be 1..32');
  assert(depth >= 1 && depth <= 32, 'depth must be 1..32');
  assert(wallHeight >= 1.2 && wallHeight <= 3.2, 'wallHeight must be 1.2..3.2');
  assert(
      wallThickness >= 0.1 && wallThickness <= 0.5, 'wallThickness must be 0.1..0.5');
  assert(
      doorWidthCells >= 1 &&
          doorWidthCells <= math.min(2, math.min(width, depth)),
      'doorWidthCells must be 1..min(2, width, depth)');
  assert(doorHeight >= 0.6 && doorHeight <= wallHeight,
      'doorHeight must be 0.6..wallHeight');
  assert(windowWidth >= 0.3 && windowWidth <= 2.0,
      'windowWidth must be 0.3..2.0');
  assert(windowHeight >= 0.3 && windowHeight <= 2.0,
      'windowHeight must be 0.3..2.0');
  assert(windowSill >= 0.0 && windowSill <= 3.2, 'windowSill must be 0..3.2');
  assert(walls.length == RoomSide.values.length, 'walls must cover all 4 sides');

  // The room IS the model footprint: width×depth cells, walls on the
  // border cells from the inside.
  final w = width;
  final l = depth;
  logStage(
    'template',
    'room: id=$id name=$name ${w}x$l '
        'wallH=$wallHeight t=$wallThickness '
        'walls=${walls.map((k, v) => MapEntry(k.name, v.name))} '
        'doorH=$doorHeight doorCells=$doorWidthCells '
        'window=${windowWidth}x$windowHeight sill=$windowSill '
        'table=$table bed=$bed assets=${[assets.wall, assets.floor, assets.ceiling, assets.window, assets.table, assets.bed]}',
  );

  final h = (wallHeight + roomCeilingH).ceil();
  final t = wallThickness;
  final cx = (w - 1) / 2;
  final cz = (l - 1) / 2;

  // Wall runs hug the border from the INSIDE: a panel of thickness t runs
  // along the full border edge (from corner to corner, so the perpendicular
  // panels overlap at the corners and the box is closed) and its inner face
  // sits t off the border — the wall eats t off the outer edge of the
  // border cells instead of enlarging the footprint.
  final runA = -0.5;
  final runBX = w - 0.5;
  final runBZ = l - 0.5;
  final doorH = math.min(doorHeight, wallHeight);

  final objects = <ModelObject>[];
  final groups = <String, List<String>>{};
  var n = 0;
  String nextId() => 'obj_${++n}';
  void group(String g, String objId) {
    (groups[g] ??= []).add(objId);
  }

  ModelObject cuboid(
    String name,
    num x,
    num y,
    num z,
    num ww,
    num hh,
    num dd, {
    String texKey = '',
    double tileScale = 1.0,
  }) {
    final mat = texKey.isEmpty
        ? null
        : ModelMaterial(
            type: MaterialType.texture,
            key: texKey,
            stretch: 'tile',
            tileScale: tileScale,
          );
    return ModelObject(
      id: nextId(),
      name: name,
      kind: 'cuboid',
      x: x.toDouble(),
      y: y.toDouble(),
      z: z.toDouble(),
      dims: {'w': ww, 'h': hh, 'd': dd},
      material: mat,
    );
  }

  /// One cuboid piece of a wall: [along0]..[along1] along the wall axis,
  /// vertical [y0]..[y1], thickness center at [perp].
  void seg(String nm, double along0, double along1, double y0, double y1,
      double perp,
      {required bool alongX}) {
    final len = along1 - along0;
    final hh = y1 - y0;
    if (len < 1e-6 || hh < 1e-6) return;
    final mid = (along0 + along1) / 2;
    objects.add(alongX
        ? cuboid(nm, mid, y0, perp, len, hh, t, texKey: assets.wall)
        : cuboid(nm, perp, y0, mid, t, hh, len, texKey: assets.wall));
  }

  /// The full-height span of a wall segment along [a0]..[a1].
  void segFull(String nm, double a0, double a1, double perp,
      {required bool alongX}) {
    seg(nm, a0, a1, 0, wallHeight, perp, alongX: alongX);
  }

  /// Builds one wall: [along0]..[along1] along its axis, opening center
  /// [gapC], plane position [perp]; [type] decides the opening shape.
  void buildWall({
    required String sideName,
    required bool alongX,
    required double along0,
    required double along1,
    required double perp,
    required WallType type,
  }) {
    if (type == WallType.blank) {
      segFull('Стена $sideName', along0, along1, perp, alongX: alongX);
      return;
    }
    final gapC = alongX ? cx : cz;
    if (type == WallType.entrance) {
      final half = doorWidthCells / 2.0;
      final gL = gapC - half;
      final gR = gapC + half;
      segFull('Стена $sideName', along0, gL, perp, alongX: alongX);
      segFull('Стена $sideName', gR, along1, perp, alongX: alongX);
      if (doorH < wallHeight - 1e-6) {
        seg('Стена $sideName', gL, gR, doorH, wallHeight, perp,
            alongX: alongX);
      }
      return;
    }
    // Window: the wall is cut by a rectangle
    // [winB..winT] × gapC ± windowWidth/2. When the requested sill does not
    // fit (a header of at least 0.15 must stay above the window), the
    // window is pushed down so it hugs the ceiling.
    final gL = gapC - windowWidth / 2;
    final gR = gapC + windowWidth / 2;
    final winB =
        math.min(windowSill, math.max(0.05, wallHeight - windowHeight - 0.15));
    final winT = math.min(winB + windowHeight, wallHeight - 0.15);
    segFull('Стена $sideName', along0, gL, perp, alongX: alongX);
    segFull('Стена $sideName', gR, along1, perp, alongX: alongX);
    seg('Стена $sideName', gL, gR, 0, winB, perp, alongX: alongX);
    if (winT < wallHeight - 1e-6) {
      seg('Стена $sideName', gL, gR, winT, wallHeight, perp, alongX: alongX);
    }
    // The opening stays bare (broken window) until a window sprite exists.
    if (assets.window.isEmpty) return;
    // Plane orientation follows the house template's empirical table (the
    // renderer mirrors plane rotations): south 0, north 180, east 270,
    // west 90; every rotY ≠ 0 plane gets a flipX material. side 'both'
    // keeps the mask-cutout window visible from inside the room.
    final rotY = switch (sideName) {
      'Север' => 180.0,
      'Юг' => 0.0,
      'Запад' => 90.0,
      _ => 270.0,
    };
    final mat = ModelMaterial(
      type: MaterialType.sprite,
      key: assets.window,
      flipX: rotY != 0,
      side: 'both',
    );
    final window = ModelObject(
      id: nextId(),
      name: 'Окно $sideName',
      kind: 'plane',
      x: alongX ? gapC : perp,
      y: winB,
      z: alongX ? perp : gapC,
      rotY: rotY,
      dims: {'w': windowWidth, 'd': winT - winB, 'vertical': 1},
      material: mat,
    );
    objects.add(window);
    group('Окна', window.id);
  }

  // ── walls ─────────────────────────────────────────────────────────────

  buildWall(
    sideName: 'Север',
    alongX: true,
    along0: runA,
    along1: runBX,
    perp: -0.5 + t / 2,
    type: walls[RoomSide.north]!,
  );
  buildWall(
    sideName: 'Юг',
    alongX: true,
    along0: runA,
    along1: runBX,
    perp: l - 0.5 - t / 2,
    type: walls[RoomSide.south]!,
  );
  buildWall(
    sideName: 'Запад',
    alongX: false,
    along0: runA,
    along1: runBZ,
    perp: -0.5 + t / 2,
    type: walls[RoomSide.west]!,
  );
  buildWall(
    sideName: 'Восток',
    alongX: false,
    along0: runA,
    along1: runBZ,
    perp: w - 0.5 - t / 2,
    type: walls[RoomSide.east]!,
  );
  logStage('template', 'room walls: ${objects.length} objects');

  // ── floor + ceiling slabs (whole footprint — the walls sit on top) ────

  objects.add(cuboid('Пол', cx, 0, cz, w, roomFloorH, l,
      texKey: assets.floor));
  objects.add(cuboid(
      'Потолок', cx, wallHeight, cz, w, roomCeilingH, l,
      texKey: assets.ceiling));
  logStage('template', 'room slabs: ${objects.length} objects');

  // ── furniture (decor — free to move or delete) ────────────────────────

  if (table) {
    final legOffsetX = roomTableW / 2 - roomTableLeg / 2;
    final legOffsetZ = roomTableD / 2 - roomTableLeg / 2;
    final top = cuboid('Стол', cx, roomTableLegH, cz, roomTableW,
        roomTableTopH, roomTableD,
        texKey: assets.table);
    objects.add(top);
    group('Стол', top.id);
    for (final (sx, sz) in [
      (-legOffsetX, -legOffsetZ),
      (legOffsetX, -legOffsetZ),
      (-legOffsetX, legOffsetZ),
      (legOffsetX, legOffsetZ),
    ]) {
      final leg = cuboid('Ножка', cx + sx, 0, cz + sz, roomTableLeg,
          roomTableLegH, roomTableLeg,
          texKey: assets.table);
      objects.add(leg);
      group('Стол', leg.id);
    }
    logStage('template', 'room table: ${objects.length} objects');
  }

  if (bed) {
    // Against the first wall without an entrance (the headboard side), so
    // the bed never blocks a door opening; all-entrance rooms fall back to
    // the north wall.
    var bedSide = RoomSide.north;
    for (final s in RoomSide.values) {
      if (walls[s] != WallType.entrance) {
        bedSide = s;
        break;
      }
    }
    final alongX =
        bedSide == RoomSide.north || bedSide == RoomSide.south;
    final axisLen = alongX ? w.toDouble() : l.toDouble();
    final wallC = alongX ? cx : cz;
    // All-entrance rooms shift the bed off the door axis; keep the block
    // inside the footprint.
    final clear = walls[bedSide] == WallType.entrance;
    final alongC = clear
        ? (wallC + doorWidthCells + 0.3).clamp(0.5, axisLen - 0.5)
        : wallC;
    // Flush against the wall's INNER face (t off the border), 0.02 away.
    final off = 0.02 + roomBedW / 2;
    final (bx, bz) = switch (bedSide) {
      RoomSide.north => (alongC, -0.5 + t + off),
      RoomSide.south => (alongC, l - 0.5 - t - off),
      RoomSide.west => (-0.5 + t + off, alongC),
      RoomSide.east => (w - 0.5 - t - off, alongC),
    };
    final b = cuboid('Кровать', bx, 0, bz, alongX ? roomBedLen : roomBedW,
        roomBedH, alongX ? roomBedW : roomBedLen,
        texKey: assets.bed);
    objects.add(b);
    group('Кровать', b.id);
    logStage('template', 'room bed: ${objects.length} objects');
  }

  final data = ModelData(
    id: id,
    name: name,
    size: ModelSize(w: w, l: l, h: h),
    objects: objects,
    groups: [
      for (final (i, e) in groups.entries.indexed)
        ModelGroup(id: 'group_${i + 1}', name: e.key, members: e.value),
    ],
  );
  logStage(
    'template',
    'room done ${w}x$l h=$h objects=${objects.length} '
        'groups=${data.groups.length}',
  );
  return data;
}
