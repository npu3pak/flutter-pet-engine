// Сводка perf-сессии, снятой scripts/perf/capture.sh.
//
// Запуск из корня репозитория:
//   fvm dart run scripts/perf/report.dart <tag>
import 'dart:io';
import 'dart:math' as math;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('использование: dart run scripts/perf/report.dart <tag>');
    exit(1);
  }
  final dir = Directory('temp/perf/${args.first}');
  if (!dir.existsSync()) {
    stderr.writeln('Нет каталога ${dir.path} — сначала capture.sh');
    exit(1);
  }
  _reportFrames(File('${dir.path}/logcat.log'));
  _reportMemory(File('${dir.path}/meminfo.log'));
  _reportThermal(File('${dir.path}/thermal.log'));
}

class _Window {
  _Window(this.phase, this.t, this.at, this.fps, this.frames, this.uiAvg,
      this.rasterAvg, this.spanMax, this.jank, this.rss);
  final String phase;
  final double t;
  final double at;
  final double fps;
  final int frames;
  final double uiAvg;
  final double rasterAvg;
  final double spanMax;
  final double jank;
  final double rss;
}

class _FreqSample {
  _FreqSample(this.uptime, this.clock, this.max, this.busy, this.tmu);
  final double uptime;
  final double clock;
  final double max;
  final double busy;
  final double tmu;
}

double _field(String line, String key) {
  final m = RegExp('$key=([0-9.]+)').firstMatch(line);
  return m == null ? double.nan : double.parse(m.group(1)!);
}

String _phaseField(String line) {
  final m = RegExp(r'phase=(\S+)').firstMatch(line);
  return m == null ? '?' : m.group(1)!;
}

/// Logcat `-v monotonic` prefix: seconds since boot.
double _monotonicAt(String line) {
  final m = RegExp(r'^\s*([0-9]+\.[0-9]+)\s').firstMatch(line);
  return m == null ? double.nan : double.parse(m.group(1)!);
}

void _reportFrames(File file) {
  if (!file.existsSync()) return;
  final windows = <_Window>[];
  var sessionStart = '';
  var meters = 0;
  var phase = 'boot';
  final infos = <String>[];
  final engine = <String>[];
  final passMs = <String, List<double>>{};
  for (final line in file.readAsLinesSync()) {
    if (line.contains('[perf]') && line.contains('session-start')) {
      sessionStart = line.substring(line.indexOf('[perf]'));
    } else if (line.contains('[perf]') && line.contains('phase=')) {
      phase = _phaseField(line);
    } else if (line.contains('[perf]') && line.contains('fps=')) {
      final frames = _field(line, 'frames');
      windows.add(_Window(
        phase,
        _field(line, 't'),
        _monotonicAt(line),
        _field(line, 'fps'),
        frames.isNaN ? 0 : frames.round(),
        _field(line, 'ui_avg'),
        _field(line, 'raster_avg'),
        _field(line, 'span_max'),
        _field(line, 'jank'),
        _field(line, 'rss_mb'),
      ));
    } else if (line.contains('[perf]') && line.contains('meter=')) {
      meters++;
    } else if (line.contains('[perf]') && line.contains('info:')) {
      infos.add(line.substring(line.indexOf('info:')));
    } else if (line.contains('[perf-pass]')) {
      for (final m in RegExp(r'(\w+)=([0-9.]+)')
          .allMatches(line.substring(line.indexOf('[perf-pass]')))) {
        final key = m.group(1)!;
        if (key == 'frames') continue;
        passMs.putIfAbsent(key, () => []).add(double.parse(m.group(2)!));
      }
    } else if (line.contains('[pet_engine')) {
      engine.add(line.substring(line.indexOf('[pet_engine')));
    }
  }
  print('── Кадры ────────────────────────────────────────────────');
  if (sessionStart.isNotEmpty) print(sessionStart);
  for (final info in infos) {
    print(info);
  }
  if (windows.isEmpty) {
    print('нет окон [perf] — логгер был включён? (--dart-define=perf.log=true)');
    return;
  }
  final fps = [for (final w in windows) w.fps]..sort();
  final totalFrames = windows.fold<int>(0, (sum, w) => sum + w.frames);
  final duration = windows.last.t - windows.first.t;
  print('окон ${windows.length}, кадров $totalFrames, '
      'длительность ${duration.toStringAsFixed(1)}s, meter-строк $meters');
  print('fps: min ${fps.first.toStringAsFixed(1)} · '
      'p50 ${_pct(fps, 0.5).toStringAsFixed(1)} · '
      'avg ${_avg(fps).toStringAsFixed(1)} · '
      'p95 ${_pct(fps, 0.95).toStringAsFixed(1)} · '
      'max ${fps.last.toStringAsFixed(1)}');
  final rss = [for (final w in windows) w.rss].where((v) => !v.isNaN).toList();
  if (rss.length >= 2) {
    print('rss: ${rss.first.toStringAsFixed(1)} → ${rss.last.toStringAsFixed(1)} MB '
        '(Δ ${(rss.last - rss.first).toStringAsFixed(1)})');
  }
  print('');
  print('по фазам:');
  print('  фаза                          окон  кадр     fps   ui_avg  rast_avg  jank');
  final byPhase = <String, List<_Window>>{};
  for (final w in windows) {
    byPhase.putIfAbsent(w.phase, () => []).add(w);
  }
  for (final entry in byPhase.entries) {
    final ws = entry.value;
    final phaseFps = [for (final w in ws) w.fps];
    print('  ${entry.key.padRight(28)}'
        '${ws.length.toString().padLeft(4)}'
        '${ws.fold<int>(0, (s, w) => s + w.frames).toString().padLeft(6)}'
        '${_avg(phaseFps).toStringAsFixed(1).padLeft(8)}'
        '${_avg([for (final w in ws) w.uiAvg]).toStringAsFixed(1).padLeft(8)}'
        '${_avg([for (final w in ws) w.rasterAvg]).toStringAsFixed(1).padLeft(10)}'
        '${_avg([for (final w in ws) w.jank]).toStringAsFixed(0).padLeft(6)}%');
  }
  print('');
  if (passMs.isNotEmpty) {
    print('пассы рендера (avg ms/кадр за окно 2s):');
    final entries = passMs.entries.toList()
      ..sort((a, b) => _avg(b.value).compareTo(_avg(a.value)));
    for (final e in entries) {
      print('  ${e.key.padRight(24)}'
          '${_avg(e.value).toStringAsFixed(2).padLeft(8)}'
          '  max ${e.value.reduce(math.max).toStringAsFixed(1)}');
    }
  }
  print('');
  _reportFrequency(windows, File('${file.parent.path}/thermal.log'));
  print('худшие окна (fps):');
  final worst = [...windows]..sort((a, b) => a.fps.compareTo(b.fps));
  for (final w in worst.take(8)) {
    print('  t=${w.t.toStringAsFixed(1).padLeft(6)}s  '
        'fps=${w.fps.toStringAsFixed(1).padLeft(5)}  '
        'ui=${w.uiAvg.toStringAsFixed(2).padLeft(5)}ms  '
        'raster=${w.rasterAvg.toStringAsFixed(2).padLeft(6)}ms  '
        'span_max=${w.spanMax.toStringAsFixed(1).padLeft(6)}ms  '
        'jank=${w.jank.toStringAsFixed(0).padLeft(3)}%  ${w.phase}');
  }
  if (engine.isNotEmpty) {
    print('');
    print('движок (последние ${math.min(8, engine.length)} из ${engine.length}):');
    for (final line in engine.sublist(math.max(0, engine.length - 8))) {
      print('  $line');
    }
  }
}

double _avg(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _pct(List<double> sorted, double p) => sorted.isEmpty
    ? 0
    : sorted[(sorted.length * p).floor().clamp(0, sorted.length - 1)];

List<_FreqSample> _parseFreqSamples(File file) {
  if (!file.existsSync()) return const [];
  final samples = <_FreqSample>[];
  for (final line in file.readAsLinesSync()) {
    final up = _field(line, 'uptime');
    if (up.isNaN) continue;
    var clock = _field(line, 'gpu_clock');
    if (clock.isNaN) clock = _field(line, 'gpu');
    samples.add(_FreqSample(
      up,
      clock,
      _field(line, 'gpu_max'),
      _field(line, 'gpu_busy'),
      _field(line, 'gpu_tmu'),
    ));
  }
  return samples;
}

_FreqSample? _nearestSample(List<_FreqSample> samples, double at) {
  if (samples.isEmpty || at.isNaN) return null;
  _FreqSample? best;
  var bestD = double.infinity;
  for (final s in samples) {
    final d = (s.uptime - at).abs();
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return bestD <= 10 ? best : null;
}

void _reportFrequency(List<_Window> windows, File file) {
  final samples = _parseFreqSamples(file);
  if (samples.isEmpty) return;
  print('── Частоты GPU ─────────────────────────────────────────');
  final clocks = [
    for (final s in samples)
      if (!s.clock.isNaN && s.clock > 0) s.clock,
  ];
  final maxes = [for (final s in samples) if (!s.max.isNaN) s.max];
  final busy = [for (final s in samples) if (!s.busy.isNaN) s.busy];
  final tmus = [for (final s in samples) if (!s.tmu.isNaN) s.tmu];
  if (clocks.isNotEmpty) {
    print('clock: min ${(clocks.reduce(math.min) / 1000).round()} · '
        'avg ${(_avg(clocks) / 1000).round()} · '
        'max ${(clocks.reduce(math.max) / 1000).round()} MHz');
  }
  if (maxes.isNotEmpty) {
    print('cap (gpu_max): min ${(maxes.reduce(math.min) / 1000).round()} · '
        'max ${(maxes.reduce(math.max) / 1000).round()} MHz');
  }
  if (busy.isNotEmpty) {
    print('gpu_busy: avg ${_avg(busy).toStringAsFixed(0)}% · '
        'max ${busy.reduce(math.max).toStringAsFixed(0)}%');
  }
  if (tmus.isNotEmpty) {
    print('gpu_tmu: ${tmus.first.toStringAsFixed(0)} → '
        '${tmus.last.toStringAsFixed(0)} °C · max ${tmus.reduce(math.max).toStringAsFixed(0)}');
  }
  if (windows.isEmpty) return;

  final buckets = <int, List<_Window>>{};
  final samplesByWindow = <_Window, _FreqSample>{};
  for (final w in windows) {
    final s = _nearestSample(samples, w.at);
    if (s == null) continue;
    samplesByWindow[w] = s;
    final ref = s.max.isNaN || s.max <= 0 ? s.clock : s.max;
    if (ref.isNaN || ref <= 0) continue;
    final bucket = (ref / 50000).round() * 50;
    buckets.putIfAbsent(bucket, () => []).add(w);
  }
  if (buckets.isEmpty) return;
  print('fps по потолку частоты (gpu_max, МГц):');
  final sortedKeys = buckets.keys.toList()..sort();
  for (final k in sortedKeys) {
    final ws = buckets[k]!;
    final ss = [
      for (final w in ws)
        if (samplesByWindow[w] != null) samplesByWindow[w]!,
    ];
    final tmu = [for (final s in ss) if (!s.tmu.isNaN) s.tmu];
    final b = [for (final s in ss) if (!s.busy.isNaN) s.busy];
    print('  ${k.toString().padLeft(4)} МГц: окон ${ws.length.toString().padLeft(3)}'
        ' · fps ${_avg([for (final w in ws) w.fps]).toStringAsFixed(1).padLeft(5)}'
        ' · ui ${_avg([for (final w in ws) w.uiAvg]).toStringAsFixed(1).padLeft(5)}ms'
        ' · raster ${_avg([for (final w in ws) w.rasterAvg]).toStringAsFixed(1).padLeft(5)}ms'
        ' · tmu ${tmu.isEmpty ? '—' : _avg(tmu).toStringAsFixed(0)}'
        ' · busy ${b.isEmpty ? '—' : '${_avg(b).toStringAsFixed(0)}%'}');
  }
  print('сегменты (по смене потолка):');
  int? current;
  var startT = 0.0;
  var segFps = <double>[];
  var segTmu = <double>[];
  void flush(double endT) {
    if (current == null || segFps.isEmpty) return;
    print('  ${startT.toStringAsFixed(0).padLeft(4)}–'
        '${endT.toStringAsFixed(0).padLeft(4)}s  cap=${current.toString().padLeft(4)}'
        '  fps ${_avg(segFps).toStringAsFixed(1).padLeft(5)}'
        '${segTmu.isEmpty ? '' : '  tmu ${_avg(segTmu).toStringAsFixed(0)}'}');
  }

  for (final w in windows) {
    final s = samplesByWindow[w];
    final ref = s == null || s.max.isNaN || s.max <= 0 ? null : s.max;
    final bucket = ref == null ? null : (ref / 50000).round() * 50;
    if (bucket != current) {
      flush(w.t);
      current = bucket;
      startT = w.t;
      segFps = [];
      segTmu = [];
    }
    segFps.add(w.fps);
    if (s != null && !s.tmu.isNaN) segTmu.add(s.tmu);
  }
  flush(windows.last.t);
}

void _reportMemory(File file) {
  if (!file.existsSync()) return;
  final samples = <String, Map<String, int>>{};
  String? current;
  for (final line in file.readAsLinesSync()) {
    final marker = RegExp(r'^=== (.+) ===$').firstMatch(line);
    if (marker != null) {
      current = marker.group(1)!;
      samples[current] = {};
      continue;
    }
    if (current == null) continue;
    final m = RegExp(
            r'^\s*(Native Heap|EGL mtrack|GL mtrack|Graphics:|TOTAL PSS:)\s+(\d+)')
        .firstMatch(line);
    if (m != null) {
      samples[current]![m.group(1)!] = int.parse(m.group(2)!);
    }
  }
  print('');
  print('── Память (PSS, MB) ────────────────────────────────────');
  if (samples.isEmpty) {
    print('нет сэмплов');
    return;
  }
  const labels = ['Native Heap', 'EGL mtrack', 'GL mtrack', 'Graphics:'];
  final header = StringBuffer('  время              ');
  for (final l in labels) {
    header.write(l.replaceAll(':', '').padLeft(11));
  }
  header.write('TOTAL PSS'.padLeft(11));
  print(header);
  for (final entry in samples.entries) {
    final b = StringBuffer('  ${entry.key.substring(11, 19)}          ');
    for (final l in labels) {
      b.write(_mb(entry.value[l]).padLeft(11));
    }
    b.write(_mb(entry.value['TOTAL PSS:']).padLeft(11));
    print(b);
  }
  final first = samples.values.first;
  final last = samples.values.last;
  print('  Δ TOTAL PSS: ${(last['TOTAL PSS:']! - first['TOTAL PSS:']!) / 1024} MB'
      ' · Δ GL: ${(last['GL mtrack']! - first['GL mtrack']!) / 1024} MB'
      ' · Δ Native: ${(last['Native Heap']! - first['Native Heap']!) / 1024} MB');
}

String _mb(int? kb) => kb == null ? '—' : (kb / 1024).toStringAsFixed(0);

void _reportThermal(File file) {
  if (!file.existsSync()) return;
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
  print('');
  print('── Температура ─────────────────────────────────────────');
  final batteries = <double>[];
  final zones = <double>[];
  final cpus = <double>[];
  for (final line in lines) {
    final b = RegExp(r'battery=(\d+)').firstMatch(line);
    if (b != null) batteries.add(int.parse(b.group(1)!) / 10);
    final c = RegExp(r'cpu7=(\d+)').firstMatch(line);
    if (c != null) cpus.add(int.parse(c.group(1)!) / 1000);
    final z = RegExp(r'zones=(.*)$').firstMatch(line);
    if (z != null) {
      for (final token in z.group(1)!.trim().split(RegExp(r'\s+'))) {
        final v = double.tryParse(token);
        if (v != null && v > 0) zones.add(v > 1000 ? v / 1000 : v);
      }
    }
  }
  if (batteries.isEmpty && zones.isEmpty && cpus.isEmpty) {
    print('нет сэмплов');
    return;
  }
  if (batteries.isNotEmpty) {
    print('батарея: ${batteries.first.toStringAsFixed(1)} → '
        '${batteries.last.toStringAsFixed(1)} °C, max ${batteries.reduce(math.max).toStringAsFixed(1)}');
  }
  if (zones.isNotEmpty) {
    print('thermal zones: max ${zones.reduce(math.max).toStringAsFixed(1)} °C');
  }
  if (cpus.isNotEmpty) {
    print('CPU7: min ${cpus.reduce(math.min).toStringAsFixed(0)} · '
        'max ${cpus.reduce(math.max).toStringAsFixed(0)} MHz');
  }
}
