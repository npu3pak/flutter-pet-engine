import '../models/model_scene.dart';
import 'build_ops.dart';
import 'construction_model.dart';
import 'level_grid.dart';
import 'scene_placement.dart';

/// Severity of a [LevelIssue].
enum LevelIssueSeverity { warning, error }

/// What a [LevelIssue] reports.
enum LevelIssueKind {
  /// A cell references a region id the grid does not define.
  unknownRegion,

  /// A passable cell is unreachable from the entries.
  disconnectedCell,

  /// Scene footprints overlap on the level grid.
  placementOverlap,

  /// Adjacent scenes have doors that do not line up.
  dockingMismatch,

  /// A door box sits on a border side the scene does not declare as an entry.
  doorWithoutEntry,

  /// A modern scene declares an entry side with no door (a hole in the wall).
  entryWithoutDoor,

  /// A scene's declared entry side faces another scene's solid wall.
  entryFacesWall,

  /// The facade (`front`) is set but is not one of the entry sides.
  frontNotEntry,

  /// A grid opening references a cell outside the grid.
  openingOutsideGrid,

  /// A door opening does not connect two passable cells.
  openingBlocked,

  /// Two construction elements share an id (or one has no id).
  duplicateElementId,

  /// A construction element reaches outside the level grid (the grid is
  /// assumed aligned with the model: cell (0,0) at the model origin, bounds
  /// −0.5…cols−0.5 × −0.5…rows−0.5 — review note 9).
  elementOutsideGrid,

  /// Two construction elements' bounds intersect (debug check, opt-in).
  elementOverlap,
}

/// One validator finding: kind, severity, human-readable message and the
/// location (a level cell and/or an element id).
class LevelIssue {
  const LevelIssue({
    required this.kind,
    required this.severity,
    required this.message,
    this.cell,
    this.elementId,
    this.otherElementId,
  });

  final LevelIssueKind kind;
  final LevelIssueSeverity severity;
  final String message;
  final (int, int)? cell;
  final String? elementId;
  final String? otherElementId;

  @override
  String toString() => '${severity.name}: $message';
}

/// Pure-data checks of the level layer (no GPU): connectivity, gaps,
/// intersections, door/entries consistency and construction structure.
///
/// The checks are intentionally conservative: a legacy scene's declared entry
/// without a door box is an open passage (no warning); only modern scenes
/// (with door boxes) are expected to have a door per entry side. An entry
/// side adjacent to another scene must face at least one passable border cell
/// of the neighbor ([LevelIssueKind.entryFacesWall]); the facade must be one
/// of the entry sides ([LevelIssueKind.frontNotEntry]).
class LevelValidator {
  const LevelValidator();

  /// Runs every check the given inputs allow.
  List<LevelIssue> validate({
    LevelGrid? grid,
    List<ScenePlacement>? placements,
    ConstructionModel? model,
    Set<(int, int)>? starts,
  }) =>
      [
        if (grid != null) ...checkGrid(grid),
        if (grid != null) ...checkGridConnectivity(grid, starts: starts),
        if (placements != null) ...checkPlacements(placements, starts: starts),
        if (model != null) ...checkConstruction(model, grid: grid),
      ];

  // ── grid ─────────────────────────────────────────────────────────────

  /// Structural grid checks: cells referencing unknown regions and opening
  /// placement (a door must connect two passable cells; a border opening
  /// leading outside the grid is allowed and not checked).
  List<LevelIssue> checkGrid(LevelGrid grid) {
    final issues = <LevelIssue>[];
    for (final (cell, data) in grid.cells) {
      final region = data.regionId;
      if (region != null && !grid.regions.containsKey(region)) {
        issues.add(LevelIssue(
          kind: LevelIssueKind.unknownRegion,
          severity: LevelIssueSeverity.warning,
          message: 'клетка (${cell.$1}, ${cell.$2}) ссылается на '
              'неизвестный регион «$region»',
          cell: cell,
        ));
      }
    }
    for (final opening in grid.openings) {
      final cell = (opening.row, opening.col);
      if (!grid.contains(opening.row, opening.col)) {
        issues.add(LevelIssue(
          kind: LevelIssueKind.openingOutsideGrid,
          severity: LevelIssueSeverity.warning,
          message: 'открытие (${opening.row}, ${opening.col}) вне сетки',
          cell: cell,
        ));
        continue;
      }
      // Windows are geometry only — only doors must connect two
      // passable cells. A door on the outer border leads outside the level
      // and is not checked.
      if (opening.kind != LevelOpeningKind.door) continue;
      final neighbor =
          grid.sideNeighbor(opening.row, opening.col, opening.side);
      if (neighbor == null) continue;
      if (!grid.isPassable(opening.row, opening.col) ||
          !grid.isPassable(neighbor.$1, neighbor.$2)) {
        issues.add(LevelIssue(
          kind: LevelIssueKind.openingBlocked,
          severity: LevelIssueSeverity.warning,
          message: 'дверь (${opening.row}, ${opening.col}) на стороне '
              '${opening.side.name} соединяет непроходимые клетки',
          cell: cell,
        ));
      }
    }
    return issues;
  }

  /// Connectivity of the grid's passable cells: every passable cell must be
  /// reachable from [starts] (default: the passable border cells; a single
  /// passable cell when the border has none).
  List<LevelIssue> checkGridConnectivity(
    LevelGrid grid, {
    Set<(int, int)>? starts,
  }) {
    final passable = {for (final c in grid.passableCells) c};
    if (passable.isEmpty) return const [];
    final startSet = _startSet(
      passable,
      starts,
      () => _borderCells(grid.rows, grid.cols).where(passable.contains).toSet(),
    );
    final visited = _flood(passable, startSet);
    return [
      for (final cell in passable)
        if (!visited.contains(cell))
          LevelIssue(
            kind: LevelIssueKind.disconnectedCell,
            severity: LevelIssueSeverity.warning,
            message: 'клетка (${cell.$1}, ${cell.$2}) недостижима от входов',
            cell: cell,
          ),
    ];
  }

  // ── scene placements ─────────────────────────────────────────────────

  /// Placement checks: footprint overlaps, door/entries consistency, docking
  /// of adjacent scenes and connectivity of the covered cells.
  List<LevelIssue> checkPlacements(
    List<ScenePlacement> placements, {
    Set<(int, int)>? starts,
  }) {
    final issues = <LevelIssue>[];
    final layout = SceneLayout(placements);

    for (final e in layout.overlaps.entries) {
      final ids = e.value.map((p) => p.scene.id).join(', ');
      issues.add(LevelIssue(
        kind: LevelIssueKind.placementOverlap,
        severity: LevelIssueSeverity.error,
        message: 'сцены накладываются в клетке (${e.key.$1}, ${e.key.$2}): $ids',
        cell: e.key,
      ));
    }

    for (final p in placements) {
      for (final side in ModelSide.values) {
        final doors = p.doorBorderCells(side);
        final hasEntry = p.hasEntry(side);
        if (doors.isNotEmpty && !hasEntry) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.doorWithoutEntry,
            severity: LevelIssueSeverity.warning,
            message: '${p.scene.id}: дверь на стороне ${side.name} '
                'не заявлена во entries',
            elementId: p.scene.id,
          ));
        }
        if (p.hasDoors && hasEntry && doors.isEmpty) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.entryWithoutDoor,
            severity: LevelIssueSeverity.warning,
            message: '${p.scene.id}: вход ${side.name} без двери '
                '(открытый проход)',
            elementId: p.scene.id,
          ));
        }
      }
      final front = p.scene.front;
      if (front != null && !p.scene.entries.contains(front)) {
        issues.add(LevelIssue(
          kind: LevelIssueKind.frontNotEntry,
          severity: LevelIssueSeverity.warning,
          message: '${p.scene.id}: лицевая сторона ${front.name} '
              'не входит во входные стороны',
          elementId: p.scene.id,
        ));
      }
    }

    for (var i = 0; i < placements.length; i++) {
      for (var j = i + 1; j < placements.length; j++) {
        final a = placements[i], b = placements[j];
        final side = SceneLayout.sharedSide(a, b);
        if (side == null) continue;
        final opposite = oppositeSide(side);
        if (!layout.dockedWith(a, b)) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.dockingMismatch,
            severity: LevelIssueSeverity.warning,
            message: '${a.scene.id} и ${b.scene.id}: двери на общем стыке '
                'не совпадают',
            elementId: a.scene.id,
            otherElementId: b.scene.id,
          ));
        }
        // Entry-declared openings must not face a solid neighbor wall (the
        // legacy scenes carry no door boxes — their openings are implicit).
        if (a.hasEntry(side) && b.openBorderCells(opposite).isEmpty) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.entryFacesWall,
            severity: LevelIssueSeverity.warning,
            message: '${a.scene.id}: вход ${side.name} упирается в глухую '
                'стену ${b.scene.id}',
            elementId: a.scene.id,
            otherElementId: b.scene.id,
          ));
        }
        if (b.hasEntry(opposite) && a.openBorderCells(side).isEmpty) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.entryFacesWall,
            severity: LevelIssueSeverity.warning,
            message: '${b.scene.id}: вход ${opposite.name} упирается в глухую '
                'стену ${a.scene.id}',
            elementId: b.scene.id,
            otherElementId: a.scene.id,
          ));
        }
      }
    }

    issues.addAll(_placementConnectivity(placements, layout, starts));
    return issues;
  }

  List<LevelIssue> _placementConnectivity(
    List<ScenePlacement> placements,
    SceneLayout layout,
    Set<(int, int)>? starts,
  ) {
    if (placements.isEmpty) return const [];
    var minRow = placements.first.originRow;
    var maxRow = minRow + placements.first.footprintRows - 1;
    var minCol = placements.first.originCol;
    var maxCol = minCol + placements.first.footprintCols - 1;
    for (final p in placements) {
      minRow = p.originRow < minRow ? p.originRow : minRow;
      minCol = p.originCol < minCol ? p.originCol : minCol;
      final endRow = p.originRow + p.footprintRows - 1;
      final endCol = p.originCol + p.footprintCols - 1;
      maxRow = endRow > maxRow ? endRow : maxRow;
      maxCol = endCol > maxCol ? endCol : maxCol;
    }
    final domain = <(int, int)>{};
    for (var r = minRow; r <= maxRow; r++) {
      for (var c = minCol; c <= maxCol; c++) {
        domain.add((r, c));
      }
    }
    // Uncovered cells are open level floor (the street between houses).
    bool passable(int r, int c) => layout.isPassableAt(r, c) ?? true;
    final passableCells = {for (final cell in domain) if (passable(cell.$1, cell.$2)) cell};
    if (passableCells.isEmpty) return const [];
    final startSet = _startSet(
      passableCells,
      starts,
      () => {
        for (final cell in passableCells)
          if (cell.$1 == minRow ||
              cell.$1 == maxRow ||
              cell.$2 == minCol ||
              cell.$2 == maxCol)
            cell,
      },
    );
    final visited = _flood(passableCells, startSet);
    final issues = <LevelIssue>[];
    for (final cell in passableCells) {
      if (visited.contains(cell)) continue;
      // Report only cells a scene actually covers (the open street is not an
      // error even if the starts miss it).
      if (layout.isPassableAt(cell.$1, cell.$2) == null) continue;
      issues.add(LevelIssue(
        kind: LevelIssueKind.disconnectedCell,
        severity: LevelIssueSeverity.warning,
        message: 'клетка (${cell.$1}, ${cell.$2}) недостижима от входов',
        cell: cell,
      ));
    }
    return issues;
  }

  // ── construction model ───────────────────────────────────────────────

  /// Structural checks of the construction model: duplicate/empty ids and
  /// elements reaching outside the grid. Element-bounds intersections are an
  /// opt-in debug check ([checkOverlaps]) — legitimate corner crossings make
  /// it noisy.
  List<LevelIssue> checkConstruction(
    ConstructionModel model, {
    LevelGrid? grid,
    bool checkOverlaps = false,
  }) {
    final issues = <LevelIssue>[];
    final seen = <String>{};
    for (final o in model.elements) {
      if (o.id.isEmpty) {
        issues.add(const LevelIssue(
          kind: LevelIssueKind.duplicateElementId,
          severity: LevelIssueSeverity.error,
          message: 'элемент без id',
        ));
      } else if (!seen.add(o.id)) {
        issues.add(LevelIssue(
          kind: LevelIssueKind.duplicateElementId,
          severity: LevelIssueSeverity.error,
          message: 'дублирующийся id элемента «${o.id}»',
          elementId: o.id,
        ));
      }
      if (grid != null) {
        final (lo, hi) = objectBounds(o);
        const eps = 1e-6;
        if (lo.x < -0.5 - eps ||
            hi.x > grid.cols - 0.5 + eps ||
            lo.z < -0.5 - eps ||
            hi.z > grid.rows - 0.5 + eps) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.elementOutsideGrid,
            severity: LevelIssueSeverity.warning,
            message: 'элемент «${o.id}» выходит за сетку '
                '${grid.cols}×${grid.rows}',
            elementId: o.id,
          ));
        }
      }
    }
    if (checkOverlaps) {
      issues.addAll(_elementOverlaps(model));
    }
    return issues;
  }

  List<LevelIssue> _elementOverlaps(ConstructionModel model) {
    final issues = <LevelIssue>[];
    final bounds = [
      for (final o in model.elements) (o, objectBounds(o)),
    ];
    for (var i = 0; i < bounds.length; i++) {
      for (var j = i + 1; j < bounds.length; j++) {
        final (a, (aLo, aHi)) = bounds[i];
        final (b, (bLo, bHi)) = bounds[j];
        const eps = 1e-6;
        final intersects = aLo.x < bHi.x - eps &&
            bLo.x < aHi.x - eps &&
            aLo.y < bHi.y - eps &&
            bLo.y < aHi.y - eps &&
            aLo.z < bHi.z - eps &&
            bLo.z < aHi.z - eps;
        if (intersects) {
          issues.add(LevelIssue(
            kind: LevelIssueKind.elementOverlap,
            severity: LevelIssueSeverity.warning,
            message: 'элементы «${a.id}» и «${b.id}» пересекаются',
            elementId: a.id,
            otherElementId: b.id,
          ));
        }
      }
    }
    return issues;
  }

  // ── helpers ──────────────────────────────────────────────────────────

  Set<(int, int)> _startSet(
    Set<(int, int)> passable,
    Set<(int, int)>? starts,
    Set<(int, int)> Function() defaultStarts,
  ) {
    if (starts != null) {
      final filtered = starts.where(passable.contains).toSet();
      if (filtered.isNotEmpty) return filtered;
    }
    final fallback = defaultStarts();
    if (fallback.isNotEmpty) return fallback;
    return {passable.first};
  }

  Set<(int, int)> _flood(
    Set<(int, int)> passable,
    Set<(int, int)> starts,
  ) {
    final visited = <(int, int)>{...starts};
    final queue = <(int, int)>[...starts];
    while (queue.isNotEmpty) {
      final (r, c) = queue.removeLast();
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final next = (r + dr, c + dc);
        if (passable.contains(next) && visited.add(next)) queue.add(next);
      }
    }
    return visited;
  }

  Iterable<(int, int)> _borderCells(int rows, int cols) sync* {
    for (var c = 0; c < cols; c++) {
      yield (0, c);
      if (rows > 1) yield (rows - 1, c);
    }
    for (var r = 1; r < rows - 1; r++) {
      yield (r, 0);
      if (cols > 1) yield (r, cols - 1);
    }
  }
}
