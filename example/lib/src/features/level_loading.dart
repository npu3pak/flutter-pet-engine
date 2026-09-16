import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Ключ текстуры из проекта Pet, которую обязан предзагрузить загрузчик.
const loadingTextureKey = 'wallpaper_beige.png';

/// Ключ заведомо потерянной текстуры для сценария с ошибкой.
const loadingMissingTextureKey = 'lost_texture.png';

/// Небольшой уровень построения: пол, стена и ящик. Один элемент текстурирован
/// ресурсом проекта, поэтому этап «ресурсы» что-то реально грузит.
ConstructionModel buildLoadingLevel({bool withMissingTexture = false}) {
  final model = ConstructionModel(id: 'level_loading', name: 'Загрузка уровня');
  model.data.size = doc.ModelSize(w: 6, l: 6, h: 3);
  model.add(
    sceneObject(
      id: 'floor',
      name: 'Пол',
      kind: 'plane',
      x: 2.5,
      z: 2.5,
      dims: const {'w': 6, 'd': 6},
      material: textureMat(loadingTextureKey),
    ),
    bake: BakeMode.merge,
    tag: 'floor',
  );
  model.add(
    sceneObject(
      id: 'wall',
      name: 'Стена',
      kind: 'cuboid',
      x: 2.5,
      y: 0,
      z: 5,
      dims: const {'w': 6, 'h': 1.4, 'd': 0.3},
      material: colorMat(SceneColors.gray),
    ),
    bake: BakeMode.merge,
    tag: 'wall',
  );
  model.add(
    sceneObject(
      id: 'crate',
      name: 'Ящик',
      kind: 'cuboid',
      x: 2,
      y: 0,
      z: 2,
      dims: const {'w': 0.8, 'h': 0.8, 'd': 0.8},
      material: colorMat(SceneColors.orange),
    ),
    bake: BakeMode.node,
    tag: 'crate',
  );
  // Спрайт-билборд: запекается отдельным узлом и должен разворачиваться к
  // камере каждый кадр (реестр билбордов в результате запекания).
  model.add(
    sceneObject(
      id: 'sprite',
      name: 'Спрайт',
      kind: 'sprite',
      x: 4,
      y: 0,
      z: 4,
      dims: const {'w': 0.8, 'h': 1.2},
      material: spriteMat('window_1.png'),
    ),
    bake: BakeMode.node,
    tag: 'sprite',
  );
  // Сцена-заготовка (kind model): запекается отдельным узлом-обёрткой,
  // ресурсы её замыкания предзагружает загрузчик.
  model.add(
    sceneObject(
      id: 'prefab',
      name: 'Заготовка',
      kind: modelRefKind,
      x: 1,
      y: 0,
      z: 1,
      refModelId: 'model_1',
      refSize: doc.ModelSize(w: 3, l: 3, h: 3),
    ),
    bake: BakeMode.node,
    tag: 'prefab',
  );
  if (withMissingTexture) {
    model.add(
      sceneObject(
        id: 'lost',
        name: 'Потерянный ресурс',
        kind: 'cuboid',
        x: 4,
        y: 0,
        z: 2,
        dims: const {'w': 0.8, 'h': 0.8, 'd': 0.8},
        material: textureMat(loadingMissingTextureKey),
      ),
      bake: BakeMode.merge,
      tag: 'lost',
    );
  }
  return model;
}

/// Пустая сцена фичи: уровень собирает и монтирует загрузчик.
doc.ModelData buildLoadingShell() => doc.ModelData(
  id: 'level_loading',
  name: 'Загрузка уровня',
  size: doc.ModelSize(w: 6, l: 6, h: 3),
);

final FeatureSpec levelLoadingFeature = FeatureSpec(
  id: 'level_loading',
  group: kFeatureGroups[5],
  title: 'Загрузка уровня',
  project: 'Pet',
  phase: 5,
  description:
      'Загрузчик уровня движка проходит пять этапов — проект, '
      'модели, ресурсы, геометрия, запекание — и сообщает прогресс и ошибки. '
      'К моменту завершения готовы и геометрия, и все текстуры, поэтому '
      'уровень появляется целиком, без серых заглушек. Потерянный ресурс '
      'попадает в список ошибок, но уровень всё равно показывается.',
  checks: const [
    'В управлении видна полоса прогресса и название этапа с процентом.',
    'После завершения уровень появляется целиком: пол текстурирован, без серых заглушек.',
    'Спрайт-билборд разворачивается к камере при повороте.',
    'Сцена-заготовка (kind model) стоит на уровне, её ресурсы предзагружены.',
    'Переключатель «потерянный ресурс» добавляет ошибку в список, а уровень показывается.',
    'В списке ошибок указано, какой файл не загрузился и почему.',
  ],
  build: (context) => buildLoadingShell(),
  camera: CameraMode.free,
  controls: (context, feature) => _LevelLoadingControls(feature: feature),
);

class _LevelLoadingControls extends StatefulWidget {
  const _LevelLoadingControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_LevelLoadingControls> createState() => _LevelLoadingControlsState();
}

class _LevelLoadingControlsState extends State<_LevelLoadingControls> {
  bool _running = false;
  bool _missing = false;
  SceneLoadPhase? _stage;
  double _fraction = 0;
  String _label = '';
  LevelLoadResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    widget.feature.controller?.unmountLevel();
    super.dispose();
  }

  Future<void> _run() async {
    final controller = widget.feature.controller;
    if (controller == null) return;
    setState(() {
      _running = true;
      _result = null;
      _stage = null;
      _fraction = 0;
      _label = '';
    });
    void onStatus() {
      if (!mounted) return;
      setState(() {
        _stage = controller.status.phase;
        _fraction = controller.status.fraction;
        _label = controller.status.label;
      });
    }

    controller.addListener(onStatus);
    controller.unmountLevel();
    final result = await controller.loadLevel(
      buildLoadingLevel(withMissingTexture: _missing),
      extraResources: _missing
          ? [const LevelExtraResource('тень травы', _lostExtra)]
          : const [],
    );
    controller.removeListener(onStatus);
    if (!mounted) return;
    final baked = result.baked;
    if (baked != null) controller.mountLevel(baked);
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Этапы загрузки'),
        if (_running) ...[
          LinearProgressIndicator(value: _fraction),
          Text(
            '${_stage?.label ?? 'Подготовка'}: '
            '${(_fraction * 100).round()}% — $_label',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ] else if (result != null) ...[
          Text(
            result.baked == null
                ? 'Сборка не удалась'
                : 'Уровень готов за ${result.elapsed.inMilliseconds} мс',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (result.hasErrors)
            Text(
              'Ошибок: ${result.errors.length}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            )
          else
            const Text(
              'Ошибок нет',
              style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12),
            ),
          for (final error in result.errors)
            Text(
              '• ${error.resource}: ${error.reason}',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
        ],
        fcSwitch(
          label: 'Потерянный ресурс',
          value: _missing,
          onChanged: _running
              ? (_) {}
              : (v) {
                  setState(() => _missing = v);
                  _run();
                },
        ),
        fcButton(
          _running ? 'Идёт загрузка…' : 'Загрузить заново',
          _running ? null : _run,
        ),
        fcNote(
          'Загрузчик предзагружает текстуры и спрайты сцен, затем '
          'запекает геометрию — уровень монтируется только после полной '
          'готовности. С потерянным ресурсом список ошибок не пуст, но '
          'уровень всё равно показывается.',
        ),
      ],
    );
  }
}

Future<void> _lostExtra() async {
  throw StateError('ресурс потерян при загрузке');
}
