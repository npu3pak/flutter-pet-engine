import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'features/level_common.dart';
import 'paths.dart';

/// Результат одной стресс-проверки.
class StressResult {
  const StressResult({
    required this.size,
    required this.buildMs,
    required this.bakeMs,
    required this.elements,
    required this.mergedMeshes,
    required this.batchMeshes,
    required this.separateNodes,
    required this.vertices,
    required this.triangles,
    required this.fps,
    required this.at,
  });

  final int size;
  final int buildMs;
  final int bakeMs;
  final int elements;
  final int mergedMeshes;
  final int batchMeshes;
  final int separateNodes;
  final int vertices;
  final int triangles;
  final double fps;
  final DateTime at;

  int get cells => size * size;
}

/// Запускает стресс-проверку (подставляется в тестах).
typedef StressRunner = Future<StressResult> Function(int size);

/// Последний результат сессии — для оценки времени следующего запуска.
StressResult? lastStressResult;

/// Выполняет сборку и запекание стресс-уровня на реальной сцене.
Future<StressResult> runStressLevel(
  SceneController controller,
  int size,
) async {
  final buildSw = Stopwatch()..start();
  final model = buildStressLevel(rows: size, cols: size);
  buildSw.stop();
  final result = await controller.loadLevel(
    model,
    options: const LevelBakeOptions(collectStats: true),
  );
  final baked = result.baked;
  if (baked == null) {
    throw StateError(
      result.errors.isEmpty ? 'уровень не запечён' : result.errors.join('; '),
    );
  }
  final stats = baked.stats;
  return StressResult(
    size: size,
    buildMs: buildSw.elapsedMilliseconds,
    bakeMs: baked.buildTime.inMilliseconds,
    elements: stats.elements,
    mergedMeshes: stats.mergedMeshes,
    batchMeshes: stats.batchMeshes,
    separateNodes: stats.separateNodes,
    vertices: stats.vertices,
    triangles: stats.triangles,
    fps: 0,
    at: DateTime.now(),
  );
}

/// Запись замеров в `docs/perf_journal.md`.
abstract final class PerfJournal {
  /// Дописывает секцию с результатом; возвращает null при успехе и текст
  /// ошибки, если файл недоступен. Запись синхронная: файл небольшой, а
  /// асинхронная запись не завершилась бы во время блокирующего запекания.
  static String? appendStress(File file, StressResult result) {
    try {
      final existing = file.existsSync()
          ? file.readAsStringSync()
          : '# Perf-журнал\n';
      final buffer = StringBuffer(existing.trimRight())
        ..writeln()
        ..writeln()
        ..writeln()
        ..write(stressSection(result));
      file.writeAsStringSync(buffer.toString(), flush: true);
      return null;
    } on FileSystemException catch (e) {
      return 'Не удалось записать журнал: ${e.message}';
    } on UnsupportedError catch (e) {
      return 'Не удалось записать журнал: $e';
    }
  }

  static String stressSection(StressResult result) {
    final date =
        '${result.at.day.toString().padLeft(2, '0')}.${result.at.month.toString().padLeft(2, '0')}.${result.at.year}';
    return '## Стресс уровневого слоя из приложения-примера ($date)\n'
        '\n'
        'Стенд `demo`, macOS debug (Impeller), '
        'размер ${result.size}×${result.size} (${result.cells} клеток).\n'
        '\n'
        '| Метрика | Значение |\n'
        '|---|---|\n'
        '| Сборка `ConstructionModel` (BuildOps) | ${result.buildMs} мс |\n'
        '| Запекание `LevelBaker.bake` | ${result.bakeMs} мс |\n'
        '| Элементов | ${result.elements} |\n'
        '| Слитых мешей (merge) | ${result.mergedMeshes} |\n'
        '| Пакетных мешей (batch) | ${result.batchMeshes} |\n'
        '| Отдельных узлов | ${result.separateNodes} |\n'
        '| Вершин / треугольников | ${result.vertices} / ${result.triangles} |\n'
        '| FPS (macOS) | ${result.fps > 0 ? result.fps.toStringAsFixed(1) : '—'} |\n';
  }
}

/// Экран стресс-проверки: размер уровня, предупреждение, запуск и результаты.
class StressScreen extends StatefulWidget {
  const StressScreen({
    super.key,
    required this.paths,
    required this.initialSize,
    required this.runner,
    required this.fpsLabel,
    required this.onBack,
    this.autoRun = false,
  });

  final AppPaths paths;
  final int initialSize;
  final StressRunner runner;
  final String Function() fpsLabel;
  final VoidCallback onBack;
  final bool autoRun;

  @override
  State<StressScreen> createState() => _StressScreenState();
}

class _StressScreenState extends State<StressScreen> {
  late int _size;
  bool _running = false;
  StressResult? _result;
  String? _error;
  String? _journalError;

  @override
  void initState() {
    super.initState();
    _size = widget.initialSize.clamp(10, 100);
    if (widget.autoRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  double get _estimateMs {
    final last = lastStressResult;
    if (last == null) return 0;
    final scale = (_size * _size) / (last.size * last.size);
    return last.bakeMs * scale;
  }

  double _parseFps() {
    final match = RegExp(r'([\d.]+) FPS').firstMatch(widget.fpsLabel());
    return match == null ? 0 : (double.tryParse(match.group(1)!) ?? 0);
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _journalError = null;
    });
    try {
      final result = await widget.runner(_size);
      final withFps = StressResult(
        size: result.size,
        buildMs: result.buildMs,
        bakeMs: result.bakeMs,
        elements: result.elements,
        mergedMeshes: result.mergedMeshes,
        batchMeshes: result.batchMeshes,
        separateNodes: result.separateNodes,
        vertices: result.vertices,
        triangles: result.triangles,
        fps: _parseFps(),
        at: result.at,
      );
      lastStressResult = withFps;
      final journalError = PerfJournal.appendStress(
        widget.paths.perfJournalFile,
        withFps,
      );
      if (!mounted) return;
      setState(() {
        _result = withFps;
        _journalError = journalError;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Стресс-проверка не выполнена: $e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Стресс-проверка уровневого слоя',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('stress-back'),
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Назад'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Сборка и запекание выполняются сразу в потоке интерфейса: окно '
              'на это время перестаёт отвечать. Для 100×100 это около '
              'двадцати секунд.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const Divider(height: 24),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Сторона сетки: $_size',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('stress-size'),
                    value: _size.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 90,
                    label: '$_size',
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _size = v.round()),
                  ),
                ),
              ],
            ),
            Text(
              'клеток: ${_size * _size}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              _estimateMs > 0
                  ? 'Оценка запекания по последнему измерению: '
                        '${_estimateMs.toStringAsFixed(0)} мс'
                  : 'Оценка появится после первого запуска.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('stress-run'),
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Идёт проверка…' : 'Запустить'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('stress-error'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            if (_result != null) ...[
              const Divider(height: 24),
              const Text(
                'Результаты',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _metric('Размер уровня', '${_result!.size}×${_result!.size}'),
              _metric('Клеток', '${_result!.cells}'),
              _metric('Сборка ConstructionModel', '${_result!.buildMs} мс'),
              _metric('Запекание LevelBaker.bake', '${_result!.bakeMs} мс'),
              _metric('Элементов', '${_result!.elements}'),
              _metric('Слитых мешей (merge)', '${_result!.mergedMeshes}'),
              _metric('Пакетных мешей (batch)', '${_result!.batchMeshes}'),
              _metric('Отдельных узлов', '${_result!.separateNodes}'),
              _metric(
                'Вершин / треугольников',
                '${_result!.vertices} / ${_result!.triangles}',
              ),
              _metric(
                'Частота кадров',
                _result!.fps > 0
                    ? '${_result!.fps.toStringAsFixed(1)} FPS'
                    : '—',
              ),
              if (_journalError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _journalError!,
                    key: const Key('stress-journal-error'),
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Запись добавлена в docs/perf_journal.md.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
