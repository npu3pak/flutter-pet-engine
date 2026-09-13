import 'package:flutter/widgets.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import '../paths.dart';
import '../scene_host.dart';
import 'document_scene.dart';
import 'dynamics.dart';
import 'level.dart';
import 'light_picture.dart';
import 'particles.dart';
import 'placement.dart';
import 'ready_scenes.dart';
import 'render_sprites.dart';

/// Режим камеры фичи.
enum CameraMode {
  /// Свободная камера: правой кнопкой мыши осматриваемся, W/A/S/D летим,
  /// Q/E меняют высоту, Shift ускоряет.
  free,

  /// Камера по клеткам: повороты и шаги с анимацией, кнопки внизу рабочей
  /// области.
  cell,

  /// Заранее заданная точка обзора без управления (сравнительные сцены).
  fixed,
}

/// Строит сцену фичи. Возвращает чистые данные — тесты проверяют сцену без
/// видеокарты; рендер выполняет движок.
typedef SceneBuilder = doc.ModelData Function(FeatureBuildContext context);

/// Строит управление фичи в рабочей области.
typedef ControlsBuilder = Widget Function(
  BuildContext context,
  FeatureContext feature,
);

/// Описание одной возможности движка: постоянный идентификатор, группа в
/// левой панели, паспорт для человека (что демонстрируется и что проверить),
/// сборка сцены и режим камеры.
class FeatureSpec {
  const FeatureSpec({
    required this.id,
    required this.group,
    required this.title,
    this.project,
    required this.phase,
    required this.description,
    required this.checks,
    required this.build,
    this.asyncBuild,
    this.camera = CameraMode.free,
    this.startCell,
    this.controls,
  });

  /// Постоянный идентификатор, например `weather_rain` (ключ в
  /// `visual_tests.json`).
  final String id;

  /// Группа в левой панели (см. [kFeatureGroups]).
  final String group;

  /// Название для человека.
  final String title;

  /// Имя проекта ресурсов: `'Pet'`, `'Streets'`, `'Dungeon'`, `'Forest'`,
  /// `'AbandonedBuilding'` или `null` — сцена из кода.
  final String? project;

  /// Фаза проекта, к которой относится возможность (для группировки
  /// проверок).
  final int phase;

  /// Что демонстрируется: что видно на экране и как управлять.
  final String description;

  /// Что нужно проверить: проверяемые утверждения.
  final List<String> checks;

  /// Как собрать сцену.
  final SceneBuilder build;

  /// Асинхронная сборка (чтение файлов проекта); используется вместо [build].
  final Future<doc.ModelData> Function(FeatureBuildContext context)? asyncBuild;

  /// Режим камеры.
  final CameraMode camera;

  /// Стартовая клетка камеры по клеткам (по умолчанию — центр сцены).
  final (int, int)? startCell;

  /// Управление фичей в рабочей области (пресеты, ползунки, кнопки).
  final ControlsBuilder? controls;
}

/// Данные для сборки сцены фичи.
class FeatureBuildContext {
  const FeatureBuildContext({
    required this.project,
    required this.paths,
    this.params = const {},
  });

  /// Открытый проект ресурсов или null (сцена из кода).
  final SceneResources? project;

  /// Каталоги приложения.
  final AppPaths paths;

  /// Параметры сцены, заданные управлением фичи (радиус, режимы и т.п.).
  final Map<String, Object?> params;

  /// Параметр [key] или null. Числа из диплинков приходят как int/double,
  /// поэтому значение приводится к запрошенному числовому типу.
  T? param<T>(String key) {
    final value = params[key];
    if (value is T) return value;
    if (value is num) {
      if (T == double) return value.toDouble() as T;
      if (T == int) return value.toInt() as T;
    }
    if (T == String && value != null) return value.toString() as T;
    return null;
  }

  /// Модель проекта по идентификатору (null, если проекта нет).
  doc.ModelData? model(String id) => project?.model(id);

  /// Ключи текстур проекта (без расширения).
  List<String> get textureKeys => project?.textureKeys ?? const [];

  /// Ключи спрайтов проекта (без расширения).
  List<String> get spriteKeys => project?.spriteKeys ?? const [];
}

/// Управление сценой, которое фича получает в рабочей области.
///
/// Конкретный объект создаёт хост сцены: приложение — поверх реальной сцены
/// движка, автотесты — без видеокарты.
class FeatureContext {
  const FeatureContext({
    required this.host,
    required this.spec,
    required this.controller,
    required this.project,
    required this.paths,
    required this.reloadScene,
    required this.refresh,
    required this.toast,
    required this.stepCamera,
    required this.cellNavigation,
    required this.setCellNavigation,
    required this.setTick,
    required this.setTap,
    required this.setPointerHandlers,
    required this.setOverlay,
    required this.setBackground,
    required this.openStress,
    required this.params,
    required this.updateParams,
  });

  /// Хост сцены: настройки картинки (туман, тени, сглаживание).
  final SceneHost host;

  /// Описание текущей фичи.
  final FeatureSpec spec;

  /// Готовая сцена (null, пока она не загружена).
  final SceneController? controller;

  /// Открытый проект ресурсов (null для сцен из кода).
  final SceneResources? project;

  /// Каталоги приложения.
  final AppPaths paths;

  /// Пересобирает сцену фичи (ползунки, переключатели сцены).
  final void Function() reloadScene;

  /// Обновляет интерфейс без пересборки сцены.
  final void Function() refresh;

  /// Короткое сообщение внизу экрана.
  final void Function(String message) toast;

  /// Поворот/шаг камеры по клеткам.
  final void Function(AnimationType type) stepCamera;

  /// Показывать ли кнопки камеры по клеткам.
  final bool cellNavigation;

  /// Включает и выключает кнопки камеры по клеткам.
  final void Function(bool value) setCellNavigation;

  /// Покадровый обработчик фичи (частицы, эффекты).
  final void Function(void Function(double deltaSeconds)? tick) setTick;

  /// Обработчик нажатия по рабочей области (выбор объекта).
  final void Function(void Function(Offset position, Size size)? handler)
  setTap;

  /// Обработчики указателя для драга (гизмо): нажатие, движение,
  /// отпускание; позиция в логических пикселях, размер — вьюпорта.
  final void Function({
    void Function(Offset position, Size size)? down,
    void Function(Offset position, Size size)? move,
    void Function(Offset position, Size size)? up,
  })
  setPointerHandlers;

  /// Дополнительный слой поверх сцены (метки и рамки).
  final void Function(Widget Function(Size size)? builder) setOverlay;

  /// Фоновый слой за сценой (статический скайбокс).
  final void Function(Widget Function(Size size)? builder) setBackground;

  /// Открывает экран стресс-проверки с заданным размером уровня.
  final void Function(int size) openStress;

  /// Текущие параметры сцены фичи.
  final Map<String, Object?> params;

  /// Меняет параметры сцены и пересобирает её.
  final void Function(Map<String, Object?> values) updateParams;
}

/// Порядок групп в левой панели.
const List<String> kFeatureGroups = [
  'Документ сцены',
  'Свет и картинка',
  'Отрисовка и спрайты',
  'Динамика и взаимодействие',
  'Частицы и эффекты',
  'Уровневый слой',
  'Операции размещения',
  'Готовые сцены',
];

/// Полный каталог фич в порядке групп.
List<FeatureSpec> get kFeatureCatalog => List.unmodifiable(<FeatureSpec>[
  ...documentSceneFeatures,
  ...lightPictureFeatures,
  ...renderSpriteFeatures,
  ...dynamicsFeatures,
  ...particleFeatures,
  ...levelFeatures,
  ...placementFeatures,
  ...readySceneFeatures,
]);

/// Проверяет каталог на целостность: уникальные идентификаторы, непустые
/// тексты, группы из [kFeatureGroups]. Возвращает список проблем (пустой —
/// каталог корректен).
List<String> validateFeatureCatalog(List<FeatureSpec> features) {
  final problems = <String>[];
  final ids = <String>{};
  final idPattern = RegExp(r'^[a-z0-9_]+$');
  for (final f in features) {
    if (!idPattern.hasMatch(f.id)) {
      problems.add('идентификатор «${f.id}» должен быть из a-z, 0-9 и _');
    }
    if (!ids.add(f.id)) problems.add('идентификатор «${f.id}» повторяется');
    if (f.title.trim().length < 3) {
      problems.add('${f.id}: пустое название');
    }
    if (f.description.trim().length < 40) {
      problems.add('${f.id}: описание короче 40 символов');
    }
    if (!_hasCyrillic(f.description)) {
      problems.add('${f.id}: описание должно быть на русском языке');
    }
    if (f.checks.isEmpty) {
      problems.add('${f.id}: нет проверяемых утверждений');
    }
    for (final c in f.checks) {
      if (c.trim().length < 15) {
        problems.add('${f.id}: проверка «$c» короче 15 символов');
      }
      if (!_hasCyrillic(c)) {
        problems.add('${f.id}: проверка «$c» должна быть на русском языке');
      }
    }
    if (!kFeatureGroups.contains(f.group)) {
      problems.add('${f.id}: неизвестная группа «${f.group}»');
    }
  }
  return problems;
}

bool _hasCyrillic(String text) => RegExp(r'[а-яА-ЯёЁ]').hasMatch(text);
