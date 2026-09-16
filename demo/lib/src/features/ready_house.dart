import 'package:pet_engine/models.dart' as doc;

import 'feature_registry.dart';
import 'level_common.dart';

/// Готовая сцена проекта House: дом с кирпичными стенами, крышей, дверью и
/// окнами. Камера свободная — вращение мышью и приближение/отдаление
/// колесом.
doc.ModelData buildHouseScene(FeatureBuildContext context) {
  final project = context.project;
  final house = project?.model('house');
  return house ?? buildLevelShell().data;
}

final FeatureSpec readyHouseFeature = FeatureSpec(
  id: 'ready_house',
  group: kFeatureGroups[7],
  title: 'Готовая сцена: дом',
  project: 'House',
  phase: 2,
  description:
      'Готовая сцена проекта House: отдельный дом с кирпичными стенами, '
      'крышей, дверью и окнами. Итоговая проверка того, что собранная в '
      'редакторе сцена целиком показывает себя в движке — геометрия, '
      'материалы, спрайты двери и окон.',
  checks: const [
    'Дом отображается целиком: стены, крыша, дверь и окна без пропавших объектов.',
    'Поворот мышью осматривает дом со всех сторон без мигания и дырок.',
    'Колесо мыши приближает и отдаляет камеру, дом остаётся целиком в кадре.',
  ],
  build: buildHouseScene,
  camera: CameraMode.free,
);
