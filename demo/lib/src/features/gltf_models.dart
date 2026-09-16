import 'package:flutter/material.dart';
import 'package:pet_engine/models.dart' as doc;

import 'common.dart';
import 'controls.dart';
import 'feature_registry.dart';

/// Внешние трёхмерные модели (glTF) из проекта Pet: кот и щенок, а также
/// отсутствующий ресурс — серая подстановка.
doc.ModelData buildGltfScene(FeatureBuildContext context) {
  final objects = <doc.ModelObject>[
    sceneObject(
      id: 'cat',
      name: 'Кот (glTF)',
      kind: doc.gltfRefKind,
      x: 2.5,
      z: 3,
      gltfName: 'cat',
      gltfBounds: const [0, 0, 0, 1, 1, 1],
    ),
  ];
  if (context.project?.gltfEntry('puppy') != null) {
    objects.add(
      sceneObject(
        id: 'puppy',
        name: 'Щенок (glTF)',
        kind: doc.gltfRefKind,
        x: 5.5,
        z: 3,
        gltfName: 'puppy',
        gltfBounds: const [0, 0, 0, 1, 1, 1],
      ),
    );
  }
  objects.add(
    sceneObject(
      id: 'missing',
      name: 'Отсутствующий ресурс',
      kind: doc.gltfRefKind,
      x: 8.5,
      z: 3,
      gltfName: 'missing_resource',
      gltfBounds: const [0, 0, 0, 1, 1, 1],
    ),
  );
  return doc.ModelData(
    id: 'gltf_models',
    name: 'Модели glTF',
    size: doc.ModelSize(w: 11, l: 7, h: 4),
    objects: objects,
  );
}

final FeatureSpec gltfModelsFeature = FeatureSpec(
  id: 'gltf_models',
  group: kFeatureGroups[0],
  title: 'Модели glTF',
  project: 'Pet',
  phase: 1,
  description:
      'В сцену загружены внешние трёхмерные модели из папки '
      '3d_models проекта Pet: кот и щенок. Список анимаций модели выводится в '
      'управлении; окраску кота можно переключать. Отсутствующий ресурс '
      'показан серой подстановкой на месте потерянной модели.',
  checks: const [
    'Кот и щенок отображаются целиком, с текстурами, без чёрных или пустых участков.',
    'Список анимаций кота заполняется после загрузки модели; выбор анимации запускает её в цикле, пункт «стоп» возвращает позу покоя.',
    'Кнопки окраски меняют цвет шерсти кота, не меняя форму и анимацию.',
    'Отсутствующий ресурс показан серой подстановкой, остальные модели продолжают отображаться.',
  ],
  build: buildGltfScene,
  camera: CameraMode.free,
  controls: (context, feature) => _GltfControls(feature: feature),
);

class _GltfControls extends StatefulWidget {
  const _GltfControls({required this.feature});

  final FeatureContext feature;

  @override
  State<_GltfControls> createState() => _GltfControlsState();
}

class _GltfControlsState extends State<_GltfControls> {
  String? _skin;

  Future<void> _applySkin(String? variant) async {
    final project = widget.feature.project;
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
    widget.feature.controller?.rebuild();
    setState(() => _skin = variant);
    widget.feature.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.feature.controller?.objectNode('cat');
    final clips = cat?.animationClips ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fcTitle('Анимации модели'),
        if (cat == null)
          fcNote(
            'Модель кота загружается; список анимаций появится после '
            'загрузки.',
          )
        else if (cat.gltfFailed)
          fcNote('Не удалось загрузить модель кота.')
        else if (cat.gltfLoading)
          fcNote(
            'Модель кота загружается; список анимаций появится после '
            'загрузки.',
          )
        else if (clips.isEmpty)
          fcNote('У модели кота нет анимаций.')
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
          runSpacing: 6,
          children: [
            fcButton('Рыжий', () => _applySkin(null)),
            fcButton('Синий', () => _applySkin('-blue')),
            fcButton('Зелёный', () => _applySkin('-green')),
          ],
        ),
        fcNote(
          _skin == null
              ? 'Показана исходная текстура кота.'
              : 'Показана подменённая текстура кота (вариант $_skin).',
        ),
        fcNote(
          'Серая подстановка справа — место отсутствующего ресурса: '
          'движок сохраняет размер потерянной модели.',
        ),
      ],
    );
  }
}
