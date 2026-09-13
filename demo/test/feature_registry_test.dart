import 'package:demo/src/features/feature_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/models.dart' as doc;

import 'test_helpers/test_app.dart';

FeatureSpec raw({
  required String id,
  String title = 'Название',
  String group = 'Документ сцены',
  String description = 'Описание возможности движка для проверки каталога.',
  List<String> checks = const ['Проверяем, что сцена открывается и работает.'],
}) {
  return FeatureSpec(
    id: id,
    group: group,
    title: title,
    phase: 1,
    description: description,
    checks: checks,
    build: (context) =>
        doc.ModelData(id: id, name: id, size: doc.ModelSize(w: 1, l: 1, h: 1)),
  );
}

void main() {
  test('корректная фича не вызывает замечаний', () {
    expect(validateFeatureCatalog([testFeature(id: 'demo_feature')]), isEmpty);
  });

  test('повторяющийся идентификатор — ошибка', () {
    final problems = validateFeatureCatalog([raw(id: 'dup'), raw(id: 'dup')]);
    expect(problems, contains(contains('повторяется')));
  });

  test('короткое описание и пустые проверки — ошибки', () {
    final problems = validateFeatureCatalog([
      raw(id: 'short', description: 'мало', checks: const []),
    ]);
    expect(problems, contains(contains('описание короче')));
    expect(problems, contains(contains('нет проверяемых утверждений')));
  });

  test('неизвестная группа — ошибка', () {
    final problems = validateFeatureCatalog([
      raw(id: 'group', group: 'Чужая группа'),
    ]);
    expect(problems, contains(contains('неизвестная группа')));
  });

  test('латиница в текстах — ошибка', () {
    final problems = validateFeatureCatalog([
      raw(
        id: 'latin',
        description: 'This description is in English and long enough.',
        checks: const ['Check that the scene opens and renders.'],
      ),
    ]);
    expect(problems, contains(contains('на русском')));
  });

  test('реальный каталог проходит проверку целостности', () {
    expect(validateFeatureCatalog(kFeatureCatalog), isEmpty);
  });

  test('каталог полный: 49 фич в восьми непустых группах', () {
    expect(kFeatureCatalog, hasLength(49));
    expect(kFeatureCatalog.map((f) => f.id).toSet(), hasLength(49));
    for (final group in kFeatureGroups) {
      expect(
        kFeatureCatalog.where((f) => f.group == group),
        isNotEmpty,
        reason: 'группа «$group» пуста',
      );
    }
    expect(
      kFeatureCatalog.map((f) => f.phase).toSet(),
      containsAll(const [1, 2, 3, 4, 5]),
    );
  });
}
