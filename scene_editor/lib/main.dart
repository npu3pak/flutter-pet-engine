import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'src/app_info.dart';
import 'src/deeplink.dart';
import 'src/paths.dart';
import 'src/perf_drag.dart';
import 'src/scene/editor_scene.dart' show EditorMode;
import 'src/screenshot_saver.dart';
import 'src/state/app_state.dart';
import 'src/ui/main_screen.dart';
import 'src/ui/start_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeEngine();
  await configureFilePicker();
  final paths = AppPaths.resolve();
  runApp(
    SceneEditorApp(
      paths: paths,
      info: AppInfo.collect(paths: paths),
    ),
  );
}

/// Отключает проверку entitlements плагина `file_picker` на macOS.
///
/// Приложение собрано без песочницы, поэтому `file_picker` 11 отказывает в
/// выборе папки/файла (`ENTITLEMENT_NOT_FOUND`): его проверка рассчитана на
/// sandbox-приложения с `files.user-selected.read-*`. Штатный способ для
/// приложений без песочницы — [FilePicker.skipEntitlementsChecks].
Future<void> configureFilePicker() async {
  if (Platform.isMacOS) {
    await FilePicker.skipEntitlementsChecks();
  }
}

/// Редактор сцен pet_engine_v2: документ с отменой действий, панели,
/// трёхмерный вьюпорт с выделением и гизмо, ресурсы и разметка.
class SceneEditorApp extends StatefulWidget {
  const SceneEditorApp({
    super.key,
    required this.paths,
    required this.info,
    this.screenshotSaver,
    this.screenshotCapture,
  });

  final AppPaths paths;
  final AppInfo info;

  /// Сохранение снимков; в тестах подменяется без записи на диск.
  final ScreenshotSaver? screenshotSaver;

  /// Захват кадра; в тестах подменяется без видеоконтура.
  final ScreenshotCapture? screenshotCapture;

  @override
  State<SceneEditorApp> createState() => SceneEditorAppState();
}

class SceneEditorAppState extends State<SceneEditorApp> {
  final AppState app = AppState();
  final GlobalKey _windowKey = GlobalKey();
  late final DeeplinkController _deeplink;

  AppPaths get paths => widget.paths;
  AppInfo get info => widget.info;

  @override
  void initState() {
    super.initState();
    _deeplink = DeeplinkController(onLog: _logDeeplink)
      ..onCommand = _handleDeeplink;
    _deeplink.start();
    if (kPerfDragEnabled) {
      unawaited(runDragPerf(app));
    }
  }

  @override
  void dispose() {
    _deeplink.dispose();
    app.dispose();
    super.dispose();
  }

  void _logDeeplink(String message) {
    debugPrint(message);
    try {
      paths.deeplinkLogFile.writeAsStringSync(
        '$message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Журнал диплинков не критичен для работы приложения.
    }
  }

  Future<void> _handleDeeplink(DeeplinkCommand command) async {
    switch (command) {
      case OpenModelCommand(
          :final projectPath,
          :final modelId,
          :final select,
          :final mode,
        ):
        await _openModel(projectPath, modelId, select: select, mode: mode);
      case ScreenshotCommand():
        await _capture(command, openModel: null);
      case CaptureCommand(
          :final projectPath,
          :final modelId,
          :final select,
          :final mode,
        ):
        await _capture(
          command,
          openModel: (projectPath, modelId, select, mode),
        );
      case OpenScreenCommand(:final screen):
        if (screen == 'start') {
          app.closeProject();
        }
      case SettingsCommand(:final values):
        _applySettings(values);
    }
  }

  void _applySettings(Map<String, String> values) {
    bool flag(String key) => values[key] == '1' || values[key] == 'true';
    if (values.containsKey('gizmos')) app.setLightingGizmos(flag('gizmos'));
    if (values.containsKey('ssao')) app.setLightingSsao(flag('ssao'));
    if (values.containsKey('shadows')) app.setLightingShadows(flag('shadows'));
    if (values.containsKey('wireframe')) app.setWireframe(flag('wireframe'));
    if (values.containsKey('rotate')) app.setRotateMode(flag('rotate'));
    final ambient = double.tryParse(values['ambient'] ?? '');
    if (ambient != null) app.setLightingAmbient(ambient);
  }

  Future<void> _openModel(
    String? projectPath,
    String? modelId, {
    String? select,
    String? mode,
  }) async {
    if (projectPath == null) return;
    // Диплинк — инструмент визуальных проверок: проект перечитывается с
    // диска при каждом вызове (несохранённые правки теряются).
    final ok = await app.openProject(projectPath);
    if (!ok) return;
    if (modelId != null && app.currentModelId != modelId) {
      app.selectModel(modelId);
    }
    if (mode != null) {
      for (final value in EditorMode.values) {
        if (value.name == mode) app.setMode(value);
      }
    }
    if (select != null) {
      // The selection kind follows the mode: light sources and metas are
      // separate selections from the object one.
      switch (mode) {
        case 'lighting':
          app.selectLight(select);
        case 'markup':
          app.selectMeta(select);
        default:
          app.selectObject(select);
      }
    }
  }

  Future<void> _capture(
    DeeplinkCommand command, {
    required (String?, String?, String?, String?)? openModel,
  }) async {
    final name = switch (command) {
      ScreenshotCommand(:final name) => name,
      CaptureCommand(:final name) => name,
      _ => null,
    };
    final delayMs = switch (command) {
      ScreenshotCommand(:final delayMs) => delayMs,
      CaptureCommand(:final delayMs) => delayMs,
      _ => kScreenshotDefaultDelayMs,
    };
    final pixelRatio = switch (command) {
      ScreenshotCommand(:final scale) => scale,
      CaptureCommand(:final scale) => scale,
      _ => null,
    };
    if (openModel != null) {
      await _openModel(
        openModel.$1,
        openModel.$2,
        select: openModel.$3,
        mode: openModel.$4,
      );
    }
    // Ждём готовности модели и догрузки текстур.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (app.currentModel == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    await WidgetsBinding.instance.endOfFrame;
    final capture = widget.screenshotCapture ?? _defaultCapture;
    final bytes = await capture(_windowKey, pixelRatio ?? 1.0);
    if (bytes == null || bytes.isEmpty) {
      _logDeeplink('снимок не получен: ${name ?? '—'}');
      return;
    }
    final clean = sanitizeScreenshotName(name ?? 'screenshot');
    final meta = <String, Object?>{
      'app': info.appVersion,
      'engine': info.engineVersion,
      'platform': info.platform,
      'model': app.currentModelId,
    };
    final saver = widget.screenshotSaver ?? _defaultSaver;
    final path = await saver(clean, bytes, meta);
    _logDeeplink('снимок: $path');
  }

  Future<Uint8List?> _defaultCapture(GlobalKey boundaryKey, double pixelRatio) =>
      captureBoundary(boundaryKey, pixelRatio);

  Future<String> _defaultSaver(
    String name,
    Uint8List pngBytes,
    Map<String, Object?> meta,
  ) => writeScreenshotFiles(paths, name, pngBytes, meta);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _windowKey,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          return MaterialApp(
            title: 'Scene Editor',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF7FA7C9),
                brightness: Brightness.dark,
              ),
              scaffoldBackgroundColor: const Color(0xFF20242C),
            ),
            home: app.project == null
                ? ProjectScreen(app: app)
                : MainScreen(app: app),
          );
        },
      ),
    );
  }
}
