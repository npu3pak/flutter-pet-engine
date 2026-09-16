import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка с постаментом под эффект.
doc.ModelData buildFmatScene(FeatureBuildContext context) {
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
    sceneObject(
      id: 'pedestal',
      name: 'Постамент',
      kind: 'cuboid',
      x: 4,
      z: 3,
      dims: const {'w': 2.2, 'h': 0.4, 'd': 2.2},
      material: colorMat(SceneColors.blue),
    ),
    sceneObject(
      id: 'back',
      name: 'Задняя стенка',
      kind: 'cuboid',
      x: 4,
      z: 0.4,
      dims: const {'w': 8, 'h': 3, 'd': 0.3},
      material: colorMat(SceneColors.white),
    ),
  ];
  return doc.ModelData(
    id: 'fmat_effects',
    name: 'Материалы .fmat',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

final FeatureSpec fmatEffectsFeature = FeatureSpec(
  id: 'fmat_effects',
  group: kFeatureGroups[4],
  project: 'Pet',
  title: 'Материалы .fmat',
  phase: 2,
  description:
      'Материал с программой для видеокарты (.fmat) накладывается '
      'на спрайт над постаментом: эффект свечения и эффект пикселизации. '
      'Управление переключает эффект, задаёт его параметры и перезагружает '
      'материал без перезапуска приложения. Если программа не загрузилась, '
      'показывается запасной обычный спрайт.',
  checks: const [
    'Эффект свечения добавляет вокруг рисунка цветное сияние, яркость меняется ползунком.',
    'Эффект пикселизации дробит рисунок на крупные квадраты; ползунок задаёт степень дробления.',
    'Переключатель «Циклически менять эффект» раз в 3 секунды сменяет свечение и пикселизацию; выбор эффекта вручную сбрасывает таймер.',
    'Кнопка «Перезагрузить материал» перечитывает программу без перезапуска приложения.',
    'При выключенном эффекте и при ошибке загрузки виден обычный спрайт без искажений.',
    'Переключение эффектов не влияет на остальную сцену.',
  ],
  build: buildFmatScene,
  camera: CameraMode.free,
  controls: (context, feature) => _FmatControls(feature: feature),
);

class _FmatControls extends StatefulWidget {
  const _FmatControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_FmatControls> createState() => _FmatControlsState();
}

class _FmatControlsState extends State<_FmatControls> {
  SceneTexture? _texture;
  GroupNode? _root;
  SpriteNode? _quad;
  ShaderMaterial? _glow;
  ShaderMaterial? _pixelate;
  ShaderMaterialInstance? _instance;
  bool _loading = true;
  String? _error;
  String _kind = 'glow';
  bool _enabled = true;
  bool _cycle = true;
  double _progress = 0.5;
  double _brightness = 0.7;
  double _clock = 0;
  double _cycleClock = 0;

  /// Период автопереключения эффектов (секунды).
  static const _cyclePeriod = 3.0;

  static const _glowPath = 'assets/shaders/fx_glow.fmat';
  static const _pixelatePath = 'assets/shaders/fx_pixelate.fmat';

  @override
  void initState() {
    super.initState();
    widget.feature.setTick(_tick);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.feature.setTick(null);
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  Future<void> _load() async {
    final game = widget.feature.controller;
    final project = widget.feature.project;
    final key = projectSpriteKey(project, 'cat_bowl');
    if (game == null || project == null || key == null) {
      setState(() {
        _loading = false;
        _error =
            'Нужен проект Pet со спрайтами (запустите из каталога '
            'example на macOS).';
      });
      return;
    }
    final texture = await project.sprite(key);
    final glow = await game.shaders.load(_glowPath);
    final pixelate = await game.shaders.load(_pixelatePath);
    if (!mounted) return;
    final root = attachFeatureRoot(game, 'fmat-demo');
    setState(() {
      _texture = texture;
      _glow = glow;
      _pixelate = pixelate;
      _root = root;
      _loading = false;
      _error = texture == null ? 'Не удалось загрузить спрайт $key.' : null;
    });
    _apply();
  }

  void _apply() {
    final root = _root;
    final texture = _texture;
    if (root == null || texture == null) return;
    final old = _quad;
    if (old != null) root.remove(old);
    final shader = _enabled ? (_kind == 'glow' ? _glow : _pixelate) : null;
    final instance = shader?.instance();
    if (instance != null) {
      instance
        ..setFloat('u_time', _clock)
        ..setFloat('u_fade', 1.0)
        ..setFloat('u_brightness', _brightness);
      if (_kind == 'glow') {
        instance
          ..setFloat('u_effect', 13)
          ..setFloat('u_progress', 1.0)
          ..setFloat('u_core_r', 0.35)
          ..setFloat('u_core_g', 0.75)
          ..setFloat('u_core_b', 1.0);
      } else {
        instance
          ..setFloat('u_effect', 1)
          ..setFloat('u_progress', _progress);
      }
      instance.setTexture('base_color_texture', texture);
    }
    _instance = instance;
    final material = instance == null
        ? SceneMaterial.unlit(
            texture: texture,
            doubleSided: true,
            alphaMode: SceneAlphaMode.blend,
            color: Color.fromRGBO(255, 255, 255, _brightness.clamp(0.0, 1.0)),
          )
        : SceneMaterial.shader(instance);
    // Низ спрайта — на верхней грани постамента (высота 0.4), а не в нём.
    const pedestalHeight = 0.4;
    const spriteHeight = 1.2;
    final quad = SpriteNode(
      name: 'fmat-sprite',
      width: 1.2,
      height: spriteHeight,
      orientation: SpriteOrientation.vertical,
    )..material = material;
    quad.position = featureWorldPoint(
      widget.feature.controller,
      4,
      pedestalHeight + spriteHeight / 2,
      3,
    );
    root.add(quad);
    _quad = quad;
  }

  void _tick(double dt) {
    _clock += dt;
    if (_cycle && _enabled) {
      _cycleClock += dt;
      if (_cycleClock >= _cyclePeriod) {
        _cycleClock = 0;
        setState(() => _kind = _kind == 'glow' ? 'pixelate' : 'glow');
        _apply();
      }
    }
    final instance = _instance;
    if (instance == null) return;
    instance
      ..setFloat('u_time', _clock)
      ..setFloat('u_brightness', _brightness);
    if (_kind == 'pixelate') {
      instance.setFloat('u_progress', _progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Эффект на спрайте'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) fcNote(_error!),
        fcChoice<String>(
          label: 'Эффект',
          values: const ['glow', 'pixelate'],
          selected: _kind,
          labelOf: (v) => v == 'pixelate' ? 'пикселизация' : 'свечение',
          onChanged: (v) {
            setState(() {
              _kind = v;
              _cycleClock = 0;
            });
            _apply();
          },
        ),
        fcSwitch(
          label: 'Включить эффект',
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _apply();
          },
        ),
        fcSwitch(
          label: 'Циклически менять эффект (каждые 3 с)',
          value: _cycle,
          onChanged: (v) {
            setState(() {
              _cycle = v;
              _cycleClock = 0;
            });
          },
        ),
        if (_kind == 'pixelate')
          fcSlider(
            label: 'Степень дробления',
            value: _progress,
            min: 0,
            max: 1,
            onChanged: (v) {
              setState(() => _progress = v);
              _tick(0);
            },
          ),
        fcSlider(
          label: 'Яркость',
          value: _brightness,
          min: 0,
          max: 1.5,
          onChanged: (v) {
            setState(() => _brightness = v);
            _tick(0);
          },
        ),
        Wrap(
          spacing: 6,
          children: [
            fcButton('Перезагрузить материал', () async {
              final game = widget.feature.controller;
              await game?.shaders.reload();
              _glow = game?.shaders.materials[_glowPath];
              _pixelate = game?.shaders.materials[_pixelatePath];
              _apply();
              if (mounted) setState(() {});
            }),
          ],
        ),
        fcNote(
          _glow != null || _pixelate != null
              ? 'Материал .fmat загружен.'
              : 'Материал не загружен: показан запасной обычный спрайт.',
        ),
      ],
    );
  }
}
