import 'package:flutter/material.dart';

import '../services/house_template.dart';
import '../services/room_template.dart';
import '../services/app_log.dart';
import '../state/app_state.dart';
import 'form_fields.dart';
import 'resource_thumb.dart';

/// The «По шаблону» dialog: pick a template — a fenced house (rect/П/Н) or
/// an indoor room — then sizes, elements and textures/sprites (with live
/// previews) and generate the model. Houses: `docs/house_chunk_generator.md`;
/// rooms: ported from the chunk_builder's `docs/room_chunk_generator.md`.
class HouseTemplateDialog extends StatefulWidget {
  final AppState app;
  const HouseTemplateDialog({super.key, required this.app});

  @override
  State<HouseTemplateDialog> createState() => _HouseTemplateDialogState();
}

/// The template family shown in the «Шаблон» segmented button.
enum TemplateKind {
  houseRect,
  houseU,
  houseH,
  room;

  String get label => switch (this) {
        TemplateKind.houseRect => 'Дом',
        TemplateKind.houseU => 'Особняк П',
        TemplateKind.houseH => 'Особняк Н',
        TemplateKind.room => 'Комната',
      };

  /// The house body shape, or null for the room template.
  HouseShape? get houseShape => switch (this) {
        TemplateKind.houseRect => HouseShape.rect,
        TemplateKind.houseU => HouseShape.u,
        TemplateKind.houseH => HouseShape.h,
        TemplateKind.room => null,
      };
}

class _HouseTemplateDialogState extends State<HouseTemplateDialog> {
  TemplateKind _template = TemplateKind.houseRect;

  // ── house (house shape) parameters ─────────────────────────────────────
  int _outerW = 5;
  int _outerD = 3;
  int _floors = 2;
  bool _fence = true;
  bool _beltCourses = true;
  bool _cornerBlocks = true;

  String _houseWall = '';
  String _fenceTex = '';
  String _fenceSprite = '';
  String _trim = '';
  String _trimSprite = '';
  String _roof = '';
  String _window = '';
  String _door = '';

  // ── room parameters (outer footprint cells) ────────────────────────────
  int _roomW = 5;
  int _roomD = 5;
  double _roomWallH = 2.2;
  double _roomWallT = 0.2;
  final Map<RoomSide, WallType> _roomWalls = {
    RoomSide.north: WallType.window,
    RoomSide.east: WallType.blank,
    RoomSide.south: WallType.entrance,
    RoomSide.west: WallType.blank,
  };
  double _doorH = 1.2;
  int _doorCells = 1;
  double _winW = 0.75;
  double _winH = 0.7;
  double _winSill = 0.5;
  bool _table = false;
  bool _bed = false;

  String _roomWallTex = '';
  String _roomFloorTex = '';
  String _roomCeilingTex = '';
  String _roomWindowTex = '';
  String _tableTex = '';
  String _bedTex = '';

  String _name = '';
  bool _nameEdited = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _name = _defaultName();
  }

  String _floorSuffix(int f) => switch (f) {
        1 => 'Одноэтажный',
        2 => 'Двухэтажный',
        3 => 'Трёхэтажный',
        _ => 'в $f этажей',
      };

  String _defaultName() => _template == TemplateKind.room
      ? 'Комната $_roomW×$_roomD'
      : '${_template.label} ${_outerW}x$_outerD ${_floorSuffix(_floors)}';

  void _select(TemplateKind t) {
    setState(() {
      _template = t;
      final shape = t.houseShape;
      if (shape != null) {
        _outerW = shape.defaultW;
        _outerD = shape.defaultD;
      }
      if (!_nameEdited) _name = _defaultName();
    });
  }

  void _bump() {
    if (!_nameEdited) _name = _defaultName();
  }

  /// Warms the texture cache for a picked asset (fire-and-forget): by the
  /// time «Создать» is pressed the loads have already finished, so the
  /// viewport's first render of the new model is instant instead of a
  /// multi-second freeze.
  void _warm(String family, String key) {
    if (key.isEmpty) return;
    if (family == 'sprite') {
      app.controller.resources?.sprite(key);
    } else {
      app.controller.resources?.texture(key);
    }
  }

  /// File names (with `.png`) of one resource family for the pickers. The
  /// app's [ResourceStore] is authoritative (it follows imports/renames);
  /// the engine catalog is a fallback while the store is still scanning.
  List<String> _familyFiles(String family) {
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

  bool get _roomHasEntrance =>
      _roomWalls.values.any((t) => t == WallType.entrance);

  void _create() {
    if (_template == TemplateKind.room) {
      _createRoom();
    } else {
      _createHouse();
    }
  }

  void _createHouse() {
    final shape = _template.houseShape!;
    logStage(
      'template-dialog',
      'create: shape=$shape ${_outerW}x$_outerD floors=$_floors '
          'fence=$_fence belts=$_beltCourses corners=$_cornerBlocks '
          'assets={wall:$_houseWall fenceT:$_fenceTex fenceS:$_fenceSprite '
          'trimT:$_trim trimS:$_trimSprite roof:$_roof window:$_window door:$_door}',
    );
    final model = timed(
      'template-dialog',
      'generateHouseModel',
      () => generateHouseModel(
        id: 'model', // replaced by the next free id in createFromTemplate
        name: _name.trim().isEmpty ? _defaultName() : _name.trim(),
        shape: shape,
        outerW: _outerW,
        outerD: _outerD,
        floors: _floors,
        fence: _fence,
        beltCourses: _beltCourses,
        cornerBlocks: _cornerBlocks,
        assets: HouseAssets(
          houseWall: _houseWall,
          fence: _fenceTex,
          fenceSprite: _fenceSprite,
          trim: _trim,
          trimSprite: _trimSprite,
          roof: _roof,
          window: _window,
          door: _door,
        ),
      ),
    );
    logStage(
      'template-dialog',
      'generated objects=${model.objects.length} '
          'groups=${model.groups.length}',
    );
    app.createFromTemplate(model);
    Navigator.pop(context);
  }

  void _createRoom() {
    // DoubleField has no clamps of its own — normalize at create time.
    final wallH = _roomWallH.clamp(1.2, 3.2);
    final wallT = _roomWallT.clamp(0.1, 0.5);
    final doorH = _doorH.clamp(0.6, wallH);
    final doorCells =
        _doorCells.clamp(1, _roomW < _roomD ? _roomW : _roomD).clamp(1, 2);
    final winW = _winW.clamp(0.3, 2.0);
    final winH = _winH.clamp(0.3, 2.0);
    final winSill = _winSill.clamp(0.0, 3.2);
    logStage(
      'template-dialog',
      'room: ${_roomW}x$_roomD wallH=$wallH t=$wallT '
          'walls=${_roomWalls.map((k, v) => MapEntry(k.name, v.name))} '
          'doorH=$doorH cells=$doorCells window=${winW}x$winH sill=$winSill '
          'table=$_table bed=$_bed',
    );
    final model = timed(
      'template-dialog',
      'generateRoomModel',
      () => generateRoomModel(
        id: 'model', // replaced by the next free id in createFromTemplate
        name: _name.trim().isEmpty ? _defaultName() : _name.trim(),
        width: _roomW,
        depth: _roomD,
        wallHeight: wallH,
        wallThickness: wallT,
        walls: Map.of(_roomWalls),
        doorHeight: doorH,
        doorWidthCells: doorCells,
        windowWidth: winW,
        windowHeight: winH,
        windowSill: winSill,
        table: _table,
        bed: _bed,
        assets: RoomAssets(
          wall: _roomWallTex,
          floor: _roomFloorTex,
          ceiling: _roomCeilingTex,
          window: _roomWindowTex,
          table: _tableTex,
          bed: _bedTex,
        ),
      ),
    );
    logStage(
      'template-dialog',
      'generated objects=${model.objects.length} '
          'groups=${model.groups.length}',
    );
    app.createFromTemplate(model);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = app.project;
    final textures = _familyFiles('texture');
    final sprites = _familyFiles('sprite');
    final root = store?.directory?.path;
    final texRoot = root == null ? '' : '$root/textures';
    final spriteRoot = root == null ? '' : '$root/sprites';

    return AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: const Text(
        'Создать по шаблону',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Шаблон'),
              SegmentedButton<TemplateKind>(
                showSelectedIcon: false,
                style: appSegmentedStyle(fontSize: 11),
                segments: [
                  for (final t in TemplateKind.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_template},
                onSelectionChanged: (s) => _select(s.first),
              ),
              const SizedBox(height: 14),
              if (_template == TemplateKind.room)
                ..._roomSections(textures, sprites, texRoot, spriteRoot)
              else
                ..._houseSections(textures, sprites, texRoot, spriteRoot),
              const SizedBox(height: 14),
              const SectionTitle('Имя'),
              NameField(
                initial: _name,
                onChanged: (v) => setState(() {
                  _name = v;
                  _nameEdited = v.trim().isNotEmpty;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed:
              _template == TemplateKind.room && !_roomHasEntrance ? null : _create,
          child: const Text('Создать'),
        ),
      ],
    );
  }

  // ── house sections ─────────────────────────────────────────────────────

  List<Widget> _houseSections(
      List<String> textures, List<String> sprites, String texRoot,
      String spriteRoot) {
    final shape = _template.houseShape!;
    final (minW, maxW) = shape.wRange;
    final (minD, maxD) = shape.dRange;
    return [
      const SectionTitle('Размеры'),
      _fieldRow(
        'Ширина',
        IntField(
          initial: _outerW,
          min: minW,
          max: maxW,
          onChanged: (v) => setState(() {
            _outerW = v;
            _bump();
          }),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Глубина',
        IntField(
          initial: _outerD,
          min: minD,
          max: maxD,
          onChanged: (v) => setState(() {
            _outerD = v;
            _bump();
          }),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Этажи',
        IntField(
          initial: _floors,
          min: 1,
          max: 5,
          onChanged: (v) => setState(() {
            _floors = v;
            _bump();
          }),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Элементы'),
      _switch('Забор', _fence, (v) => setState(() => _fence = v)),
      _switch('Пояски', _beltCourses, (v) => setState(() => _beltCourses = v)),
      _switch('Угловые блоки', _cornerBlocks,
          (v) => setState(() => _cornerBlocks = v)),
      const SizedBox(height: 14),
      const SectionTitle('Текстуры и спрайты'),
      _assetRow('Стены', textures, _houseWall, texRoot, (v) {
        _warm('texture', v);
        setState(() => _houseWall = v);
      }),
      // Забор accepts BOTH families: textures and sprites.
      _assetRowDual(
        'Забор',
        textures,
        sprites,
        _fenceTex,
        _fenceSprite,
        texRoot,
        spriteRoot,
        (v) {
          _warm('texture', v);
          setState(() => _fenceTex = v);
        },
        (v) {
          _warm('sprite', v);
          setState(() => _fenceSprite = v);
        },
      ),
      // Отделка accepts BOTH families: textures and sprites.
      _assetRowDual(
        'Отделка',
        textures,
        sprites,
        _trim,
        _trimSprite,
        texRoot,
        spriteRoot,
        (v) {
          _warm('texture', v);
          setState(() => _trim = v);
        },
        (v) {
          _warm('sprite', v);
          setState(() => _trimSprite = v);
        },
      ),
      _assetRow('Кровля', textures, _roof, texRoot, (v) {
        _warm('texture', v);
        setState(() => _roof = v);
      }),
      _assetRow('Окна', sprites, _window, spriteRoot, (v) {
        _warm('sprite', v);
        setState(() => _window = v);
      }),
      _assetRow('Дверь', sprites, _door, spriteRoot, (v) {
        _warm('sprite', v);
        setState(() => _door = v);
      }),
    ];
  }

  // ── room sections ──────────────────────────────────────────────────────

  /// The walkable entrance opening must fit the room's narrowest axis.
  int get _maxDoorCells {
    final narrow = _roomW < _roomD ? _roomW : _roomD;
    return narrow.clamp(1, 2);
  }

  List<Widget> _roomSections(
      List<String> textures, List<String> sprites, String texRoot,
      String spriteRoot) {
    return [
      const SectionTitle('Размеры (клетки)'),
      _fieldRow(
        'Ширина',
        IntField(
          initial: _roomW,
          min: 1,
          max: 32,
          onChanged: (v) => setState(() {
            _roomW = v;
            _doorCells = _doorCells.clamp(1, _maxDoorCells);
            _bump();
          }),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Глубина',
        IntField(
          initial: _roomD,
          min: 1,
          max: 32,
          onChanged: (v) => setState(() {
            _roomD = v;
            _doorCells = _doorCells.clamp(1, _maxDoorCells);
            _bump();
          }),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Высота стен, м',
        DoubleField(
          initial: _roomWallH,
          step: 0.1,
          onChanged: (v) => setState(() => _roomWallH = v),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Толщина, м',
        DoubleField(
          initial: _roomWallT,
          step: 0.05,
          onChanged: (v) => setState(() => _roomWallT = v),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Стены'),
      for (final side in RoomSide.values) ...[
        _wallRow(side),
        const SizedBox(height: 6),
      ],
      if (!_roomHasEntrance)
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'Хотя бы одна стена должна быть входом',
            style: TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      const SectionTitle('Проём входа'),
      _fieldRow(
        'Высота, м',
        DoubleField(
          initial: _doorH,
          step: 0.1,
          onChanged: (v) => setState(() => _doorH = v),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Ширина, кл.',
        IntField(
          initial: _doorCells,
          min: 1,
          max: _maxDoorCells,
          onChanged: (v) => setState(() => _doorCells = v),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Окно'),
      _fieldRow(
        'Ширина, м',
        DoubleField(
          initial: _winW,
          step: 0.05,
          onChanged: (v) => setState(() => _winW = v),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Высота, м',
        DoubleField(
          initial: _winH,
          step: 0.05,
          onChanged: (v) => setState(() => _winH = v),
        ),
      ),
      const SizedBox(height: 8),
      _fieldRow(
        'Низ над полом, м',
        DoubleField(
          initial: _winSill,
          step: 0.05,
          onChanged: (v) => setState(() => _winSill = v),
        ),
      ),
      const SizedBox(height: 14),
      const SectionTitle('Мебель'),
      _switch('Стол', _table, (v) => setState(() => _table = v)),
      if (_table)
        _assetRow('Стол', textures, _tableTex, texRoot, (v) {
          _warm('texture', v);
          setState(() => _tableTex = v);
        }),
      _switch('Кровать', _bed, (v) => setState(() => _bed = v)),
      if (_bed)
        _assetRow('Кровать', textures, _bedTex, texRoot, (v) {
          _warm('texture', v);
          setState(() => _bedTex = v);
        }),
      const SizedBox(height: 8),
      const SectionTitle('Текстуры'),
      _assetRow('Стены', textures, _roomWallTex, texRoot, (v) {
        _warm('texture', v);
        setState(() => _roomWallTex = v);
      }),
      _assetRow('Пол', textures, _roomFloorTex, texRoot, (v) {
        _warm('texture', v);
        setState(() => _roomFloorTex = v);
      }),
      _assetRow('Потолок', textures, _roomCeilingTex, texRoot, (v) {
        _warm('texture', v);
        setState(() => _roomCeilingTex = v);
      }),
      _assetRow('Окно', sprites, _roomWindowTex, spriteRoot, (v) {
        _warm('sprite', v);
        setState(() => _roomWindowTex = v);
      }),
    ];
  }

  // ── shared controls ────────────────────────────────────────────────────

  Widget _fieldRow(String label, Widget field) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  Widget _wallRow(RoomSide side) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            side.label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: SegmentedButton<WallType>(
            showSelectedIcon: false,
            style: appSegmentedStyle(fontSize: 11),
            segments: [
              for (final t in WallType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_roomWalls[side]!},
            onSelectionChanged: (s) => setState(() => _roomWalls[side] = s.first),
          ),
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  /// One asset picker: label + file dropdown + a live preview of the
  /// selected PNG (or a placeholder when «Нет»).
  Widget _assetRow(
    String label,
    List<String> files,
    String value,
    String rootDir,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: value.isEmpty ? null : value,
              key: ValueKey('template-file-$label-$value'),
              dropdownColor: const Color(0xFF2E3440),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              hint: const Text('Нет', style: TextStyle(fontSize: 12)),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Нет',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                for (final k in files)
                  DropdownMenuItem(
                    value: k,
                    child: Text(k, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (k) => onChanged(k ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          _assetPreview(rootDir, value),
        ],
      ),
    );
  }

  /// One picker over BOTH asset families: textures first, then sprites
  /// (separated by non-selectable dividers). The texture and sprite keys
  /// are mutually exclusive.
  Widget _assetRowDual(
    String label,
    List<String> texFiles,
    List<String> spriteFiles,
    String texValue,
    String spriteValue,
    String texRoot,
    String spriteRoot,
    ValueChanged<String> onTex,
    ValueChanged<String> onSprite,
  ) {
    final selected = texValue.isNotEmpty
        ? 'texture:$texValue'
        : spriteValue.isNotEmpty
            ? 'sprite:$spriteValue'
            : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selected.isEmpty ? null : selected,
              key: ValueKey('template-dual-$label-$selected'),
              dropdownColor: const Color(0xFF2E3440),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              hint: const Text('Нет', style: TextStyle(fontSize: 12)),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Нет',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (texFiles.isNotEmpty) ...[
                  const DropdownMenuItem(
                    enabled: false,
                    value: '__tex_header__',
                    child: Text(
                      '— Текстуры —',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  for (final k in texFiles)
                    DropdownMenuItem(
                      value: 'texture:$k',
                      child: Text(k, overflow: TextOverflow.ellipsis),
                    ),
                ],
                if (spriteFiles.isNotEmpty) ...[
                  const DropdownMenuItem(
                    enabled: false,
                    value: '__sprite_header__',
                    child: Text(
                      '— Спрайты —',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  for (final k in spriteFiles)
                    DropdownMenuItem(
                      value: 'sprite:$k',
                      child: Text(k, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ],
              onChanged: (v) {
                final sel = v ?? '';
                if (sel.startsWith('texture:')) {
                  onTex(sel.substring(8));
                  onSprite('');
                } else if (sel.startsWith('sprite:')) {
                  onSprite(sel.substring(7));
                  onTex('');
                } else {
                  onTex('');
                  onSprite('');
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          texValue.isNotEmpty
              ? _assetPreview(texRoot, texValue)
              : spriteValue.isNotEmpty
                  ? _assetPreview(spriteRoot, spriteValue)
                  : _assetPreview('', ''),
        ],
      ),
    );
  }

  /// 40px live preview of a PNG (or a placeholder when none selected).
  Widget _assetPreview(String rootDir, String value) {
    return SizedBox(
      width: 40,
      height: 40,
      child: value.isEmpty
          ? Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF555B66)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Icon(
                Icons.image_not_supported_outlined,
                size: 18,
                color: Colors.white24,
              ),
            )
          : ResourceThumb(path: '$rootDir/$value'),
    );
  }
}
