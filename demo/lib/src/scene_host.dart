import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pet_engine_v2/models.dart' as doc;
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'features/common.dart';
import 'features/feature_registry.dart';
import 'navigation/cell_nav.dart';
import 'paths.dart';
import 'perf/device_performance.dart';
import 'perf/fps_meter.dart';
import 'perf/frame_stats_logger.dart';
import 'project_sources.dart';

/// Настройки текущей сцены, которые показывает правая панель.
class SceneSettings {
  const SceneSettings({
    this.ssao = false,
    this.shadows = false,
    this.wireframe = false,
    this.ambient = 1.0,
    this.environmentIntensity = 1.0,
    this.renderScale = 1.0,
    this.antiAliasing = SceneAntiAliasing.auto,
    this.filterQuality = FilterQuality.none,
    this.fogEnabled = false,
    this.fogStart = 1.0,
    this.fogEnd = 12.0,
    this.fogOpacity = 0.6,
    this.shadowCascades,
    this.shadowDistance,
  });

  final bool ssao;
  final bool shadows;

  /// Wireframe всей сцены: рёбра всех объектов пиксельной толщиной.
  final bool wireframe;

  final double ambient;
  final double environmentIntensity;
  final double renderScale;
  final SceneAntiAliasing antiAliasing;
  final FilterQuality filterQuality;
  final bool fogEnabled;
  final double fogStart;
  final double fogEnd;
  final double fogOpacity;

  /// Число каскадов теней.
  final int? shadowCascades;

  /// Дальность теней.
  final double? shadowDistance;

  SceneSettings copyWith({
    bool? ssao,
    bool? shadows,
    bool? wireframe,
    double? ambient,
    double? environmentIntensity,
    double? renderScale,
    SceneAntiAliasing? antiAliasing,
    FilterQuality? filterQuality,
    bool? fogEnabled,
    double? fogStart,
    double? fogEnd,
    double? fogOpacity,
    int? shadowCascades,
    double? shadowDistance,
  }) {
    return SceneSettings(
      ssao: ssao ?? this.ssao,
      shadows: shadows ?? this.shadows,
      wireframe: wireframe ?? this.wireframe,
      ambient: ambient ?? this.ambient,
      environmentIntensity: environmentIntensity ?? this.environmentIntensity,
      renderScale: renderScale ?? this.renderScale,
      antiAliasing: antiAliasing ?? this.antiAliasing,
      filterQuality: filterQuality ?? this.filterQuality,
      fogEnabled: fogEnabled ?? this.fogEnabled,
      fogStart: fogStart ?? this.fogStart,
      fogEnd: fogEnd ?? this.fogEnd,
      fogOpacity: fogOpacity ?? this.fogOpacity,
      shadowCascades: shadowCascades ?? this.shadowCascades,
      shadowDistance: shadowDistance ?? this.shadowDistance,
    );
  }
}

/// Владелец трёхмерной сцены: открывает проект ресурсов, собирает сцену
/// выбранной фичи, отдаёт виджет рабочей области и управляет камерой.
///
/// Интерфейс отделён от реализации, чтобы автотесты подставляли заглушку без
/// видеокарты ([buildViewport] и настройки переопределяются).
abstract class SceneHost extends ChangeNotifier {
  /// Готовая сцена движка (null в тестовой заглушке).
  SceneController? get controller;

  /// Открытый проект ресурсов (null для сцен из кода).
  SceneResources? get project;

  /// Идентификатор загруженной сцены.
  String? get modelId;

  /// Сцена готова к показу.
  bool get ready;

  /// Текст ошибки загрузки фичи (null — ошибок нет).
  String? get error;

  /// Строка состояния: название фичи и проекта.
  String get status;

  /// Показывать ли кнопки камеры по клеткам.
  bool get cellNavigation;
  set cellNavigation(bool value);

  /// Подпись измерителя частоты кадров.
  String get fpsLabel;

  /// Текущие настройки сцены (null, пока сцена не готова).
  SceneSettings? get settings;

  /// Управление текущей фичей для её виджетов.
  FeatureContext get context;

  /// Сообщение для пользователя (всплывающая строка).
  void Function(String message)? onToast;

  /// Нажатие без перетаскивания по рабочей области (для фич выбора объекта).
  void Function(Offset position, Size size)? onTap;

  /// Перехват указателя фичами с драгом (гизмо); null — не перехватывать.
  void Function(Offset position, Size size)? onPointerDown;
  void Function(Offset position, Size size)? onPointerMove;
  void Function(Offset position, Size size)? onPointerUp;

  /// Дополнительный слой поверх сцены (метки и рамки фич проецирования).
  Widget Function(Size size)? overlayBuilder;

  /// Фоновый слой за сценой (статический скайбокс): строится фичей и
  /// очищается при её смене.
  Widget Function(Size size)? backgroundBuilder;

  /// Запрос на открытие экрана стресс-проверки с заданным размером уровня.
  void Function(int size)? onStress;

  /// Номер загрузки сцены — сбрасывает локальное состояние панелей.
  int get revision;

  /// Открывает фичу: при смене проекта пересоздаёт сцену, собирает модель
  /// фичи и настраивает камеру. [params] задаёт параметры сцены до сборки
  /// (диплинки, автоматический прогон). [resetCamera] — принудительно
  /// вернуть камеру к стартовой (режим снимка).
  Future<void> showFeature(
    FeatureSpec spec, {
    Map<String, Object?>? params,
    bool resetCamera = false,
  });

  /// Пересобирает сцену текущей фичи; камера сохраняется, если не задан
  /// [resetCamera].
  void reloadFeature({bool resetCamera = false});

  /// Поворот/шаг камеры по клеткам.
  void stepCamera(AnimationType type);

  /// Затенение в стыках поверхностей.
  void applySsao(bool value);

  /// Тени от направленного света.
  void applyShadows(bool value);

  /// Wireframe всей сцены (рёбра объектов пиксельной толщиной).
  void applyWireframe(bool value);

  /// Яркость окружения.
  void applyAmbient(double value);

  /// Яркость отражённого света (окружения).
  void applyEnvironmentIntensity(double value);

  /// Число каскадов теней направленного света.
  void applyShadowCascades(int count);

  /// Дальность теней направленного света.
  void applyShadowDistance(double distance);

  /// Масштаб отрисовки и, при необходимости, фильтр увеличения.
  void applyRenderScale(double value, {FilterQuality? filterQuality});

  /// Сглаживание кромок.
  void applyAntiAliasing(SceneAntiAliasing value);

  /// Туман (null выключает).
  void applyFog(SceneFog? fog);

  /// Виджет трёхмерной области (в тестах — заглушка).
  Widget buildViewport(BuildContext context);

  /// Узел фокуса вьюпорта: клавиатурное управление камерой. В тестовой
  /// заглушке — null.
  FocusNode? get viewportFocus;
}

/// Реальная сцена на движке `pet_engine_v2`.
class DemoSceneHost extends SceneHost {
  DemoSceneHost({required this.paths});

  /// Каталоги приложения.
  final AppPaths paths;

  SceneController? _controller;
  SceneResources? _resources;
  QualityController? _quality;
  FeatureSpec? _spec;
  String? _projectName;
  bool _ready = false;
  String? _error;
  String _status = 'Загрузка…';
  bool _cellNavigation = false;
  int _revision = 0;
  Map<String, Object?> _params = const {};
  final FpsMeter _fps = FpsMeter();

  /// Покадровый обработчик текущей фичи (частицы, эффекты).
  void Function(double deltaSeconds)? featureTick;

  final FocusNode _viewportFocus = FocusNode(debugLabel: 'viewport');

  @override
  FocusNode? get viewportFocus => _viewportFocus;

  CellNavController? _cellNav;

  @override
  SceneController? get controller => _controller;

  @override
  SceneResources? get project => _resources;

  @override
  String? get modelId => _controller?.modelId;

  @override
  bool get ready => _ready;

  @override
  String? get error => _error;

  @override
  String get status => _status;

  @override
  bool get cellNavigation => _cellNavigation;

  @override
  set cellNavigation(bool value) {
    if (_cellNavigation == value) return;
    _cellNavigation = value;
    notifyListeners();
  }

  @override
  String get fpsLabel => _fps.label;

  @override
  int get revision => _revision;

  @override
  SceneSettings? get settings {
    final controller = _controller;
    if (controller == null) return null;
    final quality = controller.settings;
    final fog = controller.fog;
    return SceneSettings(
      ssao: quality.ssao,
      shadows: quality.shadows,
      wireframe: controller.wireframeStyle != null,
      ambient: controller.environmentIntensity,
      environmentIntensity: controller.environmentIntensity,
      renderScale: quality.renderScale,
      antiAliasing: controller.effectiveAntiAliasing,
      filterQuality: quality.filterQuality,
      fogEnabled: fog != null,
      fogStart: fog?.start ?? 1.0,
      fogEnd: fog?.end ?? 12.0,
      fogOpacity: fog?.maxOpacity ?? 0.6,
      shadowCascades: quality.shadowCascades,
      shadowDistance: quality.shadowDistance,
    );
  }

  @override
  FeatureContext get context => FeatureContext(
    host: this,
    spec: _spec!,
    controller: _controller,
    project: _resources,
    paths: paths,
    reloadScene: reloadFeature,
    refresh: refreshUi,
    toast: (message) => onToast?.call(message),
    stepCamera: stepCamera,
    cellNavigation: _cellNavigation,
    setCellNavigation: (value) => cellNavigation = value,
    // Панель управления только ставит обработчик: снятие tick при
    // удалении панели делает showFeature при смене фичи. Иначе dispose
    // старой панели гасит tick новой (порядок dispose/initState).
    setTick: (tick) {
      if (tick != null) featureTick = tick;
    },
    setTap: (handler) {
      if (handler != null) onTap = handler;
    },
    setPointerHandlers: ({down, move, up}) {
      onPointerDown = down;
      onPointerMove = move;
      onPointerUp = up;
    },
    setOverlay: (builder) {
      if (builder != null) overlayBuilder = builder;
    },
    setBackground: (builder) {
      if (builder != null) backgroundBuilder = builder;
    },
    openStress: (size) => onStress?.call(size),
    params: _params,
    updateParams: updateFeatureParams,
  );

  /// Обновляет интерфейс без пересборки сцены.
  void refreshUi() => notifyListeners();

  bool _disposed = false;
  bool _refreshScheduled = false;

  /// Отложенное обновление интерфейса после изменения сцены движком.
  void _onControllerChanged() {
    if (_refreshScheduled || _disposed) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Меняет параметры сцены текущей фичи и пересобирает её.
  void updateFeatureParams(Map<String, Object?> values) {
    _params = {..._params, ...values};
    reloadFeature();
  }

  @override
  Future<void> showFeature(
    FeatureSpec spec, {
    Map<String, Object?>? params,
    bool resetCamera = false,
  }) async {
    // Параметры сцены сбрасываются только при смене фичи; при пересборке
    // той же фичи (ползунки, переключатели) они сохраняются. Камера тоже
    // сохраняется: сброс — только при смене фичи или по явному запросу.
    final switching = _spec?.id != spec.id;
    if (switching) {
      _params = const {};
      featureTick = null;
      onTap = null;
      onPointerDown = null;
      onPointerMove = null;
      onPointerUp = null;
      overlayBuilder = null;
      backgroundBuilder = null;
    }
    if (params != null) _params = {..._params, ...params};
    _spec = spec;
    _error = null;
    _ready = false;
    notifyListeners();
    try {
      await _ensureProject(spec.project);
      final controller = _controller!;
      if (switching) controller.skybox?.remove();
      final buildContext = FeatureBuildContext(
        project: _resources,
        paths: paths,
        params: _params,
      );
      final data = spec.asyncBuild != null
          ? await spec.asyncBuild!(buildContext)
          : spec.build(buildContext);
      controller.loadModelData(data, id: spec.id);
      controller.applyLighting();
      if (switching || resetCamera) _applyCamera(spec, data);
      _revision++;
      _status = '${spec.title} · ${_resources?.projectName ?? 'сцена из кода'}';
      _ready = true;
    } catch (e, stackTrace) {
      debugPrint('feature error: $e\n$stackTrace');
      _error = 'Не удалось открыть фичу «${spec.title}»: $e';
    }
    notifyListeners();
  }

  @override
  void reloadFeature({bool resetCamera = false}) {
    final spec = _spec;
    if (spec != null) unawaited(showFeature(spec, resetCamera: resetCamera));
  }

  /// Контроллер камеры по клеткам для текущего контроллера камеры. Панель
  /// фичи может подменить активную камеру (свободная ↔ игровая), поэтому
  /// привязка обновляется в момент использования.
  CellNavController? _navForCurrentCamera() {
    final camera = _controller?.camera;
    if (camera is! FirstPersonCameraController) return null;
    final nav = _cellNav;
    if (nav == null || !identical(nav.controller, camera)) {
      _cellNav = CellNavController(camera);
    }
    return _cellNav;
  }

  @override
  void stepCamera(AnimationType type) {
    _navForCurrentCamera()?.step(type);
  }

  // Качество картинки идёт через единый QualityController: он владеет
  // настройками и политикой адаптации, а контроллер сцены только применяет
  // их к рендер-сцене. Прямые setShadows/setSsao у сцены оставили бы
  // QualityController с устаревшим состоянием.
  void _applyQuality(QualitySettings Function(QualitySettings) update) {
    final quality = _quality;
    if (quality == null) return;
    quality.apply(update(quality.settings));
  }

  @override
  void applySsao(bool value) =>
      _applyQuality((s) => s.copyWith(ssao: value));

  @override
  void applyShadows(bool value) =>
      _applyQuality((s) => s.copyWith(shadows: value));

  @override
  void applyWireframe(bool value) => _controller?.setWireframe(
    value ? const WireframeStyle(color: Color(0xFFE53935)) : null,
  );

  @override
  void applyAmbient(double value) =>
      _controller?.setEnvironmentIntensity(value);

  @override
  void applyEnvironmentIntensity(double value) =>
      _controller?.setEnvironmentIntensity(value);

  @override
  void applyShadowCascades(int count) =>
      _applyQuality((s) => s.copyWith(shadowCascades: count));

  @override
  void applyShadowDistance(double distance) =>
      _applyQuality((s) => s.copyWith(shadowDistance: distance));

  @override
  void applyRenderScale(double value, {FilterQuality? filterQuality}) =>
      _applyQuality(
        (s) => s.copyWith(
          renderScale: value,
          filterQuality: filterQuality,
        ),
      );

  @override
  void applyAntiAliasing(SceneAntiAliasing value) =>
      _applyQuality((s) => s.copyWith(antiAliasing: value));

  @override
  void applyFog(SceneFog? fog) => _controller?.setFog(fog);

  @override
  Widget buildViewport(BuildContext context) {
    final controller = _controller;
    if (controller == null || !_ready) return const SizedBox.expand();
    final down = onPointerDown;
    final move = onPointerMove;
    final up = onPointerUp;
    final capturesPointer = down != null || move != null || up != null;
    final viewport = SceneViewport(
      controller: controller,
      focusNode: _viewportFocus,
      // Драг гизмо перехватывает указатель: камера в такой сцене не
      // управляется мышью, чтобы жесты не конфликтовали.
      input: capturesPointer ? const SceneInput.none() : null,
      overlayBuilder: overlayBuilder == null
          ? null
          : (context, size) => overlayBuilder!(size),
      backgroundBuilder: backgroundBuilder == null
          ? null
          : (context, size) => backgroundBuilder!(size),
      onTap: (event) => onTap?.call(event.screenPosition, event.viewportSize),
      warmUp: false,
    );
    if (!capturesPointer) return viewport;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => down?.call(event.localPosition, size),
          onPointerMove: (event) => move?.call(event.localPosition, size),
          onPointerUp: (event) => up?.call(event.localPosition, size),
          onPointerCancel: (event) => up?.call(event.localPosition, size),
          child: viewport,
        );
      },
    );
  }

  /// Открывает проект ресурсов, если он ещё не открыт; при смене проекта
  /// полностью снимает прежнюю сцену.
  Future<void> _ensureProject(String? project) async {
    if (_controller != null && project == _projectName) return;
    _disposeScene();
    final source = sourceForProject(project);
    final controller = SceneController(mergeStatic: true);
    await controller.open(source);
    final quality = QualityController(adaptive: false);
    await quality.initialize();
    quality.attach(controller);
    quality.apply(
      QualityPreset.recommendedFor(
        detectGpuBackend(),
        DeviceCapabilities.detect(),
      ),
    );
    unawaited(
      DevicePerformance.setSustained(controller.settings.sustainedPerformance),
    );
    controller.addFrameListener((elapsed, dt) {
      featureTick?.call(dt);
      if (_fps.tick(dt)) {
        FrameStatsLogger.logMeter(_fps.label);
        notifyListeners();
      }
    });
    // Асинхронные догрузки (текстуры, glTF) меняют ревизию контроллера —
    // панели фичи должны увидеть новые данные (например, список анимаций
    // модели) без ручного обновления. Уведомление откладывается: контроллер
    // может меняться во время сборки кадра, и синхронный notifyListeners
    // привёл бы к setState во время build.
    controller.addListener(_onControllerChanged);
    _resources = controller.resources;
    _controller = controller;
    _quality = quality;
    _projectName = project;
    FrameStatsLogger.info(
      'scene: project=${project ?? 'code'} source=${source.label} '
      'scale=${controller.settings.renderScale} '
      'shadows=${controller.settings.shadows} '
      'ssao=${controller.settings.ssao}',
    );
  }

  /// Настраивает камеру под режим фичи: свободную, по клеткам или
  /// фиксированную (обзор всей сцены).
  void _applyCamera(FeatureSpec spec, doc.ModelData data) {
    final controller = _controller!;
    _cellNav = null;
    switch (spec.camera) {
      case CameraMode.cell:
        // Клетка задаётся в координатах модели, а камера — в мировых.
        final (row, column) = cameraCellFor(controller, spec.startCell);
        final camera = FirstPersonCameraController(
          facing: Direction.north,
          row: row,
          column: column,
        );
        controller.camera = camera;
        _cellNav = CellNavController(camera);
        _cellNavigation = true;
      case CameraMode.free:
      case CameraMode.fixed:
        final camera = FlyCameraController();
        camera.frameModel(data);
        controller.camera = camera;
        _cellNavigation = false;
    }
  }

  void _disposeScene() {
    featureTick = null;
    onTap = null;
    overlayBuilder = null;
    backgroundBuilder = null;
    _cellNav = null;
    _quality?.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _controller = null;
    _refreshScheduled = false;
    _resources = null;
    _quality = null;
    _projectName = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeScene();
    _viewportFocus.dispose();
    super.dispose();
  }
}
