import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';
import 'polyhedra_common.dart';

/// Пирамида: квадратное основание и четыре треугольные грани к вершине.
///
/// Показывает ручную сборку из [PolyFace.triangle] и общих вершин.
PolyMesh _pyramid({double baseWidth = 1.8, double height = 1.6}) {
  final h = baseWidth / 2;
  final vertices = <vm.Vector3>[
    vm.Vector3(-h, 0, -h),
    vm.Vector3(h, 0, -h),
    vm.Vector3(h, 0, h),
    vm.Vector3(-h, 0, h),
    vm.Vector3(0, height, 0), // вершина
  ];
  return PolyMesh(
    vertices: vertices,
    faces: [
      // Основание: тот же обход, что у кубоида, — нормаль смотрит вниз.
      PolyFace.quad(key: '-y', a: 0, b: 1, c: 2, d: 3),
      // Боковые треугольники: (низ_i, вершина, низ_след).
      for (var i = 0; i < 4; i++)
        PolyFace.triangle(key: 'side_$i', a: i, b: 4, c: (i + 1) % 4),
    ],
  );
}

/// Сцена группы: четыре многогранника, собранных в коде.
doc.ModelData buildPolyhedraAllScene(FeatureBuildContext context) {
  final cube = PolyMesh.box(w: 1.2, h: 1.2, d: 1.2);

  // Вогнутый L-профиль в плоскости (x, z): обход «по часовой стрелке»,
  // как описано в polyhedra_common.dart.
  final prism = extrudeProfile(
    profile: [
      vm.Vector2(-1.5, -1.5),
      vm.Vector2(1.5, -1.5),
      vm.Vector2(1.5, -0.5),
      vm.Vector2(-0.5, -0.5),
      vm.Vector2(-0.5, 1.5),
      vm.Vector2(-1.5, 1.5),
    ],
    height: 2,
  );

  final slab = plateWithHole(
    width: 3,
    depth: 3,
    thickness: 0.4,
    holeWidth: 1.4,
    holeDepth: 1.4,
  );

  return doc.ModelData(
    id: 'polyhedra_all',
    name: 'Многогранники: сборка',
    size: doc.ModelSize(w: 8, l: 8, h: 4),
    objects: [
      polyhedronObject(
        id: 'cube',
        name: 'Куб',
        mesh: cube,
        x: 1.5,
        z: 1.5,
        material: colorMat(SceneColors.gray),
        faces: {
          '+y': colorMat(SceneColors.green),
          '-y': colorMat(SceneColors.gray),
          '+x': colorMat(SceneColors.blue),
          '-x': colorMat(SceneColors.orange),
          '+z': colorMat(SceneColors.cyan),
          '-z': colorMat(SceneColors.red),
        },
      ),
      polyhedronObject(
        id: 'pyramid',
        name: 'Пирамида',
        mesh: _pyramid(),
        x: 4,
        z: 1.5,
        material: colorMat(SceneColors.purple),
        faces: {
          '-y': colorMat(SceneColors.gray),
          'side_0': colorMat(SceneColors.red),
          'side_1': colorMat(SceneColors.orange),
          'side_2': colorMat(SceneColors.yellow),
          'side_3': colorMat(SceneColors.green),
        },
      ),
      polyhedronObject(
        id: 'prism',
        name: 'L-призма',
        mesh: prism,
        x: 6.2,
        z: 1.5,
        rotY: 20,
        material: colorMat(SceneColors.blue),
        faces: {
          '+y': colorMat(SceneColors.green),
          '-y': colorMat(SceneColors.gray),
          'side_0': colorMat(SceneColors.cyan),
          'side_1': colorMat(SceneColors.orange),
          'side_2': colorMat(SceneColors.red),
          'side_3': colorMat(SceneColors.yellow),
          'side_4': colorMat(SceneColors.blue),
          'side_5': colorMat(SceneColors.purple),
        },
      ),
      // Подставка — обычный кубоид: многогранник ставится рядом с ним.
      sceneObject(
        id: 'pedestal',
        name: 'Подставка',
        kind: 'cuboid',
        x: 2.5,
        z: 5.6,
        dims: const {'w': 1.6, 'h': 1.0, 'd': 1.6},
        material: colorMat(SceneColors.gray),
      ),
      polyhedronObject(
        id: 'slab',
        name: 'Плита с отверстием',
        mesh: slab,
        x: 2.5,
        y: 1.0,
        z: 5.6,
        material: colorMat(SceneColors.cyan),
        faces: {
          '+y': colorMat(SceneColors.green),
          '-y': colorMat(SceneColors.gray),
          'outer_0': colorMat(SceneColors.blue),
          'outer_1': colorMat(SceneColors.orange),
          'outer_2': colorMat(SceneColors.blue),
          'outer_3': colorMat(SceneColors.orange),
          'hole_0': colorMat(SceneColors.red),
          'hole_1': colorMat(SceneColors.red),
          'hole_2': colorMat(SceneColors.red),
          'hole_3': colorMat(SceneColors.red),
        },
      ),
    ],
  );
}

final FeatureSpec polyhedraAllFeature = FeatureSpec(
  id: 'polyhedra_all',
  group: kFeatureGroups[8],
  title: 'Сборка многогранников',
  phase: 6,
  description:
      'Четыре многогранника собраны в коде из общих вершин и плоских граней: '
      'куб через PolyMesh.box, пирамида из треугольников, вогнутая L-призма '
      '(n-угольные боковые грани) и плита с прямоугольным отверстием. '
      'Все грани окрашены разными цветами, чтобы форму читали глазом; '
      'подставка — обычный кубоид для сравнения.',
  checks: const [
    'Куб, пирамида, L-призма и плита с отверстием видны и окрашены по граням.',
    'Сквозь отверстие плиты видно подставку: грань с holes действительно пустая.',
    'Вогнутая L-призма отрисована без «заливки» впадины: n-угольные грани триангулированы верно.',
    'Облёт камерой не показывает чёрных/пропавших граней: нормали смотрят наружу.',
  ],
  build: buildPolyhedraAllScene,
  camera: CameraMode.free,
  controls: (context, feature) => const _PolyhedraAllControls(),
);

class _PolyhedraAllControls extends StatelessWidget {
  const _PolyhedraAllControls();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Что показано'),
        fcLegend([
          LegendEntry(rgbColor(SceneColors.blue), 'Грани куба (PolyMesh.box)'),
          LegendEntry(rgbColor(SceneColors.purple), 'Пирамида (PolyFace.triangle)'),
          LegendEntry(rgbColor(SceneColors.cyan), 'L-призма (вогнутая грань)'),
          LegendEntry(rgbColor(SceneColors.red), 'Стенки отверстия (holes)'),
          LegendEntry(rgbColor(SceneColors.gray), 'Подставка (обычный кубоид)'),
        ]),
        fcNote(
          'Многогранник хранит общие вершины и плоские грани: у куба 8 вершин '
          'на 6 граней, у плиты грань +y имеет внешний контур и отверстие. '
          'Порядок обхода контура задаёт наружную нормаль — см. комментарии '
          'в polyhedra_common.dart.',
        ),
      ],
    );
  }
}
