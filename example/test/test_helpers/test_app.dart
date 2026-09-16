import 'dart:async';
import 'dart:io';

import 'package:example/src/app_info.dart';
import 'package:example/src/app_shell.dart';
import 'package:example/src/features/feature_registry.dart';
import 'package:example/src/paths.dart';
import 'package:example/src/scene_host.dart';
import 'package:example/src/screenshot_saver.dart';
import 'package:example/src/stress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/models.dart' as doc;
import 'package:pet_engine/pet_engine.dart';

/// Хост без видеокарты: сцена не создаётся, но весь интерфейсный контур
/// (готовность, ошибки, настройки, камера) ведёт себя как настоящий.
class FakeSceneHost extends ChangeNotifier implements SceneHost {
  FakeSceneHost({required this.paths});

  final AppPaths paths;

  FeatureSpec? _spec;
  bool _ready = false;
  String? _error;
  String _status = 'Загрузка…';
  String? _modelId;
  bool _cellNavigation = false;
  int _revision = 0;
  Map<String, Object?> _params = const {};
  doc.ModelData? _lastScene;
  SceneSettings _settings = const SceneSettings();

  /// Последняя собранная сцена (для проверки параметров в тестах).
  doc.ModelData? get lastScene => _lastScene;

  /// Шаги камеры по клеткам, зафиксированные в тесте.
  final List<String> cameraSteps = [];

  /// Сколько раз камера была применена заново (сброшена).
  int cameraApplies = 0;

  @override
  SceneController? get controller => null;

  @override
  SceneResources? get project => null;

  @override
  String? get modelId => _modelId;

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
    _cellNavigation = value;
    notifyListeners();
  }

  @override
  String get fpsLabel => '—';

  @override
  int get revision => _revision;

  @override
  SceneSettings? get settings => _settings;

  @override
  void Function(String message)? onToast;

  @override
  void Function(Offset position, Size size)? onTap;

  @override
  void Function(Offset position, Size size)? onPointerDown;

  @override
  void Function(Offset position, Size size)? onPointerMove;

  @override
  void Function(Offset position, Size size)? onPointerUp;

  @override
  Widget Function(Size size)? overlayBuilder;

  @override
  Widget Function(Size size)? backgroundBuilder;

  @override
  void Function(int size)? onStress;

  @override
  FocusNode? get viewportFocus => null;

  @override
  FeatureContext get context => FeatureContext(
    host: this,
    spec: _spec!,
    controller: null,
    project: null,
    paths: paths,
    reloadScene: reloadFeature,
    refresh: notifyListeners,
    toast: (message) => onToast?.call(message),
    stepCamera: stepCamera,
    cellNavigation: _cellNavigation,
    setCellNavigation: (value) => cellNavigation = value,
    setTick: (_) {},
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

  /// Меняет параметры сцены и пересобирает её.
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
    final switching = _spec?.id != spec.id;
    if (switching) {
      _params = const {};
      onTap = null;
      overlayBuilder = null;
      backgroundBuilder = null;
    }
    if (switching || resetCamera) cameraApplies++;
    if (params != null) _params = {..._params, ...params};
    _spec = spec;
    _ready = false;
    _error = null;
    notifyListeners();
    try {
      final buildContext = FeatureBuildContext(
        project: null,
        paths: paths,
        params: _params,
      );
      final data = spec.asyncBuild != null
          ? await spec.asyncBuild!(buildContext)
          : spec.build(buildContext);
      _lastScene = data;
      _modelId = data.id;
      _settings = _settings.copyWith(
        ssao: data.lighting.ssao,
        shadows: data.lighting.shadows,
        ambient: data.lighting.ambient,
      );
      _cellNavigation = spec.camera == CameraMode.cell;
      _status = '${spec.title} · тест';
      _ready = true;
    } catch (e) {
      _error = 'Не удалось открыть фичу «${spec.title}»: $e';
    }
    _revision++;
    notifyListeners();
  }

  @override
  void reloadFeature({bool resetCamera = false}) {
    final spec = _spec;
    if (spec != null) unawaited(showFeature(spec, resetCamera: resetCamera));
  }

  @override
  void stepCamera(AnimationType type) {
    cameraSteps.add(type.name);
  }

  @override
  void applySsao(bool value) => _settings = _settings.copyWith(ssao: value);

  @override
  void applyShadows(bool value) =>
      _settings = _settings.copyWith(shadows: value);

  @override
  void applyWireframe(bool value) =>
      _settings = _settings.copyWith(wireframe: value);

  @override
  void applyAmbient(double value) =>
      _settings = _settings.copyWith(ambient: value);

  @override
  void applyEnvironmentIntensity(double value) =>
      _settings = _settings.copyWith(environmentIntensity: value);

  @override
  void applyShadowCascades(int count) =>
      _settings = _settings.copyWith(shadowCascades: count);

  @override
  void applyShadowDistance(double distance) =>
      _settings = _settings.copyWith(shadowDistance: distance);

  @override
  void applyRenderScale(double value, {FilterQuality? filterQuality}) =>
      _settings = _settings.copyWith(
        renderScale: value,
        filterQuality: filterQuality,
      );

  @override
  void applyAntiAliasing(SceneAntiAliasing value) =>
      _settings = _settings.copyWith(antiAliasing: value);

  @override
  void applyFog(SceneFog? fog) => _settings = _settings.copyWith(
    fogEnabled: fog != null,
    fogStart: fog?.start,
    fogEnd: fog?.end,
    fogOpacity: fog?.maxOpacity,
  );

  @override
  Widget buildViewport(BuildContext context) =>
      const ColoredBox(key: Key('viewport'), color: Color(0xFF101418));
}

/// Сведения о версиях для тестов интерфейса.
const AppInfo testInfo = AppInfo(
  appVersion: '0.1.0+1',
  engineVersion: '0.1.0-dev.1',
  flutterVersion: '',
  dartVersion: '3.10.0',
  platform: 'macOS',
  gpu: 'Metal',
  commit: '',
  buildDate: '',
  changelog: 'История изменений для теста.',
);

/// Каталоги приложения во временном каталоге репозитория.
AppPaths testPaths() {
  final dir = Directory('temp/test_app');
  dir.createSync(recursive: true);
  return AppPaths(dir);
}

/// Простая сцена из одного объекта для тестов.
doc.ModelData emptyScene(String id) =>
    doc.ModelData(id: id, name: id, size: doc.ModelSize(w: 2, l: 2, h: 2));

/// Фича для тестов интерфейса.
FeatureSpec testFeature({
  required String id,
  String group = 'Документ сцены',
  String title = 'Тестовая фича',
  doc.ModelData Function()? build,
  Widget Function(BuildContext context, FeatureContext feature)? controls,
  CameraMode camera = CameraMode.free,
}) {
  return FeatureSpec(
    id: id,
    group: group,
    title: title,
    phase: 1,
    description: 'Тестовое описание возможности движка для автотеста.',
    checks: const ['Проверяем, что тестовая сцена открывается и работает.'],
    build: (context) => (build ?? () => emptyScene(id))(),
    camera: camera,
    controls: controls,
  );
}

/// Открывает каркас приложения в тесте.
Future<void> pumpShell(
  WidgetTester tester, {
  required List<FeatureSpec> features,
  SceneHost? host,
  StressRunner? stressRunner,
  AppPaths? paths,
  ScreenshotSaver? screenshotSaver,
  ScreenshotCapture? screenshotCapture,
}) async {
  final resolved = paths ?? testPaths();
  await tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        paths: resolved,
        info: testInfo,
        host: host ?? FakeSceneHost(paths: resolved),
        features: features,
        stressRunner: stressRunner,
        screenshotSaver: screenshotSaver,
        screenshotCapture: screenshotCapture,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Показывает управление фичи без каркаса (для проверки переключателей).
Future<void> pumpFeatureControls(
  WidgetTester tester,
  FakeSceneHost host,
  FeatureSpec spec,
) async {
  await host.showFeature(spec);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (context) => spec.controls!(context, host.context),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
