import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Площадка под витрину кадров.
doc.ModelData buildSpriteAtlasScene(FeatureBuildContext context) {
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
    id: 'sprite_atlas',
    name: 'Атлас кадров',
    size: doc.ModelSize(w: 8, l: 6, h: 3),
    objects: objects,
  );
}

/// Собирает атлас из спрайтов проекта: один ряд ячеек [cellSize]² с
/// отступом; при [borders] вокруг каждой ячейки рисуется яркая рамка.
Future<({ui.Image image, List<String> keys})?> composeProjectAtlas(
  SceneResources project,
  List<String> keys, {
  bool borders = false,
  int cellSize = 128,
}) async {
  final images = <ui.Image>[];
  final resolved = <String>[];
  for (final key in keys) {
    final bytes = await project.readBytes('sprites/$key');
    if (bytes == null) continue;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    images.add(frame.image);
    resolved.add(key);
  }
  if (images.isEmpty) return null;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final borderPaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = const ui.Color(0xFF00E5FF);
  for (var i = 0; i < images.length; i++) {
    final image = images[i];
    final dst = ui.Rect.fromLTWH(
      (i * cellSize + 1).toDouble(),
      1,
      (cellSize - 2).toDouble(),
      (cellSize - 2).toDouble(),
    );
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint,
    );
    if (borders) canvas.drawRect(dst, borderPaint);
    image.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(resolved.length * cellSize, cellSize);
  picture.dispose();
  return (image: image, keys: resolved);
}

final FeatureSpec spriteAtlasFeature = FeatureSpec(
  id: 'sprite_atlas',
  group: kFeatureGroups[2],
  project: 'Pet',
  title: 'Атлас кадров',
  phase: 2,
  description:
      'Несколько спрайтов проекта собираются в одну текстуру-атлас '
      'из кадров; каждый кадр показывается отдельным спрайтом в ряд, поэтому '
      'видно границы кадров и порядок. Переключатель «показать границы» '
      'обводит ячейки атласа яркой рамкой, а «проигрывать» листает кадры в '
      'цикле.',
  checks: const [
    'В ряд показан каждый кадр атласа; число спрайтов совпадает с числом кадров.',
    'При включённых границах вокруг каждой ячейки видна яркая рамка, рисунок не заезжает за неё.',
    'При проигрывании кадры сменяются по кругу без мерцания и без захвата соседних ячеек.',
    'Отсутствующий спрайт пропускается, остальные кадры сдвигаются без пустых мест.',
  ],
  build: buildSpriteAtlasScene,
  camera: CameraMode.free,
  controls: (context, feature) => _AtlasControls(feature: feature),
);

class _AtlasControls extends StatefulWidget {
  const _AtlasControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_AtlasControls> createState() => _AtlasControlsState();
}

class _AtlasControlsState extends State<_AtlasControls> {
  BillboardBatchNode? _batch;
  GroupNode? _root;
  List<String> _keys = const [];
  bool _borders = true;
  bool _playing = true;
  bool _loading = true;
  String? _error;
  double _clock = 0;

  @override
  void initState() {
    super.initState();
    widget.feature.setTick(_tick);
    unawaited(_rebuildAtlas());
  }

  @override
  void dispose() {
    widget.feature.setTick(null);
    final root = _root;
    if (root != null) detachFeatureRoot(root);
    super.dispose();
  }

  Future<void> _rebuildAtlas() async {
    final project = widget.feature.project;
    final game = widget.feature.controller;
    if (project == null || game == null) {
      setState(() {
        _loading = false;
        _error =
            'Нужен проект Pet со спрайтами (запустите из каталога '
            'demo на macOS).';
      });
      return;
    }
    setState(() => _loading = true);
    final keys = [for (final key in project.spriteKeys.take(6)) '$key.png'];
    final composed = await composeProjectAtlas(
      project,
      keys,
      borders: _borders,
    );
    if (!mounted) return;
    if (composed == null) {
      setState(() {
        _loading = false;
        _error = 'В проекте нет спрайтов для атласа.';
      });
      return;
    }
    final previousRoot = _root;
    if (previousRoot != null) detachFeatureRoot(previousRoot);
    final batch = BillboardBatchNode(
      capacity: 64,
      atlas: SceneTexture.fromImage(composed.image),
      blendMode: SpriteBlendMode.alpha,
      flipbookColumns: composed.keys.length,
      flipbookRows: 1,
    );
    final root = attachFeatureRoot(game, 'sprite-atlas-demo');
    root.add(batch);
    setState(() {
      _keys = composed.keys;
      _root = root;
      _batch = batch;
      _loading = false;
    });
  }

  void _tick(double dt) {
    _clock += dt;
    final batch = _batch;
    if (batch == null) return;
    final frameCount = batch.flipbookColumns;
    for (var i = 0; i < _keys.length; i++) {
      final frame = _playing ? (_clock * 4 + i) % frameCount : i.toDouble();
      batch.setInstance(
        center: featureWorldPoint(
          widget.feature.controller,
          1.2 + i * 1.1,
          1.1,
          2.5,
        ),
        width: 0.9,
        height: 0.9,
        frame: frame.round(),
      );
    }
    batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Атлас из спрайтов проекта'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) fcNote(_error!),
        fcSwitch(
          label: 'Показать границы кадров',
          value: _borders,
          onChanged: (v) {
            setState(() => _borders = v);
            unawaited(_rebuildAtlas());
          },
        ),
        fcSwitch(
          label: 'Проигрывать кадры',
          value: _playing,
          onChanged: (v) => setState(() => _playing = v),
        ),
        fcNote(
          _keys.isEmpty
              ? 'Кадры не загружены.'
              : 'Кадры атласа: ${_keys.join(', ')}',
        ),
      ],
    );
  }
}
