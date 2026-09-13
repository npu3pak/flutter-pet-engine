import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка для динамических объектов.
doc.ModelData buildDynamicScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ground',
      name: 'Пол',
      kind: 'plane',
      x: 4,
      z: 3,
      dims: const {'w': 8, 'd': 6},
      material: colorMat(SceneColors.gray),
    ),
    for (final (id, x, z, color) in const [
      ('post_1', 1.5, 1.5, SceneColors.red),
      ('post_2', 6.5, 1.5, SceneColors.green),
      ('post_3', 1.5, 4.5, SceneColors.blue),
      ('post_4', 6.5, 4.5, SceneColors.orange),
    ])
      sceneObject(
        id: id,
        name: 'Ориентир $id',
        kind: 'cuboid',
        x: x,
        z: z,
        dims: const {'w': 0.5, 'h': 1.0, 'd': 0.5},
        material: colorMat(color),
      ),
  ];
  return doc.ModelData(
    id: 'dynamic_objects',
    name: 'Динамические объекты',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

final FeatureSpec dynamicObjectsFeature = FeatureSpec(
  id: 'dynamic_objects',
  group: kFeatureGroups[3],
  project: 'Pet',
  title: 'Динамические объекты',
  phase: 2,
  description:
      'Динамический мир (DynamicWorld) создаёт и удаляет объекты во '
      'время работы: у каждого объекта есть время жизни, слой отрисовки, '
      'события появления и завершения, подсветка и повторное использование '
      'узлов. Управление создаёт и очищает объекты, задаёт время жизни и '
      'слой, подсвечивает выбранный объект.',
  checks: const [
    'Кнопка «Создать 5» добавляет пять спрайтов, счётчик живых объектов растёт.',
    'Объекты со временем жизни исчезают сами; счётчик завершённых растёт, событие завершения записывается в журнал.',
    'При повторных созданиях число узлов не растёт бесконечно — узлы берутся из пула повторно.',
    'Кнопка подсветки обводит один объект, остальные остаются без подсветки.',
    'Смена слоя меняет порядок отрисовки: объекты верхнего слоя рисуются поверх нижних.',
  ],
  build: buildDynamicScene,
  camera: CameraMode.free,
  controls: (context, feature) => _DynamicControls(feature: feature),
);

class _DynamicControls extends StatefulWidget {
  const _DynamicControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_DynamicControls> createState() => _DynamicControlsState();
}

class _DynamicControlsState extends State<_DynamicControls> {
  SceneTexture? _texture;
  bool _loading = true;
  String? _error;
  int _spawned = 0;
  int _finished = 0;
  int _layer = 0;
  double _lifetime = 4;
  String _log = '—';
  DynamicObject? _highlighted;

  SceneController? get _game => widget.feature.controller;

  @override
  void initState() {
    super.initState();
    final lifetime = widget.feature.params['lifetime'];
    if (lifetime is num) _lifetime = lifetime.toDouble();
    unawaited(_load());
  }

  Future<void> _load() async {
    final project = widget.feature.project;
    final key = projectSpriteKey(project, 'cat_bowl');
    if (project == null || key == null) {
      setState(() {
        _loading = false;
        _error =
            'Нужен проект Pet со спрайтами (запустите из каталога '
            'demo на macOS).';
      });
      return;
    }
    final texture = await project.sprite(key);
    if (!mounted) return;
    setState(() {
      _texture = texture;
      _loading = false;
      if (texture == null) _error = 'Не удалось загрузить спрайт $key.';
    });
    // Для автоматического прогона: спавн по параметру диплинка.
    final spawn = widget.feature.params['spawn'];
    if (texture != null && (spawn == true || spawn == 1)) {
      _spawn();
    }
  }

  void _spawn() {
    final game = _game;
    final texture = _texture;
    if (game == null || texture == null) return;
    for (var i = 0; i < 5; i++) {
      final id = 'demo_${_spawned++}';
      final phase = i * 1.3;
      final baseX = 2.0 + (i % 3) * 1.8;
      final baseZ = 2.0 + (i ~/ 3) * 1.8;
      final at = featureWorldPoint(game, baseX, 0.5, baseZ);
      game.dynamics.spawn(
        id: id,
        node: SpriteNode(
          name: 'Динамический $id',
          texture: texture,
          width: 0.5,
          height: 0.5,
          billboard: true,
        ),
        layer: _layer,
        position: at,
        lifetime: Duration(milliseconds: (_lifetime * 1000).round()),
        userData: phase,
        onUpdate: (object, dt) {
          final p = object.userData as double? ?? 0;
          final age = object.ageSeconds.inMicroseconds / 1000000.0;
          object.position
            ..x = at.x + math.cos(age * 1.5 + p) * 0.4
            ..z = at.z + math.sin(age * 1.5 + p) * 0.4
            ..y = 0.5 + math.sin(age * 2.0) * 0.15;
        },
        onFinished: (object) {
          if (!mounted) return;
          setState(() {
            _finished++;
            final age = object.ageSeconds.inMicroseconds / 1000000.0;
            _log =
                'завершён ${object.id} (прожил '
                '${age.toStringAsFixed(1)} с)';
          });
        },
      );
    }
    setState(() => _log = 'создано 5 объектов, слой $_layer');
  }

  void _clear() {
    _game?.dynamics.clear();
    setState(() {
      _highlighted = null;
      _log = 'все объекты удалены';
    });
  }

  void _highlightFirst() {
    final game = _game;
    if (game == null) return;
    _highlighted?.node.highlightColor = null;
    final objects = game.dynamics.objects.toList();
    if (objects.isEmpty) {
      setState(() => _log = 'нет объектов для подсветки');
      return;
    }
    final object = objects.first;
    object.node.highlightColor = vm.Vector4(1.0, 0.85, 0.2, 1.0);
    _highlighted = object;
    setState(() => _log = 'подсвечен ${object.id}');
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Динамический мир'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) fcNote(_error!),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            fcButton('Создать 5', game == null ? null : _spawn),
            fcButton('Очистить', game == null ? null : _clear),
            fcButton(
              'Подсветить первый',
              game == null ? null : _highlightFirst,
            ),
          ],
        ),
        fcSlider(
          label: 'Время жизни',
          value: _lifetime,
          min: 1,
          max: 10,
          format: (v) => '${v.toStringAsFixed(0)} с',
          onChanged: (v) => setState(() => _lifetime = v),
        ),
        fcChoice<int>(
          label: 'Слой отрисовки',
          values: const [0, 1, 2],
          selected: _layer,
          labelOf: (v) => '$v',
          onChanged: (v) => setState(() => _layer = v),
        ),
        Text(
          'живых: ${game?.dynamics.aliveCount ?? 0} · завершено: $_finished',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        fcNote('Журнал: $_log'),
      ],
    );
  }
}
