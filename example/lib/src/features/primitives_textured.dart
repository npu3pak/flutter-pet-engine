import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Те же примитивы с наложенными текстурами; режимы задаются управлением.
doc.ModelData buildTexturedPrimitivesScene(FeatureBuildContext context) {
  final stretch = context.param<String>('stretch') ?? 'stretch';
  final tileScale = context.param<double>('tileScale') ?? 1.0;
  final uvDir = context.param<int>('uvDir') ?? 0;
  final flipX = context.param<bool>('flipX') ?? false;
  final flipY = context.param<bool>('flipY') ?? false;
  final side = context.param<String>('side') ?? 'outer';
  final faceMode = context.param<String>('faceMode') ?? 'all';
  final materialKind = context.param<String>('materialKind') ?? 'texture';

  doc.ModelMaterial materialFor(String texturePrefix, List<int> color) {
    return switch (materialKind) {
      'color' => colorMat(color, side: side),
      'sprite' => spriteMat(pickSprite(context, 'window_'), side: side),
      _ => textureMat(
        pickTexture(context, texturePrefix),
        stretch: stretch,
        tileScale: tileScale,
        uvDir: uvDir,
        flipX: flipX,
        flipY: flipY,
        side: side,
      ),
    };
  }

  doc.ModelObject textured({
    required String id,
    required String name,
    required String kind,
    required double x,
    required double z,
    required Map<String, num> dims,
    required String texturePrefix,
    required List<int> color,
    double y = 0,
  }) {
    final material = materialFor(texturePrefix, color);
    if (faceMode == 'face') {
      return sceneObject(
        id: id,
        name: name,
        kind: kind,
        x: x,
        y: y,
        z: z,
        dims: dims,
        material: colorMat(SceneColors.gray),
        faces: {'+y': material},
      );
    }
    return sceneObject(
      id: id,
      name: name,
      kind: kind,
      x: x,
      y: y,
      z: z,
      dims: dims,
      material: material,
    );
  }

  final objects = <doc.ModelObject>[
    textured(
      id: 'cube',
      name: 'Куб',
      kind: 'cuboid',
      x: 1.5,
      z: 2,
      dims: const {'w': 1.2, 'h': 1.2, 'd': 1.2},
      texturePrefix: 'wallpaper_',
      color: SceneColors.red,
    ),
    textured(
      id: 'rounded',
      name: 'Куб со скруглением',
      kind: 'cuboid',
      x: 3.5,
      z: 2,
      dims: const {
        'w': 1.2,
        'h': 1.2,
        'd': 1.2,
        'roundR': 0.25,
        'roundSegments': 12,
      },
      texturePrefix: 'fabric_',
      color: SceneColors.green,
    ),
    textured(
      id: 'trapezoid',
      name: 'Трапеция',
      kind: 'trapezoid',
      x: 5.5,
      z: 2,
      dims: const {
        'bottomW': 1.4,
        'bottomD': 1.4,
        'topW': 0.6,
        'topD': 0.6,
        'h': 1.2,
      },
      texturePrefix: 'wallpaper_',
      color: SceneColors.blue,
    ),
    textured(
      id: 'cylinder',
      name: 'Цилиндр',
      kind: 'cylinder',
      x: 7.5,
      z: 2,
      dims: const {'bottomR': 0.55, 'topR': 0.55, 'h': 1.2, 'segments': 24},
      texturePrefix: 'fabric_',
      color: SceneColors.orange,
    ),
    textured(
      id: 'cone',
      name: 'Конус',
      kind: 'cylinder',
      x: 1.5,
      z: 5,
      dims: const {'bottomR': 0.55, 'topR': 0.0, 'h': 1.2, 'segments': 24},
      texturePrefix: 'wallpaper_',
      color: SceneColors.purple,
    ),
    textured(
      id: 'plane_h',
      name: 'Горизонтальная плоскость',
      kind: 'plane',
      x: 3.5,
      z: 5,
      dims: const {'w': 1.6, 'd': 1.6},
      texturePrefix: 'floor_',
      color: SceneColors.gray,
    ),
    textured(
      id: 'plane_v',
      name: 'Вертикальная плоскость',
      kind: 'plane',
      x: 5.5,
      z: 5,
      dims: const {'w': 1.6, 'd': 1.6, 'vertical': 1},
      texturePrefix: 'wallpaper_',
      color: SceneColors.yellow,
    ),
    textured(
      id: 'sprite',
      name: 'Спрайт',
      kind: 'sprite',
      x: 7.5,
      y: 0.45,
      z: 5,
      dims: const {'w': 0.9, 'h': 0.9},
      texturePrefix: 'window_',
      color: SceneColors.cyan,
    ),
  ];
  return doc.ModelData(
    id: 'primitives_textured',
    name: 'Текстурирование примитивов',
    size: doc.ModelSize(w: 9, l: 7, h: 3),
    objects: objects,
  );
}

final FeatureSpec primitivesTexturedFeature = FeatureSpec(
  id: 'primitives_textured',
  group: kFeatureGroups[0],
  title: 'Текстурирование примитивов',
  project: 'Pet',
  phase: 1,
  description:
      'Те же примитивы, что и на предыдущей сцене, но с материалами: '
      'цвет, текстура из проекта Pet и спрайт из его набора. Управление '
      'переключает растяжение и замостивание, масштаб мозаики, поворот и '
      'отражение рисунка, видимую сторону, материал на весь объект или на '
      'одну грань.',
  checks: const [
    'Переключатель «растянуть / замостить» меняет рисунок на гранях куба: при замостивании видно повторение узора.',
    'Ползунок масштаба мозаики увеличивает и уменьшает рисунок, а ползунок поворота меняет его ориентацию на 90 градусов.',
    'Отражение по осям X и Y зеркалит рисунок, не меняя форму объекта.',
    'Материал «на одну грань» виден только на верхней грани, остальные грани остаются серыми.',
    'Режим «обе стороны» делает материал видимым и с внутренней стороны поверхности.',
  ],
  build: buildTexturedPrimitivesScene,
  camera: CameraMode.free,
  controls: (context, feature) => _TexturedControls(feature: feature),
);

class _TexturedControls extends StatefulWidget {
  const _TexturedControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_TexturedControls> createState() => _TexturedControlsState();
}

class _TexturedControlsState extends State<_TexturedControls> {
  late String _stretch;
  late double _tileScale;
  late int _uvDir;
  late bool _flipX;
  late bool _flipY;
  late String _side;
  late String _faceMode;
  late String _materialKind;

  @override
  void initState() {
    super.initState();
    final params = widget.feature.params;
    _stretch = params['stretch'] as String? ?? 'stretch';
    _tileScale = params['tileScale'] as double? ?? 1.0;
    _uvDir = params['uvDir'] as int? ?? 0;
    _flipX = params['flipX'] as bool? ?? false;
    _flipY = params['flipY'] as bool? ?? false;
    _side = params['side'] as String? ?? 'outer';
    _faceMode = params['faceMode'] as String? ?? 'all';
    _materialKind = params['materialKind'] as String? ?? 'texture';
  }

  void _update() {
    widget.feature.updateParams({
      'stretch': _stretch,
      'tileScale': _tileScale,
      'uvDir': _uvDir,
      'flipX': _flipX,
      'flipY': _flipY,
      'side': _side,
      'faceMode': _faceMode,
      'materialKind': _materialKind,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Материал'),
        fcChoice<String>(
          label: 'Тип материала',
          values: const ['texture', 'color', 'sprite'],
          selected: _materialKind,
          labelOf: (v) => switch (v) {
            'color' => 'цвет',
            'sprite' => 'спрайт',
            _ => 'текстура',
          },
          onChanged: (v) {
            setState(() => _materialKind = v);
            _update();
          },
        ),
        fcChoice<String>(
          label: 'Нанесение',
          values: const ['stretch', 'tile'],
          selected: _stretch,
          labelOf: (v) => v == 'tile' ? 'замостить' : 'растянуть',
          onChanged: (v) {
            setState(() => _stretch = v);
            _update();
          },
        ),
        fcSlider(
          label: 'Масштаб мозаики',
          value: _tileScale,
          min: 0.25,
          max: 4,
          onChanged: (v) {
            setState(() => _tileScale = v);
            _update();
          },
        ),
        fcChoice<int>(
          label: 'Поворот рисунка',
          values: const [0, 90, 180, 270],
          selected: _uvDir,
          labelOf: (v) => '$v°',
          onChanged: (v) {
            setState(() => _uvDir = v);
            _update();
          },
        ),
        fcSwitch(
          label: 'Отразить по оси X',
          value: _flipX,
          onChanged: (v) {
            setState(() => _flipX = v);
            _update();
          },
        ),
        fcSwitch(
          label: 'Отразить по оси Y',
          value: _flipY,
          onChanged: (v) {
            setState(() => _flipY = v);
            _update();
          },
        ),
        fcChoice<String>(
          label: 'Видимая сторона',
          values: const ['outer', 'inner', 'both'],
          selected: _side,
          labelOf: (v) => switch (v) {
            'inner' => 'внутренняя',
            'both' => 'обе',
            _ => 'наружная',
          },
          onChanged: (v) {
            setState(() => _side = v);
            _update();
          },
        ),
        fcChoice<String>(
          label: 'Куда наносить',
          values: const ['all', 'face'],
          selected: _faceMode,
          labelOf: (v) => v == 'face' ? 'на одну грань' : 'на весь объект',
          onChanged: (v) {
            setState(() => _faceMode = v);
            _update();
          },
        ),
        fcNote(
          'Материал на одну грань наносится на верхнюю грань (+y); '
          'остальные грани остаются серыми.',
        ),
      ],
    );
  }
}
