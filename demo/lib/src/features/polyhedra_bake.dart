import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Строит объект-многогранник из любого объекта документа через
/// [bakePolyhedron]: сеть и материалы граней берутся из конверсии, позиция
/// и поворот оригинала сохраняются (кроме CSG — там поворот уже запечён в
/// вершины, его нужно обнулить: `bake.rotationBaked`).
doc.ModelObject? _convert(
  doc.ModelData model,
  String id, {
  double dx = 0,
  double dz = 0,
}) {
  final source = model.objectById(id);
  if (source == null) return null;
  final bake = bakePolyhedron(model, source);
  if (bake == null) return null;
  return doc.ModelObject(
    id: '${id}_poly',
    name: '${source.name} → многогранник',
    kind: doc.polyhedronKind,
    x: source.x + dx,
    y: source.y,
    z: source.z + dz,
    rotX: bake.rotationBaked ? 0 : source.rotX,
    rotY: bake.rotationBaked ? 0 : source.rotY,
    rotZ: bake.rotationBaked ? 0 : source.rotZ,
    mesh: bake.mesh,
    material: source.material,
    faces: bake.faces,
  );
}

/// Сцена: примитивы и CSG в верхнем ряду, их многогранники — в нижнем.
doc.ModelData buildPolyhedraBakeScene(FeatureBuildContext context) {
  final showOriginals = context.param<bool>('showOriginals') ?? true;

  final originals = <doc.ModelObject>[
    sceneObject(
      id: 'box',
      name: 'Кубоид',
      kind: 'cuboid',
      x: 1.5,
      z: 1.5,
      dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
      material: colorMat(SceneColors.blue),
      faces: {'+y': colorMat(SceneColors.green)},
    ),
    sceneObject(
      id: 'trap',
      name: 'Трапеция',
      kind: 'trapezoid',
      x: 4,
      z: 1.5,
      rotY: 15,
      dims: const {
        'bottomW': 1.4,
        'bottomD': 1.4,
        'topW': 0.6,
        'topD': 0.6,
        'h': 1.4,
      },
      material: colorMat(SceneColors.orange),
      faces: {'+y': colorMat(SceneColors.green)},
    ),
    sceneObject(
      id: 'cyl',
      name: 'Цилиндр',
      kind: 'cylinder',
      x: 6.5,
      z: 1.5,
      dims: const {'bottomR': 0.6, 'topR': 0.6, 'h': 1.2, 'segments': 16},
      material: colorMat(SceneColors.purple),
      faces: {
        'side': colorMat(SceneColors.purple),
        '+y': colorMat(SceneColors.green),
        '-y': colorMat(SceneColors.gray),
      },
    ),
    // CSG: из большого куба вырезан узкий столб — остаются две стенки.
    sceneObject(
      id: 'cut_a',
      name: 'Операнд A',
      kind: 'cuboid',
      x: 8.8,
      z: 1.5,
      dims: const {'w': 1.4, 'h': 1.4, 'd': 1.4},
      material: colorMat(SceneColors.gray),
    ),
    sceneObject(
      id: 'cut_b',
      name: 'Операнд B',
      kind: 'cuboid',
      x: 8.8,
      z: 1.5,
      dims: const {'w': 0.6, 'h': 2.0, 'd': 1.6},
      material: colorMat(SceneColors.red),
    ),
    sceneObject(
      id: 'cut',
      name: 'CSG-вырез',
      kind: doc.csgKind,
      op: doc.csgOpDifference,
      operands: const ['cut_a', 'cut_b'],
      material: colorMat(SceneColors.cyan),
    ),
  ];

  // Модель с оригиналами нужна и для конверсии CSG (её операнды лежат в
  // документе), и для финальной сцены.
  final model = doc.ModelData(
    id: 'polyhedra_bake',
    name: 'Многогранники: конверсия',
    size: doc.ModelSize(w: 10, l: 8, h: 4),
    objects: originals,
  );

  final converted = <doc.ModelObject>[
    for (final id in const ['box', 'trap', 'cyl'])
      _convert(model, id, dz: 3.9)!,
    _convert(model, 'cut', dz: 3.9)!,
  ];

  return doc.ModelData(
    id: model.id,
    name: model.name,
    size: model.size,
    objects: [
      if (showOriginals) ...originals,
      ...converted,
    ],
  );
}

final FeatureSpec polyhedraBakeFeature = FeatureSpec(
  id: 'polyhedra_bake',
  group: kFeatureGroups[8],
  title: 'Конверсия в многогранник',
  phase: 6,
  description:
      'Верхний ряд — обычные объекты (кубоид, трапеция, цилиндр и результат '
      'CSG), нижний — они же, преобразованные функцией bakePolyhedron в '
      'многогранники. Переключатель скрывает оригиналы, чтобы сравнить '
      'форму; материалы граней при конверсии сохраняются, а запечённый '
      'поворот CSG обнуляется.',
  checks: const [
    'Нижний ряд повторяет форму верхнего: конверсия не меняет силуэт.',
    'Цвета граней сохраняются: зелёный верх, цветные стенки, серые низ и круглые крышки.',
    'У трапеции в нижнем ряду сохранён поворот: он не запечён в вершины.',
    'Выключите «Показывать оригиналы» — останутся только многогранники, форма та же.',
  ],
  build: buildPolyhedraBakeScene,
  camera: CameraMode.free,
  controls: (context, feature) => _PolyhedraBakeControls(feature: feature),
);

class _PolyhedraBakeControls extends StatefulWidget {
  const _PolyhedraBakeControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_PolyhedraBakeControls> createState() => _PolyhedraBakeControlsState();
}

class _PolyhedraBakeControlsState extends State<_PolyhedraBakeControls> {
  bool _showOriginals = true;

  @override
  void initState() {
    super.initState();
    _showOriginals = widget.feature.params['showOriginals'] as bool? ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Сравнение'),
        fcSwitch(
          label: 'Показывать оригиналы',
          value: _showOriginals,
          onChanged: (value) {
            setState(() => _showOriginals = value);
            widget.feature.updateParams({'showOriginals': value});
          },
        ),
        fcLegend([
          LegendEntry(rgbColor(SceneColors.blue), 'Кубоид → сеть из 6 граней'),
          LegendEntry(rgbColor(SceneColors.orange), 'Трапеция → наклонные грани'),
          LegendEntry(rgbColor(SceneColors.purple), 'Цилиндр → side_0…side_15'),
          LegendEntry(rgbColor(SceneColors.cyan), 'CSG-вырез → грани результата'),
        ]),
        fcNote(
          'bakePolyhedron(model, object) возвращает mesh и материалы граней. '
          'Если rotationBaked == true (CSG и скруглённый кубоид), поворот уже '
          'в вершинах — после подстановки его обнуляют. Материал по умолчанию '
          'остаётся у объекта, переопределения — в faces.',
        ),
      ],
    );
  }
}
