import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Вставка одних сцен внутрь других, поворот и масштаб вставки, а также
/// отсутствующий источник (ярко-розовый куб).
doc.ModelData buildModelRefsScene(FeatureBuildContext context) {
  final rotY = context.param<double>('rotY') ?? 0;
  final scale = context.param<double>('scale') ?? 1.0;
  final showMissing = context.param<bool>('showMissing') ?? true;
  final ids = context.project?.modelIds ?? const <String>[];
  final first = ids.isNotEmpty ? ids.first : 'model_1';
  final second = ids.length > 1 ? ids[1] : 'model_2';

  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'ref_first',
      name: 'Вставка сцены $first',
      kind: doc.modelRefKind,
      x: 2,
      z: 3,
      rotY: rotY,
      scale: scale,
      refModelId: first,
    ),
    sceneObject(
      id: 'ref_second',
      name: 'Вложенная вставка сцены $second',
      kind: doc.modelRefKind,
      x: 6,
      z: 3,
      rotY: rotY,
      scale: scale,
      refModelId: second,
    ),
  ];
  if (showMissing) {
    objects.add(
      sceneObject(
        id: 'ref_missing',
        name: 'Отсутствующий источник',
        kind: doc.modelRefKind,
        x: 9.5,
        z: 3,
        refModelId: 'missing_scene',
        refSize: doc.ModelSize(w: 2, l: 2, h: 2),
      ),
    );
  }
  return doc.ModelData(
    id: 'model_refs',
    name: 'Ссылки на другие модели',
    size: doc.ModelSize(w: 12, l: 7, h: 4),
    objects: objects,
  );
}

final FeatureSpec modelRefsFeature = FeatureSpec(
  id: 'model_refs',
  group: kFeatureGroups[0],
  title: 'Ссылки на другие модели',
  project: 'Pet',
  phase: 1,
  description:
      'В сцену вставлены другие сцены проекта Pet как единые '
      'объекты: первая модель, модель, которая сама содержит вложенную '
      'ссылку, и отсутствующий источник. Поворот и масштаб вставки задаются '
      'ползунками; у отсутствующего источника виден ярко-розовый куб того же '
      'размера, что и потерянная сцена.',
  checks: const [
    'Обе вставленные сцены отображаются целиком и двигаются как один объект при повороте и масштабировании.',
    'Вложенная вставка (сцена внутри сцены) видна целиком, без разрывов и пропавших частей.',
    'При увеличении масштаба вставка растёт вокруг своей точки привязки, не смещаясь по сцене.',
    'Отсутствующий источник показан ярко-розовым кубом, остальные вставки не затронуты.',
    'Выключение показа отсутствующего источника убирает розовый куб из сцены.',
  ],
  build: buildModelRefsScene,
  camera: CameraMode.free,
  controls: (context, feature) => _ModelRefsControls(feature: feature),
);

class _ModelRefsControls extends StatefulWidget {
  const _ModelRefsControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_ModelRefsControls> createState() => _ModelRefsControlsState();
}

class _ModelRefsControlsState extends State<_ModelRefsControls> {
  late double _rotY;
  late double _scale;
  late bool _showMissing;

  @override
  void initState() {
    super.initState();
    _rotY = widget.feature.params['rotY'] as double? ?? 0;
    _scale = widget.feature.params['scale'] as double? ?? 1.0;
    _showMissing = widget.feature.params['showMissing'] as bool? ?? true;
  }

  void _update() {
    widget.feature.updateParams({
      'rotY': _rotY,
      'scale': _scale,
      'showMissing': _showMissing,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Размещение вставок'),
        fcSlider(
          label: 'Поворот',
          value: _rotY,
          min: 0,
          max: 360,
          format: (v) => '${v.round()}°',
          onChanged: (v) {
            setState(() => _rotY = v);
            _update();
          },
        ),
        fcSlider(
          label: 'Масштаб',
          value: _scale,
          min: 0.5,
          max: 2,
          onChanged: (v) {
            setState(() => _scale = v);
            _update();
          },
        ),
        fcSwitch(
          label: 'Показывать отсутствующий источник',
          value: _showMissing,
          onChanged: (v) {
            setState(() => _showMissing = v);
            _update();
          },
        ),
        fcNote(
          'Ярко-розовый куб — это подстановка для сцены, которой нет в '
          'проекте; его размер равен сохранённому размеру потерянной сцены.',
        ),
      ],
    );
  }
}
