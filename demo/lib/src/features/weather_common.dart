import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Погодная сцена: площадка, стены и ориентиры, чтобы частицы было видно.
doc.ModelData buildWeatherScene(FeatureBuildContext context, String id) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 6,
      z: 6,
      dims: const {'w': 12, 'd': 12},
      material: colorMat(SceneColors.gray),
    ),
    for (final (name, x, z, h) in const [
      ('building_1', 2.0, 2.0, 2.4),
      ('building_2', 10.0, 2.0, 3.0),
      ('building_3', 2.0, 10.0, 2.0),
      ('building_4', 10.0, 10.0, 2.6),
    ])
      sceneObject(
        id: name,
        name: 'Строение $name',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: {'w': 2.4, 'h': h, 'd': 2.4},
        material: colorMat(SceneColors.blue),
      ),
    sceneObject(
      id: 'lamp',
      name: 'Фонарь',
      kind: 'cylinder',
      x: 6,
      z: 6,
      dims: const {'bottomR': 0.15, 'topR': 0.15, 'h': 3.0, 'segments': 12},
      material: colorMat(SceneColors.orange),
    ),
  ];
  return doc.ModelData(
    id: id,
    name: 'Погода',
    size: doc.ModelSize(w: 12, l: 12, h: 4),
    objects: objects,
  );
}

/// Копия конфигурации частиц с заменой отдельных полей.
ParticleConfig copyParticleConfig(
  ParticleConfig base, {
  int? maxPerCell,
  int? fullDensityRings,
  int? viewRadius,
  double? spawnChance,
  double? windSpeed,
  double? opacity,
  vm.Vector3? windDirection,
}) {
  return ParticleConfig(
    kind: base.kind,
    sprites: base.sprites,
    maxPerCell: maxPerCell ?? base.maxPerCell,
    fullDensityRings: fullDensityRings ?? base.fullDensityRings,
    viewRadius: viewRadius ?? base.viewRadius,
    spawnChance: spawnChance ?? base.spawnChance,
    bottomY: base.bottomY,
    topY: base.topY,
    fallSpeedMin: base.fallSpeedMin,
    fallSpeedMax: base.fallSpeedMax,
    swayAmp: base.swayAmp,
    swayFreq: base.swayFreq,
    windSpeed: windSpeed ?? base.windSpeed,
    slantDrift: base.slantDrift,
    opacity: opacity ?? base.opacity,
    rotationSpin: base.rotationSpin,
    velocityStretch: base.velocityStretch,
    crisp: base.crisp,
    additive: base.additive,
    blendOrder: base.blendOrder,
    windDirection: windDirection ?? base.windDirection,
    color: base.color,
  );
}

/// Управление погодной фичей: пресет, включение и интенсивность.
class WeatherControls extends StatefulWidget {
  const WeatherControls({
    super.key,
    required this.feature,
    required this.preset,
    required this.note,
    this.secondPreset,
  });

  final FeatureContext feature;

  /// Основной пресет частиц.
  final ParticleConfig preset;

  /// Второй слой (для сквозняка — блики поверх струй).
  final ParticleConfig? secondPreset;

  /// Пояснение под управлением.
  final String note;

  @override
  State<WeatherControls> createState() => _WeatherControlsState();
}

class _WeatherControlsState extends State<WeatherControls> {
  ParticleNode? _layer;
  ParticleNode? _secondLayer;
  GroupNode? _root;
  bool _enabled = true;
  double _intensity = 1.0;

  @override
  void initState() {
    super.initState();
    _buildLayers();
  }

  @override
  void dispose() {
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  void _buildLayers() {
    final game = widget.feature.controller;
    if (game == null) return;
    final root = _root ?? attachFeatureRoot(game, 'weather-demo');
    _root = root;
    final model = game.model;
    final width = model?.size.w ?? 12;
    final length = model?.size.l ?? 12;
    final field = ParticleField(
      rows: length,
      columns: width,
      origin: chunkWorld(0, 0, width, length),
      seed: 11,
    );
    final focus = field.cellCenter(length ~/ 2, width ~/ 2);
    final layer = ParticleNode(
      name: 'weather',
      config: widget.preset.withIntensity(_intensity),
      field: field,
      intensity: _intensity,
      enabled: _enabled,
    )..focus = focus;
    root.add(layer);
    unawaited(layer.prepare());
    _layer = layer;
    final second = widget.secondPreset;
    if (second != null) {
      final extra = ParticleNode(
        name: 'weather-extra',
        config: second.withIntensity(_intensity),
        field: field,
        intensity: _intensity,
        enabled: _enabled,
      )..focus = focus;
      root.add(extra);
      unawaited(extra.prepare());
      _secondLayer = extra;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Погода'),
        fcSwitch(
          label: 'Включить частицы',
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _layer?.enabled = v;
            _secondLayer?.enabled = v;
          },
        ),
        fcSlider(
          label: 'Интенсивность',
          value: _intensity,
          min: 0,
          max: 3,
          onChanged: (v) {
            setState(() => _intensity = v);
            _layer?.intensity = v;
            _secondLayer?.intensity = v;
          },
        ),
        fcNote(widget.note),
        fcNote(
          'Частицы привязаны к клеткам сцены и не следуют за камерой: '
          'при полёте видно, что поле остаётся на месте.',
        ),
      ],
    );
  }
}
