import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pet_engine/pet_engine.dart';

import 'about_screen.dart';
import 'app_info.dart';
import 'deeplink.dart';
import 'features/feature_registry.dart';
import 'paths.dart';
import 'scene_host.dart';
import 'screenshot_saver.dart';
import 'settings_panel.dart';
import 'stress_screen.dart';
import 'visual/visual_panels.dart';
import 'visual/visual_tests.dart';

/// Что показывается в рабочей области.
enum WorkspaceMode { welcome, feature, about, stress, checklist }

/// Каркас приложения-примера: слева каталог возможностей движка, в центре
/// рабочая область сцен, справа сворачиваемая панель настроек сцены.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.paths,
    required this.info,
    this.host,
    this.features,
    this.stressRunner,
    this.screenshotSaver,
    this.screenshotCapture,
  });

  final AppPaths paths;
  final AppInfo info;

  /// Хост сцены; в тестах подставляется заглушка без видеокарты.
  final SceneHost? host;

  /// Каталог фич; по умолчанию полный [kFeatureCatalog].
  final List<FeatureSpec>? features;

  /// Запуск стресс-проверки; в тестах подставляется без видеокарты.
  final StressRunner? stressRunner;

  /// Сохранение снимков экрана; в тестах подменяется без записи на диск.
  final ScreenshotSaver? screenshotSaver;

  /// Захват кадра; в тестах подменяется без видеоконтура.
  final ScreenshotCapture? screenshotCapture;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Область снимка: всё окно приложения.
  final GlobalKey _windowBoundaryKey = GlobalKey(debugLabel: 'window-boundary');

  /// Область снимка: только трёхмерная рабочая область.
  final GlobalKey _viewportBoundaryKey = GlobalKey(
    debugLabel: 'viewport-boundary',
  );

  late final DeeplinkController _deeplink;

  late final SceneHost _host;
  late final List<FeatureSpec> _features;
  late final VisualTestStore _visual;
  WorkspaceMode _mode = WorkspaceMode.welcome;
  FeatureSpec? _selected;
  bool _settingsOpen = false;
  bool _bugPanelOpen = false;
  bool _showAllChecks = false;
  bool _showFps = true;
  bool _panelsHidden = false;
  int _stressSize = 50;
  bool _stressAutoRun = false;

  /// Очередь команд диплинков и канала управления: следующая команда ждёт
  /// завершения предыдущей.
  Future<void> _commandChain = Future.value();

  /// Настройки сцены из команды `settings`; повторяются после открытия
  /// следующей сцены.
  Map<String, String> _sceneSettings = const {};

  /// Ключи запуска, открывающие фичу на старте (совместимость со скриптами
  /// замеров): `pet.weather=rain|snow|wind|cave`, `pet.level=stress|streets`.
  static const Map<String, String> _weatherFeature = {
    'rain': 'weather_rain',
    'snow': 'weather_snow',
    'wind': 'weather_wind',
    'cave': 'weather_cave_draft',
  };
  static const Map<String, String> _levelFeature = {
    'stress': 'level_stress',
    'streets': 'level_docking',
  };

  @override
  void initState() {
    super.initState();
    _features = widget.features ?? kFeatureCatalog;
    _visual = VisualTestStore(file: widget.paths.visualTestsFile)..load();
    _visual.data
      ..appVersion = widget.info.appVersion
      ..engineVersion = widget.info.engineVersion
      ..platform = '${widget.info.platform} · ${widget.info.gpu}';
    _host = widget.host ?? DemoSceneHost(paths: widget.paths);
    _host.onToast = (message) {
      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    };
    _host.addListener(_onHostChanged);
    _host.onStress = (size) {
      setState(() {
        _stressSize = size;
        _stressAutoRun = false;
        _mode = WorkspaceMode.stress;
      });
    };
    _startFromDefines();
    _deeplink = DeeplinkController(onLog: _logDeeplink)
      ..onCommand = _handleDeeplink;
    _deeplink.start();
    _registerControlExtension();
  }

  @override
  void dispose() {
    _deeplink.dispose();
    _host.removeListener(_onHostChanged);
    if (widget.host == null) _host.dispose();
    super.dispose();
  }

  void _startFromDefines() {
    const weather = String.fromEnvironment('pet.weather');
    const level = String.fromEnvironment('pet.level');
    String? id;
    if (level.isNotEmpty) {
      id = _levelFeature[level];
    } else if (weather.isNotEmpty) {
      id = _weatherFeature[weather] ?? 'weather_rain';
    }
    if (id == null) return;
    final spec = _featureById(id);
    if (spec == null) return;
    _select(spec);
    if (level == 'stress') {
      // Совместимость со скриптами замеров: сразу открываем экран стресса.
      setState(() {
        _stressSize = 100;
        _stressAutoRun = true;
        _mode = WorkspaceMode.stress;
      });
    }
  }

  FeatureSpec? _featureById(String id) {
    for (final f in _features) {
      if (f.id == id) return f;
    }
    return null;
  }

  // ── диплинки и снимки экрана ─────────────────────────────────────────

  /// Выполняет команду диплинка в общей очереди.
  Future<void> _handleDeeplink(DeeplinkCommand command) =>
      _serialize(() => _executeDeeplink(command));

  /// Ставит действие в очередь команд и возвращает его результат.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _commandChain = _commandChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Выполняет команду диплинка: открывает сцену, снимает экран или
  /// открывает служебный экран; снимок сохраняется на устройство.
  Future<void> _executeDeeplink(DeeplinkCommand command) async {
    await _runCommand(command, save: true);
  }

  /// Выполняет команду и возвращает её результат: `{ok: true, …}` или
  /// `{ok: false, error: …}`. Канал управления забирает PNG в base64.
  Future<Map<String, Object?>> _runCommand(
    DeeplinkCommand command, {
    required bool save,
  }) async {
    switch (command) {
      case OpenSceneCommand(
        :final featureId,
        :final params,
        :final panelsHidden,
      ):
        await _setPanelsHidden(panelsHidden);
        if (!await _openFeatureFromDeeplink(featureId, params)) {
          return _featureNotFound(featureId);
        }
        return const {'ok': true};
      case CaptureCommand(
        :final featureId,
        :final name,
        :final params,
        :final region,
        :final delayMs,
        :final scale,
        :final panelsHidden,
      ):
        final wasHidden = _panelsHidden;
        await _setPanelsHidden(panelsHidden);
        if (!await _openFeatureFromDeeplink(featureId, params)) {
          if (panelsHidden) await _setPanelsHidden(wasHidden);
          return _featureNotFound(featureId);
        }
        final result = await _captureScreenshot(
          name: name,
          region: region,
          delayMs: delayMs,
          scale: scale,
        );
        if (panelsHidden) await _setPanelsHidden(wasHidden);
        if (result != null && save) await _saveScreenshot(result);
        return _screenshotResponse(result);
      case ScreenshotCommand(
        :final name,
        :final region,
        :final delayMs,
        :final scale,
        :final panelsHidden,
      ):
        final wasHidden = _panelsHidden;
        await _setPanelsHidden(panelsHidden);
        if (panelsHidden && _selected != null) {
          // Пересборка, чтобы камера сфреймила сцену под полный размер окна.
          _host.reloadFeature(resetCamera: true);
        }
        final result = await _captureScreenshot(
          name: name ?? _selected?.id ?? 'screenshot',
          region: region,
          delayMs: delayMs,
          scale: scale,
        );
        if (panelsHidden) await _setPanelsHidden(wasHidden);
        if (result != null && save) await _saveScreenshot(result);
        return _screenshotResponse(result);
      case OpenScreenCommand(:final screen):
        setState(() {
          _mode = screen == 'checklist'
              ? WorkspaceMode.checklist
              : WorkspaceMode.about;
        });
        return const {'ok': true};
      case SettingsCommand(:final values):
        _applySceneSettings(values);
        return const {'ok': true};
    }
  }

  /// Применяет настройки сцены из команды `settings`: туман, SSAO, тени,
  /// яркость окружения. Настройки запоминаются и повторяются после открытия
  /// следующей сцены (смена проекта пересоздаёт сцену и сбрасывает их).
  void _applySceneSettings(Map<String, String> values) {
    if (values['reset'] == '1') {
      _sceneSettings = const {};
      _host.applyFog(null);
      _host.applySsao(false);
      _host.applyShadows(false);
      _host.applyWireframe(false);
      _host.applyAmbient(1);
      setState(() {});
      return;
    }
    _sceneSettings = {..._sceneSettings, ...values};
    _applyStoredSceneSettings();
  }

  void _applyStoredSceneSettings() {
    final values = _sceneSettings;
    if (values.isEmpty) return;

    bool flag(String key, {bool fallback = true}) {
      final raw = values[key];
      if (raw == null) return fallback;
      return raw == '1' || raw == 'true';
    }

    double number(String key, double fallback) =>
        double.tryParse(values[key] ?? '') ?? fallback;

    if (values.containsKey('ssao')) _host.applySsao(flag('ssao'));
    if (values.containsKey('shadows')) {
      _host.applyShadows(flag('shadows'));
    }
    if (values.containsKey('wireframe')) {
      _host.applyWireframe(flag('wireframe', fallback: false));
    }
    if (values.containsKey('ambient')) {
      _host.applyAmbient(number('ambient', 1));
    }
    final cascades = int.tryParse(values['cascades'] ?? '');
    if (cascades != null) _host.applyShadowCascades(cascades);
    final shadowDistance = double.tryParse(values['shadowDistance'] ?? '');
    if (shadowDistance != null) _host.applyShadowDistance(shadowDistance);
    // Визуальные проверки камеры по клеткам: `step=forward|backward|left|right`
    // запускает шаг/поворот так же, как кнопка внизу экрана.
    final step = switch (values['step']) {
      'forward' => AnimationType.stepForward,
      'backward' => AnimationType.stepBackward,
      'left' => AnimationType.turnLeft,
      'right' => AnimationType.turnRight,
      _ => null,
    };
    if (step != null) _host.stepCamera(step);
    final hasFog = values.keys.any((key) => key.startsWith('fog'));
    if (hasFog) {
      if (!flag('fog')) {
        _host.applyFog(null);
      } else {
        _host.applyFog(
          SceneFog(
            color: _fogColor(values['fogColor']),
            start: number('fogStart', 4),
            end: number('fogEnd', 30),
            maxOpacity: number('fogOpacity', 0.75),
          ),
        );
      }
    }
    setState(() {});
  }

  /// Цвет тумана по имени (совпадает с выбором в сцене «Туман»).
  Color _fogColor(String? name) => switch (name) {
    'white' => const Color(0xFFD9DEE6),
    'green' => const Color(0xFF73997A),
    _ => const Color(0xFF8C99AD),
  };

  Map<String, Object?> _screenshotResponse(ScreenshotResult? result) {
    if (result == null) {
      return const {'ok': false, 'error': 'снимок не сделан'};
    }
    return {
      'ok': true,
      'name': result.name,
      'meta': result.meta,
      'png': base64Encode(result.pngBytes),
    };
  }

  Map<String, Object?> _featureNotFound(String id) => {
    'ok': false,
    'error': 'фича «$id» не найдена',
  };

  /// Показывает или скрывает панели интерфейса и дожидается кадра, чтобы
  /// рабочая область успела занять новый размер.
  Future<void> _setPanelsHidden(bool value) async {
    if (_panelsHidden == value) return;
    setState(() => _panelsHidden = value);
    WidgetsBinding.instance.scheduleFrame();
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 2),
      );
    } on TimeoutException {
      // Кадр не пришёл — снимок возьмёт последний отрисованный слой.
    }
  }

  /// Открывает фичу по идентификатору с параметрами сцены. Возвращает false,
  /// если фичи с таким идентификатором нет.
  Future<bool> _openFeatureFromDeeplink(
    String id,
    Map<String, Object?> params,
  ) async {
    final spec = _featureById(id);
    if (spec == null) {
      _logDeeplink('фича «$id» не найдена');
      return false;
    }
    setState(() {
      _selected = spec;
      _mode = WorkspaceMode.feature;
      _bugPanelOpen = false;
    });
    await _host.showFeature(spec, params: params.isEmpty ? null : params);
    _applyStoredSceneSettings();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    return true;
  }

  /// Ждёт готовности сцены и паузы на догрузку текстур и делает снимок окна
  /// или рабочей области. Запись — отдельный шаг ([_saveScreenshot]).
  Future<ScreenshotResult?> _captureScreenshot({
    required String name,
    required String region,
    required int delayMs,
    double? scale,
  }) async {
    final safeName = sanitizeScreenshotName(name);
    final key = region == kScreenshotRegionViewport
        ? _viewportBoundaryKey
        : _windowBoundaryKey;
    final pixelRatio = scale ?? View.of(context).devicePixelRatio;

    // Ошибку загрузки тоже нужно увидеть на снимке, поэтому ждём не только
    // готовности, но и ограниченное время.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!_host.ready &&
        _host.error == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final capture = widget.screenshotCapture ?? captureBoundary;
    final bytes = await capture(key, pixelRatio);
    if (bytes == null) {
      _logDeeplink('область снимка «$region» не найдена');
      return null;
    }
    return ScreenshotResult(
      name: safeName,
      pngBytes: bytes,
      meta: _screenshotMeta(
        region: region,
        delayMs: delayMs,
        pixelRatio: pixelRatio,
      ),
    );
  }

  /// Сохраняет снимок и печатает путь в журнал.
  Future<void> _saveScreenshot(ScreenshotResult result) async {
    final saver = widget.screenshotSaver;
    final path = saver != null
        ? await saver(result.name, result.pngBytes, result.meta)
        : await writeScreenshotFiles(
            widget.paths,
            result.name,
            result.pngBytes,
            result.meta,
          );
    _logDeeplink('снимок: $path');
  }

  /// Карточка снимка: сцена, параметры, настройки, версии.
  Map<String, Object?> _screenshotMeta({
    required String region,
    required int delayMs,
    required double pixelRatio,
  }) {
    return <String, Object?>{
      'region': region,
      'delayMs': delayMs,
      'pixelRatio': pixelRatio,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'featureId': _selected?.id,
      'title': _selected?.title,
      'params': _selected == null ? const {} : _host.context.params,
      'ready': _host.ready,
      'status': _host.status,
      'error': _host.error,
      'fps': _host.fpsLabel,
      'settings': _settingsToJson(_host.settings),
      'appVersion': widget.info.appVersion,
      'engineVersion': widget.info.engineVersion,
      'platform': '${widget.info.platform} · ${widget.info.gpu}',
    };
  }

  Map<String, Object?> _settingsToJson(SceneSettings? settings) {
    if (settings == null) return const {};
    return {
      'ssao': settings.ssao,
      'shadows': settings.shadows,
      'wireframe': settings.wireframe,
      'ambient': settings.ambient,
      'environmentIntensity': settings.environmentIntensity,
      'renderScale': settings.renderScale,
      'antiAliasing': settings.antiAliasing.name,
      'filterQuality': settings.filterQuality.name,
      'fogEnabled': settings.fogEnabled,
      'fogStart': settings.fogStart,
      'fogEnd': settings.fogEnd,
      'fogOpacity': settings.fogOpacity,
      'shadowCascades': settings.shadowCascades,
      'shadowDistance': settings.shadowDistance,
    };
  }

  void _logDeeplink(String message) {
    debugPrint(message);
    try {
      final log = widget.paths.deeplinkLogFile;
      log.parent.createSync(recursive: true);
      log.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
      );
    } on FileSystemException {
      // Журнал недоступен — работе приложения это не мешает.
    }
  }

  /// Регистрирует сервис-расширение для постоянной debug-сессии на iPad:
  /// `flutter run --machine` вызывает его через `app.callServiceExtension`.
  /// Работает только в debug и только при `--dart-define=pet.control=true`.
  void _registerControlExtension() {
    if (!kDebugMode) return;
    if (const String.fromEnvironment('pet.control') != 'true') return;
    developer.registerExtension('ext.example.deeplink', (method, parameters) {
      return _serialize(() async {
        final url = parameters['url'] ?? '';
        _logDeeplink('канал: $url');
        try {
          final result = await _runControlUrl(url);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } catch (error) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            '$error',
          );
        }
      });
    });
  }

  /// Разбирает URL канала управления и выполняет команду; снимок возвращается
  /// в ответе в base64.
  Future<Map<String, Object?>> _runControlUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    final command = uri == null ? null : parseDeeplink(uri);
    if (command == null) {
      return {'ok': false, 'error': 'команда не распознана: $raw'};
    }
    return _runCommand(command, save: false);
  }

  void _select(FeatureSpec spec) {
    setState(() {
      _selected = spec;
      _mode = WorkspaceMode.feature;
      _bugPanelOpen = false;
    });
    unawaited(_showFeatureAndRefresh(spec));
  }

  void _selectFromChecklist(FeatureSpec spec) {
    setState(() {
      _selected = spec;
      _bugPanelOpen = false;
    });
    unawaited(_showFeatureAndRefresh(spec));
  }

  /// Открывает фичу и после сборки сцены перестраивает каркас: панель
  /// управления могла установить оверлей, который включается следующим
  /// кадром (в том же кадре условия ещё видели пустой слот).
  Future<void> _showFeatureAndRefresh(FeatureSpec spec) async {
    await _host.showFeature(spec);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _showChecklist() {
    setState(() => _mode = WorkspaceMode.checklist);
  }

  void _visualChanged() {
    if (mounted) setState(() {});
  }

  void _showAbout() {
    setState(() => _mode = WorkspaceMode.about);
  }

  void _onHostChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Focus(
        canRequestFocus: false,
        child: RepaintBoundary(
          key: _windowBoundaryKey,
          child: Scaffold(
            backgroundColor: const Color(0xFF20242C),
            body: SafeArea(
              child: _panelsHidden
                  ? _buildWorkspace()
                  : Row(
                      children: [
                        SizedBox(width: 300, child: _buildNavPanel()),
                        const VerticalDivider(width: 1, color: Colors.white12),
                        Expanded(child: _buildWorkspace()),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ── левая панель ─────────────────────────────────────────────────────

  Widget _buildNavPanel() {
    return Container(
      color: const Color(0xFF1B1F26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(
              'Возможности движка',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('nav-list'),
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final group in kFeatureGroups)
                  if (_features.any((f) => f.group == group)) ...[
                    _groupHeader(group),
                    for (final f in _features.where((f) => f.group == group))
                      _featureTile(f),
                  ],
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          _navTile(
            key: const Key('nav-checklist'),
            icon: Icons.checklist,
            title: 'Визуальное тестирование',
            selected: _mode == WorkspaceMode.checklist,
            onTap: _showChecklist,
          ),
          _navTile(
            key: const Key('nav-about'),
            icon: Icons.info_outline,
            title: 'О приложении',
            selected: _mode == WorkspaceMode.about,
            onTap: _showAbout,
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _featureTile(FeatureSpec spec) {
    final selected = _mode == WorkspaceMode.feature && _selected?.id == spec.id;
    final openBugs = _visual.openBugCount(spec.id);
    final hasBugs = _visual.hasBugs(spec.id);
    return Material(
      color: selected ? const Color(0xFF2C3340) : Colors.transparent,
      child: InkWell(
        key: Key('feature-${spec.id}'),
        onTap: () => _select(spec),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  spec.title,
                  softWrap: true,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
              if (hasBugs)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bug_report,
                        size: 14,
                        color: openBugs > 0 ? Colors.redAccent : Colors.white38,
                      ),
                      if (openBugs > 0)
                        Text(
                          '$openBugs',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navTile({
    required Key key,
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF2C3340) : Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── рабочая область ──────────────────────────────────────────────────

  Widget _buildWorkspace() {
    switch (_mode) {
      case WorkspaceMode.welcome:
        return _buildWelcome();
      case WorkspaceMode.about:
        return AboutScreen(info: widget.info);
      case WorkspaceMode.stress:
        return StressScreen(
          paths: widget.paths,
          initialSize: _stressSize,
          autoRun: _stressAutoRun,
          runner: widget.stressRunner ?? _defaultStressRunner,
          fpsLabel: () => _host.fpsLabel,
          onBack: () => setState(() => _mode = WorkspaceMode.feature),
        );
      case WorkspaceMode.checklist:
        return _buildChecklistWorkspace();
      case WorkspaceMode.feature:
        return _buildFeatureWorkspace();
    }
  }

  Widget _buildChecklistWorkspace() {
    final spec = _selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Боковые панели сжимаются на узких окнах, чтобы рабочая область
        // всегда помещалась.
        final side = (constraints.maxWidth * 0.32).clamp(150.0, 340.0);
        return Row(
          children: [
            SizedBox(
              width: side,
              child: ChecklistPanel(
                features: _features,
                store: _visual,
                selectedId: spec?.id,
                showAll: _showAllChecks,
                onShowAllChanged: (v) => setState(() => _showAllChecks = v),
                onSelect: _selectFromChecklist,
              ),
            ),
            const VerticalDivider(width: 1, color: Colors.white12),
            Expanded(
              child: spec == null
                  ? const Center(
                      child: Text(
                        'Выберите фичу для проверки',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : _buildViewportArea(spec),
            ),
            if (spec != null) ...[
              const VerticalDivider(width: 1, color: Colors.white12),
              SizedBox(
                width: side,
                child: QuestionnairePanel(
                  key: ValueKey('questionnaire-${spec.id}'),
                  spec: spec,
                  store: _visual,
                  version: widget.info.versionLine,
                  onChanged: _visualChanged,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<StressResult> _defaultStressRunner(int size) {
    final controller = _host.controller;
    if (controller == null) {
      throw StateError('сцена не готова');
    }
    return runStressLevel(controller, size);
  }

  Widget _buildWelcome() {
    return const Center(
      key: Key('welcome'),
      child: Text(
        'Выберите возможность движка в левой панели.',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );
  }

  Widget _buildFeatureWorkspace() {
    final spec = _selected;
    if (spec == null) return _buildWelcome();
    return Row(
      children: [
        Expanded(child: _buildViewportArea(spec)),
        if (_bugPanelOpen) ...[
          const VerticalDivider(width: 1, color: Colors.white12),
          SizedBox(
            width: 340,
            child: BugPanel(
              key: ValueKey('bugs-${spec.id}'),
              spec: spec,
              store: _visual,
              version: widget.info.versionLine,
              onChanged: _visualChanged,
            ),
          ),
        ] else if (_settingsOpen) ...[
          const VerticalDivider(width: 1, color: Colors.white12),
          SizedBox(
            width: 300,
            child: SettingsPanel(
              key: ValueKey('settings-${_host.revision}'),
              host: _host,
              showFps: _showFps,
              onShowFpsChanged: (v) => setState(() => _showFps = v),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildViewportArea(FeatureSpec spec, {bool showControls = true}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final hasControls =
            showControls &&
            spec.controls != null &&
            _host.ready &&
            !_panelsHidden;
        final panelWidth = (constraints.maxWidth * 0.35).clamp(240.0, 360.0);
        return RepaintBoundary(
          key: _viewportBoundaryKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _host.viewportFocus?.requestFocus(),
                  child: _host.buildViewport(context),
                ),
              ),
              if (_host.overlayBuilder != null)
                Positioned.fill(
                  key: const ValueKey('feature-overlay-layer'),
                  child: IgnorePointer(
                    child: _host.overlayBuilder!(viewportSize),
                  ),
                ),
              if (_host.error != null)
                Positioned.fill(
                  key: const ValueKey('scene-error-layer'),
                  child: ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _host.error!,
                          key: const Key('scene-error'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (!_host.ready)
                const Positioned.fill(
                  key: ValueKey('scene-loading-layer'),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Загрузка сцены…',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              // Левая колонка: карточка частоты кадров/статуса, под ней — вся
              // панель управления фичи на оставшуюся высоту (отступы 8).
              if (hasControls)
                Positioned(
                  left: 8,
                  top: 8,
                  bottom: 8,
                  width: panelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(spec),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Material(
                          key: const Key('feature-controls'),
                          color: const Color(0xE620242C),
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: KeyedSubtree(
                              key: ValueKey('controls-${spec.id}'),
                              child: spec.controls!(context, _host.context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_panelsHidden)
                Positioned(
                  key: const ValueKey('status-card-layer'),
                  top: 8,
                  left: 8,
                  child: _buildStatusCard(spec),
                ),
              // В режиме снимка панель управления не показывается, но её
              // состояние создаёт содержимое сцены (спрайты, частицы), поэтому
              // виджет монтируется скрытым.
              if (!hasControls &&
                  _panelsHidden &&
                  showControls &&
                  spec.controls != null &&
                  _host.ready)
                Positioned.fill(
                  key: const ValueKey('feature-controls-offstage'),
                  child: Offstage(
                    offstage: true,
                    child: KeyedSubtree(
                      key: ValueKey('controls-${spec.id}'),
                      child: spec.controls!(context, _host.context),
                    ),
                  ),
                ),
              if (!_panelsHidden)
                Positioned(
                  key: const ValueKey('top-buttons-layer'),
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      if (_selected != null)
                        IconButton.filledTonal(
                          key: const Key('bug-button'),
                          tooltip: 'Сообщить о проблеме',
                          onPressed: () => setState(() {
                            _bugPanelOpen = !_bugPanelOpen;
                            if (_bugPanelOpen) _settingsOpen = false;
                          }),
                          icon: Badge(
                            isLabelVisible:
                                _selected != null &&
                                _visual.openBugCount(_selected!.id) > 0,
                            label: Text(
                              '${_visual.openBugCount(_selected?.id ?? '')}',
                            ),
                            child: Icon(
                              Icons.bug_report,
                              color: _bugPanelOpen
                                  ? Colors.redAccent
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        key: const Key('settings-button'),
                        tooltip: 'Настройки сцены',
                        onPressed: () => setState(() {
                          _settingsOpen = !_settingsOpen;
                          if (_settingsOpen) _bugPanelOpen = false;
                        }),
                        icon: Icon(_settingsOpen ? Icons.close : Icons.tune),
                      ),
                    ],
                  ),
                ),
              if (_host.cellNavigation && !_panelsHidden)
                Positioned(
                  key: const ValueKey('cell-nav-layer'),
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(child: _buildCellNavBar()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(FeatureSpec spec) {
    return Container(
      key: const Key('status-card'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.title,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            _host.status,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (_showFps)
            Text(
              _host.fpsLabel,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCellNavBar() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('cell-turn-left'),
              tooltip: 'Повернуть влево',
              onPressed: () => _host.stepCamera(AnimationType.turnLeft),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              key: const Key('cell-forward'),
              tooltip: 'Шаг вперёд',
              onPressed: () => _host.stepCamera(AnimationType.stepForward),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              key: const Key('cell-backward'),
              tooltip: 'Шаг назад',
              onPressed: () => _host.stepCamera(AnimationType.stepBackward),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              key: const Key('cell-turn-right'),
              tooltip: 'Повернуть вправо',
              onPressed: () => _host.stepCamera(AnimationType.turnRight),
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
      ),
    );
  }
}
