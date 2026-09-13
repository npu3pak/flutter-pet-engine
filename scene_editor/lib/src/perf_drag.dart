import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

import 'state/app_state.dart';

/// ВРЕМЕННЫЙ замер производительности драга (этап 0 перф-прохода).
///
/// Включается `--dart-define=pet.perf.drag=true`: открывает `projects/Pet`,
/// модель `model_2`, и для каждого вида объекта (куб, вставка, CSG, спрайт,
/// glTF) шлёт настоящие pointer-события и тянет ось X гизмо 60 шагов.
/// Печатает sync (сам обработчик) и frame (до конца кадра) p50/p95. Строки
/// `renderer: rebuild ... (Nms)` в общем логе дают стоимость пересборки.
const bool kPerfDragEnabled = bool.fromEnvironment('pet.perf.drag');

const String _projectPath = '../projects/Pet';
const String _modelId = 'model_2';
const List<String> _ids = [
  'obj_6', // куб (стена)
  'obj_13', // вставка модели (кресло)
  'csg_1', // CSG-результат
  'obj_4', // спрайт
  'obj_14', // glTF (кот)
];

Future<void> runDragPerf(AppState app) async {
  // Дать приложению подняться и открыть окно.
  await Future<void>.delayed(const Duration(milliseconds: 800));
  debugPrint('PERF: открываю $_projectPath/$_modelId');
  final ok = await app.openProject(_projectPath);
  if (!ok) {
    debugPrint('PERF: проект не открылся');
    exit(1);
  }
  app.selectModel(_modelId);
  await _frames(30);

  final model = app.currentModel;
  if (model == null) {
    debugPrint('PERF: модель не загрузилась');
    exit(1);
  }

  // Хвосты при пересоздании вьюпорта: «Ресурсы» → «Композиция» → смена
  // модели. Старый EditorScene не должен оставлять свои оверлеи.
  await _capture('remount_before');
  await _tapText('Ресурсы');
  await _frames(20);
  await _tapText('Композиция');
  await _frames(20);
  app.selectModel('model_1');
  await _frames(20);
  await _capture('remount_after');
  app.selectModel(_modelId);
  await _frames(20);

  for (final id in _ids) {
    if (model.objectById(id) == null) continue;
    // Пауза больше окна двойного клика, чтобы клик не считался фокусом.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _benchDrag(app, id);
  }

  debugPrint('PERF: готово');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  exit(0);
}

Future<void> _benchDrag(AppState app, String id) async {
  final controller = app.controller;
  final model = app.currentModel!;
  final object = model.objectById(id)!;
  app.selectObject(id);
  await _frames(3);

  final gizmo =
      controller.gizmos.firstWhere((g) => g.mode == GizmoMode.translate);
  final anchorScreen = controller.worldToScreen(gizmo.anchor);
  final tipScreen = controller.worldToScreen(
    gizmo.anchor + gizmoAxisDirection(GizmoAxis.x),
  );
  if (anchorScreen == null || tipScreen == null) {
    debugPrint('PERF $id: гизмо за кадром — пропуск');
    return;
  }
  final dir = tipScreen - anchorScreen;
  if (dir.distance < 1e-6) {
    debugPrint('PERF $id: ось вырождена — пропуск');
    return;
  }
  final axisScreen = dir / dir.distance;
  // Берём точку недалеко от якоря вдоль оси: экранная длина ручки зависит от
  // ракурса, а допуск попадания — 12 px. 10 px вдоль оси надёжно попадает.
  final handle = anchorScreen + axisScreen * 10.0;

  final box = _viewportBox();
  if (box == null) {
    debugPrint('PERF $id: вьюпорт не найден');
    return;
  }
  final origin = box.localToGlobal(Offset.zero);

  // Для CSG документ двигает операнды — сдвиг меряем по первому из них.
  final moved = model.moveExpansion({id});
  final subject = moved.isEmpty ? object : moved.first;
  final x0 = subject.x;
  await _capture('before_$id');
  debugPrint('PERF-BEGIN $id');
  debugPrint('PERF $id: selectedIds=${app.selectedIds}');
  final binding = GestureBinding.instance;
  const pointer = 7;
  binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: origin + handle,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    ),
  );
  await _frames(1);
  debugPrint('PERF $id: dragging=${gizmo.dragging}');
  if (!gizmo.dragging) {
    debugPrint('PERF $id: драг не начался');
    binding.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: origin + handle),
    );
    return;
  }

  final syncSamples = <double>[];
  final frameSamples = <double>[];
  const steps = 60;
  var position = origin + handle;
  for (var i = 0; i < steps; i++) {
    final next = origin + handle + axisScreen * (i + 1.0);
    final delta = next - position;
    position = next;
    final sw = Stopwatch()..start();
    binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: position,
        delta: delta,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      ),
    );
    syncSamples.add(sw.elapsedMicroseconds / 1000);
    sw.reset();
    await WidgetsBinding.instance.endOfFrame;
    frameSamples.add(sw.elapsedMicroseconds / 1000);
  }

  binding.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: position),
  );
  await _frames(2);
  await _capture('after_$id');

  debugPrint(
    'PERF $id: сдвиг x=${(subject.x - x0).toStringAsFixed(3)} '
    'sync p50=${_p50(syncSamples).toStringAsFixed(2)} '
    'p95=${_p95(syncSamples).toStringAsFixed(2)} '
    'frame p50=${_p50(frameSamples).toStringAsFixed(2)}',
  );
  debugPrint('PERF-END $id');

  app.selectObject(null);
  await _frames(2);
}

RenderBox? _viewportBox() {
  RenderBox? walk(Element element) {
    if (element is StatefulElement && element.widget is SceneViewport) {
      return element.renderObject as RenderBox?;
    }
    RenderBox? found;
    element.visitChildren((child) {
      found ??= walk(child);
    });
    return found;
  }

  final root = WidgetsBinding.instance.rootElement;
  return root == null ? null : walk(root);
}

/// Снимок вьюпорта в `temp/perf_screenshots` (визуальная проверка переноса).
Future<void> _capture(String name) async {
  SceneViewportState? state;
  void walk(Element element) {
    if (state != null) return;
    if (element is StatefulElement && element.state is SceneViewportState) {
      state = element.state as SceneViewportState;
      return;
    }
    element.visitChildren(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) walk(root);
  if (state == null) return;
  final bytes = await state!.capture();
  if (bytes.isEmpty) return;
  await saveScreenshot(
    Directory('temp/perf_screenshots'),
    name,
    bytes,
    {'model': _modelId},
  );
  debugPrint('PERF снимок: temp/perf_screenshots/$name.png');
}

/// Тап по виджету [Text] с данным текстом настоящими pointer-событиями —
/// переключение вкладок «Ресурсы»/«Композиция» для проверки пересоздания
/// вьюпорта.
Future<void> _tapText(String text) async {
  RenderBox? box;
  void walk(Element element) {
    if (box != null) return;
    final widget = element.widget;
    if (widget is Text && widget.data == text) {
      box = element.renderObject as RenderBox?;
      return;
    }
    element.visitChildren(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) walk(root);
  if (box == null) {
    debugPrint('PERF: текст «$text» не найден');
    return;
  }
  final center = box!.localToGlobal(box!.size.center(Offset.zero));
  final binding = GestureBinding.instance;
  const pointer = 11;
  binding.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: center,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    ),
  );
  binding.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: center,
      kind: PointerDeviceKind.mouse,
    ),
  );
  await _frames(2);
}

double _p50(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

double _p95(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length * 95 / 100).floor().clamp(
        0,
        sorted.length - 1,
      )];
}

Future<void> _frames(int count) async {
  for (var i = 0; i < count; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
}
