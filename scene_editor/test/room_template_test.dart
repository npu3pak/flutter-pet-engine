import 'package:flutter_test/flutter_test.dart';

import 'package:scene_editor/src/services/room_template.dart';
import 'package:pet_engine/pet_engine.dart';

/// Default 7×7 room walls: north — window, south — entrance, east/west —
/// blank (what the dialog starts with). width/depth ARE the room footprint
/// — the room is the footprint, walls hug the border from the inside.
Map<RoomSide, WallType> defaultWalls() => {
      RoomSide.north: WallType.window,
      RoomSide.east: WallType.blank,
      RoomSide.south: WallType.entrance,
      RoomSide.west: WallType.blank,
    };

ModelData room({
  int w = 7,
  int l = 7,
  double wallH = 2.2,
  double t = 0.2,
  Map<RoomSide, WallType>? walls,
  double doorH = 1.2,
  int doorCells = 1,
  double winW = roomWindowW,
  double winH = roomWindowH,
  double winSill = roomWindowSill,
  bool table = false,
  bool bed = false,
  RoomAssets assets = const RoomAssets(),
}) =>
    generateRoomModel(
      id: 'model',
      name: 'Комната',
      width: w,
      depth: l,
      wallHeight: wallH,
      wallThickness: t,
      walls: walls ?? defaultWalls(),
      doorHeight: doorH,
      doorWidthCells: doorCells,
      windowWidth: winW,
      windowHeight: winH,
      windowSill: winSill,
      table: table,
      bed: bed,
      assets: assets,
    );

/// Whether [obj]'s solid volume covers the world point ([px], [py], [pz])
/// (axis-aligned cuboids at rotY 0; vertical planes are 0.01 thick).
bool covers(ModelObject obj, double px, double py, double pz) {
  final x = obj.x, y = obj.y, z = obj.z;
  if (obj.kind == 'plane') {
    final vertical = obj.flag('vertical');
    if (vertical) {
      final w = obj.dim('w', 0) / 2;
      final d = obj.dim('d', 0);
      return (px - x).abs() <= w && py >= y && py <= y + d && (pz - z).abs() <= 0.005;
    }
    return false;
  }
  if (obj.kind != 'cuboid') return false;
  final w = obj.dim('w', 0) / 2;
  final h = obj.dim('h', 0);
  final d = obj.dim('d', 0) / 2;
  return (px - x).abs() <= w && py >= y && py <= y + h && (pz - z).abs() <= d;
}

/// Whether ANY [objects] cuboid covers the point.
bool coveredBy(List<ModelObject> objects, double px, double py, double pz) =>
    objects.any((o) => covers(o, px, py, pz));

/// Whether ANY solid CUBOID covers the point (window planes excluded — the
/// plane sits exactly in its opening and would mask the hole).
bool wallCoveredBy(List<ModelObject> objects, double px, double py,
        double pz) =>
    objects
        .where((o) => o.kind == 'cuboid')
        .any((o) => covers(o, px, py, pz));

void main() {
  group('room shell', () {
    test('model is exactly the requested footprint; h = ⌈wallH + ceiling⌉',
        () {
      final c = room(w: 5, l: 9);
      expect(c.size.w, 5);
      expect(c.size.l, 9);
      expect(c.size.h, (2.2 + roomCeilingH).ceil());
      // Everything renders above floor level (0) and below the ceiling,
      // inside the footprint [-0.5, w-0.5] × [-0.5, l-0.5].
      for (final o in c.objects) {
        expect(o.y, greaterThanOrEqualTo(0), reason: '${o.name} below floor');
        expect(o.y + o.dim('h', o.dim('d', 1e9)), lessThanOrEqualTo(c.size.h),
            reason: '${o.name} above the model');
        expect(o.x + o.dim('w', 0) / 2, lessThanOrEqualTo(c.size.w - 0.5 + 1e-9),
            reason: '${o.name} outside the east border');
        expect(o.x - o.dim('w', 0) / 2, greaterThanOrEqualTo(-0.5 - 1e-9),
            reason: '${o.name} outside the west border');
        expect(o.z + o.dim('d', 0) / 2, lessThanOrEqualTo(c.size.l - 0.5 + 1e-9),
            reason: '${o.name} outside the south border');
        expect(o.z - o.dim('d', 0) / 2, greaterThanOrEqualTo(-0.5 - 1e-9),
            reason: '${o.name} outside the north border');
      }
    });

    test('floor + ceiling slabs cover the whole footprint', () {
      final c = room();
      final floor = c.objects.singleWhere((o) => o.name == 'Пол');
      expect(floor.kind, 'cuboid');
      expect(floor.dim('w', 0), closeTo(7, 1e-9));
      expect(floor.dim('d', 0), closeTo(7, 1e-9));
      expect(floor.y, 0);
      final ceiling = c.objects.singleWhere((o) => o.name == 'Потолок');
      expect(ceiling.y, closeTo(2.2, 1e-9));
      expect(ceiling.dim('h', 0), closeTo(roomCeilingH, 1e-9));
      expect(ceiling.dim('w', 0), closeTo(7, 1e-9));
    });

    test('walls hug the footprint border from the inside (t eats the cell)',
        () {
      final allBlank = {
        RoomSide.north: WallType.blank,
        RoomSide.east: WallType.blank,
        RoomSide.south: WallType.blank,
        RoomSide.west: WallType.blank,
      };
      final c = room(walls: allBlank);
      // North wall: full run x ∈ [-0.5, 6.5], panel z ∈ [-0.5, -0.3].
      final north = c.objects.singleWhere((o) => o.name == 'Стена Север');
      expect(north.dim('w', 0), closeTo(7, 1e-9));
      expect(north.dim('d', 0), closeTo(0.2, 1e-9));
      expect(north.z, closeTo(-0.4, 1e-9));
      expect(north.dim('h', 0), closeTo(2.2, 1e-9));
      // East wall: z-run [-0.5, 6.5], panel x ∈ [6.3, 6.5].
      final east = c.objects.singleWhere((o) => o.name == 'Стена Восток');
      expect(east.dim('d', 0), closeTo(7, 1e-9));
      expect(east.x, closeTo(6.4, 1e-9));
      // A thicker wall eats more of the border cell.
      final thick = room(walls: allBlank, t: 0.4);
      final thickNorth =
          thick.objects.singleWhere((o) => o.name == 'Стена Север');
      expect(thickNorth.z, closeTo(-0.3, 1e-9)); // z ∈ [-0.5, -0.1]
      expect(thickNorth.dim('d', 0), closeTo(0.4, 1e-9));
    });

    test('groups are well-formed and reference real objects', () {
      final c = room(table: true, bed: true,
          assets: const RoomAssets(window: 'window.png'));
      final ids = c.objects.map((o) => o.id).toSet();
      expect(ids.length, c.objects.length);
      for (final g in c.groups) {
        expect(g.members, isNotEmpty);
        for (final m in g.members) {
          expect(ids, contains(m));
        }
      }
      final names = c.groups.map((g) => g.name).toSet();
      expect(names, containsAll(['Окна', 'Стол', 'Кровать']));
    });

    test('texture assets land on the slabs and walls', () {
      final allBlank = {
        RoomSide.north: WallType.blank,
        RoomSide.east: WallType.blank,
        RoomSide.south: WallType.blank,
        RoomSide.west: WallType.blank,
      };
      final c = room(walls: allBlank, assets: const RoomAssets(
          wall: 'wall.png', floor: 'floor.png', ceiling: 'ceiling.png'));
      final floor = c.objects.singleWhere((o) => o.name == 'Пол');
      final ceiling = c.objects.singleWhere((o) => o.name == 'Потолок');
      final wall = c.objects.singleWhere((o) => o.name == 'Стена Север');
      expect(floor.material!.type, MaterialType.texture);
      expect(floor.material!.key, 'floor.png');
      expect(ceiling.material!.key, 'ceiling.png');
      expect(wall.material!.key, 'wall.png');
      expect(wall.material!.stretch, 'tile');
    });
  });

  group('walls', () {
    test('south entrance: opening + header above doorHeight', () {
      final c = room();
      final perp = 6.4; // l − 0.5 − t/2
      // Opening is walkable up to doorHeight…
      expect(coveredBy(c.objects, 3, 0.9, perp), isFalse);
      // …and sealed by the header above it…
      expect(coveredBy(c.objects, 3, 2.1, perp), isTrue);
      // …while the wall continues on both sides of the 1-cell gap.
      expect(coveredBy(c.objects, 4.6, 1.1, perp), isTrue);
    });

    test('entrance with doorHeight == wallHeight is a through arch', () {
      final c = room(doorH: 2.2);
      final perp = 6.4;
      expect(coveredBy(c.objects, 3, 0.9, perp), isFalse);
      expect(coveredBy(c.objects, 3, 2.15, perp), isFalse); // no header
    });

    test('2-cell entrance opens a wider gap', () {
      final c = room(doorCells: 2);
      final perp = 6.4;
      expect(coveredBy(c.objects, 2.5, 0.9, perp), isFalse);
      expect(coveredBy(c.objects, 3.5, 0.9, perp), isFalse);
      expect(coveredBy(c.objects, 0.9, 0.9, perp), isTrue);
    });

    test('even footprint width: door gap straddles the half-cell center', () {
      final c = room(w: 8, walls: {
        RoomSide.north: WallType.entrance,
        RoomSide.east: WallType.blank,
        RoomSide.south: WallType.blank,
        RoomSide.west: WallType.blank,
      });
      expect(c.size.w, 8);
      final perp = -0.4; // north wall mid-thickness
      expect(coveredBy(c.objects, 3.5, 0.9, perp), isFalse); // gap [3, 4]
      expect(coveredBy(c.objects, 2.4, 0.9, perp), isTrue);
    });

    test('blank walls keep a full-height run with no gaps', () {
      final allBlank = {
        RoomSide.north: WallType.blank,
        RoomSide.east: WallType.blank,
        RoomSide.south: WallType.blank,
        RoomSide.west: WallType.blank,
      };
      final c = room(walls: allBlank);
      final names = c.objects.map((o) => o.name).toList();
      expect(names.where((n) => n.startsWith('Стена ')).length, 4);
      expect(names.where((n) => n.startsWith('Окно ')), isEmpty);
      expect(c.groups.where((g) => g.name == 'Окна'), isEmpty);
    });
  });

  group('window wall', () {
    test('cut in the wall: sill below, header above the opening', () {
      final c = room(); // north is a window wall
      final perp = -0.4; // north wall mid-thickness
      // Default window band: 0.5..1.2 (sill 0.5, height 0.7).
      expect(coveredBy(c.objects, 3, 0.8, perp), isFalse); // the opening
      expect(coveredBy(c.objects, 3, 0.2, perp), isTrue); // sill below
      expect(coveredBy(c.objects, 3, 1.5, perp), isTrue); // header above
      // Solid wall further along the run.
      expect(coveredBy(c.objects, 1.2, 0.8, perp), isTrue);
    });

    test('window plane with sprite: mask cutout, visible from both sides',
        () {
      final c = room(assets: const RoomAssets(window: 'window.png'));
      final win = c.objects.singleWhere((o) => o.name == 'Окно Север');
      expect(win.kind, 'plane');
      final m = win.material!;
      expect(m.type, MaterialType.sprite);
      expect(m.key, 'window.png');
      expect(m.side, 'both');
      expect(m.flipX, isTrue); // rotY ≠ 0 mirrors the plane
      expect(win.rotY, closeTo(180, 1e-9));
      // Plane sits at the mid-thickness of the wall (z = −0.5 + t/2 = −0.4),
      // filling the opening [0.5..1.2] at the room center.
      expect(win.x, closeTo(3, 1e-9));
      expect(win.z, closeTo(-0.4, 1e-9));
      expect(win.y, closeTo(0.5, 1e-9));
      expect(win.dim('w', 0), closeTo(roomWindowW, 1e-9));
      expect(win.dim('d', 0), closeTo(roomWindowH, 1e-9));
      final group = c.groups.singleWhere((g) => g.name == 'Окна');
      expect(group.members, [win.id]);
    });

    test('custom window sill and size move and resize the opening', () {
      final c = room(assets: const RoomAssets(window: 'window.png'),
          winSill: 0.8, winH: 1.0, winW: 1.0);
      final win = c.objects.singleWhere((o) => o.name == 'Окно Север');
      expect(win.y, closeTo(0.8, 1e-9));
      expect(win.dim('d', 0), closeTo(1.0, 1e-9)); // 0.8..1.8
      expect(win.dim('w', 0), closeTo(1.0, 1e-9));
      final perp = -0.4;
      expect(wallCoveredBy(c.objects, 3, 1.5, perp), isFalse); // the hole
      expect(wallCoveredBy(c.objects, 3, 0.3, perp), isTrue); // sill below
      expect(wallCoveredBy(c.objects, 3, 2.0, perp), isTrue); // header above
    });

    test('sill that does not fit is pushed down to hug the ceiling', () {
      // Requested sill 1.9 with height 0.7 needs 2.75 — a wall of 2.2 keeps
      // only 0.15 of header → the window bottom lands at 1.35.
      final c = room(winSill: 1.9,
          assets: const RoomAssets(window: 'window.png'));
      final win = c.objects.singleWhere((o) => o.name == 'Окно Север');
      expect(win.y, closeTo(1.35, 1e-9));
      expect(win.dim('d', 0), closeTo(0.7, 1e-9));
    });

    test('window wall without a sprite leaves a bare opening', () {
      final c = room(); // default assets: no window
      expect(c.objects.where((o) => o.name.startsWith('Окно')), isEmpty);
      expect(c.groups.where((g) => g.name == 'Окна'), isEmpty);
    });

    test('rotY per side follows the house plane table', () {
      final c = room(walls: {
        RoomSide.north: WallType.window,
        RoomSide.east: WallType.window,
        RoomSide.south: WallType.window,
        RoomSide.west: WallType.window,
      }, assets: const RoomAssets(window: 'window.png'));
      double rotYOf(String side) => c.objects
          .singleWhere((o) => o.name == 'Окно $side')
          .rotY;
      expect(rotYOf('Север'), 180);
      expect(rotYOf('Юг'), 0);
      expect(rotYOf('Запад'), 90);
      expect(rotYOf('Восток'), 270);
    });
  });

  group('corridors and tiny rooms', () {
    test('1×N corridor: entrances on both ends, walls hug the border', () {
      final c = room(w: 1, l: 7, walls: {
        RoomSide.north: WallType.entrance,
        RoomSide.east: WallType.blank,
        RoomSide.south: WallType.entrance,
        RoomSide.west: WallType.blank,
      });
      expect(c.size.w, 1);
      expect(c.size.l, 7);
      // A 1-cell door spans the whole end wall (gap = full run).
      expect(coveredBy(c.objects, 0, 0.9, -0.4), isFalse); // north opening
      expect(coveredBy(c.objects, 0, 0.9, 6.4), isFalse); // south opening
      // The side walls (0.2 thick at x ±0.5±...) keep their runs.
      final west = c.objects.singleWhere((o) => o.name == 'Стена Запад');
      expect(west.dim('d', 0), closeTo(7, 1e-9));
      expect(west.x, closeTo(-0.4, 1e-9));
    });

    test('door opening never exceeds the narrowest footprint axis', () {
      expect(() => room(w: 1, l: 5, doorCells: 2), throwsAssertionError);
      expect(() => room(w: 1, l: 1, doorCells: 2), throwsAssertionError);
      // A 2-cell door fits a 2-wide room.
      expect(() => room(w: 2, l: 5, doorCells: 2), returnsNormally);
    });

    test('window on a 1-wide room wall', () {
      final c = room(w: 1, l: 5,
          assets: const RoomAssets(window: 'window.png'));
      final win = c.objects.singleWhere((o) => o.name == 'Окно Север');
      expect(win.x, closeTo(0, 1e-9)); // room center of the 1-wide model
    });
  });

  group('furniture', () {
    test('table: top + 4 square legs in its own group', () {
      final c = room(table: true);
      final members = c.groups.singleWhere((g) => g.name == 'Стол').members;
      expect(members, hasLength(5));
      final byId = {for (final o in c.objects) o.id: o};
      final top = byId[members.first]!;
      expect(top.name, 'Стол');
      expect(top.dim('w', 0), closeTo(roomTableW, 1e-9));
      expect(top.dim('h', 0), closeTo(roomTableTopH, 1e-9));
      expect(top.y, closeTo(roomTableLegH, 1e-9));
      final legs =
          members.skip(1).map((id) => byId[id]!).toList();
      expect(legs, hasLength(4));
      for (final leg in legs) {
        expect((leg.x - 3).abs(), closeTo(roomTableW / 2 - roomTableLeg / 2, 1e-6));
        expect((leg.z - 3).abs(), closeTo(roomTableD / 2 - roomTableLeg / 2, 1e-6));
        expect(leg.dim('w', 0), closeTo(roomTableLeg, 1e-9));
        expect(leg.dim('h', 0), closeTo(roomTableLegH, 1e-9));
      }
    });

    test('bed sits flush against the first wall without an entrance', () {
      final c = room(bed: true);
      final bed = c.objects.singleWhere((o) => o.name == 'Кровать');
      final group = c.groups.singleWhere((g) => g.name == 'Кровать');
      expect(group.members, [bed.id]);
      // Default walls: south is the entrance → the headboard hugs the north
      // wall (z = −0.5 + t + off), the block spans the room center row.
      expect(bed.z, closeTo(-0.5 + 0.2 + 0.02 + roomBedW / 2, 1e-9));
      expect(bed.x, closeTo(3, 1e-9));
      expect(bed.dim('w', 0), closeTo(roomBedLen, 1e-9));
      expect(bed.dim('d', 0), closeTo(roomBedW, 1e-9));
      expect(bed.dim('h', 0), closeTo(roomBedH, 1e-9));
    });

    test('all-entrance room shifts the bed off the door axis', () {
      final allEntrance = {
        RoomSide.north: WallType.entrance,
        RoomSide.east: WallType.entrance,
        RoomSide.south: WallType.entrance,
        RoomSide.west: WallType.entrance,
      };
      final c = room(w: 7, l: 9, walls: allEntrance, bed: true);
      final bed = c.objects.singleWhere((o) => o.name == 'Кровать');
      // Falls back to the north wall (entrance there too → off the door
      // axis along the wall), hugging the wall's inner face.
      expect(bed.x, isNot(closeTo(3, 1e-6))); // off the north door axis
      expect(bed.x, inInclusiveRange(0.5, 6.5));
      expect(bed.z, inInclusiveRange(-0.5, 8.5)); // inside the footprint
      expect(bed.z, closeTo(-0.5 + 0.2 + 0.02 + roomBedW / 2, 1e-6));
    });

    test('no furniture by default', () {
      final c = room();
      expect(c.groups.where((g) => g.name == 'Стол'), isEmpty);
      expect(c.groups.where((g) => g.name == 'Кровать'), isEmpty);
      expect(c.objects.where((o) => o.name == 'Стол'), isEmpty);
    });
  });
}
