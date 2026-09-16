import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Порядок граней и их цвета в сценах размещения.
const List<String> placementFaces = ['+x', '-x', '+y', '-y', '+z', '-z'];

const List<List<int>> placementFaceColors = [
  [214, 76, 76], // +x
  [86, 132, 214], // -x
  [96, 186, 112], // +y
  [222, 196, 88], // -y
  [230, 150, 70], // +z
  [166, 106, 214], // -z
];

/// Опора одного примера: испытываемая грань подсвечена цветом, остальные
/// серые. Опора повёрнута так, чтобы эта грань смотрела на камеру — тогда
/// все шесть примеров читаются в одном кадре.
doc.ModelObject orientedTarget(
  String id,
  String face, {
  required double x,
  required double y,
  required double z,
  required int colorIndex,
}) {
  final rotY = switch (face) {
    '-z' => 180.0,
    '+x' => -90.0,
    '-x' => 90.0,
    _ => 0.0,
  };
  final rotX = face == '-y' ? 180.0 : 0.0;
  return sceneObject(
    id: id,
    name: 'Опора $face',
    kind: 'cuboid',
    x: x,
    y: y,
    z: z,
    rotX: rotX,
    rotY: rotY,
    dims: const {'w': 1.0, 'h': 1.0, 'd': 1.0},
    faces: {
      for (var i = 0; i < placementFaces.length; i++)
        placementFaces[i]: colorMat(
          i == colorIndex ? placementFaceColors[i] : SceneColors.gray,
        ),
    },
  );
}

/// Точка нажатия на боковой поверхности цилиндра в визуальном (зеркальном)
/// кадре: операции принимают её так же, как редактор.
vm.Vector3 cylinderSideClick(
  doc.ModelObject cylinder,
  double localX,
  double localY,
  double localZ,
) {
  final rot = objectRotation(cylinder);
  final model =
      rot.transform3(vm.Vector3(localX, localY, localZ)) +
      vm.Vector3(cylinder.x, cylinder.y, cylinder.z);
  return vm.Vector3(2 * cylinder.x - model.x, model.y, model.z);
}

/// Пластина-«табличка»: тонкий куб, который после [parallelToFace] ложится
/// на грань и выступает наружу вдоль нормали.
doc.ModelObject facePlate(
  String id,
  doc.ModelObject target,
  String face, {
  List<int>? color,
  double size = 0.5,
  double thickness = 0.06,
  double gap = 0.03,
  vm.Vector3? clickLocal,
}) {
  final plate = sceneObject(
    id: id,
    name: 'Табличка $face',
    kind: 'cuboid',
    dims: {'w': size, 'h': thickness, 'd': size},
    material: colorMat(color ?? SceneColors.green),
  );
  parallelToFace(plate, target, face, clickLocal: clickLocal);
  snapToFace(plate, target, face, gap: gap, clickLocal: clickLocal);
  return plate;
}

/// 1. Прильнуть к грани: все шесть. Шесть опор в ряд; у каждой подсвечена
/// испытываемая грань и к ней прильнула табличка того же цвета.
doc.ModelData buildPlacementSnapFaces() {
  final model = ConstructionModel(
    id: 'placement_ops',
    name: 'Прильнуть к грани',
  );
  model.data.size = doc.ModelSize(w: 12, l: 5, h: 3);
  model.add(
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 5.5,
      z: 2.5,
      dims: const {'w': 12, 'd': 5},
      material: colorMat(SceneColors.gray),
    ),
    tag: 'ground',
  );
  for (var i = 0; i < placementFaces.length; i++) {
    final face = placementFaces[i];
    final target = orientedTarget(
      'target_$i',
      face,
      x: 1.2 + i * 1.85,
      y: face == '-y' ? 1.0 : 0.0,
      z: 2.5,
      colorIndex: i,
    );
    model.add(target, tag: 'target');
    model.add(
      facePlate(
        'plate_$i',
        target,
        face,
        color: placementFaceColors[i],
        size: 0.7,
        thickness: 0.12,
        gap: 0.04,
      ),
      tag: 'plate',
    );
  }
  return model.data;
}

/// 2. Прильнуть к цилиндру: бок, торцы и наклоны (конус и повёрнутый
/// цилиндр).
doc.ModelData buildPlacementSnapCylinder() {
  final model = ConstructionModel(
    id: 'placement_snap_cylinder',
    name: 'Прильнуть к цилиндру',
  );
  model.data.size = doc.ModelSize(w: 16, l: 8, h: 4);

  final cylinder = sceneObject(
    id: 'cylinder',
    name: 'Цилиндр',
    kind: 'cylinder',
    x: 3,
    y: 0.7,
    z: 4,
    dims: const {'bottomR': 0.8, 'topR': 0.8, 'h': 1.6, 'segments': 24},
    material: colorMat(SceneColors.gray),
  );
  model.add(cylinder, tag: 'target');
  // Бок: четыре таблички под 0°, 90°, 180°, 270°.
  for (var i = 0; i < 4; i++) {
    final angle = i * 3.141592653589793 / 2;
    final click = cylinderSideClick(
      cylinder,
      0.8 * math.cos(angle),
      0.8,
      0.8 * math.sin(angle),
    );
    model.add(
      facePlate(
        'side_$i',
        cylinder,
        'side',
        color: SceneColors.cyan,
        clickLocal: click,
      ),
      tag: 'plate',
    );
  }
  // Торцы.
  model.add(
    facePlate('top', cylinder, '+y', color: SceneColors.blue),
    tag: 'plate',
  );
  model.add(
    facePlate('bottom', cylinder, '-y', color: SceneColors.blue),
    tag: 'plate',
  );

  // Конус: бок наклонён, табличка повторяет наклон.
  final cone = sceneObject(
    id: 'cone',
    name: 'Конус',
    kind: 'cylinder',
    x: 8,
    y: 0.7,
    z: 4,
    dims: const {'bottomR': 0.8, 'topR': 0.0, 'h': 1.6, 'segments': 24},
    material: colorMat(SceneColors.orange),
  );
  model.add(cone, tag: 'target');
  // Точка нажатия — сторона, обращённая к камере (θ=90°), иначе табличка
  // видна на ребре и не показывает повтор наклона.
  model.add(
    facePlate(
      'cone_side',
      cone,
      'side',
      color: SceneColors.cyan,
      clickLocal: cylinderSideClick(cone, 0, 0.8, 0.8),
    ),
    tag: 'plate',
  );

  // Повёрнутый цилиндр: табличка на боку с учётом поворота.
  final tilted = sceneObject(
    id: 'tilted',
    name: 'Наклонённый цилиндр',
    kind: 'cylinder',
    x: 13,
    y: 0.7,
    z: 4,
    rotZ: 30,
    dims: const {'bottomR': 0.7, 'topR': 0.7, 'h': 1.6, 'segments': 24},
    material: colorMat(SceneColors.purple),
  );
  model.add(tilted, tag: 'target');
  model.add(
    facePlate(
      'tilted_side',
      tilted,
      'side',
      color: SceneColors.cyan,
      clickLocal: cylinderSideClick(tilted, 0, 0.8, 0.7),
    ),
    tag: 'plate',
  );
  return model.data;
}

/// 3. Встать параллельно грани: шесть опор в ряд, на испытываемой грани —
/// табличка и брусок, развёрнутые по нормали.
doc.ModelData buildPlacementParallel() {
  final model = ConstructionModel(
    id: 'placement_parallel',
    name: 'Параллельно грани',
  );
  model.data.size = doc.ModelSize(w: 12, l: 5, h: 3);
  model.add(
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 5.5,
      z: 2.5,
      dims: const {'w': 12, 'd': 5},
      material: colorMat(SceneColors.gray),
    ),
    tag: 'ground',
  );
  for (var i = 0; i < placementFaces.length; i++) {
    final face = placementFaces[i];
    final target = orientedTarget(
      'target_$i',
      face,
      x: 1.2 + i * 1.85,
      y: face == '-y' ? 1.0 : 0.0,
      z: 2.5,
      colorIndex: i,
    );
    model.add(target, tag: 'target');
    model.add(
      facePlate(
        'plate_$i',
        target,
        face,
        color: placementFaceColors[i],
        size: 0.7,
        thickness: 0.1,
        gap: 0.05,
      ),
      tag: 'plate',
    );
    // Брусок: локальная ось +Y смотрит по нормали грани, сам брусок
    // вытянут в плоскости грани и стоит вертикально. У горизонтальных
    // граней «верх» в плоскости не определён, поэтому длинная ось
    // ставится вдоль нормали (на табличку), иначе брусок лежит.
    final beam = sceneObject(
      id: 'beam_$i',
      name: 'Брусок $face',
      kind: 'cuboid',
      dims: const {'w': 0.18, 'h': 0.18, 'd': 0.7},
      material: colorMat(SceneColors.cyan),
    );
    parallelToFace(beam, target, face);
    final horizontal = face == '+y' || face == '-y';
    if (horizontal) {
      beam
        ..rotX = -90
        ..rotY = 0
        ..rotZ = 0;
    }
    snapToFace(beam, target, face, gap: horizontal ? 0.5 : 0.55);
    model.add(beam, tag: 'beam');
  }
  return model.data;
}

/// 4. Выровнять по осям: зелёный элемент смещён, голубой выровнен по оси.
doc.ModelData buildPlacementAlign() {
  final model = ConstructionModel(
    id: 'placement_align',
    name: 'Выровнять по осям',
  );
  model.data.size = doc.ModelSize(w: 15, l: 6, h: 4);
  model.add(
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 7.5,
      z: 3,
      dims: const {'w': 15, 'd': 6},
      material: colorMat(SceneColors.gray),
    ),
    tag: 'ground',
  );
  final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
  final labels = ['x', 'y', 'z'];
  for (var i = 0; i < axes.length; i++) {
    final x = 2.0 + i * 5.0;
    final base = sceneObject(
      id: 'base_$i',
      name: 'Опора ${labels[i]}',
      kind: 'cuboid',
      x: x,
      y: 0,
      z: 3,
      dims: const {'w': 1.2, 'h': 1.8, 'd': 1.2},
      material: colorMat(SceneColors.gray),
    );
    model.add(base, tag: 'base');
    final before = sceneObject(
      id: 'before_$i',
      name: 'До ${labels[i]}',
      kind: 'cuboid',
      x: x + 1.8,
      y: 0,
      z: 4.2,
      dims: const {'w': 0.5, 'h': 0.5, 'd': 0.5},
      material: colorMat(SceneColors.green),
    );
    model.add(before, tag: 'before');
    final after = sceneObject(
      id: 'after_$i',
      name: 'После ${labels[i]}',
      kind: 'cuboid',
      x: x + 1.8,
      y: 0,
      z: 4.2,
      dims: const {'w': 0.5, 'h': 0.5, 'd': 0.5},
      material: colorMat(SceneColors.cyan),
    );
    alignTo(after, base, axes[i]);
    model.add(after, tag: 'after');
  }
  return model.data;
}

/// 5. Заполнить промежуток: между двумя стойками вставлен заполнитель,
/// который упирается в их ближние грани.
doc.ModelData buildPlacementFillGap() {
  final model = ConstructionModel(
    id: 'placement_fill_gap',
    name: 'Заполнить промежуток',
  );
  model.data.size = doc.ModelSize(w: 15, l: 6, h: 4);
  final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
  final labels = ['x', 'y', 'z'];
  for (var i = 0; i < axes.length; i++) {
    final x = 2.5 + i * 5.0;
    // Стойки расставляются вдоль своей оси, чтобы промежуток был именно по ней.
    final (a, b) = switch (axes[i]) {
      LevelAxis.x => (
        sceneObject(
          id: 'post_a_$i',
          name: 'Стойка A ${labels[i]}',
          kind: 'cuboid',
          x: x - 1.2,
          y: 0.2,
          z: 3,
          dims: const {'w': 0.5, 'h': 1.6, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
        sceneObject(
          id: 'post_b_$i',
          name: 'Стойка B ${labels[i]}',
          kind: 'cuboid',
          x: x + 1.2,
          y: 0.2,
          z: 3,
          dims: const {'w': 0.5, 'h': 1.6, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
      ),
      LevelAxis.y => (
        sceneObject(
          id: 'post_a_$i',
          name: 'Стойка A ${labels[i]}',
          kind: 'cuboid',
          x: x,
          y: 0.2,
          z: 3,
          dims: const {'w': 0.5, 'h': 0.5, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
        sceneObject(
          id: 'post_b_$i',
          name: 'Стойка B ${labels[i]}',
          kind: 'cuboid',
          x: x,
          y: 2.2,
          z: 3,
          dims: const {'w': 0.5, 'h': 0.5, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
      ),
      LevelAxis.z => (
        sceneObject(
          id: 'post_a_$i',
          name: 'Стойка A ${labels[i]}',
          kind: 'cuboid',
          x: x,
          y: 0.2,
          z: 3 - 1.2,
          dims: const {'w': 0.5, 'h': 1.6, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
        sceneObject(
          id: 'post_b_$i',
          name: 'Стойка B ${labels[i]}',
          kind: 'cuboid',
          x: x,
          y: 0.2,
          z: 3 + 1.2,
          dims: const {'w': 0.5, 'h': 1.6, 'd': 0.5},
          material: colorMat(SceneColors.gray),
        ),
      ),
    };
    model.add(a, tag: 'post');
    model.add(b, tag: 'post');
    final filler = sceneObject(
      id: 'filler_$i',
      name: 'Заполнитель ${labels[i]}',
      kind: 'cuboid',
      x: x,
      y: 0.4,
      z: 3,
      dims: const {'w': 0.3, 'h': 0.3, 'd': 0.3},
      material: colorMat(SceneColors.cyan),
    );
    fillGap(filler, a, b, axes[i]);
    model.add(filler, tag: 'filler');
  }
  return model.data;
}

/// 6. Накрыть: крышка повторяет размер площадки и стоит на её верхней грани.
doc.ModelData buildPlacementCover() {
  final model = ConstructionModel(id: 'placement_cover', name: 'Накрыть');
  model.data.size = doc.ModelSize(w: 14, l: 6, h: 3);
  for (var i = 0; i < 3; i++) {
    final x = 2.5 + i * 4.5;
    final size = 1.0 + i * 0.6;
    final pad = sceneObject(
      id: 'pad_$i',
      name: 'Площадка $i',
      kind: 'cuboid',
      x: x,
      y: 0.2,
      z: 3,
      dims: {'w': size, 'h': 0.4, 'd': size},
      material: colorMat(SceneColors.gray),
    );
    model.add(pad, tag: 'pad');
    final coverBox = sceneObject(
      id: 'cover_$i',
      name: 'Крышка $i',
      kind: 'cuboid',
      x: x,
      y: 1.4,
      z: 3,
      dims: const {'w': 1, 'h': 0.2, 'd': 1},
      material: colorMat(SceneColors.cyan),
    );
    cover(coverBox, pad);
    model.add(coverBox, tag: 'cover');
  }
  return model.data;
}

/// 7. Отступить внутрь и наружу: у каждой площадки стопкой лежат
/// уменьшенная и увеличенная копии.
doc.ModelData buildPlacementInsetOutset() {
  final model = ConstructionModel(
    id: 'placement_inset_outset',
    name: 'Отступить внутрь и наружу',
  );
  model.data.size = doc.ModelSize(w: 16, l: 6, h: 3);
  const amounts = [0.2, 0.5, 0.9];
  for (var i = 0; i < amounts.length; i++) {
    final x = 2.5 + i * 5.0;
    // Концентрическая стопка: наружу (зелёная) — снизу, основа (серая) в
    // середине, внутрь (голубая) — сверху. Так все три копии видны из
    // фиксированной камеры, а отступ читается ступенькой.
    final outer = sceneObject(
      id: 'outer_$i',
      name: 'Наружу ${amounts[i]}',
      kind: 'cuboid',
      x: x,
      y: 0,
      z: 3,
      dims: const {'w': 2.0, 'h': 0.2, 'd': 2.0},
      material: colorMat(SceneColors.green),
    );
    outset(outer, amounts[i]);
    model.add(outer, tag: 'outer');
    final base = sceneObject(
      id: 'base_$i',
      name: 'Площадка $i',
      kind: 'cuboid',
      x: x,
      y: 0.2,
      z: 3,
      dims: const {'w': 2.0, 'h': 0.2, 'd': 2.0},
      material: colorMat(SceneColors.gray),
    );
    model.add(base, tag: 'base');
    final inner = sceneObject(
      id: 'inner_$i',
      name: 'Внутрь ${amounts[i]}',
      kind: 'cuboid',
      x: x,
      y: 0.4,
      z: 3,
      dims: const {'w': 2.0, 'h': 0.2, 'd': 2.0},
      material: colorMat(SceneColors.cyan),
    );
    inset(inner, amounts[i]);
    model.add(inner, tag: 'inner');
  }
  return model.data;
}

/// 8. Растянуть до: элемент дотягивается дальней гранью до ближней грани
/// опоры, не проходя сквозь неё.
doc.ModelData buildPlacementStretch() {
  final model = ConstructionModel(
    id: 'placement_stretch',
    name: 'Растянуть до',
  );
  model.data.size = doc.ModelSize(w: 15, l: 6, h: 4);
  model.add(
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 7.5,
      z: 3,
      dims: const {'w': 15, 'd': 6},
      material: colorMat(SceneColors.gray),
    ),
    tag: 'ground',
  );
  final axes = [LevelAxis.x, LevelAxis.y, LevelAxis.z];
  final labels = ['x', 'y', 'z'];
  for (var i = 0; i < axes.length; i++) {
    final x = 2.0 + i * 5.0;
    // Опора смещена от элемента вдоль своей оси.
    final post = switch (axes[i]) {
      LevelAxis.x => sceneObject(
        id: 'post_$i',
        name: 'Опора ${labels[i]}',
        kind: 'cuboid',
        x: x + 1.8,
        y: 0,
        z: 3,
        dims: const {'w': 0.5, 'h': 1.8, 'd': 0.5},
        material: colorMat(SceneColors.gray),
      ),
      LevelAxis.y => sceneObject(
        id: 'post_$i',
        name: 'Опора ${labels[i]}',
        kind: 'cuboid',
        x: x,
        y: 2.4,
        z: 3,
        dims: const {'w': 0.5, 'h': 0.5, 'd': 0.5},
        material: colorMat(SceneColors.gray),
      ),
      LevelAxis.z => sceneObject(
        id: 'post_$i',
        name: 'Опора ${labels[i]}',
        kind: 'cuboid',
        x: x,
        y: 0,
        z: 3 + 1.8,
        dims: const {'w': 0.5, 'h': 1.8, 'd': 0.5},
        material: colorMat(SceneColors.gray),
      ),
    };
    model.add(post, tag: 'post');
    final element = switch (axes[i]) {
      LevelAxis.x => sceneObject(
        id: 'element_$i',
        name: 'Элемент ${labels[i]}',
        kind: 'cuboid',
        x: x - 1.4,
        y: 0,
        z: 3,
        dims: const {'w': 0.4, 'h': 0.4, 'd': 0.4},
        material: colorMat(SceneColors.cyan),
      ),
      LevelAxis.y => sceneObject(
        id: 'element_$i',
        name: 'Элемент ${labels[i]}',
        kind: 'cuboid',
        x: x,
        y: 0,
        z: 3,
        dims: const {'w': 0.4, 'h': 0.4, 'd': 0.4},
        material: colorMat(SceneColors.cyan),
      ),
      LevelAxis.z => sceneObject(
        id: 'element_$i',
        name: 'Элемент ${labels[i]}',
        kind: 'cuboid',
        x: x,
        y: 0,
        z: 3 - 1.4,
        dims: const {'w': 0.4, 'h': 0.4, 'd': 0.4},
        material: colorMat(SceneColors.cyan),
      ),
    };
    stretchTo(element, post, axes[i]);
    model.add(element, tag: 'element');
  }
  return model.data;
}

/// Панель-легенда для сцен размещения: цвет и его роль.
Widget placementLegend(List<(List<int>, String)> entries) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      fcTitle('Обозначения'),
      fcLegend([
        for (final (color, label) in entries)
          LegendEntry(rgbColor(color), label),
      ]),
      fcNote('Камера фиксированная: все примеры операции видны в одном кадре.'),
    ],
  );
}

// ── описания фич ────────────────────────────────────────────────────────

final FeatureSpec placementSnapFacesFeature = FeatureSpec(
  id: 'placement_ops',
  group: kFeatureGroups[6],
  title: 'Прильнуть к грани: все шесть',
  phase: 3,
  description:
      'Вокруг куба-опоры с разноцветными гранями стоят шесть тонких '
      'табличек — по одной на каждую грань. Цвет таблички совпадает с цветом '
      'грани, к которой она прильнула. Операция ставит якорь элемента в центр '
      'грани и разворачивает его по нормали грани.',
  checks: const [
    'Каждая табличка стоит у грани того же цвета, что и она сама.',
    'Между табличкой и гранью виден одинаковый зазор, пересечений нет.',
    'Табличка на верхней грани лежит сверху, на нижней — снизу, боковые стоят сбоку.',
  ],
  build: (context) => buildPlacementSnapFaces(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([214, 76, 76], 'Табличка грани +x'),
    ([86, 132, 214], 'Табличка грани −x'),
    ([96, 186, 112], 'Табличка грани +y (верх)'),
    ([222, 196, 88], 'Табличка грани −y (низ)'),
    ([230, 150, 70], 'Табличка грани +z'),
    ([166, 106, 214], 'Табличка грани −z'),
  ]),
);

final FeatureSpec placementSnapCylinderFeature = FeatureSpec(
  id: 'placement_snap_cylinder',
  group: kFeatureGroups[6],
  title: 'Прильнуть к цилиндру: бок, торцы, наклоны',
  phase: 3,
  description:
      'Слева цилиндр: четыре голубые таблички на боку под разными '
      'углами и по табличке на верхнем и нижнем торцах. В середине конус, '
      'справа наклонённый цилиндр. Операция прилегания использует точку '
      'нажатия, поэтому таблички на боку стоят по нормали поверхности.',
  checks: const [
    'Таблички на боку цилиндра стоят на середине высоты и не пересекают его.',
    'Таблички на торцах лежат на верхнем и нижнем дисках.',
    'На конусе и наклонённом цилиндре табличка повторяет наклон поверхности.',
  ],
  build: (context) => buildPlacementSnapCylinder(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Цилиндр, конус, наклонённый цилиндр'),
    ([86, 196, 204], 'Табличка, прильнувшая к поверхности'),
    ([86, 132, 214], 'Таблички на торцах'),
  ]),
);

final FeatureSpec placementParallelFeature = FeatureSpec(
  id: 'placement_parallel',
  group: kFeatureGroups[6],
  title: 'Встать параллельно грани',
  phase: 3,
  description:
      'На каждой грани куба-опоры лежит табличка, на ней стоит '
      'брусок. Локальная ось +Y таблички и бруска смотрит по нормали грани, '
      'поэтому тела развёрнуты параллельно поверхности и не пересекают её. '
      'На верхней и нижней опорах брусок стоит вертикально вдоль нормали, '
      'на боковых — вертикально в плоскости грани.',
  checks: const [
    'Табличка каждой грани лежит в плоскости грани и не пересекает её.',
    'Брусок стоит вертикально: на верхней и нижней опорах — вверх от грани, на боковых — в плоскости грани.',
    'Брусок и табличка не пересекают друг друга.',
  ],
  build: (context) => buildPlacementParallel(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([214, 76, 76], 'Табличка грани +x'),
    ([86, 132, 214], 'Табличка грани −x'),
    ([96, 186, 112], 'Табличка грани +y'),
    ([222, 196, 88], 'Табличка грани −y'),
    ([230, 150, 70], 'Табличка грани +z'),
    ([166, 106, 214], 'Табличка грани −z'),
    ([86, 196, 204], 'Брусок вдоль нормали'),
  ]),
);

final FeatureSpec placementAlignFeature = FeatureSpec(
  id: 'placement_align',
  group: kFeatureGroups[6],
  title: 'Выровнять по осям',
  phase: 3,
  description:
      'Три пары «опора и элемент»: по X, Y и Z. Зелёный элемент '
      'смещён по всем осям, голубой выровнен по выбранной оси: их центры '
      'совпадают по этой оси, а по двум другим смещение сохраняется.',
  checks: const [
    'Голубой элемент совпадает с опорой по центру выбранной оси (X, Y или Z).',
    'По двум другим осям смещение голубого элемента такое же, как у зелёного.',
    'Выравнивание не меняет размеры элементов.',
  ],
  build: (context) => buildPlacementAlign(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Опора'),
    ([96, 186, 112], 'Элемент до выравнивания'),
    ([86, 196, 204], 'Элемент после выравнивания'),
  ]),
);

final FeatureSpec placementFillGapFeature = FeatureSpec(
  id: 'placement_fill_gap',
  group: kFeatureGroups[6],
  title: 'Заполнить промежуток',
  phase: 3,
  description:
      'Три пары серых стоек с промежутками по X, Y и Z. Голубой '
      'заполнитель растянут точно между ближними гранями стоек: он не '
      'оставляет зазора и не заходит на сами стойки.',
  checks: const [
    'Заполнитель упирается в ближние грани обеих стоек без зазора и нахлёста.',
    'Размер заполнителя по оси равен расстоянию между стойками.',
    'Поперечное сечение заполнителя не меняется.',
  ],
  build: (context) => buildPlacementFillGap(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Стойки промежутка'),
    ([86, 196, 204], 'Заполнитель'),
  ]),
);

final FeatureSpec placementCoverFeature = FeatureSpec(
  id: 'placement_cover',
  group: kFeatureGroups[6],
  title: 'Накрыть',
  phase: 3,
  description:
      'Три площадки разного размера; голубая крышка повторяет '
      'размер площадки по X и Z и стоит нижней гранью на её верхней грани.',
  checks: const [
    'Крышка совпадает с площадкой по размеру и центру.',
    'Низ крышки стоит ровно на верхней грани площадки.',
    'У большой площадки крышка больше, у маленькой — меньше.',
  ],
  build: (context) => buildPlacementCover(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Площадка'),
    ([86, 196, 204], 'Крышка'),
  ]),
);

final FeatureSpec placementInsetOutsetFeature = FeatureSpec(
  id: 'placement_inset_outset',
  group: kFeatureGroups[6],
  title: 'Отступить внутрь и наружу',
  phase: 3,
  description:
      'Для каждой площадки показаны две копии: голубая уменьшена '
      'отступом внутрь, зелёная увеличена отступом наружу. Отступ откладывается '
      'с каждой стороны, поэтому размер меняется на удвоенную величину. Копии '
      'уложены концентрической стопкой (зелёная снизу, серая основа, голубая '
      'сверху), чтобы все три были видны в одном кадре.',
  checks: const [
    'Голубая копия меньше исходной с каждой стороны на величину отступа.',
    'Зелёная копия больше исходной с каждой стороны на величину отступа.',
    'При отступе больше половины размера копия не становится отрицательной.',
  ],
  build: (context) => buildPlacementInsetOutset(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Исходная площадка'),
    ([86, 196, 204], 'Отступ внутрь'),
    ([96, 186, 112], 'Отступ наружу'),
  ]),
);

final FeatureSpec placementStretchFeature = FeatureSpec(
  id: 'placement_stretch',
  group: kFeatureGroups[6],
  title: 'Растянуть до',
  phase: 3,
  description:
      'Три примера: голубой элемент растягивается до ближней грани '
      'серой опоры по X, Y и Z. Элемент дотягивается до опоры и не проходит '
      'сквозь неё.',
  checks: const [
    'Элемент дотягивается до ближней грани опоры и не проходит сквозь неё.',
    'Растягивается только выбранная ось, поперечное сечение сохраняется.',
    'Направление растяжения определяется положением опоры.',
  ],
  build: (context) => buildPlacementStretch(),
  camera: CameraMode.fixed,
  controls: (context, feature) => placementLegend(const [
    ([150, 156, 166], 'Опора'),
    ([86, 196, 204], 'Растянутый элемент'),
  ]),
);

/// Фичи группы «Операции размещения».
final List<FeatureSpec> placementFeatures = [
  placementSnapFacesFeature,
  placementSnapCylinderFeature,
  placementParallelFeature,
  placementAlignFeature,
  placementFillGapFeature,
  placementCoverFeature,
  placementInsetOutsetFeature,
  placementStretchFeature,
];
