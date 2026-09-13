import 'app_log.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// Template for the «По шаблону» («Create from template») button: builds a
/// full-fledged fenced house model (the `house_preset` family) of any
/// reasonable size and shape. Specification:
/// `docs/house_chunk_generator.md`.
///
/// Coordinate conventions (model-local, matching the authored presets):
/// the origin sits at the CENTER of the bottom-left cell; cell centers land
/// on integers; an object's `pos` is the center of its base at height y and
/// the cuboid grows up by `h` (`dims {w, h, d}`); a vertical plane spans
/// y..y+d with 0.01 thickness and faces +z locally (rotY turns it).
enum HouseShape { rect, u, h }

extension HouseShapeLabel on HouseShape {
  String get label => switch (this) {
        HouseShape.rect => 'Дом',
        HouseShape.u => 'Особняк П',
        HouseShape.h => 'Особняк Н',
      };

  /// Default outer width for the dialog when switching shapes.
  int get defaultW => this == HouseShape.rect ? 5 : 9;

  /// Default outer depth for the dialog when switching shapes.
  int get defaultD => this == HouseShape.rect ? 3 : 7;

  /// Allowed outer width range.
  (int, int) get wRange => this == HouseShape.rect ? (3, 10) : (7, 13);

  /// Allowed outer depth range.
  (int, int) get dRange => this == HouseShape.rect ? (2, 6) : (5, 9);
}

/// Asset keys for the template (file names in the project's folders).
/// Empty string = no asset → the element falls back to a default color.
class HouseAssets {
  final String houseWall; //  textures/ — body/wings/connector
  final String fence; //      textures/ — all fence segments
  final String fenceSprite; // sprites/  — all fence segments
  //                    (mutually exclusive with [fence]; sprite wins)
  final String trim; //       textures/ — belt courses + corner blocks
  final String trimSprite; // sprites/  — belt courses + corner blocks
  //                      (mutually exclusive with [trim]; sprite wins)
  final String roof; //       textures/ — roof slabs
  final String window; //     sprites/  — window planes
  final String door; //       sprites/  — door plane

  const HouseAssets({
    this.houseWall = '',
    this.fence = '',
    this.fenceSprite = '',
    this.trim = '',
    this.trimSprite = '',
    this.roof = '',
    this.window = '',
    this.door = '',
  });
}

/// Builds a fenced house model per `docs/house_chunk_generator.md`:
/// - model `w = outerW + 2`, `l = outerD + 2`, `h = ⌈floors × 1.5⌉`;
/// - body shapes: rect (solid body), u (two FULL-DEPTH wings + a north slab
///   between them, courtyard open to the south), h (two full-depth wings +
///   a central connector, north/south courtyards);
/// - fence ring with a 2-cell south gap in front of the door;
/// - window rows per floor (`N = max(1, wallLen − 2)`, evenly spread with a
///   0.7 inset; the ground floor drops windows closer than 0.825 to the
///   door). The renderer rotates plane geometry MIRRORED to the map
///   convention, so side walls (east/west) use rotY 270/90 (opposite of the
///   naive table) and every rotY ≠ 0 plane gets a flipX material;
/// - belt courses at every floor boundary (per exposed wall face: rect 4,
///   u 10, h 12 strips), corner blocks on the 4 outer corners, segmented
///   roofs without overlaps.
/// (The game-only walkability fields — entries/front/blocked — are not
/// generated: `model_v1` has no use for them.)
ModelData generateHouseModel({
  required String id,
  required String name,
  required HouseShape shape,
  required int outerW,
  required int outerD,
  required int floors,
  bool fence = true,
  bool beltCourses = true,
  bool cornerBlocks = true,
  HouseAssets assets = const HouseAssets(),
}) {
  assert(floors >= 1 && floors <= 5, 'floors must be 1..5');
  final (minW, maxW) = shape.wRange;
  final (minD, maxD) = shape.dRange;
  assert(outerW >= minW && outerW <= maxW, 'outerW must be $minW..$maxW');
  assert(outerD >= minD && outerD <= maxD, 'outerD must be $minD..$maxD');

  logStage(
    'template',
    'generate id=$id name=$name shape=$shape ${outerW}x$outerD floors=$floors '
        'fence=$fence belts=$beltCourses corners=$cornerBlocks',
  );

  final w = outerW + 2;
  final l = outerD + 2;
  final height = floors * 1.5;
  final h = height.ceil();
  final centerX = (w - 1) / 2;
  final centerZ = (l - 1) / 2;
  final connectorRow = outerD ~/ 2 + 1;

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
    String spriteKey = '',
    double tileScale = 1.0,
  }) {
    final mat = spriteKey.isNotEmpty
        ? ModelMaterial(
            type: MaterialType.sprite,
            key: spriteKey,
            stretch: 'tile',
            tileScale: tileScale,
          )
        : texKey.isEmpty
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

  ModelObject plane(
    String name,
    double x,
    double y,
    double z, {
    double rotY = 0,
    double ww = 0.75,
    double dd = 0.75,
    String spriteKey = '',
    bool flipX = false,
  }) {
    final mat = spriteKey.isEmpty
        ? ModelMaterial(type: MaterialType.color, color: const [60, 60, 60])
        : ModelMaterial(
            type: MaterialType.sprite,
            key: spriteKey,
            flipX: flipX,
          );
    return ModelObject(
      id: nextId(),
      name: name,
      kind: 'plane',
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      dims: {'w': ww, 'd': dd, 'vertical': 1},
      material: mat,
    );
  }

  // ── body ──────────────────────────────────────────────────────────────

  switch (shape) {
    case HouseShape.rect:
      final body = cuboid('House', centerX, 0, centerZ, outerW, height,
          outerD, texKey: assets.houseWall);
      objects.add(body);
    case HouseShape.u:
      // Two FULL-DEPTH wings + a north slab between them (no overlaps: the
      // slab ends at the wings' inner faces).
      final body = cuboid('House', centerX, 0, 1.0, outerW - 2, height, 1,
          texKey: assets.houseWall);
      final w1 = cuboid('Wing', 1.0, 0, centerZ, 1, height, outerD,
          texKey: assets.houseWall);
      final w2 = cuboid('Wing', outerW.toDouble(), 0, centerZ, 1, height,
          outerD,
          texKey: assets.houseWall);
      objects.addAll([body, w1, w2]);
    case HouseShape.h:
      final w1 = cuboid('Wing', 1.0, 0, centerZ, 1, height, outerD,
          texKey: assets.houseWall);
      final w2 = cuboid('Wing', outerW.toDouble(), 0, centerZ, 1, height,
          outerD,
          texKey: assets.houseWall);
      final conn = cuboid('Connector', centerX, 0, connectorRow.toDouble(),
          outerW, height, 1,
          texKey: assets.houseWall);
      objects.addAll([w1, w2, conn]);
  }
  logStage('template', 'phase body: ${objects.length} objects');

  // ── fence ring (south gap [centerX−1, centerX+1] in front of the door) ─

  if (fence) {
    final f1 = cuboid('fence', centerX, 0, 0, w - 1, 1, 0.1,
        texKey: assets.fence, spriteKey: assets.fenceSprite);
    final f2 = cuboid('fence', 0, 0, centerZ, 0.1, 1, l - 1,
        texKey: assets.fence, spriteKey: assets.fenceSprite);
    final f3 = cuboid('fence', w - 1.0, 0, centerZ, 0.1, 1, l - 1,
        texKey: assets.fence, spriteKey: assets.fenceSprite);
    final f4 = cuboid('fence', (centerX - 1) / 2, 0, l - 1.0, centerX - 1, 1,
        0.1,
        texKey: assets.fence, spriteKey: assets.fenceSprite);
    final f5 = cuboid('fence', (w + centerX) / 2, 0, l - 1.0, w - centerX - 2,
        1, 0.1,
        texKey: assets.fence, spriteKey: assets.fenceSprite);
    objects.addAll([f1, f2, f3, f4, f5]);
    for (final f in [f1, f2, f3, f4, f5]) {
      group('Fence', f.id);
    }
  }
  logStage('template', 'phase fence: ${objects.length} objects');

  // ── corner blocks (4 outer corners of the bounds) ─────────────────────

  if (cornerBlocks) {
    final blocks = [
      for (final (bx, bz) in [
        (0.5, 0.5),
        (w - 1.5, 0.5),
        (w - 1.5, l - 1.5),
        (0.5, l - 1.5),
      ])
        cuboid('Corner block', bx, 0, bz, 0.25, height, 0.25,
            texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
    ];
    objects.addAll(blocks);
    for (final b in blocks) {
      group('Corner blocks', b.id);
    }
  }
  logStage('template', 'phase corner blocks: ${objects.length} objects');

  // ── belt courses (one band per floor boundary) ────────────────────────
  //
  // Per-shape strips that hug EVERY exposed wall face (0.125 outward):
  // rect — 4 perimeter strips; u — 10 (north slab N/S, wing caps ×4, sides
  // ×2, wing inner faces ×2); h — 12 (wing caps ×4, sides ×2, connector
  // faces ×2, wing inner faces split around the connector ×4). Perpendicular
  // strips overlap by 0.25×0.25 at corners — the overlap cubes self-hide
  // (interior faces are occluded, opposite faces are backface-culled).

  if (beltCourses) {
    for (var f = 1; f < floors; f++) {
      final y = f * 1.5;
      final belts = switch (shape) {
        HouseShape.rect => [
            cuboid('Belt course', centerX, y, 0.5, outerW, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', centerX, y, l - 1.5, outerW, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', 0.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 1.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
          ],
        HouseShape.u => [
            // North slab, north face (z=0.5) and courtyard face (z=1.5).
            cuboid('Belt course', centerX, y, 0.5, outerW - 2, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', centerX, y, 1.5, outerW - 2, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Wing north caps (z=0.5) and south caps (z=l−1.5).
            cuboid('Belt course', 1.0, y, 0.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', outerW.toDouble(), y, 0.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', 1.0, y, l - 1.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', outerW.toDouble(), y, l - 1.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Sides (x=0.5 / w−1.5) and wing INNER faces (x=1.5 / w−2.5),
            // full depth.
            cuboid('Belt course', 0.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 1.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', 1.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 2.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
          ],
        HouseShape.h => [
            // Wing north caps — two strips, no crossbar over the courtyard.
            cuboid('Belt course', 1.0, y, 0.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', outerW.toDouble(), y, 0.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Wing south caps.
            cuboid('Belt course', 1.0, y, l - 1.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', outerW.toDouble(), y, l - 1.5, 1, 0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Sides, full depth.
            cuboid('Belt course', 0.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 1.5, y, centerZ, 0.25, 0.25, outerD,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Connector faces (the main building over the entrance).
            cuboid('Belt course', centerX, y, connectorRow - 0.5, outerW - 2,
                0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', centerX, y, connectorRow + 0.5, outerW - 2,
                0.25, 0.25,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            // Wing inner faces, split around the connector (north/south
            // courtyard segments).
            cuboid('Belt course', 1.5, y, connectorRow / 2, 0.25, 0.25,
                connectorRow - 1,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 2.5, y, connectorRow / 2, 0.25, 0.25,
                connectorRow - 1,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', 1.5, y, (connectorRow + l - 1) / 2, 0.25,
                0.25, l - connectorRow - 2,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
            cuboid('Belt course', w - 2.5, y, (connectorRow + l - 1) / 2,
                0.25, 0.25, l - connectorRow - 2,
                texKey: assets.trim, spriteKey: assets.trimSprite, tileScale: 0.25),
          ],
      };
      objects.addAll(belts);
      for (final b in belts) {
        group('Belt courses', b.id);
      }
    }
  }
  logStage('template', 'phase belts: ${objects.length} objects');

  // ── windows + door ────────────────────────────────────────────────────

  /// Centers of a window row on a wall spanning [min]..[max] (world
  /// coordinates along the wall axis): `N = len − 2` windows evenly from
  /// `min + 0.7` to `max − 0.7` (a single one in the middle for N = 1).
  List<double> spreadCenters(double min, double max, int n) {
    if (n <= 0) return const [];
    if (n == 1) return [(min + max) / 2];
    final lo = min + 0.7;
    final hi = max - 0.7;
    return [for (var k = 0; k < n; k++) lo + k * (hi - lo) / (n - 1)];
  }

  /// One floor's window row on a wall segment. [wallMin]/[wallMax] span the
  /// wall along its axis; [fixedPos] is the coordinate on the other axis;
  /// [alongX] says whether the wall runs along x (planes at z = fixedPos).
  /// The renderer rotates plane geometry mirrored to the map convention, so
  /// side walls (east/west) take rotY 270/90 and every rotY ≠ 0 plane gets
  /// a flipX material (see `docs/house_chunk_generator.md`).
  void addWindowRow({
    required double yBase,
    required double wallMin,
    required double wallMax,
    required double fixedPos,
    required bool alongX,
    required double rotY,
    required bool dropNearDoor,
  }) {
    final len = wallMax - wallMin;
    final n = ((len - 2).round()).clamp(1, 64);
    final doorX = centerX;
    for (final c in spreadCenters(wallMin, wallMax, n)) {
      if (dropNearDoor && (c - doorX).abs() < 0.825) continue;
      objects.add(alongX
          ? plane('window', c, yBase, fixedPos,
              rotY: rotY, spriteKey: assets.window, flipX: rotY != 0)
          : plane('window', fixedPos, yBase, c,
              rotY: rotY, spriteKey: assets.window, flipX: rotY != 0));
      group('windows', objects.last.id);
    }
  }

  // Door: 0.75 × 1.2 on the south facade on the centerX axis.
  final door = switch (shape) {
    HouseShape.rect => plane('door', centerX, 0.1, l - 1.45,
        ww: 0.75, dd: 1.2, spriteKey: assets.door),
    HouseShape.u => plane('door', centerX, 0.1, 1.55,
        ww: 0.75, dd: 1.2, spriteKey: assets.door),
    HouseShape.h => plane('door', centerX, 0.1, connectorRow + 0.55,
        ww: 0.75, dd: 1.2, spriteKey: assets.door),
  };
  objects.add(door);

  for (var f = 0; f < floors; f++) {
    final yBase = 0.5 + f * 1.5;
    switch (shape) {
      case HouseShape.rect:
        // South facade (rotY 0), full width.
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: w - 1.5,
          fixedPos: l - 1.45,
          alongX: true,
          rotY: 0,
          dropNearDoor: f == 0,
        );
      case HouseShape.u:
        // North slab, north wall (rotY 180) — over the slab span only.
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: w - 2.5,
          fixedPos: 0.45,
          alongX: true,
          rotY: 180,
          dropNearDoor: false,
        );
        // North slab, courtyard face (rotY 0).
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: w - 2.5,
          fixedPos: 1.55,
          alongX: true,
          rotY: 0,
          dropNearDoor: f == 0,
        );
        // Wings' outer walls (west rotY 90, east rotY 270 — the renderer
        // mirrors the rotation, so the naive table is inverted).
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: l - 1.5,
          fixedPos: 0.45,
          alongX: false,
          rotY: 90,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: l - 1.5,
          fixedPos: w - 1.45,
          alongX: false,
          rotY: 270,
          dropNearDoor: false,
        );
        // Wings' inner faces into the courtyard (west rotY 270, east
        // rotY 90) — windows only, no doors in the wings. The row skips the
        // north slab's band (z 0.5..1.5) — the slab covers it.
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: l - 1.5,
          fixedPos: 1.55,
          alongX: false,
          rotY: 270,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: l - 1.5,
          fixedPos: w - 2.55,
          alongX: false,
          rotY: 90,
          dropNearDoor: false,
        );
      case HouseShape.h:
        // Wings' outer walls (west rotY 90, east rotY 270), full depth.
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: l - 1.5,
          fixedPos: 0.45,
          alongX: false,
          rotY: 90,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: l - 1.5,
          fixedPos: w - 1.45,
          alongX: false,
          rotY: 270,
          dropNearDoor: false,
        );
        // Connector faces into the courtyards — only over the courtyard
        // gap x 1.5..w−2.5 (the wings cover the connector's ends).
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: w - 2.5,
          fixedPos: connectorRow + 0.55,
          alongX: true,
          rotY: 0,
          dropNearDoor: f == 0,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: 1.5,
          wallMax: w - 2.5,
          fixedPos: connectorRow - 0.55,
          alongX: true,
          rotY: 180,
          dropNearDoor: false,
        );
        // Wings' inner faces into the courtyards (west rotY 270, east
        // rotY 90) — split around the connector, which covers the middle
        // of the faces. Windows only, no doors in the wings.
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: connectorRow - 0.5,
          fixedPos: 1.55,
          alongX: false,
          rotY: 270,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: connectorRow + 0.5,
          wallMax: l - 1.5,
          fixedPos: 1.55,
          alongX: false,
          rotY: 270,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: 0.5,
          wallMax: connectorRow - 0.5,
          fixedPos: w - 2.55,
          alongX: false,
          rotY: 90,
          dropNearDoor: false,
        );
        addWindowRow(
          yBase: yBase,
          wallMin: connectorRow + 0.5,
          wallMax: l - 1.5,
          fixedPos: w - 2.55,
          alongX: false,
          rotY: 90,
          dropNearDoor: false,
        );
    }
  }
  logStage('template', 'phase windows+door: ${objects.length} objects');

  // ── roofs (segments without overlaps — no z-fighting at the seams) ────

  switch (shape) {
    case HouseShape.rect:
      objects.add(cuboid('roof', centerX, height, centerZ, outerW + 0.5, 0.25,
          outerD + 0.5, texKey: assets.roof));
    case HouseShape.u:
      // Wing slabs, full depth; the north slab trimmed to the gap between
      // the wings (its overhang is covered by the wing slabs).
      objects.add(cuboid('roof', centerX, height, 1.0, outerW - 2.5, 0.25,
          1.5, texKey: assets.roof));
      objects.add(cuboid('roof', 1.0, height, centerZ, 1.5, 0.25, outerD + 0.5,
              texKey: assets.roof));
      objects.add(cuboid('roof', outerW.toDouble(), height, centerZ, 1.5,
          0.25, outerD + 0.5, texKey: assets.roof));
    case HouseShape.h:
      objects.add(cuboid('roof', 1.0, height, centerZ, 1.5, 0.25, outerD + 0.5,
              texKey: assets.roof));
      objects.add(cuboid('roof', outerW.toDouble(), height, centerZ, 1.5,
          0.25, outerD + 0.5, texKey: assets.roof));
      objects.add(cuboid('roof', w / 2, height, connectorRow.toDouble(),
          outerW - 1.5, 0.25, 1.5, texKey: assets.roof));
  }
  logStage('template', 'phase roofs: ${objects.length} objects');

  // ── game-only walkability (entries/front/blocked) — not part of model_v1 ──

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
    'done ${w}x$l h=$h objects=${objects.length} '
        'groups=${data.groups.length}',
  );
  return data;
}
