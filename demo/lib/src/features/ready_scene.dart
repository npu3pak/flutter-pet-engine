import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'controls.dart';
import 'feature_registry.dart';
import 'level_common.dart';

doc.ModelData buildReadyScene(FeatureBuildContext context) {
  final project = context.project;
  if (project == null) return buildLevelShell().data;
  final preferred = project.model('model_2');
  if (preferred != null) return preferred;
  for (final id in project.modelIds) {
    final model = project.model(id);
    if (model != null) return model;
  }
  return buildLevelShell().data;
}

final FeatureSpec readySceneFeature = FeatureSpec(
  id: 'ready_scene',
  group: kFeatureGroups[7],
  title: 'Готовая сцена. Питомец в комнате',
  project: 'Pet',
  phase: 2,
  description:
      'Эталонная сцена проекта Pet: комната с котом. Проверяется '
      'готовая сцена целиком — анимации кота, смена окраса, переключение '
      'обоев, пола и окон, виды камеры. Это итоговая проверка того, что '
      'движок одинаково показывает собранную в редакторе сцену.',
  checks: const [
    'Комната отображается целиком: стены, пол, потолок, мебель и кот без пропавших объектов.',
    'Список анимаций кота заполнен; выбор анимации проигрывает её в цикле, «поза покоя» останавливает.',
    'Кнопки окраски меняют цвет шерсти кота, форма и анимация сохраняются.',
    'Переключение обоев, пола и окон меняет материалы соответствующих объектов, не ломая сцену.',
    'Виды камеры «Обзор», «В комнату» и «К коту» показывают сцену с разных точек без ошибок.',
  ],
  build: buildReadyScene,
  camera: CameraMode.free,
  controls: (context, feature) => _ReadySceneControls(feature: feature),
);

class _ReadySceneControls extends StatefulWidget {
  const _ReadySceneControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_ReadySceneControls> createState() => _ReadySceneControlsState();
}

class _ReadySceneControlsState extends State<_ReadySceneControls> {
  String? _skin;

  SceneController? get _game => widget.feature.controller;
  SceneResources? get _project => widget.feature.project;

  ModelNode? get _cat {
    final game = _game;
    final model = game?.model;
    if (game == null || model == null) return null;
    for (final object in model.objects) {
      if (object.kind == doc.gltfRefKind) return game.objectNode(object.id);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Автоматический прогон: вид камеры задаётся параметром диплинка.
    final view = widget.feature.params['view'];
    if (view == 'inside' || view == 'cat') {
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        if (view == 'cat') {
          _frameToCat();
        } else {
          _frameInsideRoom();
        }
      });
    }
  }

  vm.Vector3 _worldOf(ModelNode node) => node.worldPosition;

  void _frameOverview() {
    final game = _game;
    final model = game?.model;
    if (game == null || model == null) return;
    game.camera = FlyCameraController()..frameModel(model);
    widget.feature.refresh();
  }

  void _frameInsideRoom() {
    final game = _game;
    if (game == null) return;
    final cat = _cat;
    final target = cat == null ? vm.Vector3(0, 0.9, 0) : _worldOf(cat);
    final pos =
        target +
        vm.Vector3(0, 1.35, 0) +
        vm.Vector3(1.0, 0, 0.6).normalized() * 1.6;
    final camera = FlyCameraController()
      ..eye = pos
      ..lookAt(target);
    game.camera = camera;
    widget.feature.refresh();
  }

  void _frameToCat() {
    final game = _game;
    final cat = _cat;
    if (game == null || cat == null) return;
    final target = _worldOf(cat) + vm.Vector3(0, 0.7, 0);
    final camera = FlyCameraController()
      ..eye = target + vm.Vector3(0, 0.35, 1.5)
      ..lookAt(target);
    game.camera = camera;
    widget.feature.refresh();
  }

  Future<void> _applySkin(String? variant) async {
    final project = _project;
    if (project == null) return;
    if (variant == null) {
      project.clearGltfTextureOverride('cat');
    } else {
      final bytes = await project.readBytes(
        '3d_models/cat/textures/MI_Cat_diffuse$variant.png',
      );
      if (bytes == null) return;
      project.setGltfTextureOverride('cat', {
        'textures/MI_Cat_diffuse.png': bytes,
      });
    }
    _game?.rebuild();
    setState(() => _skin = variant);
    widget.feature.refresh();
  }

  void _applyFamily(String family, String key) {
    final game = _game;
    final model = game?.model;
    if (game == null || model == null) return;
    for (final object in model.objects) {
      if ((object.material?.key ?? '').startsWith(family)) {
        game.objectNode(object.id)?.setTexture(key);
      }
    }
    widget.feature.refresh();
  }

  /// Пол в эталонной сцене — объект `obj_11` с материалом
  /// `furniture_texture_3.png`, поэтому префикс `floor_` к нему не подходит;
  /// меняем текстуру адресно.
  void _applyFloor(String key) {
    final game = _game;
    if (game == null) return;
    final floor = _floorNode;
    floor?.setTexture(key);
    widget.feature.refresh();
  }

  ModelNode? get _floorNode {
    final game = _game;
    if (game == null) return null;
    final byId = game.objectNode('obj_11');
    if (byId != null) return byId;
    final model = game.model;
    if (model == null) return null;
    for (final object in model.objects) {
      if (object.name == 'Пол') return game.objectNode(object.id);
    }
    return null;
  }

  void _applyWindow(String key) {
    final game = _game;
    final model = game?.model;
    if (game == null || model == null) return;
    for (final object in model.objects) {
      final material = object.material;
      if (material?.type == doc.MaterialType.sprite &&
          (material?.key ?? '').startsWith('window_')) {
        game.objectNode(object.id)?.setTexture(key, fromSprites: true);
      }
    }
    widget.feature.refresh();
  }

  List<String> _family(String prefix) {
    final project = _project;
    if (project == null) return const [];
    return [
      for (final key in project.textureKeys)
        if (key.startsWith(prefix)) '$key.png',
    ];
  }

  List<String> _windows() {
    final project = _project;
    if (project == null) return const [];
    return [
      for (final key in project.spriteKeys)
        if (key.startsWith('window_')) '$key.png',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    final clips = cat?.animationClips ?? const [];
    final wallpapers = _family('wallpaper_');
    final floors = _family('floor_');
    final windows = _windows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Виды камеры'),
        Wrap(
          spacing: 6,
          children: [
            fcButton('Обзор', _frameOverview),
            fcButton('В комнату', _frameInsideRoom),
            fcButton('К коту', _frameToCat),
          ],
        ),
        const Divider(height: 18),
        fcTitle('Анимации кота'),
        if (cat == null)
          fcNote('Кот не найден в сцене.')
        else if (clips.isEmpty)
          fcNote('Анимации ещё загружаются.')
        else
          DropdownButtonFormField<String>(
            initialValue: clips.any((c) => c.fullName == cat.animation)
                ? cat.animation
                : '',
            isExpanded: true,
            dropdownColor: const Color(0xFF2C313B),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('— поза покоя')),
              for (final clip in clips)
                DropdownMenuItem(
                  value: clip.fullName,
                  child: Text(clip.shortName),
                ),
            ],
            onChanged: (value) {
              cat.play(value ?? '');
              widget.feature.refresh();
            },
          ),
        fcTitle('Окраска кота'),
        Wrap(
          spacing: 6,
          children: [
            fcButton('Рыжий', () => _applySkin(null)),
            fcButton('Синий', () => _applySkin('-blue')),
            fcButton('Зелёный', () => _applySkin('-green')),
          ],
        ),
        fcNote(_skin == null ? 'Исходная окраска.' : 'Вариант $_skin.'),
        if (wallpapers.isNotEmpty) ...[
          fcTitle('Обои'),
          _keyRow(wallpapers, (key) => _applyFamily('wallpaper_', key)),
        ],
        if (floors.isNotEmpty) ...[
          fcTitle('Пол'),
          _keyRow(floors, _applyFloor),
        ],
        if (windows.isNotEmpty) ...[
          fcTitle('Окна'),
          _keyRow(windows, _applyWindow),
        ],
      ],
    );
  }

  Widget _keyRow(List<String> keys, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final key in keys)
          ActionChip(
            label: Text(key.replaceAll('.png', '')),
            visualDensity: VisualDensity.compact,
            onPressed: () => onPick(key),
          ),
      ],
    );
  }
}
