import 'package:flutter/material.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'src/app_info.dart';
import 'src/app_shell.dart';
import 'src/features/feature_registry.dart';
import 'src/paths.dart';
import 'src/perf/frame_stats_logger.dart';
import 'src/scene_host.dart';
import 'src/screenshot_saver.dart';
import 'src/stress_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeEngine();
  FrameStatsLogger.start();
  final paths = AppPaths.resolve();
  runApp(
    DemoApp(
      paths: paths,
      info: AppInfo.collect(paths: paths),
    ),
  );
}

/// Приложение-пример движка `pet_engine_v2`: слева каталог возможностей, в
/// центре рабочая область сцен, справа настройки сцены.
class DemoApp extends StatelessWidget {
  const DemoApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFC),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AppShell(
        paths: paths,
        info: info,
        host: host,
        features: features,
        stressRunner: stressRunner,
        screenshotSaver: screenshotSaver,
        screenshotCapture: screenshotCapture,
      ),
    );
  }
}
