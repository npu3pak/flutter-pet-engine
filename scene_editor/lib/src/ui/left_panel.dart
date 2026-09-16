import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pet_engine/pet_engine.dart';

import '../scene/editor_scene.dart';
import '../state/app_state.dart';
import 'form_fields.dart';
import 'house_template_dialog.dart';
import 'unsaved_dialog.dart';

class LeftPanel extends StatelessWidget {
  final AppState app;
  const LeftPanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF262B34),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Модели'),
                Tab(text: 'Объекты'),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                children: [
                  _ModelsTab(app: app),
                  _InspectorTab(app: app),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Модели ─────────────────────────────────────────────────────────────

class _ModelsTab extends StatelessWidget {
  final AppState app;
  const _ModelsTab({required this.app});

  @override
  Widget build(BuildContext context) {
    final store = app.project;
    if (store == null) {
      return const Center(child: Text('Проект не открыт', style: TextStyle(color: Colors.white54)));
    }
    final ids = store.modelIds;
    final errors = app.controller.resources?.loadErrors ?? const <String>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    if (await confirmUnsavedChanges(context, app)) {
                      app.createModel();
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Создать модель'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    if (!await confirmUnsavedChanges(context, app)) return;
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (c) => HouseTemplateDialog(app: app),
                    );
                  },
                  icon: const Icon(Icons.home_outlined, size: 16),
                  label: const Text('По шаблону'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final id = ids[i];
              final model = store.models[id]!;
              final selected = app.currentModelId == id;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: const Color(0xFF2E5F8F),
                title: Text(
                  '${model.name}${model.dirty ? ' •' : ''}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  '${model.size.w}×${model.size.l}×${model.size.h} · '
                  '${model.objects.length} об.',
                  style: TextStyle(
                    color: selected ? Colors.white70 : Colors.white54,
                    fontSize: 11,
                  ),
                ),
                onTap: () => app.selectModel(id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Дублировать',
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => app.duplicateModel(id),
                    ),
                    PopupMenuButton<String>(
                      iconSize: 16,
                      onSelected: (action) {
                        switch (action) {
                          case 'rename':
                            _renameDialog(context, app, id);
                          case 'delete':
                            _deleteDialog(context, app, id);
                        }
                      },
                      itemBuilder: (c) => const [
                        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Ошибки: ${errors.join(', ')}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
      ],
    );
  }

  void _renameDialog(BuildContext context, AppState app, String id) {
    final controller = TextEditingController(text: id);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Переименовать модель'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(c),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final err = await app.renameModel(id, controller.text.trim());
              if (!c.mounted) return;
              Navigator.pop(c);
              if (err != null) {
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  void _deleteDialog(BuildContext context, AppState app, String id) {
    final users = app.modelsUsingModel(id);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить модель?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Модель «$id» будет удалена с диска.'),
            if (users.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Модель используется в сценах: ${users.join(', ')}. '
                'На местах её вставок останется куб фуксии.',
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              app.deleteModel(id);
              Navigator.pop(c);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

// ── Инспектор ─────────────────────────────────────────────────────────

class _InspectorTab extends StatefulWidget {
  final AppState app;
  const _InspectorTab({required this.app});

  @override
  State<_InspectorTab> createState() => _InspectorTabState();
}

class _InspectorTabState extends State<_InspectorTab> {
  String _query = '';
  AppState get app => widget.app;

  DateTime? _lastClickTime;
  String? _lastClickObject;

  /// Pointer-event double-click detection (same pattern as the viewport):
  /// a second press on the same object within the double-tap window. Unlike
  /// GestureDetector.onDoubleTap, it never delays the single-tap selection.
  bool _isDoubleClick(String id) {
    final now = DateTime.now();
    final isDouble = _lastClickObject == id &&
        _lastClickTime != null &&
        now.difference(_lastClickTime!) < kDoubleTapTimeout;
    _lastClickTime = now;
    _lastClickObject = id;
    return isDouble;
  }

  @override
  Widget build(BuildContext context) {
    final model = app.currentModel;
    if (model == null) {
      return const Center(
        child: Text('Нет модели', style: TextStyle(color: Colors.white54)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Поиск по имени…',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (q) => _query = q.toLowerCase(),
          ),
        ),
        if (model.objects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: app.selectAllObjects,
                icon: const Icon(Icons.select_all, size: 16),
                label: const Text(
                  'Выделить все',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        if (app.selectedCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: app.hasGroupedSelection
                    ? app.ungroupSelection
                    : app.createGroup,
                icon: Icon(
                  app.hasGroupedSelection
                      ? Icons.group_remove
                      : Icons.group_add,
                  size: 16,
                ),
                label: Text(
                  app.hasGroupedSelection ? 'Разгруппировать' : 'Сгруппировать',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        if (app.selectedCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => app.selectObject(null),
                icon: const Icon(Icons.deselect, size: 16),
                label: const Text(
                  'Снять выделение',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: _buildTree(model),
        ),
      ],
    );
  }

  final Set<String> _collapsedGroups = {};
  final Set<String> _collapsedCsg = {};

  /// True when a group (or any of its members) matches the search query.
  bool _groupVisible(ModelGroup g) {
    if (_query.isEmpty) return true;
    if (g.name.toLowerCase().contains(_query)) return true;
    final model = app.currentModel;
    for (final mid in g.members) {
      final o = _find(model, mid);
      if (o != null && o.name.toLowerCase().contains(_query)) return true;
    }
    return false;
  }

  ModelObject? _find(ModelData? model, String id) {
    if (model == null) return null;
    for (final o in model.objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  Widget _buildTree(ModelData model) {
    // Rows are collected in display order: the lighting section (light
    // sources of the «Освещение» mode), the markup section (meta-objects),
    // named groups (with their members), then the operation forest (csg
    // roots with their operands indented under them), then the remaining
    // free objects. The lighting mode edits sources only — it hides the
    // object/group sections.
    final rows = <Widget>[];
    final lighting = app.mode == EditorMode.lighting;
    if (lighting) {
      if (_query.isEmpty) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            'Освещение',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ));
      }
      for (final light in model.lighting.lights) {
        if (_query.isNotEmpty &&
            !light.name.toLowerCase().contains(_query)) {
          continue;
        }
        rows.add(_lightRow(model, light));
      }
    }
    // The meta section shows in the markup mode only (its entries are still
    // matched by the search query, so the section disappears on a query
    // that only matches objects).
    if (app.mode == EditorMode.markup) {
      if (model.metas.isNotEmpty && _query.isEmpty) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            'Разметка',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ));
      }
      for (final meta in model.metas) {
        if (_query.isNotEmpty &&
            !meta.name.toLowerCase().contains(_query) &&
            !meta.comment.toLowerCase().contains(_query)) {
          continue;
        }
        rows.add(_metaRow(model, meta));
      }
    }
    if (!lighting) {
      for (final g in model.groups) {
        if (!_groupVisible(g)) continue;
        rows.add(_groupRow(model, g));
        if (!_collapsedGroups.contains(g.id)) {
          for (final mid in g.members) {
            final obj = _find(model, mid);
            if (obj == null) continue;
            if (obj.isCsg) {
              _addCsgRows(rows, model, obj, indent: true);
              continue;
            }
            if (_query.isNotEmpty &&
                !obj.name.toLowerCase().contains(_query) &&
                !g.name.toLowerCase().contains(_query)) {
              continue;
            }
            rows.add(_objectRow(model, obj, indent: true));
          }
        }
      }
    }
    final csgRoots = model.csgRoots();
    for (final node in csgRoots) {
      if (lighting) break;
      if (app.groupOf(node.id) != null) continue; // shown under its group
      _addCsgRows(rows, model, node, indent: false);
    }
    if (!lighting) {
      for (final obj in model.objects) {
        if (app.groupOf(obj.id) != null) continue; // shown under its group
        if (obj.isCsg) continue; // shown as a csg root above (if a root)
        if (model.isCsgOperand(obj.id)) continue; // hidden under its operation
        if (_query.isNotEmpty &&
            !obj.name.toLowerCase().contains(_query)) {
          continue;
        }
        rows.add(_objectRow(model, obj, indent: false));
      }
    }
    // The whole list is also a drop target: dropping not on a group row
    // moves the object out of its group (to the root).
    return DragTarget<String>(
      onAcceptWithDetails: (d) {
        final id = d.data;
        if (id.isNotEmpty) app.moveObjectToGroup(id, null);
      },
      builder: (context, candidates, rejected) => Container(
        color: candidates.isNotEmpty
            ? const Color(0x332E5F8F)
            : null,
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    app.mode == EditorMode.lighting && _query.isEmpty
                        ? 'Источников света нет — добавьте точечный или '
                            'направленный на верхней панели'
                        : 'Объектов нет',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: rows,
              ),
      ),
    );
  }

  /// Whether [node] or anything in its csg subtree matches the query.
  bool _csgVisible(ModelData model, ModelObject node) {
    if (_query.isEmpty) return true;
    if (node.name.toLowerCase().contains(_query)) return true;
    for (final l in model.csgLeavesOf(node.id)) {
      if (l.name.toLowerCase().contains(_query)) return true;
    }
    return false;
  }

  /// Appends the expandable row of a csg [node] and its operands (recursing
  /// into nested operation nodes).
  void _addCsgRows(List<Widget> rows, ModelData model, ModelObject node,
      {required bool indent}) {
    if (!_csgVisible(model, node)) return;
    final selected = app.selectedObjectId == node.id;
    final operands = node.operands ?? const <String>[];
    final collapsed = _collapsedCsg.contains(node.id);
    rows.add(Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: selected ? const Color(0xFF2E5F8F) : null,
        contentPadding: EdgeInsets.only(left: indent ? 28.0 : 16.0, right: 8.0),
        leading: InkWell(
          onTap: () => setState(() {
            if (collapsed) {
              _collapsedCsg.remove(node.id);
            } else {
              _collapsedCsg.add(node.id);
            }
          }),
          child: Icon(
            collapsed ? Icons.account_tree_outlined : Icons.account_tree,
            size: 16,
            color: selected ? const Color(0xFFCFE6FF) : const Color(0xFF9FB4C7),
          ),
        ),
        title: Text(
          node.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${_opLabel(node.op)} · ${model.csgLeavesOf(node.id).length} об.',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        onTap: () => app.selectObject(node.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Дублировать',
              icon: const Icon(Icons.copy, size: 15),
              onPressed: () {
                app.selectObject(node.id);
                app.duplicateObject();
              },
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline, size: 15),
              onPressed: () => app.deleteObject(node.id),
            ),
          ],
        ),
      ),
    ));
    if (collapsed) return;
    for (final mid in operands) {
      final o = _find(model, mid);
      if (o == null) continue;
      if (o.isCsg) {
        _addCsgRows(rows, model, o, indent: true);
      } else {
        rows.add(_objectRow(model, o, indent: true));
      }
    }
  }

  String _opLabel(String? op) => switch (op) {
        csgOpDifference => 'Вычитание',
        csgOpIntersect => 'Пересечение',
        _ => 'Объединение',
      };

  /// Row of a light source (select, double-click = camera focus).
  Widget _lightRow(ModelData model, ModelLight light) {
    final selected = app.selectedLightId == light.id;
    final color = _lightUiColor(light);
    final sub = '${lightKindLabel(light.kind)} · '
        '${light.isPoint ? 'дальность ${round2(light.range)}' : ''}'
        'интенсивность ${round2(light.intensity)}';
    return Listener(
      onPointerDown: (e) {
        if ((e.buttons & kPrimaryMouseButton) != 0 &&
            _isDoubleClick(light.id)) {
          app.selectLight(light.id);
          app.requestFocusLight(light.id);
        }
      },
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: selected ? const Color(0xFF2E5F8F) : null,
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        leading: Icon(
          light.isPoint ? Icons.lightbulb_outline : Icons.light_mode,
          size: 16,
          color: selected ? const Color(0xFFCFE6FF) : color,
        ),
        title: Text(
          light.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          sub.length > 60 ? '${sub.substring(0, 60)}…' : sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white70 : Colors.white54,
            fontSize: 10,
          ),
        ),
        onTap: () => app.selectLight(light.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Дублировать',
              icon: const Icon(Icons.copy, size: 15),
              onPressed: () {
                app.selectLight(light.id);
                app.duplicateLight();
              },
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline, size: 15),
              onPressed: () {
                app.selectLight(null);
                app.deleteLight(light.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  double round2(double v) => (v * 100).roundToDouble() / 100;

  Color _lightUiColor(ModelLight l) => Color.fromRGBO(
        (l.r * 255).round().clamp(0, 255),
        (l.g * 255).round().clamp(0, 255),
        (l.b * 255).round().clamp(0, 255),
        1,
      );

  /// Row of a markup meta-object (select, double-click = camera focus).
  Widget _metaRow(ModelData model, ModelMeta meta) {
    final selected = app.selectedMetaId == meta.id;
    final sub = meta.comment.trim().isNotEmpty
        ? meta.comment.trim().replaceAll('\n', ' ')
        : '${_metaKindName(meta.kind)} · ${meta.name}';
    return Listener(
      onPointerDown: (e) {
        if ((e.buttons & kPrimaryMouseButton) != 0 && _isDoubleClick(meta.id)) {
          app.selectMeta(meta.id);
          app.requestFocusMeta(meta.id);
        }
      },
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: selected ? const Color(0xFF2E5F8F) : null,
        contentPadding: const EdgeInsets.only(left: 16, right: 8),
        leading: Icon(
          _metaKindIcon(meta.kind),
          size: 16,
          color: selected ? const Color(0xFFCFE6FF) : _metaKindColor(meta.kind),
        ),
        title: Text(
          meta.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          sub.length > 60 ? '${sub.substring(0, 60)}…' : sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white70 : Colors.white54,
            fontSize: 10,
          ),
        ),
        onTap: () => app.selectMeta(meta.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Дублировать',
              icon: const Icon(Icons.copy, size: 15),
              onPressed: () {
                app.selectMeta(meta.id);
                app.duplicateMeta();
              },
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline, size: 15),
              onPressed: () {
                app.selectMeta(null);
                app.deleteMeta(meta.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _metaKindIcon(String kind) => switch (kind) {
        'marker' => Icons.flag,
        'box' => Icons.crop_free,
        _ => Icons.chat_bubble_outline,
      };

  String _metaKindName(String kind) => switch (kind) {
        'marker' => 'Маркер',
        'box' => 'Бокс',
        _ => 'Комментарий',
      };

  Color _metaKindColor(String kind) => switch (kind) {
        'marker' => const Color(0xFFFFD180),
        'box' => const Color(0xFF8FB0FF),
        _ => const Color(0xFF8CE99A),
      };

  Widget _groupRow(ModelData model, ModelGroup g) {
    final selected = app.selectedGroupId == g.id;
    return DragTarget<String>(
      onAcceptWithDetails: (d) {
        final id = d.data;
        if (id.isNotEmpty) app.moveObjectToGroup(id, g.id);
      },
      builder: (context, candidates, rejected) => Material(
        color: candidates.isNotEmpty ? const Color(0x332E5F8F) : Colors.transparent,
        child: ListTile(
          selected: selected,
          selectedTileColor: selected ? const Color(0xFF2E5F8F) : null,
          dense: true,
          leading: InkWell(
            onTap: () {
              if (_collapsedGroups.contains(g.id)) {
                _collapsedGroups.remove(g.id);
              } else {
                _collapsedGroups.add(g.id);
              }
              setState(() {});
            },
            child: Icon(
              _collapsedGroups.contains(g.id)
                  ? Icons.folder
                  : Icons.folder_open,
              size: 16,
              color: selected ? const Color(0xFFCFE6FF) : const Color(0xFF9FB4C7),
            ),
          ),
          title: Text(
            g.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${g.members.length} об.',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          onTap: () => app.selectGroup(g.id),
          trailing: IconButton(
            tooltip: 'Удалить группу',
            icon: const Icon(Icons.delete_outline, size: 15),
            onPressed: () => app.deleteGroup(g.id),
          ),
        ),
      ),
    );
  }

  Widget _objectRow(ModelData model, ModelObject obj, {required bool indent}) {
    final inGroup = app.isSelected(obj.id);
    final primary = app.selectedObjectId == obj.id;
    return Draggable<String>(
      data: obj.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2E5F8F),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            obj.name,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _objectTile(indent, inGroup, primary, obj)),
      child: _objectTile(indent, inGroup, primary, obj),
    );
  }

  Widget _objectTile(
      bool indent, bool inGroup, bool primary, ModelObject obj) {
    // Model instances and gltf instances are unpickable in the texture mode
    // (their content is not editable here) — tree clicks just select them
    // as objects.
    final notTexturable =
        (obj.isModelRef || obj.isGltfRef) && app.mode == EditorMode.texture;
    final modelSource = obj.isModelRef
        ? app.project?.models[obj.refModelId]?.name
        : null;
    final gltfCatalog = app.project == null ? null : app.model3d;
    // Only a settled catalog scan may claim a resource is missing.
    final gltfMissing = obj.isGltfRef &&
        gltfCatalog != null &&
        gltfCatalog.scanned &&
        gltfCatalog.entry(obj.gltfName) == null;
    return Listener(
      // Double-click detection via pointer events: the ListTile's own tap
      // recognizer is the only one in the gesture arena, so a single click
      // selects instantly (no kDoubleTapTimeout wait).
      onPointerDown: (e) {
        if ((e.buttons & kPrimaryMouseButton) != 0 && _isDoubleClick(obj.id)) {
          if (!notTexturable &&
              app.mode == EditorMode.texture &&
              app.texSubmode == TexSubmode.faces) {
            app.selectAllFaces(obj.id);
          } else {
            app.selectObject(obj.id);
          }
          app.requestFocusObject(obj.id);
        }
      },
      child: ListTile(
        dense: true,
        selected: inGroup,
        selectedTileColor: inGroup ? const Color(0xFF2E5F8F) : null,
          contentPadding: EdgeInsets.only(
            left: indent ? 28.0 : 16.0,
            right: 8.0,
          ),
          leading: _kindIcon(obj.kind, selected: inGroup),
          title: Text(
            obj.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: primary ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            modelSource != null
                ? 'модель · $modelSource'
                : obj.isModelRef
                    ? 'модель · ${obj.refModelId} (удалена)'
                    : obj.isGltfRef
                        ? gltfMissing
                            ? 'gltf · ${obj.gltfName} (удалён)'
                            : 'gltf · ${obj.gltfName}'
                        : '${obj.kind} · ${_fmt(obj.x)}, ${_fmt(obj.y)}, ${_fmt(obj.z)}',
            style: TextStyle(
              color: inGroup ? Colors.white70 : Colors.white54,
              fontSize: 10,
            ),
          ),
          onTap: () {
            final shift = HardwareKeyboard.instance.isShiftPressed ||
                HardwareKeyboard.instance.isControlPressed;
            if (!notTexturable &&
                app.mode == EditorMode.texture &&
                app.texSubmode == TexSubmode.faces) {
              app.selectAllFaces(obj.id, shift: shift);
            } else {
              app.selectObject(obj.id, shift: shift);
            }
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Дублировать',
                icon: const Icon(Icons.copy, size: 15),
                onPressed: () {
                  app.selectObject(obj.id);
                  app.duplicateObject();
                },
              ),
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline, size: 15),
                onPressed: () => app.deleteObject(obj.id),
              ),
            ],
          ),
        ),
    );
  }

  String _fmt(double v) => fmtDouble(v);

  Widget _kindIcon(String kind, {bool selected = false}) {
    final icon = switch (kind) {
      'cuboid' => Icons.crop_square,
      'trapezoid' => Icons.filter_tilt_shift,
      'cylinder' => Icons.crop_landscape,
      'plane' => Icons.crop_16_9,
      'sprite' => Icons.image,
      'polyhedron' => Icons.polyline,
      'model' => Icons.view_in_ar,
      'gltf' => Icons.animation,
      _ => Icons.square_outlined,
    };
    return Icon(
      icon,
      size: 16,
      color: selected ? const Color(0xFFCFE6FF) : const Color(0xFF9FB4C7),
    );
  }
}
