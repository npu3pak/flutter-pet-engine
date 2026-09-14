import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/editor_scene.dart';
import '../scene/light_renderer.dart' show kLightBallRadius;
import '../scene/meta_renderer.dart' show kCommentBallRadius;
import '../services/app_log.dart';
import '../services/model3d_store.dart';
import '../services/resource_store.dart';

/// One undoable mutation of the current model.
class _Cmd {
  final String description;
  final String? mergeKey;
  final DateTime time;
  final void Function() apply;
  final void Function() undo;
  _Cmd(this.description, this.apply, this.undo, {this.mergeKey, DateTime? time})
      : time = time ?? DateTime.now();
}

/// The armed face-snap operation (see [AppState.faceSnapMode]).
enum FaceSnapMode {
  /// «Перенести к грани»: the next face click moves the selected object's
  /// anchor to the clicked face's center.
  moveToFace,

  /// «Параллельно грани»: the next face click orients the selected object
  /// parallel to the clicked face.
  parallelToFace,
}

class AppState extends ChangeNotifier {
  AppState() {
    // Догрузки движка (текстуры, glTF) меняют ревизию контроллера — панели
    // должны увидеть новые данные (например, список анимаций модели) без
    // ручного действия. Уведомление откладывается: контроллер может
    // меняться во время сборки кадра.
    controller.addListener(_onControllerChanged);
  }

  /// The engine scene controller of the editor: the document, resources and
  /// the render scene (per-face, no static merging).
  final SceneController controller = SceneController(mergeStatic: false);

  bool _disposed = false;
  bool _controllerNotifyScheduled = false;
  int _lastControllerRevision = -1;

  /// Отложенное обновление интерфейса после изменения сцены движком.
  ///
  /// Будим интерфейс только когда выросла ревизия (догрузка текстур/glTF,
  /// пересборка документа): добавление оверлеев и нод вьюпорта тоже
  /// уведомляет контроллер, и без этого гейта уведомление зациклилось бы.
  void _onControllerChanged() {
    final revision = controller.revision;
    if (_disposed || revision == _lastControllerRevision) return;
    _lastControllerRevision = revision;
    if (_controllerNotifyScheduled) return;
    _controllerNotifyScheduled = true;
    scheduleMicrotask(() {
      _controllerNotifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  ProjectStore? store;

  /// Resources of the currently open project (lazily created).
  ResourceStore? _resources;
  ResourceStore get resources => _resources ??= ResourceStore(store!)
    ..onMutation = _invalidateResources
    ..reload();

  /// The «Модели» catalog (`3d_models/`) of the currently open project
  /// (lazily created; only the Resources tab uses it in v1).
  Model3dStore? _model3d;
  Model3dStore get model3d => _model3d ??= Model3dStore(store!)..reload();
  String? currentModelId;
  EditorMode mode = EditorMode.compose;
  String? selectedObjectId;
  String? selectedFaceKey;

  /// Bridge: any catalog mutation (import/rename/delete from the Resources
  /// tab, or an external disk change picked up by a scan) must reach the 3D
  /// editor — gltf instances re-check the catalog on every rebuild and drop
  /// to their fuchsia cube when the resource vanished.
  void _onModel3dChanged() {
    controller.reloadResources();
    notifyListeners();
  }

  /// Resource files changed on disk (import/rename/delete/apply): drop the
  /// engine's texture caches and rebuild the scene.
  void _invalidateResources() {
    controller.resources?.invalidate();
    controller.rebuild();
    notifyListeners();
  }

  /// Rebuilds the scene and notifies the interface. Every document mutation
  /// goes through here.
  void _touchScene() {
    controller.rebuild();
    notifyListeners();
  }

  /// Texture-mode submode: whole objects or individual faces.
  TexSubmode texSubmode = TexSubmode.objects;

  /// Selected faces in faces mode — keys `'<objectId>:<faceKey>'`.
  final Set<String> selectedFaces = {};

  /// Правка многогранника: объект/грани/вершины. Сбрасывается в
  /// [PolyEditMode.object] при смене объекта и по Esc.
  PolyEditMode polyEditMode = PolyEditMode.object;

  /// Выбранные вершины текущего многогранника (индексы в его сети).
  final Set<int> selectedVertexIndices = {};

  /// Активная (последняя выбранная) вершина — подсвечивается жёлтым.
  int? activeVertexIndex;

  /// Режим добавления вершины: следующий клик по объекту вставит вершину.
  bool polyAddVertexArmed = false;

  /// Multi-selection: all currently selected object ids (always includes
  /// [selectedObjectId], the primary/last-clicked).
  final Set<String> selectedIds = {};

  /// The meta-object selected in the markup mode («Разметка»), if any.
  /// Independent of the object selection — both may coexist.
  String? selectedMetaId;

  /// The light source selected in the lighting mode («Освещение»), if any.
  /// Like the meta selection it is independent of the object selection; the
  /// lighting mode clears the object selection when it becomes active.
  String? selectedLightId;

  /// The named group selected in the objects tree (its members are in
  /// [selectedIds]).
  String? selectedGroupId;

  /// The selected meta-object of the current model, if any.
  ModelMeta? selectedMeta() {
    final model = currentModel;
    final id = selectedMetaId;
    if (model == null || id == null) return null;
    return model.metaById(id);
  }

  void selectMeta(String? id) {
    if (selectedMetaId == id) {
      notifyListeners();
      return;
    }
    selectedMetaId = id;
    notifyListeners();
  }

  /// The selected light source of the current model, if any.
  ModelLight? selectedLight() {
    final model = currentModel;
    final id = selectedLightId;
    if (model == null || id == null) return null;
    return model.lighting.lightById(id);
  }

  void selectLight(String? id) {
    if (selectedLightId == id) {
      notifyListeners();
      return;
    }
    selectedLightId = id;
    notifyListeners();
  }

  /// Virtual cursor (model-local coords).
  double cursorX = 0, cursorY = 0, cursorZ = 0;
  double snapStep = 0.5;

  /// Armed face-snap operation: the next face click in the viewport applies
  /// it to the selected object (see [applyFaceSnap]). Null = no armed
  /// operation. Set by the «Перенести к грани» / «Параллельно грани»
  /// buttons; cleared by a face click, a non-face click, Esc, or a mode/
  /// model switch.
  FaceSnapMode? faceSnapMode;

  /// TopBar toggle: forces the rotate gizmo (the Alt/Option equivalent for
  /// touch devices). The viewport uses `Alt || rotateGizmoMode`.
  bool rotateGizmoMode = false;

  void toggleRotateMode() {
    rotateGizmoMode = !rotateGizmoMode;
    notifyListeners();
  }

  /// Sets the rotate-gizmo mode explicitly (deeplink visual checks).
  void setRotateMode(bool enabled) {
    if (rotateGizmoMode == enabled) return;
    rotateGizmoMode = enabled;
    notifyListeners();
  }

  /// Whether the whole-scene wireframe overlay is on (the top bar toggle).
  bool wireframeEnabled = false;

  static const WireframeStyle _editorWireframe = WireframeStyle(
    color: Color(0xFFE53935),
  );

  /// Turns the whole-scene wireframe overlay on or off.
  void setWireframe(bool enabled) {
    if (wireframeEnabled == enabled) return;
    wireframeEnabled = enabled;
    controller.setWireframe(enabled ? _editorWireframe : null);
    notifyListeners();
  }

  /// Whether [objectId] has its own wireframe overlay.
  bool objectWireframe(String objectId) =>
      controller.objectNode(objectId)?.wireframe != null;

  /// Toggles the wireframe overlay of one document object.
  void setObjectWireframe(String objectId, bool enabled) {
    final node = controller.objectNode(objectId);
    if (node == null) return;
    node.wireframe = enabled ? _editorWireframe : null;
    notifyListeners();
  }

  /// Fly-camera mode (RMB held): the viewport flips this; the bottom hint
  /// bar listens to it to switch its hotkey context.
  final ValueNotifier<bool> flying = ValueNotifier(false);

  static const _undoLimit = 100;

  /// Grows on any structural change (objects, model settings, materials);
  /// the viewport uses it to decide when to rebuild the 3D scene. Mirrors
  /// the engine controller's revision.
  int get sceneRevision => controller.revision;

  final Map<String, List<_Cmd>> _undoStacks = {};
  final Map<String, List<_Cmd>> _redoStacks = {};

  // ── accessors ────────────────────────────────────────────────────────

  ProjectStore? get project => store;

  ModelData? get currentModel {
    final s = store;
    final id = currentModelId;
    if (s == null || id == null) return null;
    return s.models[id];
  }

  ModelObject? selectedObject() {
    final model = currentModel;
    final id = selectedObjectId;
    if (model == null || id == null) return null;
    for (final o in model.objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// All selected objects in model order.
  List<ModelObject> selectedObjects() {
    final model = currentModel;
    if (model == null) return const [];
    return [
      for (final o in model.objects)
        if (selectedIds.contains(o.id)) o,
    ];
  }

  bool isSelected(String id) => selectedIds.contains(id);

  int get selectedCount => selectedIds.length;

  /// Center of the union AABB of all selected objects (model-local). Csg
  /// nodes expand to their primitive leaves (they carry no own geometry);
  /// model instances fold in their resolved content bounds.
  (double, double, double)? groupCenter() {
    final model = currentModel;
    if (model == null) return null;
    final objs = model.moveExpansion(selectedIds);
    if (objs.isEmpty) return null;
    final (minX, minY, minZ, maxX, maxY, maxZ) = unionAabbResolved(
      objs,
      modelOf: (id) => store?.models[id],
    );
    return ((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
  }

  /// The named group selected in the tree, if any.
  ModelGroup? selectedGroup() {
    final model = currentModel;
    final id = selectedGroupId;
    if (model == null || id == null) return null;
    for (final g in model.groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// The group an object belongs to, if any.
  ModelGroup? groupOf(String objId) {
    final model = currentModel;
    if (model == null) return null;
    for (final g in model.groups) {
      if (g.members.contains(objId)) return g;
    }
    return null;
  }

  /// True when any selected object is inside a named group.
  bool get hasGroupedSelection {
    if (selectedGroupId != null) return true;
    for (final id in selectedIds) {
      if (groupOf(id) != null) return true;
    }
    return false;
  }

  /// The group tab shows for multi-selection or a selected named group.
  bool get showGroupTab => selectedCount > 1 || selectedGroupId != null;

  bool get canUndo =>
      (_undoStacks[currentModelId]?.isNotEmpty ?? false) && currentModel != null;
  bool get canRedo =>
      (_redoStacks[currentModelId]?.isNotEmpty ?? false) && currentModel != null;

  // ── project / model management ─────────────────────────────────────────

  /// Opens a project folder; returns false (and keeps the previous state)
  /// when the folder is not a project or cannot be read.
  Future<bool> openProject(String path) async {
    final sw = Stopwatch()..start();
    await controller.open(DirectoryProjectSource(Directory(path)));
    if (controller.status.hasError) {
      logStage('store', 'openProject FAIL $path: ${controller.status.errors}');
      return false;
    }
    // The previous document must not survive the switch: the new project may
    // have no models at all, and the old render scene would stay behind.
    controller.unloadModel();
    currentModelId = null;
    selectedObjectId = null;
    selectedFaceKey = null;
    selectedIds.clear();
    selectedGroupId = null;
    selectedMetaId = null;
    selectedLightId = null;
    faceSnapMode = null;
    final s = controller.project;
    logStage(
      'store',
      'openProject $path models=${s.models.length} '
          'errors=${controller.status.errors.length}',
      ms: sw.elapsedMilliseconds,
    );
    store = s;
    _resources?.dispose();
    _resources = ResourceStore(s)..onMutation = _invalidateResources;
    await _resources!.reload();
    _model3d?.removeListener(_onModel3dChanged);
    _model3d?.dispose();
    _model3d = Model3dStore(s);
    await _model3d!.reload();
    _model3d!.addListener(_onModel3dChanged);
    _undoStacks.clear();
    _redoStacks.clear();
    final savedLast = s.lastModelId;
    currentModelId = (savedLast != null && s.models.containsKey(savedLast))
        ? savedLast
        : (s.modelIds.isEmpty ? null : s.modelIds.first);
    if (currentModelId != null) {
      controller.loadModel(currentModelId!);
    }
    notifyListeners();
    return true;
  }

  /// Creates a `project_v1` folder at [path] and opens it. A legacy `chunks/`
  /// folder is migrated into `models/` like the old editor did.
  Future<bool> createProject(String path, {required String name}) async {
    final dir = Directory(path);
    final ok = await controller.createProject(dir, name: name);
    if (!ok) return false;
    await _migrateLegacyChunks(dir);
    return openProject(path);
  }

  Future<void> _migrateLegacyChunks(Directory root) async {
    final chunks = Directory(p.join(root.path, 'chunks'));
    if (!chunks.existsSync()) return;
    final store = controller.project;
    for (final f in chunks.listSync().whereType<File>()) {
      if (!f.path.toLowerCase().endsWith('.json')) continue;
      try {
        final id = p.basenameWithoutExtension(f.path);
        final model = loadModelData(f.readAsStringSync(), id: id);
        await store.saveModel(model);
        logStage('store', 'migrated $id');
      } catch (e) {
        logStage('store', 'migration FAIL ${p.basename(f.path)}: $e');
      }
    }
  }

  void closeProject() {
    logStage('store', 'closeProject');
    _resources?.dispose();
    _resources = null;
    _model3d?.removeListener(_onModel3dChanged);
    _model3d?.dispose();
    _model3d = null;
    controller.unloadModel();
    store = null;
    currentModelId = null;
    selectedObjectId = null;
    selectedFaceKey = null;
    selectedIds.clear();
    selectedGroupId = null;
    selectedMetaId = null;
    selectedLightId = null;
    faceSnapMode = null;
    _undoStacks.clear();
    _redoStacks.clear();
    notifyListeners();
  }

  void selectModel(String id) {
    if (currentModelId == id) return;
    currentModelId = id;
    store?.lastModelId = id;
    selectedObjectId = null;
    selectedFaceKey = null;
    selectedIds.clear();
    selectedGroupId = null;
    selectedMetaId = null;
    selectedLightId = null;
    faceSnapMode = null;
    final model = store?.models[id];
    if (model != null) controller.loadModelData(model, id: id);
    logStage(
      'store',
      'selectModel $id'
          '${model == null ? '' : ' name=${model.name} ${model.size.w}x${model.size.l}x${model.size.h} objects=${model.objects.length} groups=${model.groups.length}'}',
    );
    notifyListeners();
  }

  /// A model id must be a valid file name.
  String? _validateModelId(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'Имя не может быть пустым';
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(clean)) {
      return 'Имя содержит запрещённые символы';
    }
    return null;
  }

  String _nextModelId() {
    final s = store!;
    var n = 1;
    while (s.models.containsKey('model_$n')) {
      n++;
    }
    return 'model_$n';
  }

  void createModel() {
    final s = store!;
    final id = _nextModelId();
    final model = s.createModel(id: id);
    // A fresh model has no file on disk yet: it counts as unsaved until the
    // first save.
    model.dirty = true;
    logStage('store', 'createModel $id');
    model.size = ModelSize();
    // The floor covers the whole model footprint: centered on the model
    // ((w−1)/2, (l−1)/2), size w×l.
    final w = model.size.w, l = model.size.l;
    final floor = ModelObject(
      id: 'obj_1',
      name: 'floor',
      kind: 'cuboid',
      x: (w - 1) / 2,
      y: 0,
      z: (l - 1) / 2,
      dims: {'w': w, 'h': 0.05, 'd': l},
    );
    model.objects.add(floor);
    _undoStacks[id] = [];
    _redoStacks[id] = [];
    currentModelId = id;
    controller.loadModelData(model, id: id);
    _touchScene();
    notifyListeners();
  }

  /// Adds a model built from a template (the «По шаблону» button): in-memory
  /// and dirty like «Создать модель» — the user saves it with the save button.
  void createFromTemplate(ModelData model) {
    final s = store;
    if (s == null) return;
    final id = _nextModelId();
    model.id = id;
    model.dirty = true;
    s.models[id] = model;
    logStage(
      'store',
      'createFromTemplate $id objects=${model.objects.length} '
          'groups=${model.groups.length}',
    );
    _undoStacks[id] = [];
    _redoStacks[id] = [];
    currentModelId = id;
    controller.loadModelData(model, id: id);
    selectedObjectId = null;
    selectedFaceKey = null;
    selectedIds.clear();
    selectedGroupId = null;
    selectedMetaId = null;
    selectedLightId = null;
    _touchScene();
    notifyListeners();
  }

  void duplicateModel(String id) {
    final s = store!;
    final src = s.models[id];
    if (src == null) return;
    final newId = _nextModelId();
    final copy = ModelData.copy(src)..id = newId;
    copy.name = '${src.name}_copy';
    // The copy is not on disk yet.
    copy.dirty = true;
    s.models[newId] = copy;
    _undoStacks[newId] = [];
    _redoStacks[newId] = [];
    currentModelId = newId;
    controller.loadModelData(copy, id: newId);
    _touchScene();
    notifyListeners();
  }

  void deleteModel(String id) {
    final s = store!;
    if (!s.models.containsKey(id)) return;
    // Instances that reference the model about to vanish keep a last-known
    // size snapshot — the fuchsia placeholder cube needs it once the source
    // file is gone. Refresh the caches right here so the cube is accurate.
    final deleted = s.models[id]!;
    for (final other in s.models.values) {
      var changed = false;
      for (final o in other.objects) {
        if (!o.isModelRef || o.refModelId != id) continue;
        final cached = o.refSize;
        if (cached == null ||
            cached.w != deleted.size.w ||
            cached.l != deleted.size.l ||
            cached.h != deleted.size.h) {
          o.refSize = ModelSize.copy(deleted.size);
          changed = true;
        }
      }
      if (changed) other.dirty = true;
    }
    unawaited(s.deleteModel(id));
    _undoStacks.remove(id);
    _redoStacks.remove(id);
    if (currentModelId == id) {
      currentModelId = s.modelIds.isEmpty ? null : s.modelIds.first;
      selectedObjectId = null;
      selectedIds.clear();
      selectedGroupId = null;
      selectedMetaId = null;
      selectedLightId = null;
      final next = currentModelId;
      if (next == null) {
        controller.unloadModel();
      } else {
        controller.loadModelData(s.models[next]!, id: next);
      }
    }
    _touchScene();
    notifyListeners();
  }

  Future<String?> renameModel(String id, String newName) async {
    final s = store!;
    final err = _validateModelId(newName);
    if (err != null) return err;
    final clean = newName.trim();
    if (clean.isEmpty || clean == id) return null;
    final models = s.modelIds;
    if (models.contains(clean)) return 'Модель с таким именем уже есть';
    try {
      await s.renameModel(id, clean);
    } catch (e) {
      return 'Не удалось переименовать: $e';
    }
    // Model instances reference the source by id (= file name) — repoint
    // every reference so renaming never breaks the placed models.
    for (final other in s.models.values) {
      var changed = false;
      for (final o in other.objects) {
        if (o.isModelRef && o.refModelId == id) {
          o.refModelId = clean;
          changed = true;
        }
      }
      if (changed) other.dirty = true;
    }
    if (currentModelId == id) currentModelId = clean;
    _touchScene();
    notifyListeners();
    return null;
  }

  /// Whether the project has unsaved document changes: any model flagged
  /// dirty (edited since the last save, or never written to disk).
  bool get hasUnsavedChanges {
    final s = store;
    if (s == null) return false;
    for (final model in s.models.values) {
      if (model.dirty) return true;
    }
    return false;
  }

  /// Saves every dirty model and the project meta, waiting for the writes.
  /// Returns true when the project is clean afterwards.
  Future<bool> saveAll() async {
    final s = store;
    if (s == null) return true;
    var ok = true;
    // The live catalog holds models that were never written to disk (created
    // or duplicated in memory), so iterate it rather than the file ids.
    for (final model in List.of(s.models.values)) {
      if (!model.dirty) continue;
      try {
        await s.saveModel(model);
      } catch (error) {
        logStage('store', 'saveAll FAIL ${model.id}: $error');
        ok = false;
      }
      if (model.dirty) ok = false;
    }
    try {
      await s.saveMeta();
    } catch (error) {
      logStage('store', 'saveAll meta FAIL: $error');
      ok = false;
    }
    notifyListeners();
    return ok;
  }

  Future<void> saveCurrent() async {
    final model = currentModel;
    if (model == null) return;
    // Refresh the cached source sizes of this scene's instances so their
    // fuchsia placeholders (after a delete) keep the latest dimensions.
    for (final o in model.objects) {
      if (!o.isModelRef) continue;
      final target = store!.models[o.refModelId];
      if (target == null) continue;
      final cached = o.refSize;
      if (cached == null ||
          cached.w != target.size.w ||
          cached.l != target.size.l ||
          cached.h != target.size.h) {
        o.refSize = ModelSize.copy(target.size);
      }
    }
    await store!.saveModel(model);
    // Persist the last-open model id (and any resource-index changes) in
    // project.json.
    final s = store!;
    if (s.lastModelId != model.id) {
      s.lastModelId = model.id;
    }
    await s.saveMeta();
    notifyListeners();
  }

  // ── model settings ───────────────────────────────────────────────────

  void setModelSize(int w, int l, int h) {
    final model = currentModel;
    if (model == null) return;
    final old = ModelSize.copy(model.size);
    // Лимиты согласованы с model_v1: карты 1:1 (импорт) больше легаси-сетки.
    model.size.w = w.clamp(1, 16384);
    model.size.l = l.clamp(1, 16384);
    model.size.h = h.clamp(1, 4096);
    _push(_restoreSizeCmd(model, old, ModelSize.copy(model.size)));
    _touchScene();
    notifyListeners();
  }

  _Cmd _restoreSizeCmd(ModelData model, ModelSize old, ModelSize newSize) {
    return _Cmd(
      'Размер модели',
      () => model.size = newSize,
      () => model.size = old,
    );
  }

  void setModelName(String name) {
    final model = currentModel;
    if (model == null || name == model.name) return;
    model.name = name;
    model.dirty = true;
    _touchScene();
    notifyListeners();
  }

  // ── scene level fields (entries / front, plan §3.14) ─────────────────

  /// Toggles an entry side of the current scene (`entries` in `model_v1`).
  void toggleEntrySide(ModelSide side) {
    final model = currentModel;
    if (model == null) return;
    final before = Set<ModelSide>.of(model.entries);
    final after = Set<ModelSide>.of(model.entries);
    if (!after.remove(side)) after.add(side);
    model.entries = after;
    _push(_Cmd(
      'Входные стороны',
      () => currentModel!.entries = Set.of(after),
      () => currentModel!.entries = Set.of(before),
    ));
    _touchScene();
    notifyListeners();
  }

  /// Sets the scene's facade side (`front` in `model_v1`); null clears it.
  void setFrontSide(ModelSide? side) {
    final model = currentModel;
    if (model == null || model.front == side) return;
    final before = model.front;
    model.front = side;
    _push(_Cmd(
      'Лицевая сторона',
      () => currentModel!.front = side,
      () => currentModel!.front = before,
    ));
    _touchScene();
    notifyListeners();
  }

  // ── named cell-meta brush (markup, plan §3.13/§3.14) ─────────────────

  String _cellBrushName = metaNameUnpassable;
  bool _cellBrushArmed = false;
  final List<ModelMeta> _cellStroke = [];

  /// The meta name the cell brush paints (`unpassable`/`door`/`window` by
  /// default, any name allowed).
  String get cellBrushName => _cellBrushName;

  /// Whether the brush is armed: clicks paint cell metas instead of picking.
  bool get cellBrushArmed => _cellBrushArmed;

  void setCellBrushName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean == _cellBrushName) return;
    _cellBrushName = clean;
    notifyListeners();
  }

  void setCellBrushArmed(bool armed) {
    if (armed == _cellBrushArmed) return;
    _cellBrushArmed = armed;
    if (!armed) _cellStroke.clear();
    notifyListeners();
  }

  /// Starts a brush stroke (pointer down): every [paintCellMeta] until
  /// [endCellStroke] collapses into one undo step.
  void beginCellStroke() => _cellStroke.clear();

  /// Paints one 1×1 box meta named [name] at the model-local cell center
  /// (x, z). Painting the same cell+name twice is a no-op.
  void paintCellMeta(String name, int x, int z, {double y = 0}) {
    final model = currentModel;
    if (model == null) return;
    final exists = model.metas.any((m) =>
        m.kind == metaKindBox && m.name == name && m.x == x && m.z == z);
    if (exists) return;
    final meta = ModelMeta(
      id: _nextMetaId(model),
      kind: metaKindBox,
      name: name,
      x: x.toDouble(),
      y: y,
      z: z.toDouble(),
      dims: const {'w': 1.0, 'h': 1.0, 'd': 1.0},
    );
    model.metas.add(meta);
    _cellStroke.add(meta);
    _touchScene();
    notifyListeners();
  }

  /// Ends a brush stroke: one undo command removes every meta painted in it.
  void endCellStroke() {
    final model = currentModel;
    if (model == null || _cellStroke.isEmpty) return;
    final painted = List<ModelMeta>.of(_cellStroke);
    _cellStroke.clear();
    _push(_Cmd(
      'Кисть «${painted.first.name}»',
      () {
        for (final m in painted) {
          if (!currentModel!.metas.any((x) => x.id == m.id)) {
            currentModel!.metas.add(ModelMeta.copy(m));
          }
        }
      },
      () {
        for (final m in painted) {
          currentModel!.metas.removeWhere((x) => x.id == m.id);
        }
      },
    ));
    notifyListeners();
  }

  // ── object edits ─────────────────────────────────────────────────────

  ModelObject? _findObject(String id) {
    final model = currentModel;
    if (model == null) return null;
    for (final o in model.objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Restores [snapshot]'s values into [target] in place, keeping object
  /// identity stable (renderer nodes and selections reference it by id).
  void _restoreInto(ModelObject target, ModelObject snapshot) {
    target.kind = snapshot.kind;
    target.name = snapshot.name;
    target.op = snapshot.op;
    target.operands = snapshot.operands == null
        ? null
        : List.of(snapshot.operands!);
    target.refModelId = snapshot.refModelId;
    target.scale = snapshot.scale;
    target.refSize = snapshot.refSize == null
        ? null
        : ModelSize.copy(snapshot.refSize!);
    target.gltfName = snapshot.gltfName;
    target.gltfBounds = snapshot.gltfBounds == null
        ? null
        : List.of(snapshot.gltfBounds!);
    target.anim = snapshot.anim;
    target.mesh = snapshot.mesh?.copy();
    target.scaleX = snapshot.scaleX;
    target.scaleY = snapshot.scaleY;
    target.scaleZ = snapshot.scaleZ;
    target.bake = snapshot.bake;
    target.tag = snapshot.tag;
    target.x = snapshot.x;
    target.y = snapshot.y;
    target.z = snapshot.z;
    target.rotX = snapshot.rotX;
    target.rotY = snapshot.rotY;
    target.rotZ = snapshot.rotZ;
    target.dims
      ..clear()
      ..addAll(snapshot.dims);
    target.material = snapshot.material == null
        ? null
        : ModelMaterial.copy(snapshot.material!);
    target.faces
      ..clear()
      ..addAll({
        for (final e in snapshot.faces.entries)
          e.key: ModelMaterial.copy(e.value),
      });
  }

  void _objectEdit(
    String id, {
    String? description,
    void Function(ModelObject o)? mutate,
  }) {
    final model = currentModel;
    final obj = _findObject(id);
    if (model == null || obj == null) return;
    final snapshot = ModelObject.copy(obj);
    mutate?.call(obj);
    final mutated = ModelObject.copy(obj);
    _pushMerged(
      'obj:$id',
      description ?? 'Изменение объекта',
      () => _restoreInto(obj, ModelObject.copy(mutated)),
      () => _restoreInto(obj, snapshot),
    );
    // Bump the scene revision so the viewport rebuilds the scene right away
    // (parameter edits from the right panel must apply immediately).
    _touchScene();
    notifyListeners();
  }

  void setObjectPos(String id, double x, double y, double z) =>
      _objectEdit(id, description: 'Позиция', mutate: (o) {
        o.x = x;
        // Импортированные карты 1:1 живут и ниже нуля; прежний потолок 128
        // поднят вместе с лимитами модели.
        o.y = y.clamp(-4096.0, 4096.0);
        o.z = z;
      });

  void setObjectDim(String id, String key, double value) =>
      _objectEdit(id, description: 'Размер', mutate: (o) {
        // Поле радиуса живёт «на лету»: при вводе «0.15» промежуточное «0»
        // не должно выключать скругление — 0 схлопывается в минимум 0.01;
        // выключение — отдельной кнопкой ([disableCuboidRound]).
        o.setDim(key, value > 0 ? value : 0.01);
      });

  /// Включает скругление кубоида с разумным радиусом по умолчанию (0.1
  /// клетки — редактируется полем «Радиус»). Один шаг undo.
  void enableCuboidRound(String id) => setObjectDim(id, 'roundR', 0.1);

  /// Выключает скругление кубоида (radius = 0). Отдельная команда, чтобы
  /// случайный «0» при вводе радиуса не отключал скругление.
  void disableCuboidRound(String id) => _objectEdit(
      id,
      description: 'Размер',
      mutate: (o) => o.setDim('roundR', 0));

  void setObjectFlag(String id, String key, bool value) =>
      _objectEdit(id, description: 'Флаг', mutate: (o) => o.setFlag(key, value));

  void setObjectRot(String id, double rotX, double rotY, double rotZ) =>
      _objectEdit(id, description: 'Поворот', mutate: (o) {
        o.rotX = rotX % 360;
        o.rotY = rotY % 360;
        o.rotZ = rotZ % 360;
      });

  void setObjectName(String id, String name) =>
      _objectEdit(id, description: 'Имя', mutate: (o) {
        o.name = name.isEmpty ? o.id : name;
      });

  // ── правка многогранника (объект / грани / вершины) ─────────────────

  /// Переключает режим правки выбранного многогранника. В грани и вершины
  /// входят только явно; подвыделения при переключении сбрасываются.
  void setPolyEditMode(PolyEditMode m) {
    final obj = selectedObject();
    if (obj == null || !obj.isPolyhedron || polyEditMode == m) return;
    polyEditMode = m;
    selectedVertexIndices.clear();
    activeVertexIndex = null;
    polyAddVertexArmed = false;
    if (m != PolyEditMode.faces) {
      selectedFaces.clear();
      selectedFaceKey = null;
    }
    selectedIds
      ..clear()
      ..add(obj.id);
    notifyListeners();
  }

  /// Выходит из правки многогранника в режим «объект» (Esc, смена модели).
  /// Само выделение объекта не снимается — это делает следующий Esc.
  void resetPolyEdit() {
    if (polyEditMode == PolyEditMode.object &&
        selectedVertexIndices.isEmpty &&
        activeVertexIndex == null &&
        !polyAddVertexArmed) {
      return;
    }
    polyEditMode = PolyEditMode.object;
    selectedVertexIndices.clear();
    activeVertexIndex = null;
    polyAddVertexArmed = false;
    notifyListeners();
  }

  /// Выбор вершины текущего многогранника. [shift] добавляет/снимает
  /// вершину (группа), иначе выбор заменяется. null снимает выделение.
  void selectPolyVertex(int? index, {bool shift = false}) {
    final obj = selectedObject();
    final mesh = obj?.mesh;
    if (mesh == null) return;
    if (index == null) {
      if (!shift) {
        selectedVertexIndices.clear();
        activeVertexIndex = null;
      }
    } else if (index >= 0 && index < mesh.vertices.length) {
      if (shift) {
        if (!selectedVertexIndices.remove(index)) {
          selectedVertexIndices.add(index);
        }
        activeVertexIndex = selectedVertexIndices.contains(index)
            ? index
            : (selectedVertexIndices.isEmpty
                ? null
                : selectedVertexIndices.last);
      } else {
        selectedVertexIndices
          ..clear()
          ..add(index);
        activeVertexIndex = index;
      }
    }
    notifyListeners();
  }

  /// Масштаб многогранника по оси: 0 = X, 1 = Y, 2 = Z. Объект
  /// вытягивается в заданных пропорциях, положение якоря сохраняется.
  void setPolyScale(String id, int axis, double value) {
    final v = value <= 0 ? 0.01 : value;
    _objectEdit(id, description: 'Масштаб', mutate: (o) {
      switch (axis) {
        case 0:
          o.scaleX = v;
        case 1:
          o.scaleY = v;
        default:
          o.scaleZ = v;
      }
    });
  }

  /// Сдвиг выбранных вершин на [delta] — без undo: вызывается покадрово
  /// во время drag, историю пишет [endPolyVertexDrag].
  void moveSelectedPolyVertices(vm.Vector3 delta) {
    final obj = selectedObject();
    if (obj?.mesh == null || selectedVertexIndices.isEmpty) return;
    obj!.mesh!.moveVertices(selectedVertexIndices, delta);
    _refreshPolyGeometry(obj);
  }

  /// Поворот выбранных вершин вокруг [pivot] — без undo (см. выше).
  void rotateSelectedPolyVertices(
    vm.Vector3 axis,
    double radians, {
    required vm.Vector3 pivot,
  }) {
    final obj = selectedObject();
    if (obj?.mesh == null || selectedVertexIndices.isEmpty) return;
    obj!.mesh!.rotateVertices(
          selectedVertexIndices,
          axis,
          radians,
          pivot: pivot,
        );
    _refreshPolyGeometry(obj);
  }

  /// Точная установка координат вершины из полей панели (один undo).
  void setPolyVertexPosition(int index, vm.Vector3 value) {
    final obj = selectedObject();
    final mesh = obj?.mesh;
    if (mesh == null || index < 0 || index >= mesh.vertices.length) return;
    _objectEdit(obj!.id, description: 'Вершина', mutate: (o) {
      o.mesh!.vertices[index] = value.clone();
    });
  }

  ModelObject? _polyDragSnapshot;

  /// Снимок перед drag вершин (один undo на весь жест).
  void beginPolyVertexDrag() {
    final obj = selectedObject();
    if (obj?.mesh == null) return;
    _polyDragSnapshot = ModelObject.copy(obj!);
  }

  /// Завершает drag вершин: сравнивает со снимком и кладёт один undo.
  void endPolyVertexDrag({String action = 'Правка вершин'}) {
    final obj = selectedObject();
    final snapshot = _polyDragSnapshot;
    _polyDragSnapshot = null;
    if (obj?.mesh == null || snapshot == null) return;
    final mutated = ModelObject.copy(obj!);
    if (mutated.toJson().toString() == snapshot.toJson().toString()) return;
    _touchScene();
    final target = obj;
    _push(_Cmd(
      action,
      () => _restoreInto(target, ModelObject.copy(mutated)),
      () => _restoreInto(target, snapshot),
    ));
    notifyListeners();
  }

  /// Удаляет выбранные грани текущего многогранника (один undo).
  void deleteSelectedPolyFaces() {
    final obj = selectedObject();
    if (obj?.mesh == null || selectedFaces.isEmpty) return;
    final prefix = '${obj!.id}:';
    final keys = [
      for (final key in selectedFaces)
        if (key.startsWith(prefix)) key.substring(prefix.length),
    ];
    if (keys.isEmpty) return;
    _objectEdit(obj.id, description: 'Удалить грани', mutate: (o) {
      o.mesh?.deleteFaces(keys);
      pruneFaceMaterials(o);
    });
    selectedFaces.clear();
    selectedFaceKey = null;
    notifyListeners();
  }

  /// Удаляет выбранные вершины (и вырожденные ими грани) — один undo.
  void deleteSelectedPolyVertices() {
    final obj = selectedObject();
    if (obj?.mesh == null || selectedVertexIndices.isEmpty) return;
    final indices = List<int>.of(selectedVertexIndices);
    _objectEdit(obj!.id, description: 'Удалить вершины', mutate: (o) {
      o.mesh?.deleteVertices(indices);
      pruneFaceMaterials(o);
    });
    selectedVertexIndices.clear();
    activeVertexIndex = null;
    notifyListeners();
  }

  /// Включает/выключает armed-режим добавления вершины: следующий клик по
  /// объекту вставит вершину в ближайшее ребро грани под курсором.
  void togglePolyAddVertex() {
    if (polyEditMode != PolyEditMode.vertices) return;
    polyAddVertexArmed = !polyAddVertexArmed;
    notifyListeners();
  }

  /// Вставляет вершину в грань [faceKey] в локальной точке [localPoint]
  /// (мировой луч переводит вьюпорт) и сразу выбирает её. Клик по ребру
  /// расщепляет его, клик внутри пробивает грань треугольниками (без дыры);
  /// материал исходной грани переносится новым треугольникам. Режим
  /// остаётся включённым — можно добавить несколько вершин подряд.
  void addPolyVertex(String faceKey, vm.Vector3 localPoint) {
    final obj = selectedObject();
    if (obj?.mesh == null) return;
    int? index;
    _objectEdit(obj!.id, description: 'Добавить вершину', mutate: (o) {
      final before = {for (final f in o.mesh!.faces) f.key};
      index = o.mesh!.addVertexToFace(faceKey, localPoint);
      if (index == null) return;
      // Исходный ключ остаётся первой новой грани; остальным копируем
      // материал переопределения грани (иначе они наследуют материал
      // объекта, и цвет «расщепится»).
      final spec = o.faces[faceKey];
      if (spec == null) return;
      for (final f in o.mesh!.faces) {
        if (before.contains(f.key)) continue;
        o.faces[f.key] = ModelMaterial.copy(spec);
      }
    });
    if (index == null) return;
    final added = index!;
    selectedVertexIndices
      ..clear()
      ..add(added);
    activeVertexIndex = added;
    notifyListeners();
  }

  /// Преобразует объект в многогранник: `bakePolyhedron`, перенос
  /// материалов граней, удаление неиспользуемых скрытых операндов CSG —
  /// одна команда undo.
  void convertToPolyhedron(String id) {
    final model = currentModel;
    final obj = _findObject(id);
    if (model == null || obj == null) return;
    final bake = bakePolyhedron(model, obj);
    if (bake == null) return;

    final snapshot = ModelObject.copy(obj);
    final removed = <int, ModelObject>{};
    if (obj.isCsg) {
      for (final operandId in obj.operands ?? const <String>[]) {
        final stillUsed = model.objects.any(
          (o) =>
              o.isCsg &&
              o.id != obj.id &&
              (o.operands?.contains(operandId) ?? false),
        );
        if (stillUsed) continue;
        final operand = model.objectById(operandId);
        if (operand == null) continue;
        final index = model.objects.indexOf(operand);
        if (index >= 0) removed[index] = operand;
      }
    }

    void removeOperands() {
      for (final operand in removed.values) {
        model.objects.remove(operand);
      }
      model.pruneGroupMembers();
    }

    void restoreOperands() {
      final indices = removed.keys.toList()..sort();
      for (final index in indices) {
        model.objects.insert(
          index.clamp(0, model.objects.length),
          removed[index]!,
        );
      }
    }

    bake.applyTo(obj);
    pruneFaceMaterials(obj);
    removeOperands();
    final converted = ModelObject.copy(obj);
    polyEditMode = PolyEditMode.object;
    selectedFaceKey = null;
    selectedFaces.clear();
    selectedVertexIndices.clear();
    activeVertexIndex = null;
    _touchScene();
    _push(_Cmd(
      'Преобразовать в многогранник',
      () {
        _restoreInto(obj, ModelObject.copy(converted));
        removeOperands();
      },
      () {
        _restoreInto(obj, snapshot);
        restoreOperands();
      },
    ));
    notifyListeners();
  }

  void _refreshPolyGeometry(ModelObject obj) {
    // Точечная пересборка узлов объекта: drag вершин не пересобирает всю
    // модель (у моделей/gltf движок сам откатится на полный rebuild).
    controller.refreshObjectGeometry(obj.id);
    notifyListeners();
  }

  // ── face snap («Перенести к грани» / «Параллельно грани») ───────────

  /// Arms/cancels a face-snap operation (the panel buttons toggle it).
  void setFaceSnapMode(FaceSnapMode? mode) {
    if (faceSnapMode == mode) return;
    faceSnapMode = mode;
    notifyListeners();
  }

  /// Applies the armed operation to the SELECTED object using the clicked
  /// face's geometry (the face belongs to [faceObjId]): [FaceSnapMode.
  /// moveToFace] moves the anchor to the face center AND orients the object
  /// parallel to the face («работает аналогично Параллельно грани, но
  /// объект перемещается» — без переориентации старая ориентация может
  /// указывать сквозь объект-носитель: «прикрепился к противоположной
  /// грани»); [FaceSnapMode.parallelToFace] orients only. One undo command
  /// each. Always un-arms the mode.
  ///
  /// [worldPoint] is the raycast hit in WORLD space (needed for the
  /// cylinder side — its normal and position depend on the click angle);
  /// [billboardYaw] is the current sprite billboard yaw (for sprite faces).
  void applyFaceSnap(
    FaceSnapMode mode,
    String faceObjId,
    String faceKey,
    vm.Vector3? worldPoint, {
    required double billboardYaw,
  }) {
    final target = selectedObject();
    final faceObj = _findObject(faceObjId);
    final model = currentModel;
    if (target == null || faceObj == null || model == null) {
      faceSnapMode = null;
      notifyListeners();
      return;
    }
    // World → model-local (inverse of chunkWorld: world x = −(x − (w−1)/2),
    // world z = z − (l−1)/2) — same mapping as the viewport's cursor.
    final clickLocal = worldPoint == null
        ? null
        : vm.Vector3(
            (model.size.w - 1) / 2 - worldPoint.x,
            worldPoint.y,
            worldPoint.z + (model.size.l - 1) / 2,
          );
    final normal = faceNormalAt(
      faceObj,
      faceKey,
      clickLocal: clickLocal,
      billboardYaw: billboardYaw,
    );
    switch (mode) {
      case FaceSnapMode.parallelToFace:
        if (normal == null) {
          faceSnapMode = null;
          notifyListeners();
          return;
        }
        final (rx, ry, rz) = parallelToFaceAngles(target, normal);
        _objectEdit(target.id, description: 'Параллельно грани', mutate: (o) {
          o.rotX = rx % 360;
          o.rotY = ry % 360;
          o.rotZ = rz % 360;
        });
      case FaceSnapMode.moveToFace:
        final center = faceCenterAt(
          faceObj,
          faceKey,
          clickLocal: clickLocal,
          billboardYaw: billboardYaw,
        );
        if (center == null) {
          faceSnapMode = null;
          notifyListeners();
          return;
        }
        final (rx, ry, rz) =
            normal == null ? (0.0, 0.0, 0.0) : parallelToFaceAngles(target, normal);
        _objectEdit(target.id, description: 'Перенос к грани', mutate: (o) {
          o.x = round3(center.x);
          o.y = round3(center.y);
          o.z = round3(center.z);
          if (normal != null) {
            o.rotX = rx % 360;
            o.rotY = ry % 360;
            o.rotZ = rz % 360;
          }
        });
    }
    faceSnapMode = null;
    notifyListeners();
  }

  /// Adds a primitive of [kind] at the cursor; sprite needs [spriteKey].
  void addObject(String kind, {String? spriteKey}) {
    final model = currentModel;
    if (model == null) return;
    final id = _nextObjectId(model);
    final dims = switch (kind) {
      'cuboid' => {'w': 1.0, 'h': 1.0, 'd': 1.0},
      'trapezoid' => {'bottomW': 1.0, 'bottomD': 1.0, 'topW': 0.5, 'topD': 0.5, 'h': 0.5},
      'cylinder' => {'bottomR': 0.25, 'topR': 0.25, 'h': 1.0, 'segments': 16},
      'cone' => {'bottomR': 0.25, 'topR': 0.0, 'h': 1.0, 'segments': 16},
      'plane' => {'w': 1.0, 'd': 1.0, 'vertical': 0},
      'sprite' => {'w': 1.0, 'h': 1.0},
      _ => <String, num>{},
    };
    final obj = ModelObject(
      id: id,
      name: kind,
      kind: kind == 'cone' ? 'cylinder' : kind,
      x: cursorX,
      y: cursorY,
      z: cursorZ,
      dims: dims,
      // Новый многогранник стартует как куб: его сразу можно тянуть за
      // грани и вершины.
      mesh: kind == 'polyhedron' ? PolyMesh.box() : null,
    );
    if (kind == 'sprite' && spriteKey != null) {
      obj.material = ModelMaterial(type: MaterialType.sprite, key: spriteKey);
    }
    model.objects.add(obj);
    selectedObjectId = obj.id;
    selectedIds
      ..clear()
      ..add(obj.id);
    selectedFaceKey = null;
    _touchScene();
    _push(_Cmd(
      'Добавить $kind',
      () => model.objects.add(obj),
      () {
        model.objects.remove(obj);
        if (selectedObjectId == obj.id) selectedObjectId = null;
        selectedIds.remove(obj.id);
      },
    ));
    notifyListeners();
  }

  String _nextObjectId(ModelData model) {
    var n = 1;
    while (model.objects.any((o) => o.id == 'obj_$n')) {
      n++;
    }
    return 'obj_$n';
  }

  // ── model instances («Модель» — whole-model placement) ───────────────

  /// Whether the model [srcId] transitively contains a reference to
  /// [targetId] (directly or through its own instances). Cycle-safe.
  bool _references(String srcId, String targetId, Set<String> seen) {
    final m = store?.models[srcId];
    if (m == null) return false;
    for (final o in m.objects) {
      if (!o.isModelRef) continue;
      if (o.refModelId == targetId) return true;
      if (seen.add(o.refModelId) &&
          _references(o.refModelId, targetId, seen)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [candidateId] may be inserted into the model [containerId]:
  /// it must differ from the container, and inserting it must not create a
  /// reference cycle (a model may never contain itself, even transitively).
  bool canInsertModel(String containerId, String candidateId) {
    if (candidateId == containerId) return false;
    if (store == null || !store!.models.containsKey(candidateId)) return false;
    return !_references(candidateId, containerId, <String>{candidateId});
  }

  /// Models of the project that place [modelId] as an instance (kind
  /// 'model') — used by the delete warning «используется в сценах».
  List<String> modelsUsingModel(String modelId) => [
        for (final m in store?.models.values ?? const <ModelData>[])
          if (m.objects.any(
              (o) => o.isModelRef && o.refModelId == modelId))
            m.id,
      ];

  /// Places the whole model [modelId] in the current scene at the virtual
  /// cursor (one undo command). The referenced model's own coordinate
  /// system is copied «as is»: its origin lands on the cursor, content is
  /// not editable here and follows the source model.
  void addModelRef(String modelId) {
    final model = currentModel;
    final s = store;
    if (model == null || s == null) return;
    if (!canInsertModel(model.id, modelId)) return;
    final target = s.models[modelId];
    if (target == null) return;
    final id = _nextObjectId(model);
    final obj = ModelObject(
      id: id,
      name: target.name,
      kind: modelRefKind,
      x: cursorX,
      y: cursorY,
      z: cursorZ,
      refModelId: modelId,
      scale: 1,
      refSize: ModelSize.copy(target.size),
    );
    model.objects.add(obj);
    selectedObjectId = obj.id;
    selectedIds
      ..clear()
      ..add(obj.id);
    selectedFaceKey = null;
    _touchScene();
    _push(_Cmd(
      'Добавить модель «${target.name}»',
      () => model.objects.add(obj),
      () {
        model.objects.remove(obj);
        if (selectedObjectId == obj.id) selectedObjectId = null;
        selectedIds.remove(obj.id);
      },
    ));
    notifyListeners();
  }

  /// Swaps the source of the instance [instanceId] to another model — the
  /// «make a copy, recolor it, then swap it in the scene» workflow. The
  /// placement (pos/rotation/scale) is kept; the name follows the new
  /// source. One undo command.
  void replaceModelRef(String instanceId, String newModelId) {
    final model = currentModel;
    final s = store;
    final obj = _findObject(instanceId);
    if (model == null || s == null || obj == null || !obj.isModelRef) {
      return;
    }
    if (newModelId == obj.refModelId) return;
    if (!canInsertModel(model.id, newModelId)) return;
    final target = s.models[newModelId];
    if (target == null) return;
    _objectEdit(instanceId, description: 'Заменить модель', mutate: (o) {
      o.refModelId = newModelId;
      o.name = target.name;
      o.refSize = ModelSize.copy(target.size);
    });
  }

  /// Sets the uniform scale of a model instance (applied around its
  /// anchor; the content keeps its proportions).
  void setObjectScale(String id, double value) =>
      _objectEdit(id, description: 'Масштаб', mutate: (o) {
        o.scale = value > 0 ? value : 0.01;
      });

  // ── glTF/GLB instances («GLB/GLTF» — 3D-model resources) ─────────────

  /// Models of the project that place the `3d_models/` resource [name] as a
  /// gltf instance (kind 'gltf') — used by the delete warning in the
  /// Resources tab («используется в моделях»).
  List<String> modelsUsingGltf(String name) => [
        for (final m in store?.models.values ?? const <ModelData>[])
          if (m.objects
              .any((o) => o.isGltfRef && o.gltfName == name))
            m.id,
      ];

  /// Places the whole glTF/GLB resource [name] in the current scene at the
  /// virtual cursor (one undo command). The resource is loaded lazily by the
  /// viewport; until then (and while the content is unknown) a placeholder
  /// stands at the anchor, and a deleted resource shows as a fuchsia cube.
  void addGltfRef(String name) {
    final model = currentModel;
    final s = store;
    if (model == null || s == null) return;
    final entry = model3d.entry(name);
    if (entry == null) return;
    final id = _nextObjectId(model);
    final obj = ModelObject(
      id: id,
      name: entry.name,
      kind: gltfRefKind,
      x: cursorX,
      y: cursorY,
      z: cursorZ,
      gltfName: name,
      scale: 1,
    );
    model.objects.add(obj);
    selectedObjectId = obj.id;
    selectedIds
      ..clear()
      ..add(obj.id);
    selectedFaceKey = null;
    _touchScene();
    _push(_Cmd(
      'Добавить GLB/GLTF «${entry.name}»',
      () => model.objects.add(obj),
      () {
        model.objects.remove(obj);
        if (selectedObjectId == obj.id) selectedObjectId = null;
        selectedIds.remove(obj.id);
      },
    ));
    notifyListeners();
  }

  /// Swaps the source resource of the gltf instance [instanceId] to another
  /// `3d_models/` entry — the placement (pos/rotation/scale) is kept, the
  /// animation choice and the cached footprint are reset. One undo command.
  void replaceGltfRef(String instanceId, String newName) {
    final model = currentModel;
    final s = store;
    final obj = _findObject(instanceId);
    if (model == null || s == null || obj == null || !obj.isGltfRef) {
      return;
    }
    if (newName == obj.gltfName) return;
    final entry = model3d.entry(newName);
    if (entry == null) return;
    _objectEdit(instanceId, description: 'Заменить ресурс', mutate: (o) {
      o.gltfName = newName;
      o.name = entry.name;
      o.gltfBounds = null;
      o.anim = '';
    });
  }

  /// Selects the animation [animName] (a full glTF name; '' = none — the
  /// model keeps its rest pose) played in a loop by the gltf instance
  /// [id]. One undo command.
  void setGltfAnim(String id, String animName) =>
      _objectEdit(id, description: 'Анимация', mutate: (o) {
        o.anim = animName;
      });


  /// Deletes a `3d_models/` resource via [Model3dStore]; references of gltf
  /// instances stay and render as fuchsia cubes. Returns an error message or
  /// null (mirrors the Model3dPanel flow, but through AppState so the
  /// viewport and the asset cache react).
  String? deleteGltfResource(String name) {
    if (store == null) return 'Проект не открыт';
    final err = model3d.delete(name);
    if (err != null) return err;
    // The catalog mutation itself bumps the scene revision via
    // _onModel3dChanged (asset cache is dropped there too).
    return null;
  }

  /// Renames a `3d_models/` resource on disk and repoints every gltf
  /// instance that references it (by catalog name), like model instances are
  /// repointed on a model rename. Returns an error message or null.
  String? renameGltfResource(String from, String to) {
    final s = store;
    if (s == null) return 'Проект не открыт';
    final err = model3d.rename(from, to);
    if (err != null) return err;
    final clean = to.trim();
    for (final other in s.models.values) {
      var changed = false;
      for (final o in other.objects) {
        if (o.isGltfRef && o.gltfName == from) {
          o.gltfName = clean;
          changed = true;
        }
      }
      if (changed) other.dirty = true;
    }
    // The catalog mutation bumps the scene revision via _onModel3dChanged.
    return null;
  }

  void duplicateObject() {
    final model = currentModel;
    final obj = selectedObject();
    if (model == null || obj == null) return;
    // A csg result duplicates as its own independent subtree (fresh copies
    // of the operation nodes and of every operand it consumes).
    if (obj.isCsg) {
      _duplicateCsgSubtree(model, obj);
      return;
    }
    final copy = ModelObject.copy(obj);
    copy.id = _nextObjectId(model);
    copy.name = _nextDuplicateName(model, obj.name);
    copy.x += 0.3;
    model.objects.add(copy);
    selectedObjectId = copy.id;
    selectedIds
      ..clear()
      ..add(copy.id);
    selectedFaceKey = null;
    _touchScene();
    _push(_Cmd(
      'Дублировать ${obj.name}',
      () => model.objects.add(copy),
      () {
        model.objects.remove(copy);
        selectedIds.remove(copy.id);
        if (selectedObjectId == copy.id) selectedObjectId = obj.id;
      },
    ));
    notifyListeners();
  }

  String _nextDuplicateName(ModelData model, String base) {
    var n = 2;
    final names = model.objects.map((o) => o.name).toSet();
    while (names.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  // ── boolean operations (csg) ─────────────────────────────────────────

  /// Human label of a csg operation (used as the default node name).
  static String csgOpLabel(String op) => switch (op) {
        csgOpDifference => 'Вычитание',
        csgOpIntersect => 'Пересечение',
        _ => 'Объединение',
      };

  String _nextCsgId(ModelData model) {
    var n = 1;
    while (model.objects.any((o) => o.id == 'csg_$n')) {
      n++;
    }
    return 'csg_$n';
  }

  /// Whether the current selection is exactly two objects that may be
  /// combined with a boolean operation: both convex-solid eligible, both at
  /// the model root (not in a named group, not already consumed as an
  /// operand of another operation).
  bool get canCombineSelection {
    final model = currentModel;
    if (model == null || selectedGroupId != null) return false;
    final objs = selectedObjects();
    if (objs.length != 2) return false;
    for (final o in objs) {
      if (!isCsgEligible(o)) return false;
      if (model.isCsgOperand(o.id)) return false;
      if (groupOf(o.id) != null) return false;
    }
    return true;
  }

  /// Creates a csg result object combining the two selected objects with
  /// [op] (union/difference/intersect). The operands become hidden (they
  /// render only through the result); the result node becomes the
  /// selection. One undo command.
  void createCsgOperation(String op) {
    final model = currentModel;
    if (model == null || !csgOps.contains(op) || !canCombineSelection) return;
    final objs = selectedObjects();
    final node = ModelObject(
      id: _nextCsgId(model),
      name: csgOpLabel(op),
      kind: csgKind,
      op: op,
      operands: [objs[0].id, objs[1].id],
    );
    model.objects.add(node);
    selectedGroupId = null;
    selectedObjectId = node.id;
    selectedFaceKey = null;
    selectedIds
      ..clear()
      ..add(node.id);
    _touchScene();
    _push(_Cmd(
      '${csgOpLabel(op)}: ${objs[0].name}, ${objs[1].name}',
      () {
        currentModel!.objects.add(ModelObject.copy(node));
        selectedIds
          ..clear()
          ..add(node.id);
        selectedObjectId = node.id;
      },
      () {
        currentModel!.objects.removeWhere((o) => o.id == node.id);
        selectedIds.clear();
        selectedObjectId = null;
      },
    ));
    notifyListeners();
  }

  /// Swaps the operands of [nodeId] (changes the subtraction direction).
  void swapCsgOperands(String nodeId) {
    final obj = _findObject(nodeId);
    if (obj == null || !obj.isCsg) return;
    _objectEdit(nodeId, description: 'Поменять операнды', mutate: (o) {
      final ops = o.operands;
      if (ops != null && ops.length == 2) {
        final t = ops[0];
        ops[0] = ops[1];
        ops[1] = t;
      }
    });
  }

  /// All csg nodes of the operation subtree rooted at [root] (including the
  /// root itself). Leaves are never returned.
  List<ModelObject> _csgSubtreeNodes(ModelData model, ModelObject root) {
    final out = <ModelObject>[];
    void visit(String id) {
      final o = model.objectById(id);
      if (o == null || !o.isCsg) return;
      out.add(o);
      for (final mid in o.operands ?? const <String>[]) {
        visit(mid);
      }
    }

    visit(root.id);
    return out;
  }

  /// The csg chain that consumes [objId]: the referencing node, its parent,
  /// …, up to the forest root.
  List<ModelObject> _csgChainUp(ModelData model, String objId) {
    final out = <ModelObject>[];
    var cur = objId;
    while (true) {
      final p = model.csgParentOf(cur);
      if (p == null) break;
      out.add(p);
      cur = p.id;
    }
    return out;
  }

  /// Deletion victims for a target csg object (see [deleteObject] rules):
  /// deleting a RESULT node dissolves its whole operation subtree (all its
  /// csg nodes — the leaves become plain objects again); deleting an
  /// OPERAND takes its referencing operation (the whole csg chain) with it
  /// so no half-consumed result remains.
  List<ModelObject> _csgDeleteVictims(ModelData model, ModelObject obj) {
    if (obj.isCsg) {
      return _csgSubtreeNodes(model, obj);
    }
    return _csgChainUp(model, obj.id);
  }

  /// Deletes [id] honoring the csg semantics: a csg result node is
  /// «разобрана» (its operation tree is dissolved and the operands become
  /// ordinary visible objects again), and deleting an operand cascades into
  /// deleting the operation(s) that referenced it. One undo command.
  void deleteObject(String id) {
    final obj = _findObject(id);
    if (obj == null) return;
    _deleteObjects([obj]);
  }

  /// Shared deletion core (see [deleteObject]); one undo command for the
  /// whole batch.
  void _deleteObjects(List<ModelObject> objs) {
    final model = currentModel;
    if (model == null || objs.isEmpty) return;
    final victims = <ModelObject>{};
    for (final o in objs) {
      victims
        ..addAll(_csgDeleteVictims(model, o))
        ..add(o);
    }
    final list = victims.toList()
      ..sort((a, b) => model.objects.indexOf(b).compareTo(model.objects.indexOf(a)));
    final indices = [for (final o in list) model.objects.indexOf(o)];
    for (final o in list) {
      model.objects.remove(o);
    }
    model.pruneGroupMembers();
    if (list.any((o) => o.id == selectedObjectId)) {
      selectedObjectId = null;
      selectedFaceKey = null;
    }
    selectedIds.removeWhere((sid) => list.any((o) => o.id == sid));
    _touchScene();
    _push(_Cmd(
      'Удалить ${objs.length == 1 ? objs.first.name : 'выбранное'}',
      () {
        for (final o in list) {
          currentModel!.objects.remove(o);
        }
        selectedIds.clear();
        selectedObjectId = null;
      },
      () {
        // Restore in ascending index order (earlier inserts never shift the
        // later positions).
        final order = List.generate(list.length, (i) => i)
          ..sort((i, j) => indices[i].compareTo(indices[j]));
        for (final i in order) {
          currentModel!.objects.insert(indices[i], list[i]);
        }
      },
    ));
    notifyListeners();
  }

  /// Deep-duplicates the csg subtree rooted at [obj] with fresh ids (the
  /// copies reference their own operands, so editing the copy never affects
  /// the original) and selects the new root. One undo command.
  void _duplicateCsgSubtree(ModelData model, ModelObject obj) {
    // Everything the subtree owns: its csg nodes and the consumed leaves.
    final owned = {for (final n in _csgSubtreeNodes(model, obj)) n.id};
    owned.addAll(model.csgLeavesOf(obj.id).map((l) => l.id));
    final subtreeObjects = [
      for (final o in model.objects)
        if (owned.contains(o.id)) o,
    ];
    final idMap = <String, String>{};
    final copies = <ModelObject>[];
    final taken = {for (final o in model.objects) o.id};
    String freshId() {
      var n = 1;
      while (taken.contains('obj_$n')) {
        n++;
      }
      taken.add('obj_$n');
      return 'obj_$n';
    }

    for (final o in subtreeObjects) {
      final copy = ModelObject.copy(o);
      final newId = freshId();
      idMap[o.id] = newId;
      copy.id = newId;
      copy.name = _nextDuplicateName(model, o.name);
      if (o.isCsg) {
        copy.operands = [
          for (final m in (o.operands ?? const <String>[]))
            idMap[m] ?? m,
        ];
      } else {
        copy.x += 0.3;
      }
      copies.add(copy);
    }
    final rootId = idMap[obj.id] ?? obj.id;
    model.objects.addAll(copies);
    selectedObjectId = rootId;
    selectedIds
      ..clear()
      ..add(rootId);
    selectedFaceKey = null;
    _touchScene();
    _push(_Cmd(
      'Дублировать ${obj.name}',
      () {
        currentModel!.objects.addAll(copies);
        selectedIds
          ..clear()
          ..add(rootId);
        selectedObjectId = rootId;
      },
      () {
        currentModel!.objects.removeWhere(copies.contains);
        selectedIds.clear();
        selectedObjectId = null;
      },
    ));
    notifyListeners();
  }

  void beginGizmoDrag() {
    // Правка многогранника: снимок сети вместо позиций объектов.
    final selected = selectedObject();
    if (selected != null &&
        selected.isPolyhedron &&
        polyEditMode != PolyEditMode.object) {
      beginPolyVertexDrag();
      return;
    }
    final model = currentModel;
    final objs = model?.moveExpansion(selectedIds);
    if (model == null || objs == null || objs.isEmpty) return;
    _dragSnapshots = [for (final o in objs) ModelObject.copy(o)];
  }

  /// Finalizes a gizmo drag (translate or rotate — [action] labels the undo
  /// command): compares the pre-drag snapshots with the current state and
  /// pushes ONE undo command when anything moved.
  void endGizmoDrag({String action = 'Перенос'}) {
    if (_polyDragSnapshot != null) {
      endPolyVertexDrag(action: action);
      return;
    }
    final model = currentModel;
    if (model == null) return;
    final objs = model.moveExpansion(selectedIds);
    final snapshots = _dragSnapshots;
    if (objs.isEmpty || snapshots == null || snapshots.length != objs.length) {
      _dragSnapshots = null;
      return;
    }
    _dragSnapshots = null;
    var moved = false;
    for (var i = 0; i < objs.length; i++) {
      if (ModelObject.copy(objs[i]).toJson().toString() !=
          snapshots[i].toJson().toString()) {
        moved = true;
        break;
      }
    }
    if (!moved) return;
    final mutated = [for (final o in objs) ModelObject.copy(o)];
    _touchScene();
    _push(_Cmd(
      objs.length == 1 ? '$action ${objs.first.name}' : '$action группы',
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], ModelObject.copy(mutated[i]));
        }
      },
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], snapshots[i]);
        }
      },
    ));
    notifyListeners();
  }

  List<ModelObject>? _dragSnapshots;

  /// Moves every selected object (csg nodes — their leaves) by the same
  /// delta (one undo command).
  void moveGroup(double dx, double dy, double dz) {
    final model = currentModel;
    final objs = model?.moveExpansion(selectedIds);
    if (model == null || objs == null || objs.isEmpty) return;
    final snapshots = [for (final o in objs) ModelObject.copy(o)];
    for (final o in objs) {
      o.x += dx;
      o.y = (o.y + dy).clamp(0.0, 128.0);
      o.z += dz;
    }
    final mutated = [for (final o in objs) ModelObject.copy(o)];
    _touchScene();
    _pushMerged(
      'group-move',
      objs.length == 1 ? 'Перенос ${objs.first.name}' : 'Перенос группы',
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], ModelObject.copy(mutated[i]));
        }
      },
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], snapshots[i]);
        }
      },
    );
    notifyListeners();
  }

  /// Applies a material to EVERY selected object's object-level material
  /// (one undo command).
  void setGroupMaterial(ModelMaterial material) {
    final objs = selectedObjects();
    if (objs.isEmpty) return;
    final snapshots = [for (final o in objs) ModelObject.copy(o)];
    for (final o in objs) {
      o.material = ModelMaterial.copy(material);
    }
    _touchScene();
    _push(_Cmd(
      'Материал группы',
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], ModelObject.copy(snapshots[i]));
        }
      },
      () {
        for (var i = 0; i < objs.length; i++) {
          _restoreInto(objs[i], snapshots[i]);
        }
      },
    ));
    notifyListeners();
  }

  /// Deletes every selected object (one undo command).
  void deleteSelected() {
    final model = currentModel;
    if (model == null) return;
    final objs = selectedObjects();
    if (objs.isEmpty) return;
    _deleteObjects(objs);
  }

  // ── named groups ─────────────────────────────────────────────────────

  String _nextGroupId(ModelData model) {
    var n = 1;
    while (model.groups.any((g) => g.id == 'group_$n')) {
      n++;
    }
    return 'group_$n';
  }

  /// Snapshot of the model's groups list for undo/redo.
  List<ModelGroup> _snapshotGroups() =>
      [for (final g in currentModel!.groups) ModelGroup.copy(g)];

  void _restoreGroups(List<ModelGroup> snapshot) {
    currentModel!.groups
      ..clear()
      ..addAll([for (final g in snapshot) ModelGroup.copy(g)]);
  }

  /// Creates a new named group with the selected objects (one undo command).
  /// Objects consumed as csg operands stay hidden under their operation and
  /// cannot be regrouped here.
  void createGroup() {
    final model = currentModel;
    final objs = selectedObjects();
    if (model == null || objs.isEmpty) return;
    if (objs.any((o) => model.isCsgOperand(o.id))) return;
    final g = ModelGroup(
      id: _nextGroupId(model),
      name: 'Группа ${model.groups.length + 1}',
      members: [for (final o in objs) o.id],
    );
    model.groups.add(g);
    selectedGroupId = g.id;
    _touchScene();
    _push(_Cmd(
      'Сгруппировать',
      () {
        currentModel!.groups.add(ModelGroup.copy(g));
        selectedGroupId = g.id;
      },
      () {
        currentModel!.groups.removeWhere((x) => x.id == g.id);
        if (selectedGroupId == g.id) selectedGroupId = null;
      },
    ));
    notifyListeners();
  }

  /// Selects a named group in the tree: its members become the selection.
  void selectGroup(String id) {
    final model = currentModel;
    if (model == null) return;
    final g = model.groups.where((g) => g.id == id).firstOrNull;
    if (g == null) return;
    selectedGroupId = id;
    selectedIds
      ..clear()
      ..addAll(g.members);
    selectedObjectId = g.members.isEmpty ? null : g.members.first;
    selectedFaceKey = null;
    notifyListeners();
  }

  /// «Разгруппировать»: dissolves the selected group (members to root), or
  /// extracts the selected objects from their groups (one undo command).
  void ungroupSelection() {
    final model = currentModel;
    if (model == null) return;
    final snap = _snapshotGroups();
    if (selectedGroupId != null) {
      model.groups.removeWhere((g) => g.id == selectedGroupId);
      selectedGroupId = null;
    } else {
      for (final g in model.groups) {
        g.members.removeWhere(selectedIds.contains);
      }
    }
    final mutated = _snapshotGroups();
    _touchScene();
    _push(_Cmd(
      'Разгруппировать',
      () => _restoreGroups(mutated),
      () => _restoreGroups(snap),
    ));
    notifyListeners();
  }

  /// Drag-and-drop: moves [objId] into [groupId] (null = root). Operands
  /// consumed by a csg operation stay hidden under it and cannot be dragged
  /// into a named group (they have no independent spot in the tree).
  void moveObjectToGroup(String objId, String? groupId) {
    final model = currentModel;
    if (model == null) return;
    if (model.isCsgOperand(objId)) return;
    if (groupOf(objId)?.id == groupId) return;
    final snap = _snapshotGroups();
    for (final g in model.groups) {
      g.members.remove(objId);
    }
    if (groupId != null) {
      final target = model.groups.where((g) => g.id == groupId).firstOrNull;
      if (target != null && !target.members.contains(objId)) {
        target.members.add(objId);
      }
    }
    final mutated = _snapshotGroups();
    _touchScene();
    _push(_Cmd(
      'Переместить в группу',
      () => _restoreGroups(mutated),
      () => _restoreGroups(snap),
    ));
    notifyListeners();
  }

  /// Renames a group (undoable).
  void renameGroup(String id, String name) {
    final model = currentModel;
    if (model == null) return;
    final g = model.groups.where((g) => g.id == id).firstOrNull;
    if (g == null || name == g.name) return;
    final old = g.name;
    g.name = name;
    _push(_Cmd(
      'Имя группы',
      () => g.name = name,
      () => g.name = old,
    ));
    notifyListeners();
  }

  /// Deletes a named group; its members go to the root (one undo command).
  void deleteGroup(String id) {
    final model = currentModel;
    if (model == null) return;
    final idx = model.groups.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final g = model.groups[idx];
    model.groups.removeAt(idx);
    if (selectedGroupId == id) {
      selectedGroupId = null;
    }
    _touchScene();
    _push(_Cmd(
      'Удалить группу',
      () => currentModel!.groups.removeWhere((x) => x.id == g.id),
      () => currentModel!.groups.insert(idx, ModelGroup.copy(g)),
    ));
    notifyListeners();
  }

  /// Contextual duplicate: a selected named group duplicates the whole group
  /// (copies of members, +0.3 offset); otherwise duplicates the selected
  /// objects. Csg result nodes are deep-duplicated together with the
  /// subtree they consume (fresh operands). One undo command.
  void duplicateGroupSelection() {
    final model = currentModel;
    if (model == null) return;
    final objsSnap = [for (final o in model.objects) ModelObject.copy(o)];
    final groupsSnap = _snapshotGroups();
    final g = selectedGroup();
    final sourceIds = (g != null ? g.members : selectedIds.toList()).toSet();
    // Everything the selected csg roots own (nodes + leaves) is copied with
    // them exactly once.
    final owned = <String>{};
    for (final id in sourceIds) {
      final src = model.objectById(id);
      if (src == null || !src.isCsg) continue;
      for (final n in _csgSubtreeNodes(model, src)) {
        owned.add(n.id);
      }
      owned.addAll(model.csgLeavesOf(src.id).map((l) => l.id));
    }
    final idMap = <String, String>{};
    final copies = <ModelObject>[];
    final taken = {for (final o in model.objects) o.id};
    String freshId() {
      var n = 1;
      while (taken.contains('obj_$n')) {
        n++;
      }
      taken.add('obj_$n');
      return 'obj_$n';
    }

    for (final o in model.objects) {
      if (!sourceIds.contains(o.id) && !owned.contains(o.id)) continue;
      final copy = ModelObject.copy(o);
      final newId = freshId();
      idMap[o.id] = newId;
      copy.id = newId;
      copy.name = _nextDuplicateName(model, o.name);
      if (o.isCsg) {
        copy.operands = [
          for (final m in (o.operands ?? const <String>[]))
            idMap[m] ?? m,
        ];
      } else {
        copy.x += 0.3;
      }
      copies.add(copy);
    }
    model.objects.addAll(copies);
    ModelGroup? newGroup;
    final copyRootIds = <String>[];
    if (g != null) {
      newGroup = ModelGroup(
        id: _nextGroupId(model),
        name: '${g.name}_копия',
        members: [
          for (final mid in g.members)
            if (idMap[mid] != null) idMap[mid]!,
        ],
      );
      model.groups.add(newGroup);
      copyRootIds.addAll(newGroup.members);
    } else {
      copyRootIds.addAll([
        for (final id in sourceIds)
          if (idMap[id] != null) idMap[id]!,
      ]);
    }
    selectedGroupId = newGroup?.id;
    selectedIds
      ..clear()
      ..addAll(copyRootIds);
    selectedObjectId = copyRootIds.isEmpty ? null : copyRootIds.first;
    _touchScene();
    final objsMutated = [for (final o in model.objects) ModelObject.copy(o)];
    final groupsMutated = _snapshotGroups();
    _push(_Cmd(
      'Дублировать',
      () {
        currentModel!.objects
          ..clear()
          ..addAll([for (final o in objsMutated) ModelObject.copy(o)]);
        _restoreGroups(groupsMutated);
      },
      () {
        currentModel!.objects
          ..clear()
          ..addAll([for (final o in objsSnap) ModelObject.copy(o)]);
        _restoreGroups(groupsSnap);
        selectedIds.clear();
        selectedGroupId = null;
      },
    ));
    notifyListeners();
  }

  /// Contextual delete from the group tab: a selected named group deletes
  /// the group (members to root); otherwise deletes the selected objects.
  void deleteGroupOrSelection() {
    if (selectedGroupId != null) {
      deleteGroup(selectedGroupId!);
    } else {
      deleteSelected();
    }
  }

  // ── materials ────────────────────────────────────────────────────────

  void setMaterial(String id, {String? faceKey, ModelMaterial? material}) {
    _objectEdit(id, description: 'Материал', mutate: (o) {
      if (faceKey != null) {
        if (material == null) {
          o.faces.remove(faceKey);
        } else {
          o.faces[faceKey] = material;
        }
      } else {
        o.material = material;
      }
    });
  }

  /// Applies [material] to every selected face ('id:key' in
  /// [selectedFaces]). No-op in object mode.
  void setFacesMaterial(ModelMaterial material) {
    if (selectedFaces.isEmpty) return;
    for (final key in selectedFaces) {
      final i = key.indexOf(':');
      if (i <= 0) continue;
      final id = key.substring(0, i);
      final faceKey = key.substring(i + 1);
      _objectEdit(id, description: 'Материал', mutate: (o) {
        o.faces[faceKey] = ModelMaterial.copy(material);
      });
    }
  }

  /// Removes the material from every selected face (reset to the object's
  /// own material).
  void resetFaces() {
    if (selectedFaces.isEmpty) return;
    for (final key in selectedFaces) {
      final i = key.indexOf(':');
      if (i <= 0) continue;
      final id = key.substring(0, i);
      final faceKey = key.substring(i + 1);
      _objectEdit(id, description: 'Сброс грани', mutate: (o) {
        o.faces.remove(faceKey);
      });
    }
  }

  void resetFace(String id, String faceKey) {
    _objectEdit(id, description: 'Сброс грани', mutate: (o) {
      o.faces.remove(faceKey);
    });
  }

  // ── meta objects (Разметка) ──────────────────────────────────────────

  String _nextMetaId(ModelData model) {
    var n = 1;
    while (model.metas.any((m) => m.id == 'meta_$n')) {
      n++;
    }
    return 'meta_$n';
  }

  /// Adds a meta-object of [kind] at the virtual cursor (markup mode):
  /// `comment` — a green ball, `marker` — a flag, `box` — a blue cuboid.
  /// One undo command; the new meta becomes the selection.
  void addMeta(String kind) {
    final model = currentModel;
    if (model == null) return;
    if (kind != metaKindComment && kind != metaKindMarker && kind != metaKindBox) {
      return;
    }
    final id = _nextMetaId(model);
    final meta = ModelMeta(
      id: id,
      kind: kind,
      name: switch (kind) {
        metaKindComment => 'Комментарий',
        metaKindMarker => 'Маркер',
        _ => 'Бокс',
      },
      x: cursorX,
      y: cursorY,
      z: cursorZ,
      // A comment's bubble is collapsed by default (its «…» invites the
      // click-to-expand); markers/boxes show their short names expanded.
      collapsed: kind == metaKindComment,
      // A comment is a ball anchored at its center — lift it by the ball
      // radius when placing it on the floor so it does not sink halfway in.
      dims: kind == metaKindBox ? {'w': 1.0, 'h': 1.0, 'd': 1.0} : const {},
    );
    if (kind == metaKindComment) {
      meta.y = (cursorY + kCommentBallRadius).clamp(0.0, 128.0);
    }
    model.metas.add(meta);
    selectedMetaId = meta.id;
    _touchScene();
    _push(_Cmd(
      'Добавить ${meta.name}',
      () => currentModel!.metas.add(ModelMeta.copy(meta)),
      () {
        currentModel!.metas.removeWhere((x) => x.id == meta.id);
        if (selectedMetaId == meta.id) selectedMetaId = null;
      },
    ));
    notifyListeners();
  }

  /// One undoable edit of a meta-object ([ModelMeta] lives in [ModelData
  /// .metas]; restore is in place to keep node identity — same pattern as
  /// [_objectEdit]).
  void _metaEdit(
    String id, {
    String description = 'Изменение мета',
    required void Function(ModelMeta m) mutate,
  }) {
    final model = currentModel;
    final meta = model?.metaById(id);
    if (model == null || meta == null) return;
    final snapshot = ModelMeta.copy(meta);
    mutate(meta);
    final mutated = ModelMeta.copy(meta);
    _pushMerged(
      'meta:$id',
      description,
      () {
        final m = currentModel!.metaById(id);
        if (m != null) _restoreMetaInto(m, ModelMeta.copy(mutated));
      },
      () {
        final m = currentModel!.metaById(id);
        if (m != null) _restoreMetaInto(m, snapshot);
      },
    );
    _touchScene();
    notifyListeners();
  }

  void _restoreMetaInto(ModelMeta target, ModelMeta snapshot) {
    target.kind = snapshot.kind;
    target.name = snapshot.name;
    target.comment = snapshot.comment;
    target.x = snapshot.x;
    target.y = snapshot.y;
    target.z = snapshot.z;
    target.zIndex = snapshot.zIndex;
    target.collapsed = snapshot.collapsed;
    target.dims
      ..clear()
      ..addAll(snapshot.dims);
  }

  void setMetaName(String id, String name) =>
      _metaEdit(id, description: 'Имя мета', mutate: (m) {
        m.name = name.isEmpty ? m.id : name;
      });

  void setMetaComment(String id, String comment) =>
      _metaEdit(id, description: 'Комментарий мета', mutate: (m) {
        m.comment = comment;
      });

  void setMetaZIndex(String id, int zIndex) =>
      _metaEdit(id, description: 'Z-индекс мета', mutate: (m) {
        m.zIndex = zIndex;
      });

  void setMetaDim(String id, String key, double value) =>
      _metaEdit(id, description: 'Размер мета', mutate: (m) {
        m.setDim(key, value > 0 ? value : 0.01);
      });

  /// «Раскрыть/Схлопнуть» a meta comment bubble (a click on the bubble).
  void toggleMetaCollapsed(String id) =>
      _metaEdit(id, description: 'Раскрыть комментарий', mutate: (m) {
        m.collapsed = !m.collapsed;
      });

  void setMetaPos(String id, double x, double y, double z) =>
      _metaEdit(id, description: 'Позиция мета', mutate: (m) {
        m.x = x;
        m.y = y.clamp(0.0, 128.0);
        m.z = z;
      });

  void deleteMeta(String id) {
    final model = currentModel;
    final meta = model?.metaById(id);
    if (model == null || meta == null) return;
    final idx = model.metas.indexOf(meta);
    model.metas.remove(meta);
    if (selectedMetaId == id) selectedMetaId = null;
    _touchScene();
    _push(_Cmd(
      'Удалить мета ${meta.name}',
      () => currentModel!.metas.removeWhere((x) => x.id == meta.id),
      () => currentModel!.metas.insert(idx, ModelMeta.copy(meta)),
    ));
    notifyListeners();
  }

  void duplicateMeta() {
    final model = currentModel;
    final meta = selectedMeta();
    if (model == null || meta == null) return;
    final copy = ModelMeta.copy(meta);
    copy.id = _nextMetaId(model);
    copy.name = _nextMetaDuplicateName(model, meta.name);
    copy.x += 0.3;
    model.metas.add(copy);
    selectedMetaId = copy.id;
    _touchScene();
    _push(_Cmd(
      'Дублировать мета ${meta.name}',
      () => currentModel!.metas.add(ModelMeta.copy(copy)),
      () {
        currentModel!.metas.removeWhere((x) => x.id == copy.id);
        if (selectedMetaId == copy.id) selectedMetaId = meta.id;
      },
    ));
    notifyListeners();
  }

  String _nextMetaDuplicateName(ModelData model, String base) {
    var n = 2;
    final names = model.metas.map((m) => m.name).toSet();
    while (names.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  // ── meta gizmo drag (markup mode) ────────────────────────────────────

  ModelMeta? _dragMetaSnapshot;

  /// Snapshots the selected meta before a gizmo drag starts.
  void beginMetaGizmoDrag() {
    final meta = selectedMeta();
    _dragMetaSnapshot = meta == null ? null : ModelMeta.copy(meta);
  }

  /// Finalizes a meta gizmo drag: pushes ONE undo command when the meta
  /// moved.
  void endMetaGizmoDrag({String action = 'Перенос'}) {
    final meta = selectedMeta();
    final snap = _dragMetaSnapshot;
    _dragMetaSnapshot = null;
    if (meta == null || snap == null || meta.id != snap.id) return;
    if (meta.x == snap.x && meta.y == snap.y && meta.z == snap.z) return;
    final mutated = ModelMeta.copy(meta);
    _touchScene();
    _push(_Cmd(
      '$action мета ${meta.name}',
      () {
        final m = currentModel!.metaById(meta.id);
        if (m != null) _restoreMetaInto(m, ModelMeta.copy(mutated));
      },
      () {
        final m = currentModel!.metaById(meta.id);
        if (m != null) _restoreMetaInto(m, snap);
      },
    ));
    notifyListeners();
  }

  // ── light sources (Освещение) ─────────────────────────────────────────

  String _nextLightId(ModelData model) {
    var n = 1;
    while (model.lighting.lights.any((l) => l.id == 'light_$n')) {
      n++;
    }
    return 'light_$n';
  }

  /// Adds a light source of [kind] at the virtual cursor (lighting mode):
  /// `point` — a small colored sphere, `directional` — a sphere with an aim
  /// arrow. One undo command; the new source becomes the selection.
  void addLight(String kind) {
    final model = currentModel;
    if (model == null) return;
    if (kind != lightKindPoint && kind != lightKindDirectional) return;
    final id = _nextLightId(model);
    // Lift the gizmo anchor by the marker ball radius when placing on the
    // floor so the sphere does not sink halfway in (like the comment ball).
    final light = ModelLight(
      id: id,
      kind: kind,
      name: lightKindLabel(kind),
      x: cursorX,
      y: (cursorY + kLightBallRadius).clamp(0.0, 128.0),
      z: cursorZ,
    );
    model.lighting.lights.add(light);
    selectedLightId = light.id;
    _touchScene();
    _push(_Cmd(
      'Добавить ${light.name}',
      () => currentModel!.lighting.lights.add(ModelLight.copy(light)),
      () {
        currentModel!.lighting.lights.removeWhere((l) => l.id == light.id);
        if (selectedLightId == light.id) selectedLightId = null;
      },
    ));
    notifyListeners();
  }

  /// One undoable edit of a light source ([ModelLight] lives in
  /// [ModelLighting.lights]; restore is by whole-light snapshot, the light
  /// nodes are rebuilt from ids on every scene revision — no identity to
  /// keep).
  void _lightEdit(
    String id, {
    String description = 'Изменение света',
    required void Function(ModelLight l) mutate,
  }) {
    final model = currentModel;
    final light = model?.lighting.lightById(id);
    if (model == null || light == null) return;
    final snapshot = ModelLight.copy(light);
    mutate(light);
    final mutated = ModelLight.copy(light);
    _pushMerged(
      'light:$id',
      description,
      () {
        final m = currentModel!.lighting.lightById(id);
        if (m != null) _restoreLightInto(m, mutated);
      },
      () {
        final m = currentModel!.lighting.lightById(id);
        if (m != null) _restoreLightInto(m, snapshot);
      },
    );
    _touchScene();
    notifyListeners();
  }

  void _restoreLightInto(ModelLight target, ModelLight snapshot) {
    target.name = snapshot.name;
    target.x = snapshot.x;
    target.y = snapshot.y;
    target.z = snapshot.z;
    target.r = snapshot.r;
    target.g = snapshot.g;
    target.b = snapshot.b;
    target.intensity = snapshot.intensity;
    target.range = snapshot.range;
    target.dirX = snapshot.dirX;
    target.dirY = snapshot.dirY;
    target.dirZ = snapshot.dirZ;
  }

  void setLightName(String id, String name) =>
      _lightEdit(id, description: 'Имя источника', mutate: (l) {
        final clean = name.trim();
        l.name = clean.isEmpty ? lightKindLabel(l.kind) : clean;
      });

  /// Sets the source's color in sRGB 0..1 (the UI/JSON space; the renderer
  /// converts to the engine's linear space).
  void setLightColor(String id, double r, double g, double b) =>
      _lightEdit(id, description: 'Цвет света', mutate: (l) {
        l.r = r.clamp(0.0, 1.0);
        l.g = g.clamp(0.0, 1.0);
        l.b = b.clamp(0.0, 1.0);
      });

  void setLightIntensity(String id, double intensity) =>
      _lightEdit(id, description: 'Интенсивность света', mutate: (l) {
        l.intensity = intensity.clamp(0.0, 1000.0);
      });

  void setLightRange(String id, double range) =>
      _lightEdit(id, description: 'Дальность света', mutate: (l) {
        if (!l.isPoint) return;
        l.range = range.clamp(0.0, 1000.0);
      });

  /// Sets a directional light's aim (a world-space vector; it is normalized
  /// for storage — a null vector keeps the current aim).
  void setLightDirection(String id, double dx, double dy, double dz) =>
      _lightEdit(id, description: 'Направление света', mutate: (l) {
        if (!l.isDirectional) return;
        final len = (dx * dx + dy * dy + dz * dz);
        if (len < 1e-12) return;
        final inv = 1.0 / math.sqrt(len);
        l.dirX = dx * inv;
        l.dirY = dy * inv;
        l.dirZ = dz * inv;
      });

  void setLightPos(String id, double x, double y, double z) =>
      _lightEdit(id, description: 'Позиция источника', mutate: (l) {
        l.x = x;
        l.y = y.clamp(0.0, 128.0);
        l.z = z;
      });

  void deleteLight(String id) {
    final model = currentModel;
    final light = model?.lighting.lightById(id);
    if (model == null || light == null) return;
    final idx = model.lighting.lights.indexOf(light);
    model.lighting.lights.remove(light);
    if (selectedLightId == id) selectedLightId = null;
    _touchScene();
    _push(_Cmd(
      'Удалить ${light.name}',
      () => currentModel!.lighting.lights.removeWhere((l) => l.id == light.id),
      () => currentModel!.lighting.lights.insert(idx, ModelLight.copy(light)),
    ));
    notifyListeners();
  }

  void duplicateLight() {
    final model = currentModel;
    final light = selectedLight();
    if (model == null || light == null) return;
    final copy = ModelLight.copy(light);
    copy.id = _nextLightId(model);
    copy.name = _nextLightDuplicateName(model, light.name);
    copy.x += 0.3;
    copy.z += 0.3;
    model.lighting.lights.add(copy);
    selectedLightId = copy.id;
    _touchScene();
    _push(_Cmd(
      'Дублировать ${light.name}',
      () => currentModel!.lighting.lights.add(ModelLight.copy(copy)),
      () {
        currentModel!.lighting.lights.removeWhere((l) => l.id == copy.id);
        if (selectedLightId == copy.id) selectedLightId = light.id;
      },
    ));
    notifyListeners();
  }

  String _nextLightDuplicateName(ModelData model, String base) {
    var n = 2;
    final names = model.lighting.lights.map((l) => l.name).toSet();
    while (names.contains('${base}_$n')) {
      n++;
    }
    return '${base}_$n';
  }

  // ── light gizmo drag (lighting mode) ─────────────────────────────────

  ModelLight? _dragLightSnapshot;

  /// Snapshots the selected light before a gizmo drag starts (move or aim).
  void beginLightGizmoDrag() {
    final light = selectedLight();
    _dragLightSnapshot = light == null ? null : ModelLight.copy(light);
  }

  /// Finalizes a light gizmo drag: pushes ONE undo command when the source
  /// actually moved or turned.
  void endLightGizmoDrag({String action = 'Перенос'}) {
    final light = selectedLight();
    final snap = _dragLightSnapshot;
    _dragLightSnapshot = null;
    if (light == null || snap == null || light.id != snap.id) return;
    final moved = light.x != snap.x ||
        light.y != snap.y ||
        light.z != snap.z ||
        light.dirX != snap.dirX ||
        light.dirY != snap.dirY ||
        light.dirZ != snap.dirZ;
    if (!moved) return;
    final mutated = ModelLight.copy(light);
    _touchScene();
    _push(_Cmd(
      '$action ${light.name}',
      () {
        final l = currentModel!.lighting.lightById(light.id);
        if (l != null) _restoreLightInto(l, ModelLight.copy(mutated));
      },
      () {
        final l = currentModel!.lighting.lightById(light.id);
        if (l != null) _restoreLightInto(l, snap);
      },
    ));
    notifyListeners();
  }

  // ── scene lighting settings (lighting mode) ──────────────────────────

  /// One undoable edit of the whole [ModelLighting] config (scene knobs).
  /// Restores by fresh copies — light nodes rebuild from ids on every
  /// scene revision.
  void _lightingEdit(
    String mergeKey,
    String description,
    void Function(ModelLighting cfg) mutate,
  ) {
    final model = currentModel;
    if (model == null) return;
    final snapshot = ModelLighting.copy(model.lighting);
    mutate(model.lighting);
    final mutated = ModelLighting.copy(model.lighting);
    _pushMerged(
      mergeKey,
      description,
      () => currentModel!.lighting = ModelLighting.copy(mutated),
      () => currentModel!.lighting = ModelLighting.copy(snapshot),
    );
    _touchScene();
    notifyListeners();
  }

  /// Global ambient light: the IBL environment intensity (0 = analytic
  /// sources only, 1 = the engine default, up to 2+).
  void setLightingAmbient(double ambient) =>
      _lightingEdit('lighting-ambient', 'Глобальное освещение', (cfg) {
        cfg.ambient = ambient.clamp(0.0, 4.0);
      });

  /// Hides/shows the light-source gizmos in the lighting mode.
  void setLightingGizmos(bool gizmos) =>
      _lightingEdit('lighting-gizmos', 'Гизмо источников', (cfg) {
        cfg.gizmos = gizmos;
        if (!gizmos) selectedLightId = null;
      });

  /// Enables/disables shadow casting (directional sources cast shadows; the
  /// default editor key light casts them too when no custom lights exist).
  void setLightingShadows(bool shadows) =>
      _lightingEdit('lighting-shadows', 'Тени', (cfg) {
        cfg.shadows = shadows;
      });

  /// Enables/disables screen-space ambient occlusion.
  void setLightingSsao(bool ssao) =>
      _lightingEdit('lighting-ssao', 'SSAO', (cfg) {
        cfg.ssao = ssao;
      });

  // ── selection ────────────────────────────────────────────────────────

  /// Selects every object of the current model (same semantics as
  /// [selectObject]: primary = first object, named group and faces cleared).
  void selectAllObjects() {
    final model = currentModel;
    if (model == null || model.objects.isEmpty) return;
    selectedGroupId = null;
    selectedObjectId = model.objects.first.id;
    selectedIds
      ..clear()
      ..addAll([for (final o in model.objects) o.id]);
    selectedFaceKey = null;
    selectedFaces.clear();
    notifyListeners();
  }

  void selectObject(String? id, {String? faceKey, bool shift = false}) {
    final previousId = selectedObjectId;
    if (shift) {
      if (id == null) {
        // Shift-click on empty keeps the group.
        return;
      }
      selectedGroupId = null;
      if (selectedIds.contains(id)) {
        // Toggle off; the primary falls back to the last remaining object.
        selectedIds.remove(id);
        if (selectedObjectId == id) {
          selectedObjectId = selectedObjects().isEmpty
              ? null
              : selectedObjects().last.id;
        }
      } else {
        selectedIds.add(id);
        selectedObjectId = id;
      }
      if (selectedIds.length > 1) selectedFaceKey = null;
    } else {
      selectedGroupId = null;
      selectedObjectId = id;
      selectedIds
        ..clear()
        ..addAll(id == null ? const [] : [id]);
      selectedFaceKey = faceKey;
    }
    // Object selection is mutually exclusive with face selection.
    selectedFaces.clear();
    // Смена объекта выходит из правки многогранника: режим по умолчанию —
    // «объект», подвыделения сбрасываются.
    if (selectedObjectId != previousId) {
      polyEditMode = PolyEditMode.object;
      selectedVertexIndices.clear();
      activeVertexIndex = null;
      polyAddVertexArmed = false;
    }
    notifyListeners();
  }

  /// Face-mode selection (texture submode = faces). Shift-click on an
  /// already-selected face removes it (toggle), so a mistaken face can be
  /// un-picked without reselecting. [selectedIds] mirrors the objects that
  /// have at least one selected face.
  void selectFace(String id, String faceKey, {bool shift = false}) {
    selectedGroupId = null;
    final key = '$id:$faceKey';
    if (shift) {
      if (selectedFaces.contains(key)) {
        selectedFaces.remove(key);
        if (selectedObjectId == id && selectedFaceKey == faceKey) {
          // Primary fell off — fall back to any remaining face.
          _repickPrimaryFace();
        }
      } else {
        selectedFaces.add(key);
        selectedObjectId = id;
        selectedFaceKey = faceKey;
      }
    } else {
      selectedFaces
        ..clear()
        ..add(key);
      selectedObjectId = id;
      selectedFaceKey = faceKey;
    }
    _syncFaceObjectIds();
    notifyListeners();
  }

  /// Selects every face of one object; with [shift] toggles them (all
  /// currently selected → cleared). Used by the objects tree in the faces
  /// submode.
  void selectAllFaces(String id, {bool shift = false}) {
    final obj = _findObject(id);
    if (obj == null) return;
    selectedGroupId = null;
    final keys = {for (final f in facesOf(obj)) '$id:$f'};
    if (shift) {
      final allSelected = keys.every(selectedFaces.contains);
      if (allSelected) {
        selectedFaces.removeAll(keys);
        _repickPrimaryFace();
      } else {
        selectedFaces.addAll(keys);
        selectedObjectId = id;
        selectedFaceKey = facesOf(obj).isNotEmpty ? facesOf(obj).first : null;
      }
    } else {
      selectedFaces
        ..clear()
        ..addAll(keys);
      selectedObjectId = id;
      selectedFaceKey = facesOf(obj).isNotEmpty ? facesOf(obj).first : null;
    }
    _syncFaceObjectIds();
    notifyListeners();
  }

  void _repickPrimaryFace() {
    if (selectedFaces.isEmpty) {
      selectedObjectId = null;
      selectedFaceKey = null;
      return;
    }
    final first = selectedFaces.first;
    final i = first.indexOf(':');
    selectedObjectId = first.substring(0, i);
    selectedFaceKey = first.substring(i + 1);
  }

  void _syncFaceObjectIds() {
    selectedIds
      ..clear()
      ..addAll({
        for (final k in selectedFaces)
          if (k.indexOf(':') > 0) k.substring(0, k.indexOf(':')),
      });
  }

  /// Switches the texture submode; the selection converts between objects
  /// and faces on the way.
  void setTexSubmode(TexSubmode m) {
    if (texSubmode == m) return;
    texSubmode = m;
    if (m == TexSubmode.faces) {
      _objectsToFaces();
    } else {
      _facesToObjects();
    }
    notifyListeners();
  }

  /// Every face of every selected object becomes selected.
  void _objectsToFaces() {
    final model = currentModel;
    if (model == null) return;
    selectedFaces
      ..clear()
      ..addAll({
        for (final id in selectedIds)
          for (final o in model.objects)
            if (o.id == id)
              for (final f in facesOf(o)) '$id:$f',
      });
    _repickPrimaryFace();
    _syncFaceObjectIds();
  }

  /// Objects with at least one selected face become selected; face
  /// selection is cleared.
  void _facesToObjects() {
    selectedFaces.clear();
    selectedFaceKey = null;
  }

  /// Mode switch: compose ↔ texture ↔ lighting ↔ markup. Object/face
  /// selections keep their semantics between compose and markup (both are
  /// object-oriented editor modes); the texture mode converts per its
  /// submode. The lighting mode edits light sources only — entering it drops
  /// the object/group selection (its panel shows the scene lighting
  /// settings), leaving it drops the light selection. The armed face snap is
  /// compose-only.
  void setMode(EditorMode m) {
    if (mode == m) return;
    final leavingLighting = mode == EditorMode.lighting;
    mode = m;
    selectedFaceKey = null;
    // The armed face snap is compose-only.
    faceSnapMode = null;
    if (m == EditorMode.texture && texSubmode == TexSubmode.faces) {
      _objectsToFaces();
    } else if (m == EditorMode.compose) {
      _facesToObjects();
    } else {
      selectedFaces.clear();
    }
    if (leavingLighting) selectedLightId = null;
    if (m == EditorMode.lighting) {
      selectObject(null);
      selectedGroupId = null;
    }
    notifyListeners();
  }

  /// Registered by the viewport: moves the camera to look at an object.
  void Function(ModelObject obj)? onFocusObject;

  /// Registered by the viewport: moves the camera to look at a meta-object.
  void Function(ModelMeta meta)? onFocusMeta;

  /// Registered by the viewport: moves the camera to look at a light source.
  void Function(ModelLight light)? onFocusLight;

  void requestFocusObject(String id) {
    final obj = _findObject(id);
    if (obj == null) return;
    onFocusObject?.call(obj);
  }

  void requestFocusMeta(String id) {
    final meta = currentModel?.metaById(id);
    if (meta == null) return;
    onFocusMeta?.call(meta);
  }

  void requestFocusLight(String id) {
    final light = currentModel?.lighting.lightById(id);
    if (light == null) return;
    onFocusLight?.call(light);
  }

  void setCursor(double x, double y, double z) {
    cursorX = x;
    cursorY = y;
    cursorZ = z;
    notifyListeners();
  }

  void setSnapStep(double step) {
    if (snapStep == step) return;
    snapStep = step;
    notifyListeners();
  }

  /// Resource click from the left panel: in texture mode assigns the
  /// texture/sprite to the selected object/faces; in compose mode adds a
  /// sprite object at the cursor.
  void pickResource(String type, String name) {
    if (mode == EditorMode.texture) {
      final obj = selectedObject();
      if (obj == null) return;
      final mat = ModelMaterial(
        type: type == 'sprite' ? MaterialType.sprite : MaterialType.texture,
        key: name,
        stretch: type == 'texture' ? 'tile' : 'stretch',
      );
      if (texSubmode == TexSubmode.faces && selectedFaces.isNotEmpty) {
        setFacesMaterial(mat);
      } else {
        setMaterial(obj.id, faceKey: null, material: mat);
      }
      return;
    }
    if (mode == EditorMode.compose && type == 'sprite') {
      addObject('sprite', spriteKey: name);
    }
  }

  // ── undo / redo ──────────────────────────────────────────────────────

  void _push(_Cmd cmd) {
    final model = currentModel;
    if (model == null) return;
    model.dirty = true;
    final undo = _undoStacks.putIfAbsent(model.id, () => []);
    undo.add(cmd);
    if (undo.length > _undoLimit) undo.removeAt(0);
    _redoStacks[model.id]?.clear();
  }

  /// Pushes a command, merging it with the previous one of the same
  /// [mergeKey] within a short window (rapid +/− clicks collapse into a
  /// single undo step; the undo always restores the pre-drag state).
  void _pushMerged(
    String mergeKey,
    String description,
    void Function() apply,
    void Function() undo,
  ) {
    final model = currentModel;
    if (model == null) return;
    final stack = _undoStacks.putIfAbsent(model.id, () => []);
    final now = DateTime.now();
    if (stack.isNotEmpty) {
      final last = stack.last;
      if (last.mergeKey == mergeKey &&
          now.difference(last.time) < const Duration(milliseconds: 1000)) {
        // Merge: keep the PREVIOUS command's undo (it restores the
        // original pre-drag state), refresh the apply with the new state.
        stack.removeLast();
        model.dirty = true;
        _redoStacks[model.id]?.clear();
        stack.add(_Cmd(description, apply, last.undo, mergeKey: mergeKey));
        return;
      }
    }
    _push(_Cmd(description, apply, undo, mergeKey: mergeKey));
  }

  void undo() {
    final model = currentModel;
    if (model == null) return;
    final stack = _undoStacks[model.id];
    if (stack == null || stack.isEmpty) return;
    final cmd = stack.removeLast();
    cmd.undo();
    (_redoStacks[model.id] ??= []).add(cmd);
    model.dirty = true;
    _touchScene();
    notifyListeners();
  }

  void redo() {
    final model = currentModel;
    if (model == null) return;
    final stack = _redoStacks[model.id];
    if (stack == null || stack.isEmpty) return;
    final cmd = stack.removeLast();
    cmd.apply();
    (_undoStacks[model.id] ??= []).add(cmd);
    model.dirty = true;
    _touchScene();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    _resources?.dispose();
    _model3d?.removeListener(_onModel3dChanged);
    _model3d?.dispose();
    super.dispose();
  }
}
