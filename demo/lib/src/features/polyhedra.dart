import 'feature_registry.dart';
import 'polyhedra_all.dart';
import 'polyhedra_bake.dart';
import 'polyhedra_map.dart';

/// Фичи группы «Многогранники» — примеры произвольной геометрии
/// (`polyhedron`): ручная сборка, конверсия примитивов, фрагмент карты,
/// runtime-узел и выделение граней.
final List<FeatureSpec> polyhedraFeatures = [
  polyhedraAllFeature,
  polyhedraBakeFeature,
  polyhedraMapFeature,
];
