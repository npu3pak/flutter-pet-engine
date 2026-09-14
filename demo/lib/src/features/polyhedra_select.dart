import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';
import 'polyhedra_common.dart';

/// Мировая матрица объекта документа: зеркальный якорь ([chunkWorld]) ·
/// поворот · масштаб — ровно то, что применяет рендер. Помощник нужен,
/// чтобы рисовать подсветку выбранных граней и вершин поверх сцены.
vm.Matrix4 documentObjectWorld(doc.ModelData model, doc.ModelObject object) {
  final anchor = chunkWorld(
    object.x,
    object.z,
    model.size.w,
    model.size.l,
  );
  return vm.Matrix4.translation(vm.Vector3(anchor.x, object.y, anchor.z)) *
      objectRotation(object) *
      objectScale(object);
}

/// Отрезки контуров одной грани в мировых координатах (внешний контур и
/// дырки): пары точек для [LineGeometry].
List<vm.Vector3> faceOutlinePoints(
  doc.ModelData model,
  doc.ModelObject object,
  String faceKey,
) {
  final matrix = documentObjectWorld(model, object);
  final points = <vm.Vector3>[];
  for (final loop in faceLoops(object, faceKey)) {
    for (var i = 0; i < loop.length; i++) {
      points
        ..add(matrix.transform3(loop[i].clone()))
        ..add(matrix.transform3(loop[(i + 1) % loop.length].clone()));
    }
  }
  return points;
}

/// Индекс ближайшей к нажатию вершины: [project] переводит мировую точку в
/// экранные координаты (null — точка за камерой). Возвращает null, если в
/// радиусе [radius] пикселей ничего нет. Чистая функция — тестируется без
/// видеокарты.
int? nearestVertexIndex({
  required List<vm.Vector3> worldVertices,
  required Offset tap,
  required Offset? Function(vm.Vector3) project,
  double radius = 14,
}) {
  var best = -1;
  var bestDistance = radius * radius;
  for (var i = 0; i < worldVertices.length; i++) {
    final screen = project(worldVertices[i]);
    if (screen == null) continue;
    final distance = (screen - tap).distanceSquared;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best < 0 ? null : best;
}

/// Сцена: три многогранника на площадке.
doc.ModelData buildPolyhedraSelectScene(FeatureBuildContext context) {
  final prism = extrudeProfile(
    profile: [
      vm.Vector2(-1.1, -1.1),
      vm.Vector2(1.1, -1.1),
      vm.Vector2(1.1, -0.3),
      vm.Vector2(-0.3, -0.3),
      vm.Vector2(-0.3, 1.1),
      vm.Vector2(-1.1, 1.1),
    ],
    height: 1.4,
  );
  final slab = plateWithHole(
    width: 1.8,
    depth: 1.8,
    thickness: 0.35,
    holeWidth: 0.9,
    holeDepth: 0.9,
  );
  return doc.ModelData(
    id: 'polyhedra_select',
    name: 'Многогранники: выделение',
    size: doc.ModelSize(w: 8, l: 5, h: 3),
    objects: [
      sceneObject(
        id: 'ground',
        name: 'Площадка',
        kind: 'plane',
        x: 4,
        z: 2.5,
        dims: const {'w': 8, 'd': 5},
        material: colorMat(SceneColors.gray),
      ),
      polyhedronObject(
        id: 'box',
        name: 'Куб',
        mesh: PolyMesh.box(w: 1.1, h: 1.1, d: 1.1),
        x: 1.5,
        z: 2.5,
        material: colorMat(SceneColors.blue),
        faces: {'+y': colorMat(SceneColors.green)},
      ),
      polyhedronObject(
        id: 'prism',
        name: 'L-призма',
        mesh: prism,
        x: 4,
        z: 2.5,
        material: colorMat(SceneColors.orange),
        faces: {'+y': colorMat(SceneColors.green)},
      ),
      polyhedronObject(
        id: 'slab',
        name: 'Плита с отверстием',
        mesh: slab,
        x: 6.5,
        y: 0.8,
        z: 2.5,
        material: colorMat(SceneColors.cyan),
        faces: {
          '+y': colorMat(SceneColors.green),
          'hole_0': colorMat(SceneColors.red),
          'hole_1': colorMat(SceneColors.red),
          'hole_2': colorMat(SceneColors.red),
          'hole_3': colorMat(SceneColors.red),
        },
      ),
    ],
  );
}

final FeatureSpec polyhedraSelectFeature = FeatureSpec(
  id: 'polyhedra_select',
  group: kFeatureGroups[8],
  title: 'Выделение граней и вершин',
  phase: 6,
  description:
      'Нажатие по сцене выбирает грань или вершину многогранника. Активный '
      'элемент подсвечивается жёлтым, остальные в группе — голубым; '
      'переключатель «Добавлять к выделению» заменяет Shift. Режим вершин '
      'показывает крестики всех вершин и выбирает ближайшую к нажатию.',
  checks: const [
    'Нажатие по грани подсвечивает её контур жёлтым; подпись внизу называет объект и грань.',
    'Включите «Добавлять к выделению» и нажмите вторую грань — она станет жёлтой, первая останется голубой.',
    'В режиме вершин видны крестики у всех вершин; нажатие рядом с вершиной выделяет её.',
    'Контур грани с отверстием обводит и отверстие; нажатие по пустому месту снимает выделение.',
  ],
  build: buildPolyhedraSelectScene,
  camera: CameraMode.free,
  controls: (context, feature) => _PolyhedraSelectControls(feature: feature),
);

class _PolyhedraSelectControls extends StatefulWidget {
  const _PolyhedraSelectControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_PolyhedraSelectControls> createState() =>
      _PolyhedraSelectControlsState();
}

class _PolyhedraSelectControlsState extends State<_PolyhedraSelectControls> {
  static const activeColor = Color(0xFFFFD91A);
  static const groupColor = Color(0xFF35D0FF);
  static const markerColor = Color(0x66FFFFFF);

  GroupNode? _root;
  GroupNode? _highlight;
  final Set<String> _selected = {};
  String? _active;
  bool _additive = false;
  String _mode = 'faces';
  String _report = 'нажмите по грани многогранника';

  @override
  void initState() {
    super.initState();
    widget.feature.setTap(_handleTap);
    final controller = widget.feature.controller;
    if (controller == null) return;
    final root = attachFeatureRoot(controller, 'polyhedra-select');
    _root = root;
    _refresh();
  }

  @override
  void dispose() {
    widget.feature.setTap(null);
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _selected.clear();
      _active = null;
      _report = mode == 'faces'
          ? 'нажмите по грани многогранника'
          : 'нажмите рядом с вершиной';
    });
    _refresh();
  }

  void _handleTap(Offset position, Size size) {
    final controller = widget.feature.controller;
    if (controller == null) return;
    final key = _mode == 'faces'
        ? _faceKeyAt(controller, position)
        : _vertexKeyAt(controller, position);
    setState(() {
      if (key == null) {
        if (!_additive) {
          _selected.clear();
          _active = null;
          _report = _mode == 'faces'
              ? 'промах: нажмите по грани'
              : 'промах: нажмите рядом с вершиной';
        }
      } else if (_additive) {
        if (!_selected.remove(key)) _selected.add(key);
        _active = key;
        _report = 'выбрано: $key (всего ${_selected.length})';
      } else {
        _selected
          ..clear()
          ..add(key);
        _active = key;
        _report = 'выбрано: $key';
      }
    });
    _refresh();
  }

  String? _faceKeyAt(SceneController controller, Offset position) {
    final hit = controller.raycast(position);
    final node = hit?.node;
    if (node is! ModelNode || hit?.face == null) return null;
    final object = node.object;
    if (!object.isPolyhedron) return null;
    return '${object.id}:${hit!.face!.key}';
  }

  String? _vertexKeyAt(SceneController controller, Offset position) {
    final model = controller.model;
    if (model == null) return null;
    String? bestKey;
    var bestDistance = 14.0 * 14.0;
    for (final object in model.objects) {
      final mesh = object.mesh;
      if (!object.isPolyhedron || mesh == null) continue;
      final matrix = documentObjectWorld(model, object);
      for (var i = 0; i < mesh.vertices.length; i++) {
        final world = matrix.transform3(mesh.vertices[i].clone());
        final screen = controller.worldToScreen(world);
        if (screen == null) continue;
        final distance = (screen - position).distanceSquared;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestKey = '${object.id}:$i';
        }
      }
    }
    return bestKey;
  }

  void _refresh() {
    final controller = widget.feature.controller;
    final root = _root;
    if (controller == null || root == null) return;
    _highlight?.remove();
    final group = GroupNode(name: 'polyhedra-select-highlight');
    _highlight = group;
    root.add(group);
    final model = controller.model;
    if (model == null) return;

    if (_mode == 'faces') {
      for (final key in _selected) {
        final separator = key.indexOf(':');
        final object = model.objectById(key.substring(0, separator));
        if (object == null || !object.isPolyhedron) continue;
        final points = faceOutlinePoints(
          model,
          object,
          key.substring(separator + 1),
        );
        if (points.isEmpty) continue;
        final node = LineNode(
          geometry: LineGeometry(points, widthPx: 2),
          color: key == _active ? activeColor : groupColor,
        );
        node.layer = SceneLayer.overlay;
        group.add(node);
      }
      return;
    }

    final normal = <vm.Vector3>[];
    final groupPoints = <vm.Vector3>[];
    final activePoints = <vm.Vector3>[];
    for (final object in model.objects) {
      final mesh = object.mesh;
      if (!object.isPolyhedron || mesh == null) continue;
      final matrix = documentObjectWorld(model, object);
      for (var i = 0; i < mesh.vertices.length; i++) {
        final world = matrix.transform3(mesh.vertices[i].clone());
        final key = '${object.id}:$i';
        final target = !_selected.contains(key)
            ? normal
            : (key == _active ? activePoints : groupPoints);
        _addCross(target, world);
      }
    }
    for (final (points, color) in [
      (normal, markerColor),
      (groupPoints, groupColor),
      (activePoints, activeColor),
    ]) {
      if (points.isEmpty) continue;
      final node = LineNode(
        geometry: LineGeometry(points, widthPx: 1),
        color: color,
      );
      node.layer = SceneLayer.overlay;
      group.add(node);
    }
  }

  void _addCross(List<vm.Vector3> out, vm.Vector3 point) {
    const m = 0.07;
    out
      ..add(point + vm.Vector3(-m, 0, 0))
      ..add(point + vm.Vector3(m, 0, 0))
      ..add(point + vm.Vector3(0, -m, 0))
      ..add(point + vm.Vector3(0, m, 0))
      ..add(point + vm.Vector3(0, 0, -m))
      ..add(point + vm.Vector3(0, 0, m));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcChoice<String>(
          label: 'Режим',
          values: const ['faces', 'vertices'],
          selected: _mode,
          labelOf: (value) => value == 'faces' ? 'Грани' : 'Вершины',
          onChanged: _setMode,
        ),
        fcSwitch(
          label: 'Добавлять к выделению (Shift)',
          value: _additive,
          onChanged: (value) => setState(() => _additive = value),
        ),
        fcButton('Снять выделение', () {
          setState(() {
            _selected.clear();
            _active = null;
            _report = 'выделение снято';
          });
          _refresh();
        }),
        const SizedBox(height: 6),
        Text(
          _report,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcLegend([
          LegendEntry(activeColor, 'Активный элемент'),
          LegendEntry(groupColor, 'Остальные выбранные (Shift)'),
          LegendEntry(markerColor, 'Все вершины в режиме вершин'),
        ]),
        fcNote(
          'Грань выбирается лучом (controller.raycast), вершина — ближайшей '
          'проекцией среди всех вершин (controller.worldToScreen). Подсветка '
          'рисуется линиями по faceLoops в мировых координатах: контур '
          'внешний плюс отверстия. Эти же приёмы будет использовать редактор.',
        ),
      ],
    );
  }
}
