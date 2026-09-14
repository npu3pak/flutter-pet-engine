import 'package:flutter/material.dart';

import '../scene/editor_scene.dart';
import '../scene/light_renderer.dart' show lightAnglesToDir, lightDirToAngles;
import '../state/app_state.dart';
import 'form_fields.dart';
import 'gltf_ref_dialog.dart';
import 'light_color_dialog.dart';
import 'model_ref_dialog.dart';
import 'resource_picker.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:pet_engine_v2/models.dart' as cs;
import 'package:vector_math/vector_math.dart' as vm;

class RightPanel extends StatefulWidget {
  final AppState app;
  const RightPanel({super.key, required this.app});

  @override
  State<RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<RightPanel> {
  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final model = app.currentModel;
    return ColoredBox(
      color: const Color(0xFF262B34),
      child: model == null
          ? const Center(
              child: Text(
                'Создайте или выберите модель',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : _contextPanel(model),
    );
  }

  /// The panel is fully context-dependent — exactly one section is shown:
  /// a light source or the scene settings (lighting mode), a meta-object
  /// (markup mode), a group (multi-selection or a named group), a single
  /// object, or the model settings when nothing is selected.
  Widget _contextPanel(cs.ModelData model) {
    // The lighting mode edits light sources first; without a selection the
    // panel shows the scene lighting knobs (ambient, gizmos, shadows, SSAO).
    if (app.mode == EditorMode.lighting) {
      final light = app.selectedLight();
      if (light != null) {
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [_LightPanel(app: app, light: light, model: model)],
        );
      }
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [_LightingSettingsPanel(app: app, model: model)],
      );
    }
    // The markup mode edits meta-objects first (an object may stay selected
    // underneath — a meta takes the panel while it is selected).
    if (app.mode == EditorMode.markup) {
      final meta = app.selectedMeta();
      if (meta != null) {
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [_MetaPanel(app: app, meta: meta, model: model)],
        );
      }
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [
          const SectionTitle('Разметка'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Инструменты на верхней панели добавляют мета-объекты '
              '(комментарий, маркер, бокс) в позицию курсора. '
              'Кликните мета-объект на сцене, чтобы выбрать его.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          _SceneFieldsPanel(app: app, model: model),
        ],
      );
    }
    // Groups are a compose-mode concept: in the texture mode the selection
    // (objects or faces) always edits materials.
    if (app.mode == EditorMode.compose && app.showGroupTab) {
      return _GroupPanel(app: app);
    }
    if (app.mode == EditorMode.texture) {
      // The texture panel (with the Объекты/Грани toggle) is always shown —
      // the toggle must stay reachable even without a selection.
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [_TexturePanel(app: app, model: model)],
      );
    }
    final obj = app.selectedObject();
    if (obj != null) {
      return ListView(
        padding: const EdgeInsets.all(10),
        children: [
          if (obj.isCsg)
            _CsgProperties(app: app, obj: obj)
          else if (obj.isModelRef)
            _ModelRefProperties(app: app, obj: obj)
          else if (obj.isGltfRef)
            _GltfRefProperties(app: app, obj: obj)
          else if (obj.isPolyhedron)
            _PolyhedronProperties(app: app, obj: obj)
          else
            _ObjectProperties(app: app, obj: obj),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [_ModelSettings(app: app, model: model)],
    );
  }
}

// ── Группа ─────────────────────────────────────────────────────────────

class _GroupPanel extends StatelessWidget {
  final AppState app;
  const _GroupPanel({required this.app});

  @override
  Widget build(BuildContext context) {
    final center = app.groupCenter();
    final group = app.selectedGroup();
    final mat = app.selectedObjects().isEmpty
        ? cs.ModelMaterial()
        : app.selectedObjects().first.material ?? cs.ModelMaterial();
    final keys = _familyFiles(
      app,
      mat.type == cs.MaterialType.sprite ? 'sprite' : 'texture',
    );
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        const SectionTitle('Группа'),
        Text(
          group != null
              ? 'Группа «${group.name}» · ${app.selectedCount} об.'
              : 'Выбрано: ${app.selectedCount}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        if (group != null) ...[
          const SizedBox(height: 8),
          const _PanelLabel('Название группы'),
          NameField(
            initial: group.name,
            onChanged: (v) => app.renameGroup(group.id, v),
          ),
        ],
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: app.hasGroupedSelection
                  ? app.ungroupSelection
                  : app.createGroup,
              icon: Icon(
                app.hasGroupedSelection ? Icons.group_remove : Icons.group_add,
                size: 15,
              ),
              label: Text(
                app.hasGroupedSelection ? 'Разгруппировать' : 'Сгруппировать',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: app.duplicateGroupSelection,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: app.deleteGroupOrSelection,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        // Boolean operations: combining two root-level solid objects.
        if (app.mode == EditorMode.compose &&
            app.selectedCount == 2 &&
            group == null) ...[
          const SizedBox(height: 14),
          const SectionTitle('Операции'),
          if (app.canCombineSelection)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (op, label) in const [
                  (cs.csgOpUnion, 'Объединение'),
                  (cs.csgOpDifference, 'Вычитание'),
                  (cs.csgOpIntersect, 'Пересечение'),
                ])
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => app.createCsgOperation(op),
                    child: Text(label, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            )
          else
            const Text(
              'Доступно для двух твёрдых объектов вне групп и операций',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
        if (app.mode == EditorMode.compose) ...[
          const SizedBox(height: 14),
          const SectionTitle('Координаты центра группы'),
          Row(
            children: [
              for (final (key, value) in [
                ('X', center == null ? 0.0 : center.$1),
                ('Y', center == null ? 0.0 : center.$2),
                ('Z', center == null ? 0.0 : center.$3),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DoubleField(
                      initial: value,
                      step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                      onChanged: (v) {
                        final c = app.groupCenter();
                        if (c == null) return;
                        final (cx, cy, cz) = c;
                        app.moveGroup(
                          key == 'X' ? v - cx : 0,
                          key == 'Y' ? v - cy : 0,
                          key == 'Z' ? v - cz : 0,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 14),
          const SectionTitle('Материал группы'),
          _GroupMaterialEditor(app: app, mat: mat, keys: keys),
        ],
      ],
    );
  }
}

/// Compact material editor that applies to every selected object.
class _GroupMaterialEditor extends StatelessWidget {
  final AppState app;
  final cs.ModelMaterial mat;
  final List<String> keys;
  const _GroupMaterialEditor({
    required this.app,
    required this.mat,
    required this.keys,
  });

  void _set(cs.ModelMaterial m) {
    app.setGroupMaterial(m);
  }

  @override
  Widget build(BuildContext context) {
    final root = app.project?.directory?.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelLabel('Тип'),
        SegmentedButton<cs.MaterialType>(
          showSelectedIcon: false,
          style: appSegmentedStyle(),
          segments: const [
            ButtonSegment(value: cs.MaterialType.texture, label: Text('Текстура')),
            ButtonSegment(value: cs.MaterialType.sprite, label: Text('Спрайт')),
            ButtonSegment(value: cs.MaterialType.color, label: Text('Цвет')),
          ],
          selected: {mat.type},
          onSelectionChanged: (s) {
            final t = s.first;
            _set(cs.ModelMaterial.copy(mat)
              ..type = t
              ..key = t == cs.MaterialType.color ? '' : mat.key);
          },
        ),
        if (mat.type != cs.MaterialType.color) ...[
          const SizedBox(height: 8),
          const _PanelLabel('Файл'),
          ResourcePicker(
            files: keys,
            rootDir: root == null
                ? ''
                : '$root/${mat.type == cs.MaterialType.sprite ? 'sprites' : 'textures'}',
            selected: validFileKey(mat.type, mat.key, app),
            onPick: (k) => _set(cs.ModelMaterial.copy(mat)..key = k),
          ),
        ],
        if (mat.type == cs.MaterialType.color) ...[
          const SizedBox(height: 8),
          const _PanelLabel('Цвет'),
          Row(
            children: [
              for (final c in _colorPresets)
                InkWell(
                  onTap: () => _set(cs.ModelMaterial.copy(mat)..color = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, c[0], c[1], c[2]),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        const _PanelLabel('Сторона грани'),
        Row(
          children: [
            Checkbox(
              value: mat.side != 'inner',
              onChanged: (v) => _setSide(mat, v == true, mat.side == 'both'),
            ),
            const Text('Внешняя', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 16),
            Checkbox(
              value: mat.side != 'outer',
              onChanged: (v) => _setSide(mat, mat.side == 'both', v == true),
            ),
            const Text('Внутренняя', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Применяется к материалу каждого выбранного объекта целиком',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  void _setSide(cs.ModelMaterial m, bool outer, bool inner) {
    if (!outer && !inner) return;
    final side = outer && inner ? 'both' : (outer ? 'outer' : 'inner');
    if (side == m.side) return;
    _set(cs.ModelMaterial.copy(m)..side = side);
  }
}

class _PanelLabel extends StatelessWidget {
  final String text;
  const _PanelLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      );
}

/// Toggle button for the face-snap tools: armed (highlighted) while the
/// operation waits for a face click in the scene; a re-click cancels it.
class _FaceSnapButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  const _FaceSnapButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? appSegSelected : null,
          foregroundColor: active ? Colors.white : null,
          side: BorderSide(
            color: active ? appSegSelected : const Color(0xFF3A4250),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Hint shown under an armed snap button: the next scene click is consumed
/// by the operation.
class _SnapHint extends StatelessWidget {
  const _SnapHint();

  @override
  Widget build(BuildContext context) => const Text(
        'Кликните грань в сцене · Esc — отмена',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      );
}

// ── Результат операции (csg) ───────────────────────────────────────────

class _CsgProperties extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  const _CsgProperties({required this.app, required this.obj});

  String _opLabel() => switch (obj.op) {
        cs.csgOpDifference => 'Вычитание',
        cs.csgOpIntersect => 'Пересечение',
        _ => 'Объединение',
      };

  @override
  Widget build(BuildContext context) {
    final ops = obj.operands ?? const <String>[];
    final a = ops.isNotEmpty ? app.currentModel?.objectById(ops[0]) : null;
    final b = ops.length > 1 ? app.currentModel?.objectById(ops[1]) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF3A4250)),
        const SectionTitle('Результат операции'),
        _label('Название'),
        NameField(initial: obj.name, onChanged: (v) => app.setObjectName(obj.id, v)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(switch (obj.op) {
              cs.csgOpDifference => Icons.remove,
              cs.csgOpIntersect => Icons.compare,
              _ => Icons.add,
            }, size: 18, color: const Color(0xFF9FB4C7)),
            const SizedBox(width: 8),
            Text(
              '${_opLabel()} — ${a?.name ?? '?'} ${_opSymbol()} ${b?.name ?? '?'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Исходники скрыты в сцене: редактируйте их в дереве слева '
          '(позиция, размер, материал) — результат пересчитывается.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        for (final (operand, idx) in [(a, 0), (b, 1)]) ...[
          if (idx == 1) const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: operand == null
                ? null
                : () => app.selectObject(operand.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF303947),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3A4250)),
              ),
              child: Row(
                children: [
                  Text(idx == 0 ? 'А' : 'Б',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      operand == null ? 'нет объекта' : '${operand.name} · ${operand.kind}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Icon(Icons.touch_app, size: 14, color: Colors.white38),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => app.swapCsgOperands(obj.id),
          icon: const Icon(Icons.swap_horiz, size: 15),
          label: const Text('Поменять местами', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF3A4250)),
        const _PanelLabel('Материал результата'),
        const Text(
          'Если задан — перекрывает поверхности результата; иначе каждая '
          'поверхность наследует материал исходной грани.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        MaterialEditor(app: app, obj: obj, faceKey: null, compact: true),
        if (obj.material != null)
          TextButton(
            onPressed: () => app.setMaterial(obj.id, material: null),
            child: const Text('Убрать материал результата', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => app.convertToPolyhedron(obj.id),
              icon: const Icon(Icons.polyline, size: 15),
              label: const Text('Преобразовать в многогранник'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать (с исходниками)'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => app.deleteObject(obj.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить (разобрать)'),
            ),
          ],
        ),
      ],
    );
  }

  String _opSymbol() => switch (obj.op) {
        cs.csgOpDifference => '−',
        cs.csgOpIntersect => '∩',
        _ => '∪',
      };

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(
          t,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      );
}

// ── Настройки модели ──────────────────────────────────────────────────

class _ModelSettings extends StatelessWidget {
  final AppState app;
  final cs.ModelData model;
  const _ModelSettings({required this.app, required this.model});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Модель'),
        _label('Имя'),
        NameField(initial: model.name, onChanged: app.setModelName),
        const SizedBox(height: 8),
        _label('Размер (клетки): ширина × длина × высота'),
        Row(
          children: [
            for (final (key, value, min, max) in [
              // Лимиты согласованы с model_v1 (карты 1:1 больше легаси-сетки).
              ('w', model.size.w, 1, 16384),
              ('l', model.size.l, 1, 16384),
              ('h', model.size.h, 1, 4096),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IntField(
                    initial: value,
                    min: min,
                    max: max,
                    onChanged: (v) {
                      final w = key == 'w' ? v : model.size.w;
                      final l = key == 'l' ? v : model.size.l;
                      final h = key == 'h' ? v : model.size.h;
                      app.setModelSize(w, l, h);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(
          t,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      );
}

/// File names (with `.png`) of one resource family for the pickers. The
/// app's [ResourceStore] is authoritative (it follows imports/renames);
/// the engine catalog is a fallback while the store is still scanning.
List<String> _familyFiles(AppState app, String family) {
  if (app.project == null) return const [];
  final local = [
    for (final i in app.resources.items)
      if (i.family == family) '${i.name}.png',
  ];
  if (local.isNotEmpty) return local;
  final keys = family == 'sprite'
      ? app.controller.resources?.spriteKeys
      : app.controller.resources?.textureKeys;
  return [for (final k in keys ?? const <String>[]) '$k.png'];
}

/// Returns [key] when it exists in the file list for [type] (textures for
/// `texture`, sprites for `sprite`), otherwise null. Guards the file
/// dropdown: its value must always be present among its items.
String? validFileKey(cs.MaterialType type, String key, AppState? app) {
  if (key.isEmpty) return null;
  if (type == cs.MaterialType.color || app == null) return null;
  final list = _familyFiles(
    app,
    type == cs.MaterialType.sprite ? 'sprite' : 'texture',
  );
  return list.contains(key) ? key : null;
}

class _ObjectProperties extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  const _ObjectProperties({required this.app, required this.obj});

  @override
  Widget build(BuildContext context) {
    final dimFields = _dimFields(obj);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF3A4250)),
        const SectionTitle('Объект'),
        NameField(initial: obj.name, onChanged: (v) => app.setObjectName(obj.id, v)),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text(
                'Wireframe',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Switch(
              key: const Key('object-wireframe'),
              value: app.objectWireframe(obj.id),
              onChanged: (v) => app.setObjectWireframe(obj.id, v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _label('Позиция (центр основания)'),
        Row(
          children: [
            for (final (key, value) in [
              ('X', obj.x),
              ('Y', obj.y),
              ('Z', obj.z),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoubleField(
                    initial: value,
                    step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                    onChanged: (v) => app.setObjectPos(
                      obj.id,
                      key == 'X' ? v : obj.x,
                      key == 'Y' ? v : obj.y,
                      key == 'Z' ? v : obj.z,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _FaceSnapButton(
          label: 'Перенести к грани',
          icon: Icons.arrow_downward,
          active: app.faceSnapMode == FaceSnapMode.moveToFace,
          onPressed: () => app.setFaceSnapMode(
            app.faceSnapMode == FaceSnapMode.moveToFace
                ? null
                : FaceSnapMode.moveToFace,
          ),
        ),
        if (app.faceSnapMode == FaceSnapMode.moveToFace) ...[
          const SizedBox(height: 4),
          const _SnapHint(),
        ],
        const SizedBox(height: 8),
        // Sprites are always billboards (face the camera) — rotation is
        // ignored. Solids rotate around the anchor as Rz·Rx·Ry; the fields
        // give exact degree input like the position fields.
        if (obj.kind != 'sprite') ...[
          _label('Поворот (градусы)'),
          Row(
            children: [
              for (final (key, value) in [
                ('X', obj.rotX),
                ('Y', obj.rotY),
                ('Z', obj.rotZ),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DoubleField(
                      initial: value,
                      step: 5,
                      onChanged: (v) => app.setObjectRot(
                        obj.id,
                        key == 'X' ? v : obj.rotX,
                        key == 'Y' ? v : obj.rotY,
                        key == 'Z' ? v : obj.rotZ,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _FaceSnapButton(
            label: 'Параллельно грани',
            icon: Icons.flip,
            active: app.faceSnapMode == FaceSnapMode.parallelToFace,
            onPressed: () => app.setFaceSnapMode(
              app.faceSnapMode == FaceSnapMode.parallelToFace
                  ? null
                  : FaceSnapMode.parallelToFace,
            ),
          ),
          if (app.faceSnapMode == FaceSnapMode.parallelToFace) ...[
            const SizedBox(height: 4),
            const _SnapHint(),
          ],
        ],
        for (final (key, label) in dimFields)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
                Expanded(
                  child: DoubleField(
                    initial: obj.dim(key, 1),
                    step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                    onChanged: (v) => app.setObjectDim(obj.id, key, v),
                  ),
                ),
              ],
            ),
          ),
        if (obj.kind == 'cuboid') ...[
          const SizedBox(height: 8),
          if (obj.dim('roundR', 0) <= 0)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(34),
              ),
              onPressed: () => app.enableCuboidRound(obj.id),
              icon: const Icon(Icons.rounded_corner, size: 16),
              label: const Text('Скруглить углы'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const SizedBox(
                      width: 90,
                      child: Text('Радиус',
                          style: TextStyle(color: Colors.white54, fontSize: 12))),
                  Expanded(
                    child: DoubleField(
                      initial: obj.dim('roundR', 0),
                      step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                      // Промежуточный «0» при вводе («0.15») не выключает
                      // скругление — выключение кнопкой ниже.
                      onChanged: (v) {
                        if (v != 0) {
                          app.setObjectDim(obj.id, 'roundR', v);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const SizedBox(
                      width: 90,
                      child: Text('Сегменты',
                          style: TextStyle(color: Colors.white54, fontSize: 12))),
                  Expanded(
                    child: IntField(
                      initial: cs.cuboidRoundSegments(obj),
                      min: 3,
                      max: 64,
                      onChanged: (v) =>
                          app.setObjectDim(obj.id, 'roundSegments', v.toDouble()),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(34),
                ),
                onPressed: () => app.disableCuboidRound(obj.id),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Убрать скругление'),
              ),
            ),
          ],
        ],
        if (obj.kind == 'plane') ...[
          const SizedBox(height: 8),
          _label('Ориентация'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: appSegmentedStyle(),
            segments: const [
              ButtonSegment(value: 'horizontal', label: Text('Горизонтальная')),
              ButtonSegment(value: 'vertical', label: Text('Вертикальная')),
            ],
            selected: {obj.flag('vertical') ? 'vertical' : 'horizontal'},
            onSelectionChanged: (s) =>
                app.setObjectFlag(obj.id, 'vertical', s.first == 'vertical'),
          ),
        ],
        if (obj.kind == 'sprite') ...[
          if (obj.material != null)
            MaterialEditor(app: app, obj: obj, faceKey: null, compact: true),
        ],
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => app.convertToPolyhedron(obj.id),
              icon: const Icon(Icons.polyline, size: 15),
              label: const Text('Преобразовать в многогранник'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => app.deleteObject(obj.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (obj.material != null || (obj.faces.isNotEmpty && obj.kind != 'sprite'))
          const Text(
            'Материал — в режиме «Текстурирование»',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
      ],
    );
  }

  List<(String, String)> _dimFields(cs.ModelObject obj) {
    switch (obj.kind) {
      case 'cuboid':
        return [('w', 'Ширина'), ('h', 'Высота'), ('d', 'Глубина')];
      case 'trapezoid':
        return [
          ('bottomW', 'Низ, ширина'),
          ('bottomD', 'Низ, глубина'),
          ('topW', 'Верх, ширина'),
          ('topD', 'Верх, глубина'),
          ('h', 'Высота'),
        ];
      case 'cylinder':
        return [
          ('bottomR', 'Радиус низ'),
          ('topR', 'Радиус верх'),
          ('h', 'Высота'),
          ('segments', 'Грани'),
        ];
      case 'plane':
        return [
          ('w', 'Ширина'),
          ('d', obj.flag('vertical') ? 'Высота' : 'Длина'),
        ];
      case 'sprite':
        return [('w', 'Ширина'), ('h', 'Высота')];
      default:
        return const [];
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );
}

// ── Многогранник ──────────────────────────────────────────────────────

/// Свойства многогранника: режим правки (объект/грани/вершины), масштаб по
/// осям и операции над гранями/вершинами. Материалы граней редактируются в
/// режиме «Текстурирование» (клик по грани выбирает её материал).
class _PolyhedronProperties extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  const _PolyhedronProperties({required this.app, required this.obj});

  @override
  Widget build(BuildContext context) {
    final mesh = obj.mesh;
    final mode = app.polyEditMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF3A4250)),
        const SectionTitle('Многогранник'),
        NameField(
          initial: obj.name,
          onChanged: (v) => app.setObjectName(obj.id, v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 90,
              child: Text(
                'Wireframe',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Switch(
              key: const Key('object-wireframe'),
              value: app.objectWireframe(obj.id),
              onChanged: (v) => app.setObjectWireframe(obj.id, v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _label('Режим правки'),
        SegmentedButton<PolyEditMode>(
          showSelectedIcon: false,
          style: appSegmentedStyle(),
          segments: const [
            ButtonSegment(value: PolyEditMode.object, label: Text('Объект')),
            ButtonSegment(value: PolyEditMode.faces, label: Text('Грани')),
            ButtonSegment(value: PolyEditMode.vertices, label: Text('Вершины')),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              app.setPolyEditMode(selection.first),
        ),
        const SizedBox(height: 10),
        if (mode == PolyEditMode.object) ..._objectFields(),
        if (mode == PolyEditMode.faces) ..._faceFields(mesh),
        if (mode == PolyEditMode.vertices) ..._vertexFields(mesh),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => app.deleteObject(obj.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Материал — в режиме «Текстурирование»',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  List<Widget> _objectFields() => [
        _label('Позиция (центр основания)'),
        Row(
          children: [
            for (final (key, value) in [
              ('X', obj.x),
              ('Y', obj.y),
              ('Z', obj.z),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoubleField(
                    initial: value,
                    step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                    onChanged: (v) => app.setObjectPos(
                      obj.id,
                      key == 'X' ? v : obj.x,
                      key == 'Y' ? v : obj.y,
                      key == 'Z' ? v : obj.z,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _label('Поворот (градусы)'),
        Row(
          children: [
            for (final (key, value) in [
              ('X', obj.rotX),
              ('Y', obj.rotY),
              ('Z', obj.rotZ),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoubleField(
                    initial: value,
                    step: 5,
                    onChanged: (v) => app.setObjectRot(
                      obj.id,
                      key == 'X' ? v : obj.rotX,
                      key == 'Y' ? v : obj.rotY,
                      key == 'Z' ? v : obj.rotZ,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _label('Масштаб (вытягивание по осям)'),
        Row(
          children: [
            for (final (axis, value) in [
              (0, obj.scaleX),
              (1, obj.scaleY),
              (2, obj.scaleZ),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoubleField(
                    initial: value,
                    step: 0.1,
                    precision: 4,
                    onChanged: (v) => app.setPolyScale(obj.id, axis, v),
                  ),
                ),
              ),
          ],
        ),
      ];

  List<Widget> _faceFields(cs.PolyMesh? mesh) {
    final total = mesh?.faces.length ?? 0;
    final prefix = '${obj.id}:';
    final count =
        app.selectedFaces.where((key) => key.startsWith(prefix)).length;
    return [
      Text(
        'Граней: $total · выбрано: $count',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        onPressed: count == 0 ? null : app.deleteSelectedPolyFaces,
        icon: const Icon(Icons.delete_outline, size: 15),
        label: const Text('Удалить грань'),
      ),
      const SizedBox(height: 4),
      const Text(
        'Клик по грани выбирает её, Shift добавляет к группе. '
        'Контуры выбранных граней подсвечены на сцене.',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      ),
    ];
  }

  List<Widget> _vertexFields(cs.PolyMesh? mesh) {
    final total = mesh?.vertices.length ?? 0;
    final count = app.selectedVertexIndices.length;
    final active = app.activeVertexIndex;
    final vertex = mesh != null && active != null && active < total
        ? mesh.vertices[active]
        : null;
    return [
      Text(
        'Вершин: $total · выбрано: $count',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: app.togglePolyAddVertex,
        icon: Icon(
          app.polyAddVertexArmed ? Icons.close : Icons.add,
          size: 15,
        ),
        label: Text(
          app.polyAddVertexArmed
              ? 'Отменить добавление'
              : 'Добавить вершину',
        ),
      ),
      if (app.polyAddVertexArmed) ...[
        const SizedBox(height: 4),
        const Text(
          'Нажмите на грань: клик по ребру вставит вершину в него, клик '
          'внутри разобьёт грань на треугольники от новой вершины (дыры '
          'не будет). UV интерполируются.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
      const SizedBox(height: 6),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
        onPressed: count == 0 ? null : app.deleteSelectedPolyVertices,
        icon: const Icon(Icons.delete_outline, size: 15),
        label: const Text('Удалить вершину'),
      ),
      if (vertex != null) ...[
        const SizedBox(height: 8),
        _label('Вершина $active (координаты)'),
        Row(
          children: [
            for (final (axis, value) in [
              (0, vertex.x),
              (1, vertex.y),
              (2, vertex.z),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: DoubleField(
                    initial: value,
                    step: 0.01,
                    precision: 4,
                    onChanged: (v) => app.setPolyVertexPosition(
                      active!,
                      vm.Vector3(
                        axis == 0 ? v : vertex.x,
                        axis == 1 ? v : vertex.y,
                        axis == 2 ? v : vertex.z,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ] else if (count > 1) ...[
        const SizedBox(height: 4),
        const Text(
          'Для точного ввода выберите одну вершину.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    ];
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(
          t,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      );
}

// ── Модель (вставка) ──────────────────────────────────────────────────

/// Properties of a model instance (kind 'model'): a whole other model
/// placed in this scene. Only its placement is editable — position,
/// rotation, uniform scale and the source model itself («Заменить
/// модель»); the content is edited in the source model and updates here
/// automatically.
class _ModelRefProperties extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  const _ModelRefProperties({required this.app, required this.obj});

  String? get _sourceName {
    final m = app.project?.models[obj.refModelId];
    return m?.name;
  }

  /// The cached source footprint (shown while the source is deleted).
  cs.ModelSize? get _cachedSize => obj.refSize;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );

  Widget _coordRow(
    List<(String, double)> fields,
    void Function(String key, double v) onChanged, {
    double step = 0.05,
  }) {
    return Row(
      children: [
        for (final (key, value) in fields)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DoubleField(
                initial: value,
                step: step,
                onChanged: (v) => onChanged(key, v),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _replaceModel(BuildContext context) async {
    final id = await pickModelDialog(context, app);
    if (id == null || id == obj.refModelId) return;
    app.replaceModelRef(obj.id, id);
  }

  @override
  Widget build(BuildContext context) {
    final source = _sourceName;
    final cached = _cachedSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF3A4250)),
        const SectionTitle('Модель'),
        NameField(initial: obj.name, onChanged: (v) => app.setObjectName(obj.id, v)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F242C),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3A4250)),
                ),
                child: source == null
                    ? Text(
                        'Источник «${obj.refModelId}» удалён — вместо него '
                        'куб фуксии '
                        '${cached == null ? '1×1×1' : '${cached.w}×${cached.l}×${cached.h}'}.',
                        style: const TextStyle(
                            color: Color(0xFFFF80FF), fontSize: 12),
                      )
                    : Text(
                        'Модель: $source · ${obj.refModelId}\n'
                        'Содержимое редактируется в самой модели и '
                        'обновляется во всех вставках.',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _replaceModel(context),
          icon: const Icon(Icons.swap_horiz, size: 15),
          label: const Text('Заменить модель…'),
        ),
        const SizedBox(height: 12),
        _label('Позиция (начало координат модели)'),
        _coordRow(
          [('X', obj.x), ('Y', obj.y), ('Z', obj.z)],
          (k, v) => app.setObjectPos(
            obj.id,
            k == 'X' ? v : obj.x,
            k == 'Y' ? v : obj.y,
            k == 'Z' ? v : obj.z,
          ),
          step: app.snapStep <= 0 ? 0.05 : app.snapStep,
        ),
        const SizedBox(height: 10),
        _label('Поворот (градусы)'),
        _coordRow(
          [('X', obj.rotX), ('Y', obj.rotY), ('Z', obj.rotZ)],
          (k, v) => app.setObjectRot(
            obj.id,
            k == 'X' ? v : obj.rotX,
            k == 'Y' ? v : obj.rotY,
            k == 'Z' ? v : obj.rotZ,
          ),
          step: 5,
        ),
        const SizedBox(height: 10),
        _label('Масштаб (равномерный)'),
        _coordRow(
          [('S', obj.scale)],
          (k, v) => app.setObjectScale(obj.id, v),
          step: app.snapStep <= 0 ? 0.05 : app.snapStep,
        ),
        const SizedBox(height: 8),
        const Text(
          'Вставка целиком масштабируется и поворачивается вокруг своей '
          'точки привязки; по частям она не редактируется.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => app.deleteObject(obj.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── GLB/GLTF (вставка) ────────────────────────────────────────────────

/// Properties of a glTF/GLB instance (kind 'gltf'): a whole imported
/// `3d_models/` resource placed in this scene. Only its placement is
/// editable — position, rotation, uniform scale, the source resource
/// («Заменить ресурс») and the looped animation choice. The content is not
/// paintable/editable part-by-part.
class _GltfRefProperties extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  const _GltfRefProperties({required this.app, required this.obj});

  String _fmt(double v) => v.toStringAsFixed(2);

  /// Human text of the cached footprint dims («1.50×0.80×0.60»), or «—».
  String get _footprintText {
    final b = obj.gltfBounds;
    if (b == null) return '1×1×1';
    return '${_fmt(b[3] - b[0])}×${_fmt(b[4] - b[1])}×${_fmt(b[5] - b[2])}';
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );

  Widget _coordRow(
    List<(String, double)> fields,
    void Function(String key, double v) onChanged, {
    double step = 0.05,
  }) {
    return Row(
      children: [
        for (final (key, value) in fields)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DoubleField(
                initial: value,
                step: step,
                onChanged: (v) => onChanged(key, v),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _replaceResource(BuildContext context) async {
    final name = await pickGltfDialog(
      context,
      app,
      title: 'Заменить ресурс',
      excludeName: obj.gltfName,
    );
    if (name == null || name == obj.gltfName) return;
    app.replaceGltfRef(obj.id, name);
  }

  /// The animation strip: «Нет — статичная поза» plus every glTF animation
  /// of the loaded resource (short names; the full name is the stored
  /// value). While the resource is not loaded yet the choice is disabled.
  Widget _animationSection() {
    final node = app.controller.objectNode(obj.id);
    final anims = node?.animationClips ?? const <GltfAnimInfo>[];
    if (anims.isEmpty && (node?.gltfFailed ?? false)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Анимация (зацикленная)'),
          const Text(
            'Не удалось загрузить ресурс модели.',
            style: TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ],
      );
    }
    if (anims.isEmpty &&
        ((node?.gltfLoading ?? false) || obj.gltfBounds == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Анимация (зацикленная)'),
          const Text(
            'Модель загружается — список анимаций появится '
            'после загрузки.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      );
    }
    final known = obj.anim.isNotEmpty &&
        anims.any((a) => a.fullName == obj.anim);
    final value = known ? obj.anim : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Анимация (зацикленная)'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1F242C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A4250)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF2E333D),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              iconEnabledColor: Colors.white54,
              value: value,
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Нет — статичная поза'),
                ),
                for (final a in anims)
                  DropdownMenuItem(
                    value: a.fullName,
                    child: Text(
                      a.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => app.setGltfAnim(obj.id, v ?? ''),
            ),
          ),
        ),
        if (anims.isEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            'В модели нет анимаций.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only a settled catalog scan may claim the resource is deleted; while
    // it scans the resource is simply «not known yet».
    final catalog = app.model3d;
    final entry =
        catalog.scanned ? catalog.entry(obj.gltfName) : null;
    final unknown = !catalog.scanned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF3A4250)),
        const SectionTitle('GLB/GLTF'),
        NameField(initial: obj.name, onChanged: (v) => app.setObjectName(obj.id, v)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1F242C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A4250)),
          ),
          child: entry == null
              ? Text(
                  unknown
                      ? 'Ресурс «${obj.gltfName}»: каталог ещё сканируется…'
                      : 'Ресурс «${obj.gltfName}» удалён — вместо него '
                          'куб фуксии $_footprintText.',
                  style: TextStyle(
                    color: unknown ? Colors.white54 : const Color(0xFFFF80FF),
                    fontSize: 12,
                  ),
                )
              : Text(
                  'Ресурс: ${entry.name} · ${entry.kindLabel} '
                  '(3d_models/)\n'
                  'Раскрашивать и редактировать нельзя — только перенос, '
                  'поворот, масштаб и выбор анимации.',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: entry == null ? null : () => _replaceResource(context),
          icon: const Icon(Icons.swap_horiz, size: 15),
          label: const Text('Заменить ресурс…'),
        ),
        const SizedBox(height: 12),
        if (entry != null) _animationSection(),
        if (entry != null) const SizedBox(height: 12),
        _label('Позиция (основание вставки)'),
        _coordRow(
          [('X', obj.x), ('Y', obj.y), ('Z', obj.z)],
          (k, v) => app.setObjectPos(
            obj.id,
            k == 'X' ? v : obj.x,
            k == 'Y' ? v : obj.y,
            k == 'Z' ? v : obj.z,
          ),
          step: app.snapStep <= 0 ? 0.05 : app.snapStep,
        ),
        const SizedBox(height: 10),
        _label('Поворот (градусы)'),
        _coordRow(
          [('X', obj.rotX), ('Y', obj.rotY), ('Z', obj.rotZ)],
          (k, v) => app.setObjectRot(
            obj.id,
            k == 'X' ? v : obj.rotX,
            k == 'Y' ? v : obj.rotY,
            k == 'Z' ? v : obj.rotZ,
          ),
          step: 5,
        ),
        const SizedBox(height: 10),
        _label('Масштаб (равномерный)'),
        _coordRow(
          [('S', obj.scale)],
          (k, v) => app.setObjectScale(obj.id, v),
          step: app.snapStep <= 0 ? 0.05 : app.snapStep,
        ),
        const SizedBox(height: 8),
        const Text(
          'Вставка целиком масштабируется и поворачивается вокруг своей '
          'точки привязки; выбранная анимация проигрывается по кругу.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: app.duplicateObject,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Дублировать'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () => app.deleteObject(obj.id),
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Текстурирование ───────────────────────────────────────────────────

class _TexturePanel extends StatelessWidget {
  final AppState app;
  final cs.ModelData model;
  const _TexturePanel({required this.app, required this.model});

  @override
  Widget build(BuildContext context) {
    final obj = app.selectedObject();
    final facesMode = app.texSubmode == TexSubmode.faces;
    final faceKey = app.selectedFaceKey;
    final count = app.selectedFaces.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Текстурирование'),
        const _PanelLabel('Режим'),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SegmentedButton<TexSubmode>(
            showSelectedIcon: false,
            style: appSegmentedStyle(),
            segments: const [
              ButtonSegment(
                value: TexSubmode.objects,
                label: Text('Объекты'),
                icon: Icon(Icons.crop_square, size: 14),
              ),
              ButtonSegment(
                value: TexSubmode.faces,
                label: Text('Грани'),
                icon: Icon(Icons.square, size: 14),
              ),
            ],
            selected: {app.texSubmode},
            onSelectionChanged: (s) => app.setTexSubmode(s.first),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Color(0xFF3A4250)),
        if (obj == null)
          const Text(
            'Выберите объект или грань в сцене',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          )
        else ...[
          Text(
            facesMode && faceKey != null
                ? '${obj.name} — грань $faceKey${count > 1 ? ' (+${count - 1})' : ''}'
                : '${obj.name} — весь объект',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (facesMode && faceKey != null)
            TextButton(
              onPressed: () => app.resetFaces(),
              child: const Text('Вернуть материал объекта для граней', style: TextStyle(fontSize: 12)),
            ),
          const Divider(color: Color(0xFF3A4250)),
          MaterialEditor(
            app: app,
            obj: obj,
            faceKey: facesMode ? faceKey : null,
            // In the faces submode the material applies to every selected
            // face; in the objects submode — to the whole object.
            applyToFaces: facesMode,
          ),
        ],
      ],
    );
  }
}

/// Material editor: type, resource key, color, UV direction, stretch.
class MaterialEditor extends StatelessWidget {
  final AppState app;
  final cs.ModelObject obj;
  final String? faceKey;
  final bool compact;

  /// When true (texture faces submode) the edits apply to ALL selected
  /// faces via [AppState.setFacesMaterial].
  final bool applyToFaces;

  const MaterialEditor({
    super.key,
    required this.app,
    required this.obj,
    required this.faceKey,
    this.compact = false,
    this.applyToFaces = false,
  });

  cs.ModelMaterial get current => faceKey != null
      ? (obj.faces[faceKey] ?? obj.material ?? cs.ModelMaterial())
      : (obj.material ?? cs.ModelMaterial());

  void _set(cs.ModelMaterial m) {
    if (applyToFaces) {
      app.setFacesMaterial(m);
    } else {
      app.setMaterial(obj.id, faceKey: faceKey, material: m);
    }
  }

  /// Applies the side checkboxes; at least one side must stay on, so
  /// unchecking the last checked side is ignored.
  void _setSide(cs.ModelMaterial mat, bool outer, bool inner) {
    if (!outer && !inner) return;
    final side = outer && inner ? 'both' : (outer ? 'outer' : 'inner');
    if (side == mat.side) return;
    _set(cs.ModelMaterial.copy(mat)..side = side);
  }

  @override
  Widget build(BuildContext context) {
    final root = app.project?.directory?.path;
    final mat = current;
    final isSpriteLike = mat.type == cs.MaterialType.sprite || obj.kind == 'sprite';
    final keys = _familyFiles(
      app,
      mat.type == cs.MaterialType.sprite ? 'sprite' : 'texture',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Тип'),
        SegmentedButton<cs.MaterialType>(
          showSelectedIcon: false,
          style: appSegmentedStyle(),
          segments: const [
            ButtonSegment(value: cs.MaterialType.texture, label: Text('Текстура')),
            ButtonSegment(value: cs.MaterialType.sprite, label: Text('Спрайт')),
            ButtonSegment(value: cs.MaterialType.color, label: Text('Цвет')),
          ],
          selected: {mat.type},
          onSelectionChanged: (s) {
            final t = s.first;
            _set(cs.ModelMaterial.copy(mat)
              ..type = t
              // Keep the key only when it belongs to the target list;
              // otherwise reset so the file dropdown never holds a value
              // that is missing from its items (which would crash it).
              ..key = validFileKey(t, mat.key, app) ?? '');
          },
        ),
        if (mat.type != cs.MaterialType.color) ...[
          const SizedBox(height: 8),
          _label('Ресурс'),
          ResourcePicker(
            files: keys,
            rootDir: mat.type == cs.MaterialType.sprite
                ? (root == null ? '' : '$root/sprites')
                : (root == null ? '' : '$root/textures'),
            selected: validFileKey(mat.type, mat.key, app),
            onPick: (k) => _set(cs.ModelMaterial.copy(mat)..key = k),
          ),
        ],
        if (mat.type == cs.MaterialType.color) ...[
          const SizedBox(height: 8),
          _label('Цвет'),
          Row(
            children: [
              for (final c in _colorPresets)
                InkWell(
                  onTap: () => _set(cs.ModelMaterial.copy(mat)..color = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, c[0], c[1], c[2]),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (obj.kind != 'sprite') ...[
          const SizedBox(height: 12),
          _label('Сторона грани'),
          Row(
            children: [
              Checkbox(
                value: mat.side != 'inner',
                onChanged: (v) => _setSide(mat, v == true, mat.side == 'both'),
              ),
              const Text('Внешняя', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 16),
              Checkbox(
                value: mat.side != 'outer',
                onChanged: (v) => _setSide(mat, mat.side == 'both', v == true),
              ),
              const Text('Внутренняя', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _label('Направление текстуры'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: appSegmentedStyle(),
          segments: const [
            ButtonSegment(value: 0, label: Text('0°')),
            ButtonSegment(value: 90, label: Text('90°')),
            ButtonSegment(value: 180, label: Text('180°')),
            ButtonSegment(value: 270, label: Text('270°')),
          ],
          selected: {mat.uvDir},
          onSelectionChanged: (s) => _set(cs.ModelMaterial.copy(mat)..uvDir = s.first),
        ),
        Row(
          children: [
            Switch(
              value: mat.flipX,
              onChanged: (v) => _set(cs.ModelMaterial.copy(mat)..flipX = v),
            ),
            const Text('Зеркало X', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 16),
            Switch(
              value: mat.flipY,
              onChanged: (v) => _set(cs.ModelMaterial.copy(mat)..flipY = v),
            ),
            const Text('Зеркало Y', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        _label('Растягивание'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: appSegmentedStyle(),
          segments: const [
            ButtonSegment(value: 'stretch', label: Text('Растянуть')),
            ButtonSegment(value: 'tile', label: Text('Тайлы')),
          ],
          selected: {mat.stretch},
          onSelectionChanged: (s) => _set(cs.ModelMaterial.copy(mat)..stretch = s.first),
        ),
        if (mat.stretch == 'tile') ...[
          const SizedBox(height: 8),
          _label('Юнитов на тайл (1 = клетка)'),
          DoubleField(
            initial: mat.tileScale,
            step: app.snapStep <= 0 ? 0.05 : app.snapStep,
            onChanged: (v) => _set(cs.ModelMaterial.copy(mat)..tileScale = v),
          ),
          const SizedBox(height: 8),
          _label('Тайл по U / V (0 = общий)'),
          Row(
            children: [
              Expanded(
                child: DoubleField(
                  initial: mat.tileScaleU,
                  step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                  onChanged: (v) =>
                      _set(cs.ModelMaterial.copy(mat)..tileScaleU = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DoubleField(
                  initial: mat.tileScaleV,
                  step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                  onChanged: (v) =>
                      _set(cs.ModelMaterial.copy(mat)..tileScaleV = v),
                ),
              ),
            ],
          ),
        ],
        if (!isSpriteLike && !compact) ...[
          const SizedBox(height: 6),
          const Text(
            'Кликните по объекту в сцене, чтобы выбрать грань',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );
}

const _colorPresets = [
  [200, 200, 200],
  [120, 80, 40],
  [60, 60, 60],
  [40, 70, 110],
  [90, 110, 40],
  [110, 40, 40],
];

// ── Разметка (meta-objects) ────────────────────────────────────────────

String _metaKindLabel(String kind) => switch (kind) {
      'marker' => 'Маркер',
      'box' => 'Бокс',
      _ => 'Комментарий',
    };

/// The properties panel of the selected meta-object in the «Разметка» mode:
/// name/comment/z-index, box dimensions, position and the collapse toggle.
class _MetaPanel extends StatefulWidget {
  final AppState app;
  final cs.ModelMeta meta;
  final cs.ModelData model;
  const _MetaPanel({
    required this.app,
    required this.meta,
    required this.model,
  });

  @override
  State<_MetaPanel> createState() => _MetaPanelState();
}

class _MetaPanelState extends State<_MetaPanel> {
  late final TextEditingController _comment = TextEditingController(
    text: widget.meta.comment,
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_MetaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meta.id != widget.meta.id) {
      _comment.text = widget.meta.comment;
    }
  }

  AppState get app => widget.app;

  cs.ModelMeta get meta =>
      app.currentModel?.metaById(widget.meta.id) ?? widget.meta;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );

  @override
  Widget build(BuildContext context) {
    final m = meta;
    final id = m.id;
    final hasLabel = m.comment.trim().isNotEmpty ||
        (m.kind != cs.metaKindComment && m.name.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('${_metaKindLabel(m.kind)} · Разметка'),
        _label('Имя'),
        NameField(
          initial: m.name,
          onChanged: (v) => app.setMetaName(id, v),
        ),
        _label('Комментарий'),
        TextField(
          controller: _comment,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintStyle: TextStyle(color: Colors.white38),
            hintText: 'Подпись над мета-объектом…',
          ),
          onChanged: (v) => app.setMetaComment(id, v),
        ),
        if (hasLabel) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => app.toggleMetaCollapsed(id),
              icon: Icon(
                m.collapsed ? Icons.unfold_more : Icons.unfold_less,
                size: 16,
              ),
              label: Text(
                m.collapsed ? 'Раскрыть подпись' : 'Схлопнуть подпись',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
        if (m.kind == 'box') ...[
          _label('Размеры (длина × высота × ширина)'),
          Row(
            children: [
              Expanded(
                child: DoubleField(
                  initial: m.dim('w', 1.0),
                  step: 0.1,
                  onChanged: (v) => app.setMetaDim(id, 'w', v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DoubleField(
                  initial: m.dim('h', 1.0),
                  step: 0.1,
                  onChanged: (v) => app.setMetaDim(id, 'h', v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DoubleField(
                  initial: m.dim('d', 1.0),
                  step: 0.1,
                  onChanged: (v) => app.setMetaDim(id, 'd', v),
                ),
              ),
            ],
          ),
        ],
        _label('Позиция (x, y, z)'),
        Row(
          children: [
            Expanded(
              child: DoubleField(
                initial: m.x,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setMetaPos(id, v, m.y, m.z),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DoubleField(
                initial: m.y,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setMetaPos(id, m.x, v, m.z),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DoubleField(
                initial: m.z,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setMetaPos(id, m.x, m.y, v),
              ),
            ),
          ],
        ),
        _label('Z-индекс (поверх при перекрытии)'),
        DoubleField(
          initial: m.zIndex.toDouble(),
          step: 1,
          onChanged: (v) => app.setMetaZIndex(id, v.round()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => app.requestFocusMeta(id),
                icon: const Icon(Icons.center_focus_strong, size: 15),
                label: const Text('В кадр', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: app.duplicateMeta,
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Дублировать', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  app.selectMeta(null);
                  app.deleteMeta(id);
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Удалить', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Освещение (light sources + scene settings) ─────────────────────────

/// sRGB 0..1 light color → [Color] for the panel chips.
Color _lightUiColor(cs.ModelLight l) => Color.fromRGBO(
      (l.r * 255).round().clamp(0, 255),
      (l.g * 255).round().clamp(0, 255),
      (l.b * 255).round().clamp(0, 255),
      1,
    );

/// The properties panel of the selected light source in the «Освещение»
/// mode: name, color (presets + picker dialog), intensity, range (point) or
/// aim (directional), position and the usual actions.
class _LightPanel extends StatefulWidget {
  final AppState app;
  final cs.ModelLight light;
  final cs.ModelData model;
  const _LightPanel({
    required this.app,
    required this.light,
    required this.model,
  });

  @override
  State<_LightPanel> createState() => _LightPanelState();
}

class _LightPanelState extends State<_LightPanel> {
  AppState get app => widget.app;

  cs.ModelLight get light =>
      app.currentModel?.lighting.lightById(widget.light.id) ?? widget.light;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );

  Future<void> _openPicker() async {
    final l = light;
    final picked = await showLightColorPicker(
      context,
      initial: _lightUiColor(l),
    );
    if (picked == null || !mounted) return;
    app.setLightColor(
      l.id,
      (picked.r * 255).round() / 255.0,
      (picked.g * 255).round() / 255.0,
      (picked.b * 255).round() / 255.0,
    );
  }

  void _setPreset(Color c) {
    final l = light;
    app.setLightColor(
      l.id,
      (c.r * 255).round() / 255.0,
      (c.g * 255).round() / 255.0,
      (c.b * 255).round() / 255.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = light;
    final id = l.id;
    final color = _lightUiColor(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('${cs.lightKindLabel(l.kind)} · Освещение'),
        _label('Имя'),
        NameField(
          initial: l.name,
          onChanged: (v) => app.setLightName(id, v),
        ),
        _label('Цвет'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in kLightColorPresets)
              GestureDetector(
                onTap: () => _setPreset(p),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: p.toARGB32() == color.toARGB32()
                          ? const Color(0xFF4C9BE8)
                          : Colors.white24,
                      width: p.toARGB32() == color.toARGB32() ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white38),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.palette_outlined, size: 15),
                label: const Text('Пикер…', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        _label('Интенсивность'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: l.intensity.clamp(0.0, 20.0),
                min: 0,
                max: 20,
                onChanged: (v) => app.setLightIntensity(id, v),
              ),
            ),
            SizedBox(
              width: 74,
              child: DoubleField(
                initial: l.intensity,
                step: 0.1,
                onChanged: (v) => app.setLightIntensity(id, v),
              ),
            ),
          ],
        ),
        if (l.isPoint) ...[
          _label('Дальность (0 = без ограничений)'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: l.range.clamp(0.0, 40.0),
                  min: 0,
                  max: 40,
                  onChanged: (v) => app.setLightRange(id, v),
                ),
              ),
              SizedBox(
                width: 74,
                child: DoubleField(
                  initial: l.range,
                  step: 0.5,
                  onChanged: (v) => app.setLightRange(id, v),
                ),
              ),
            ],
          ),
        ] else ...[
          _label('Направление (азимут · возвышение)'),
          _DirectionFields(app: app, lightId: id),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Стрелку на сцене можно повернуть гизмо в режиме вращения '
              '(Alt/Option или кнопка «Режим вращения»)',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
        _label('Позиция (x, y, z)'),
        Row(
          children: [
            Expanded(
              child: DoubleField(
                initial: l.x,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setLightPos(id, v, l.y, l.z),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DoubleField(
                initial: l.y,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setLightPos(id, l.x, v, l.z),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DoubleField(
                initial: l.z,
                step: app.snapStep <= 0 ? 0.05 : app.snapStep,
                onChanged: (v) => app.setLightPos(id, l.x, l.y, v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => app.requestFocusLight(id),
                icon: const Icon(Icons.center_focus_strong, size: 15),
                label: const Text('В кадр', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: app.duplicateLight,
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Дублировать', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  app.selectLight(null);
                  app.deleteLight(id);
                },
                icon: const Icon(Icons.delete_outline, size: 15),
                label: const Text('Удалить', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The azimuth/elevation aim editors of a directional light (world space).
class _DirectionFields extends StatelessWidget {
  final AppState app;
  final String lightId;
  const _DirectionFields({required this.app, required this.lightId});

  @override
  Widget build(BuildContext context) {
    final light = app.currentModel?.lighting.lightById(lightId);
    if (light == null) return const SizedBox.shrink();
    final (az, el) = lightDirToAngles(light.dirX, light.dirY, light.dirZ);
    return Row(
      children: [
        Expanded(
          child: DoubleField(
            initial: az,
            step: 5,
            onChanged: (v) {
              final dir = lightAnglesToDir(v, el);
              app.setLightDirection(lightId, dir.x, dir.y, dir.z);
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DoubleField(
            initial: el,
            step: 5,
            onChanged: (v) {
              final dir = lightAnglesToDir(az, v);
              app.setLightDirection(lightId, dir.x, dir.y, dir.z);
            },
          ),
        ),
      ],
    );
  }
}

/// The scene lighting knobs of the «Освещение» mode (shown when no source
/// is selected): global ambient, gizmo visibility, shadows, SSAO.
class _LightingSettingsPanel extends StatelessWidget {
  final AppState app;
  final cs.ModelData model;
  const _LightingSettingsPanel({required this.app, required this.model});

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(t,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = model.lighting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Освещение сцены'),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'Инструменты на верхней панели добавляют источники света '
            '(точечный, направленный) в позицию курсора. Пока источников '
            'нет, сцена освещается светом редактора; с первым источником '
            'включается настроенный свет модели.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        if (cfg.lights.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Источников: ${cfg.lights.length} — список и редактирование '
              'в левой панели и на сцене',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        _label('Глобальное освещение (яркость окружения)'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: cfg.ambient.clamp(0.0, 2.0),
                min: 0,
                max: 2,
                onChanged: (v) => app.setLightingAmbient(v),
              ),
            ),
            SizedBox(
              width: 74,
              child: DoubleField(
                initial: cfg.ambient,
                step: 0.05,
                onChanged: (v) => app.setLightingAmbient(v),
              ),
            ),
          ],
        ),
        const Divider(color: Color(0xFF3A4250), height: 12),
        _switchRow(
            'Показывать гизмо источников', cfg.gizmos, app.setLightingGizmos),
        _switchRow('Тени', cfg.shadows, app.setLightingShadows),
        _switchRow('SSAO (окружающее затенение)', cfg.ssao, app.setLightingSsao),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Тени отбрасывают направленные источники (точечные в движке '
            'теней не дают); SSAO затемняет стыки поверхностей. Тени и SSAO '
            'действуют во всех режимах, когда свет модели настроен.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// Scene level fields (plan §3.14): the entry sides (`entries`), the facade
/// side (`front`) and the named cell-meta brush — shown in the markup mode
/// when no meta-object is selected.
class _SceneFieldsPanel extends StatelessWidget {
  final AppState app;
  final cs.ModelData model;
  const _SceneFieldsPanel({required this.app, required this.model});

  static const _sideLabels = {
    ModelSide.north: 'Север',
    ModelSide.east: 'Восток',
    ModelSide.south: 'Юг',
    ModelSide.west: 'Запад',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 18),
        const _PanelLabel('Входные стороны (entries)'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final side in ModelSide.values)
            FilterChip(
              label: Text(_sideLabels[side]!),
              selected: model.entries.contains(side),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => app.toggleEntrySide(side),
            ),
        ]),
        const SizedBox(height: 10),
        const _PanelLabel('Лицевая сторона (front)'),
        DropdownButtonFormField<ModelSide?>(
          initialValue: model.front,
          isExpanded: true,
          dropdownColor: const Color(0xFF2C313B),
          decoration: const InputDecoration(isDense: true),
          items: [
            const DropdownMenuItem<ModelSide?>(
              value: null,
              child: Text('нет'),
            ),
            for (final side in ModelSide.values)
              DropdownMenuItem<ModelSide?>(
                value: side,
                child: Text(_sideLabels[side]!),
              ),
          ],
          onChanged: app.setFrontSide,
        ),
        const SizedBox(height: 10),
        const _PanelLabel('Кисть клеточных мет'),
        NameField(
          initial: app.cellBrushName,
          onChanged: app.setCellBrushName,
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final name in const [
            metaNameUnpassable,
            metaNameDoor,
            metaNameWindow,
          ])
            FilterChip(
              label: Text(name),
              selected: app.cellBrushName == name,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => app.setCellBrushName(name),
            ),
        ]),
        const SizedBox(height: 6),
        FilterChip(
          label: const Text('Кисть включена'),
          selected: app.cellBrushArmed,
          visualDensity: VisualDensity.compact,
          onSelected: app.setCellBrushArmed,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Клик или протяжка ставит бокс 1×1 в центр клетки. Имена '
            'unpassable/door/window — соглашения уровня (можно своё).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
