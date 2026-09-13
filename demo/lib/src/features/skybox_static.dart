import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Ключ панорамы в проекте Pet.
const skyboxTextureKey = 'skybox_1.png';

/// Небольшая площадка с ориентирами: на её фоне видно прокрутку панорамы.
doc.ModelData buildSkyboxScene(FeatureBuildContext context) {
  return doc.ModelData(
    id: 'skybox_static',
    name: 'Статический скайбокс',
    size: doc.ModelSize(w: 10, l: 10, h: 3),
    objects: [
      sceneObject(
        id: 'ground',
        name: 'Земля',
        kind: 'plane',
        x: 4.5,
        z: 4.5,
        dims: const {'w': 12, 'd': 12},
        material: colorMat(SceneColors.gray),
      ),
      sceneObject(
        id: 'near',
        name: 'Ближний столб',
        kind: 'cuboid',
        x: 2,
        z: 2,
        dims: const {'w': 0.5, 'h': 1.6, 'd': 0.5},
        material: colorMat(SceneColors.red),
      ),
      sceneObject(
        id: 'far',
        name: 'Дальний столб',
        kind: 'cuboid',
        x: 8,
        z: 6,
        dims: const {'w': 0.5, 'h': 2.4, 'd': 0.5},
        material: colorMat(SceneColors.green),
      ),
      sceneObject(
        id: 'wall',
        name: 'Стена',
        kind: 'cuboid',
        x: 4.5,
        z: 9,
        dims: const {'w': 7, 'h': 1.2, 'd': 0.4},
        material: colorMat(SceneColors.blue),
      ),
    ],
  );
}

final FeatureSpec skyboxStaticFeature = FeatureSpec(
  id: 'skybox_static',
  group: kFeatureGroups[1],
  title: 'Статический скайбокс',
  project: 'Pet',
  phase: 5,
  description:
      'Статический скайбокс движка: панорама из проекта рисуется за '
      'трёхмерной сценой и прокручивается при повороте камеры по тому же '
      'расчёту, что и игровая камера. Картинка предзагружается до показа, '
      'поэтому небо не появляется после сцены; у горизонта включается дымка '
      'того же цвета, что и туман сцены.',
  checks: const [
    'Панорама неба видна за трёхмерной сценой и не перекрывает объекты.',
    'При повороте свободной камеры панорама прокручивается без швов и рывков.',
    'Дымка у горизонта включается переключателем и совпадает по цвету с туманом.',
    'При отсутствии картинки небо не рисуется, а сцена и управление работают.',
  ],
  build: buildSkyboxScene,
  camera: CameraMode.free,
  controls: (context, feature) => _SkyboxControls(feature: feature),
);

class _SkyboxControls extends StatefulWidget {
  const _SkyboxControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_SkyboxControls> createState() => _SkyboxControlsState();
}

class _SkyboxControlsState extends State<_SkyboxControls> {
  ui.Image? _image;
  SkyboxNode? _sky;
  SkyboxImageLayer? _layer;
  bool _loading = true;
  bool _missing = false;
  bool _fog = true;
  double _fogStrength = 0.45;

  static const _fogColor = Color(0xFF9FB6C8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sky?.remove();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bytes = await widget.feature.project?.readBytes(
      'textures/$skyboxTextureKey',
    );
    final image = await loadSkyboxImage(bytes);
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      _loading = false;
      _missing = image == null;
    });
    _install();
  }

  void _install() {
    final image = _image;
    if (image == null) return;
    final controller = widget.feature.controller;
    if (controller == null) return;
    var sky = _sky;
    if (sky == null) {
      sky = SkyboxNode(backgroundColor: const Color(0xFF0B0E14));
      controller.add(sky);
      _sky = sky;
    }
    var layer = _layer;
    if (layer == null) {
      layer = SkyboxImageLayer(image: image, fogColor: _fogColor);
      sky.addLayer(layer);
      _layer = layer;
    }
    layer
      ..fogColor = _fog ? _fogColor : null
      ..fogStrength = _fog ? _fogStrength : 0.0;
    widget.feature.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Панорама неба'),
        if (_loading) const LinearProgressIndicator(),
        Text(
          _missing
              ? 'Картинка textures/$skyboxTextureKey не найдена.'
              : 'Загружена textures/$skyboxTextureKey.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcSwitch(
          label: 'Дымка у горизонта',
          value: _fog,
          onChanged: (v) {
            setState(() => _fog = v);
            _install();
          },
        ),
        fcSlider(
          label: 'Сила дымки',
          value: _fogStrength,
          min: 0,
          max: 1,
          onChanged: (v) {
            setState(() => _fogStrength = v);
            _install();
          },
        ),
        fcNote(
          'Поверните камеру перетаскиванием — панорама прокрутится. '
          'Дымка совпадает по цвету с туманом сцены и не перекрывает небо '
          'целиком.',
        ),
      ],
    );
  }
}
