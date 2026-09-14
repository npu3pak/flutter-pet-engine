import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';
import 'polyhedra_common.dart';

/// Профиль Г-образной комнаты (нижняя и вертикальная части): тот же
/// вогнутый обход, что и у L-призмы в соседних фичах.
final List<vm.Vector2> mapRoomProfile = [
  vm.Vector2(-2.5, -2.5),
  vm.Vector2(2.5, -2.5),
  vm.Vector2(2.5, -0.5),
  vm.Vector2(-0.5, -0.5),
  vm.Vector2(-0.5, 2.5),
  vm.Vector2(-2.5, 2.5),
];

/// Внутренние стены комнаты: по n-угольнику на ребро профиля, нормали
/// смотрят внутрь помещения (обход, обратный внешнему). UV заданы явно и
/// «привязаны» к длине стены: u = пройденное расстояние / [tile], v = высота
/// / [tile] — так текстура не растягивается на длинных стенах, как это
/// делает конвертер карт.
PolyMesh buildMapWalls({
  required List<vm.Vector2> profile,
  required double height,
  double tile = 1.5,
}) {
  final count = profile.length;
  final vertices = <vm.Vector3>[
    for (final p in profile) vm.Vector3(p.x, 0, p.y),
    for (final p in profile) vm.Vector3(p.x, height, p.y),
  ];
  final distance = <double>[0];
  for (var i = 0; i < count; i++) {
    final next = profile[(i + 1) % count];
    distance.add(distance[i] + (next - profile[i]).length);
  }
  final vTop = height / tile;
  return PolyMesh(
    vertices: vertices,
    faces: [
      for (var i = 0; i < count; i++)
        PolyFace(
          key: 'wall_$i',
          outer: PolyLoop(
            // Обход обратный внешнему: нормаль смотрит внутрь комнаты.
            vertices: [i, (i + 1) % count, count + (i + 1) % count, count + i],
            uvs: [
              vm.Vector2(distance[i] / tile, 0),
              vm.Vector2(distance[i + 1] / tile, 0),
              vm.Vector2(distance[i + 1] / tile, vTop),
              vm.Vector2(distance[i] / tile, vTop),
            ],
          ),
        ),
    ],
  );
}

/// Фрагмент карты: пол (вогнутый сектор), внутренние стены и колонна.
/// Пол и стены несут явные UV — так же, как их задаст будущий конвертер
/// WAD-карт, поэтому фича служит визуальной проверкой импорта.
doc.ModelData buildPolyhedraMapScene(FeatureBuildContext context) {
  final floorMaterial = textureMat(
    pickTexture(context, 'floor'),
    stretch: 'tile',
    tileScale: 2,
  );
  final wallMaterial = textureMat(
    pickTexture(context, 'wallpaper_blue'),
    stretch: 'tile',
    tileScale: 1.5,
  );

  // Пол: Г-образный сектор толщиной 0.25, верхняя грань с явными UV
  // «мировые координаты / 2» — плоские флэты карты.
  final floor = extrudeProfile(profile: mapRoomProfile, height: 0.25);
  final floorTop = floor.faceByKey('+y')!;
  floorTop.outer.uvs
    ..clear()
    ..addAll([
      for (final i in floorTop.outer.vertices)
        vm.Vector2(floor.vertices[i].x / 2, floor.vertices[i].z / 2),
    ]);

  final walls = buildMapWalls(profile: mapRoomProfile, height: 2.2);

  return doc.ModelData(
    id: 'polyhedra_map',
    name: 'Многогранники: фрагмент карты',
    size: doc.ModelSize(w: 8, l: 8, h: 4),
    objects: [
      polyhedronObject(
        id: 'floor',
        name: 'Пол сектора',
        mesh: floor,
        material: colorMat(SceneColors.gray),
        faces: {
          '+y': floorMaterial,
          '-y': colorMat(SceneColors.gray),
          'side_0': colorMat(SceneColors.gray),
          'side_1': colorMat(SceneColors.gray),
          'side_2': colorMat(SceneColors.gray),
          'side_3': colorMat(SceneColors.gray),
          'side_4': colorMat(SceneColors.gray),
          'side_5': colorMat(SceneColors.gray),
        },
      ),
      polyhedronObject(
        id: 'walls',
        name: 'Внутренние стены',
        mesh: walls,
        y: 0.25,
        material: wallMaterial,
        faces: {
          for (final face in walls.faces) face.key: wallMaterial,
        },
      ),
      polyhedronObject(
        id: 'pillar',
        name: 'Колонна',
        mesh: PolyMesh.box(w: 0.6, h: 1.6, d: 0.6),
        x: 1.4,
        y: 0.25,
        z: -1.6,
        material: wallMaterial,
        faces: {
          '+y': colorMat(SceneColors.orange),
        },
      ),
    ],
  );
}

final FeatureSpec polyhedraMapFeature = FeatureSpec(
  id: 'polyhedra_map',
  group: kFeatureGroups[8],
  title: 'Фрагмент карты',
  project: 'Pet',
  phase: 6,
  description:
      'Фрагмент карты как у Doom: вогнутый Г-образный сектор пола, '
      'внутренние стены по рёбрам сектора и колонна. UV пола и стен заданы '
      'явно и привязаны к мировым координатам и длине стен — именно так '
      'конвертер WAD-карт сможет перенести текстуры без искажений.',
  checks: const [
    'Пол — один вогнутый сектор: впадина замощена без «заливки» лишней площади.',
    'Текстура стен не растягивается на длинных стенах: повторяется по длине и высоте.',
    'Текстура пола повторяется по мировым координатам, а не растянута на весь сектор.',
    'Стены смотрят внутрь комнаты: камера снаружи видит интерьер, а не изнанку.',
  ],
  build: buildPolyhedraMapScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _PolyhedraMapControls(),
);

class _PolyhedraMapControls extends StatelessWidget {
  const _PolyhedraMapControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Что показано'),
        fcLegend([
          LegendEntry(rgbColor(SceneColors.gray), 'Пол сектора (явные UV / 2)'),
          LegendEntry(rgbColor(SceneColors.blue), 'Стены (UV по длине)'),
          LegendEntry(rgbColor(SceneColors.orange), 'Верх колонны'),
        ]),
        fcNote(
          'Пол — один PolyFace с вогнутым контуром. Стены — шесть отдельных '
          'граней с обходом «внутрь» и UV, посчитанными вручную. Такой набор '
          'граней описывает сектор карты целиком, без упрощения геометрии.',
        ),
      ],
    );
  }
}
