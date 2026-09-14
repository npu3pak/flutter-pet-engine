/// Arbitrary polygonal geometry (the `polyhedron` document kind): indexed
/// vertices plus planar faces that may have holes. Faces are flat n-gons
/// (concave allowed); the renderer triangulates them per rebuild, the editor
/// edits vertices/faces directly.
///
/// Conventions:
/// - an outer loop is ordered CCW when seen from OUTSIDE the solid, so the
///   Newell normal of the loop is the outward face normal;
/// - hole loops are ordered opposite to the outer loop (the triangulator
///   normalizes orientation regardless);
/// - the UV list of a loop is parallel to its vertex list. Explicit UVs are
///   final texture coordinates (texture repeats, as authored by an importer);
///   an empty list means "compute planar UVs from the material".
///
/// ## Пример: плита с отверстием
///
/// ```dart
/// import 'package:pet_engine_v2/pet_engine_v2.dart';
/// import 'package:vector_math/vector_math.dart' as vm;
///
/// final plate = PolyMesh(
///   vertices: [
///     vm.Vector3(0, 0, 0), vm.Vector3(4, 0, 0),   // внешний контур, CCW
///     vm.Vector3(4, 0, 4), vm.Vector3(0, 0, 4),
///     vm.Vector3(1, 0, 1), vm.Vector3(3, 0, 1),   // отверстие
///     vm.Vector3(3, 0, 3), vm.Vector3(1, 0, 3),
///   ],
///   faces: [
///     PolyFace(
///       key: '+y',
///       outer: PolyLoop(vertices: [0, 1, 2, 3]),
///       holes: [PolyLoop(vertices: [4, 5, 6, 7])],
///     ),
///   ],
/// );
/// ```
///
/// Готовые формы: [PolyMesh.box] (куб с ключами `+x`…`-z`),
/// [bakePolyhedron] (конверсия примитива или CSG в многогранник),
/// [PolyhedronNode] (рендер сети напрямую, без документа).
library;

import 'package:vector_math/vector_math.dart' as vm;

/// Rounds to 6 decimals — the serialization precision of polyhedron geometry
/// (legacy coordinates keep [round3]).
double round6(double v) => (v * 1e6).roundToDouble() / 1e6;

/// One closed contour of a face: vertex indices into [PolyMesh.vertices] and
/// optional explicit texture coordinates parallel to them.
class PolyLoop {
  final List<int> vertices;
  final List<vm.Vector2> uvs;

  PolyLoop({required List<int> vertices, List<vm.Vector2>? uvs})
      : vertices = List<int>.of(vertices),
        uvs = List<vm.Vector2>.of(uvs ?? const []);

  /// Whether the loop carries usable explicit UVs.
  bool get hasUvs => uvs.length == vertices.length && uvs.isNotEmpty;

  PolyLoop copy() => PolyLoop(
        vertices: vertices,
        uvs: [for (final uv in uvs) uv.clone()],
      );

  void addUv(vm.Vector2 uv) => uvs.add(uv);

  Map<String, Object> toJson() {
    final m = <String, Object>{'v': List<int>.of(vertices)};
    if (hasUvs) {
      m['uv'] = [
        for (final uv in uvs) [round6(uv.x), round6(uv.y)],
      ];
    }
    return m;
  }

  factory PolyLoop.fromJson(Object? json) {
    final m = (json as Map?) ?? const {};
    final verts = m['v'] is List
        ? [
            for (final v in m['v'] as List)
              if (v is num) v.toInt(),
          ]
        : <int>[];
    final uvs = <vm.Vector2>[];
    if (m['uv'] is List) {
      for (final e in m['uv'] as List) {
        if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
          uvs.add(vm.Vector2(
            (e[0] as num).toDouble(),
            (e[1] as num).toDouble(),
          ));
        }
      }
    }
    return PolyLoop(vertices: verts, uvs: uvs);
  }
}

/// One flat face of a [PolyMesh]: a stable [key] (per-face materials and
/// editor selection), the outer loop and optional holes.
class PolyFace {
  final String key;
  final PolyLoop outer;
  final List<PolyLoop> holes;

  PolyFace({
    required this.key,
    required this.outer,
    List<PolyLoop>? holes,
  }) : holes = holes == null ? <PolyLoop>[] : List<PolyLoop>.of(holes);

  /// A triangular face (`a`, `b`, `c` — CCW from outside). [uvs] are
  /// parallel to the vertices when given.
  factory PolyFace.triangle({
    required String key,
    required int a,
    required int b,
    required int c,
    List<vm.Vector2>? uvs,
  }) =>
      PolyFace(key: key, outer: PolyLoop(vertices: [a, b, c], uvs: uvs));

  /// A quadrilateral face (`a`, `b`, `c`, `d` — CCW from outside). [uvs]
  /// are parallel to the vertices when given.
  factory PolyFace.quad({
    required String key,
    required int a,
    required int b,
    required int c,
    required int d,
    List<vm.Vector2>? uvs,
  }) =>
      PolyFace(key: key, outer: PolyLoop(vertices: [a, b, c, d], uvs: uvs));

  PolyFace copy() => PolyFace(
        key: key,
        outer: outer.copy(),
        holes: [for (final h in holes) h.copy()],
      );

  Map<String, Object> toJson() {
    final m = <String, Object>{
      'k': key,
      'v': List<int>.of(outer.vertices),
    };
    if (outer.hasUvs) {
      m['uv'] = [
        for (final uv in outer.uvs) [round6(uv.x), round6(uv.y)],
      ];
    }
    if (holes.isNotEmpty) {
      m['h'] = [
        for (final h in holes)
          {
            'v': List<int>.of(h.vertices),
            if (h.hasUvs)
              'uv': [
                for (final uv in h.uvs) [round6(uv.x), round6(uv.y)],
              ],
          },
      ];
    }
    return m;
  }

  factory PolyFace.fromJson(Object? json) {
    final m = (json as Map?) ?? const {};
    final holes = <PolyLoop>[];
    if (m['h'] is List) {
      for (final h in m['h'] as List) {
        final loop = PolyLoop.fromJson(h);
        if (loop.vertices.length >= 3) holes.add(loop);
      }
    }
    return PolyFace(
      key: (m['k'] as String?) ?? '',
      outer: PolyLoop(
        vertices: m['v'] is List
            ? [
                for (final v in m['v'] as List)
                  if (v is num) v.toInt(),
              ]
            : const <int>[],
        uvs: _uvsFromJson(m['uv']),
      ),
      holes: holes,
    );
  }
}

List<vm.Vector2> _uvsFromJson(Object? json) {
  final out = <vm.Vector2>[];
  if (json is List) {
    for (final e in json) {
      if (e is List && e.length >= 2 && e[0] is num && e[1] is num) {
        out.add(vm.Vector2(
          (e[0] as num).toDouble(),
          (e[1] as num).toDouble(),
        ));
      }
    }
  }
  return out;
}

/// A polyhedron mesh: shared vertices and planar faces with holes. Pure data
/// (copy/toJson/fromJson); triangulation is computed on demand.
class PolyMesh {
  final List<vm.Vector3> vertices;
  final List<PolyFace> faces;

  PolyMesh({
    required List<vm.Vector3> vertices,
    required List<PolyFace> faces,
  })  : vertices = [for (final v in vertices) v.clone()],
        faces = List<PolyFace>.of(faces);

  /// A rectangular box centred on X/Z with its base at y = 0 — the same
  /// local frame as the document cuboid, with the same face keys
  /// (`+x`, `-x`, `+y`, `-y`, `+z`, `-z`), loops wound CCW from outside.
  ///
  /// ```dart
  /// final cube = PolyMesh.box(w: 2, h: 1, d: 3);
  /// controller.add(PolyhedronNode(mesh: cube, material: SceneMaterial.pbr()));
  /// ```
  factory PolyMesh.box({double w = 1, double h = 1, double d = 1}) {
    final hx = w / 2, hz = d / 2;
    return PolyMesh(
      vertices: [
        vm.Vector3(-hx, 0, -hz),
        vm.Vector3(hx, 0, -hz),
        vm.Vector3(hx, 0, hz),
        vm.Vector3(-hx, 0, hz),
        vm.Vector3(-hx, h, -hz),
        vm.Vector3(hx, h, -hz),
        vm.Vector3(hx, h, hz),
        vm.Vector3(-hx, h, hz),
      ],
      faces: [
        PolyFace.quad(key: '+x', a: 2, b: 1, c: 5, d: 6),
        PolyFace.quad(key: '-x', a: 0, b: 3, c: 7, d: 4),
        PolyFace.quad(key: '+y', a: 7, b: 6, c: 5, d: 4),
        PolyFace.quad(key: '-y', a: 0, b: 1, c: 2, d: 3),
        PolyFace.quad(key: '+z', a: 3, b: 2, c: 6, d: 7),
        PolyFace.quad(key: '-z', a: 1, b: 0, c: 4, d: 5),
      ],
    );
  }

  PolyMesh copy() => PolyMesh(
        vertices: vertices,
        faces: [for (final f in faces) f.copy()],
      );

  /// The axis-aligned bounds of the vertex set, or null when empty.
  (vm.Vector3, vm.Vector3)? get vertexBounds {
    if (vertices.isEmpty) return null;
    var minX = vertices.first.x, maxX = minX;
    var minY = vertices.first.y, maxY = minY;
    var minZ = vertices.first.z, maxZ = minZ;
    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
      if (v.z < minZ) minZ = v.z;
      if (v.z > maxZ) maxZ = v.z;
    }
    return (vm.Vector3(minX, minY, minZ), vm.Vector3(maxX, maxY, maxZ));
  }

  /// The face with [key], or null.
  PolyFace? faceByKey(String key) {
    for (final f in faces) {
      if (f.key == key) return f;
    }
    return null;
  }

  Map<String, Object> toJson() => {
        'verts': [
          for (final v in vertices) [round6(v.x), round6(v.y), round6(v.z)],
        ],
        'faces': [for (final f in faces) f.toJson()],
      };

  factory PolyMesh.fromJson(Object? json) {
    final m = (json as Map?) ?? const {};
    final verts = <vm.Vector3>[];
    if (m['verts'] is List) {
      for (final e in m['verts'] as List) {
        if (e is List && e.length >= 3 && e[0] is num && e[1] is num && e[2] is num) {
          verts.add(vm.Vector3(
            (e[0] as num).toDouble(),
            (e[1] as num).toDouble(),
            (e[2] as num).toDouble(),
          ));
        }
      }
    }
    final faces = <PolyFace>[];
    if (m['faces'] is List) {
      for (final e in m['faces'] as List) {
        faces.add(PolyFace.fromJson(e));
      }
    }
    final mesh = PolyMesh(vertices: verts, faces: faces);
    mesh.sanitize();
    return mesh;
  }

  /// Drops references to missing vertices and degenerate loops in place.
  /// Valid data is untouched (lossless roundtrip); corrupted files load
  /// without throwing and without phantom geometry.
  void sanitize() {
    final count = vertices.length;
    bool ok(int i) => i >= 0 && i < count;
    final valid = <PolyFace>[];
    for (final face in faces) {
      if (face.outer.vertices.length < 3 ||
          !face.outer.vertices.every(ok)) {
        continue;
      }
      final holes = <PolyLoop>[
        for (final h in face.holes)
          if (h.vertices.length >= 3 && h.vertices.every(ok)) h,
      ];
      face.holes
        ..clear()
        ..addAll(holes);
      valid.add(face);
    }
    faces
      ..clear()
      ..addAll(valid);
    // UV arrays must be parallel to their loops; a mismatch disables them
    // rather than corrupting the geometry.
    for (final face in faces) {
      if (face.outer.uvs.isNotEmpty &&
          face.outer.uvs.length != face.outer.vertices.length) {
        face.outer.uvs.clear();
      }
      for (final h in face.holes) {
        if (h.uvs.isNotEmpty && h.uvs.length != h.vertices.length) {
          h.uvs.clear();
        }
      }
    }
  }

  // ── редактирование (сцена-редактор и импортёры) ──────────────────────

  /// Все индексы вершин, на которые ссылаются грани [faceKeys] (внешние
  /// контуры и дырки). Неизвестные ключи игнорируются.
  Set<int> verticesOfFaces(Iterable<String> faceKeys) {
    final out = <int>{};
    for (final key in faceKeys) {
      final face = faceByKey(key);
      if (face == null) continue;
      out
        ..addAll(face.outer.vertices)
        ..addAll(face.holes.expand((h) => h.vertices));
    }
    return out;
  }

  /// Сдвигает вершины [indices] на [delta]. Неверные индексы пропускаются.
  void moveVertices(Iterable<int> indices, vm.Vector3 delta) {
    for (final i in indices) {
      if (i < 0 || i >= vertices.length) continue;
      vertices[i] = vertices[i] + delta;
    }
  }

  /// Поворачивает вершины [indices] вокруг [pivot] на [radians] вокруг
  /// [axis]. Неверные индексы пропускаются.
  void rotateVertices(
    Iterable<int> indices,
    vm.Vector3 axis,
    double radians, {
    required vm.Vector3 pivot,
  }) {
    if (axis.length2 < 1e-18 || radians == 0) return;
    final rotation = vm.Quaternion.axisAngle(axis.normalized(), radians);
    for (final i in indices) {
      if (i < 0 || i >= vertices.length) continue;
      final offset = vertices[i] - pivot;
      offset.applyQuaternion(rotation);
      vertices[i] = pivot + offset;
    }
  }

  /// Вставляет новую вершину в [faceKey] — в ближайшее ребро внешнего
  /// контура или дырки, в точке [position]. UV новой вершины
  /// интерполируется по параметру ближайшей точки (когда у контура есть
  /// явные UV). Возвращает индекс новой вершины или null, если грань не
  /// найдена или у контуров нет рёбер.
  int? addVertexToFace(String faceKey, vm.Vector3 position) {
    final face = faceByKey(faceKey);
    if (face == null) return null;
    PolyLoop? bestLoop;
    var bestIndex = 0;
    var bestT = 0.0;
    var bestDistance = double.infinity;
    for (final loop in [face.outer, ...face.holes]) {
      final count = loop.vertices.length;
      if (count < 2) continue;
      for (var i = 0; i < count; i++) {
        final a = vertices[loop.vertices[i]];
        final b = vertices[loop.vertices[(i + 1) % count]];
        final ab = b - a;
        final t = ab.length2 < 1e-18
            ? 0.0
            : ((position - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
        final distance = (a + ab * t - position).length2;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestLoop = loop;
          bestIndex = i;
          bestT = t;
        }
      }
    }
    if (bestLoop == null) return null;
    final hasUvs = bestLoop.hasUvs;
    final index = vertices.length;
    vertices.add(position.clone());
    final next = (bestIndex + 1) % bestLoop.vertices.length;
    bestLoop.vertices.insert(bestIndex + 1, index);
    if (hasUvs) {
      final a = bestLoop.uvs[bestIndex];
      final b = bestLoop.uvs[next];
      bestLoop.uvs.insert(bestIndex + 1, a + (b - a) * bestT);
    }
    return index;
  }

  /// Удаляет вершины [indices] из всех контуров, перенумеровывает
  /// оставшиеся и удаляет вырожденные контуры/грани. Неиспользуемые
  /// вершины отбрасываются ([compact]).
  void deleteVertices(Iterable<int> indices) {
    final removed = indices
        .where((i) => i >= 0 && i < vertices.length)
        .toSet();
    if (removed.isEmpty) return;
    for (final face in faces) {
      _removeFromLoop(face.outer, removed);
      for (final hole in face.holes) {
        _removeFromLoop(hole, removed);
      }
    }
    _dropDegenerate();
    compact();
  }

  /// Удаляет грани по ключам; неиспользуемые вершины отбрасываются.
  void deleteFaces(Iterable<String> faceKeys) {
    final keys = faceKeys.toSet();
    if (keys.isEmpty) return;
    faces.removeWhere((f) => keys.contains(f.key));
    compact();
  }

  /// Отбрасывает вершины, на которые никто не ссылается, и перенумеровывает
  /// индексы контуров. Точки, грани и их порядок не меняются.
  void compact() {
    final referenced = <int>{};
    for (final face in faces) {
      referenced
        ..addAll(face.outer.vertices)
        ..addAll(face.holes.expand((h) => h.vertices));
    }
    if (referenced.isEmpty) {
      vertices.clear();
      faces.clear();
      return;
    }
    final sorted = referenced.toList()..sort();
    final remap = <int, int>{
      for (var i = 0; i < sorted.length; i++) sorted[i]: i,
    };
    final compacted = <vm.Vector3>[
      for (final old in sorted) vertices[old],
    ];
    vertices
      ..clear()
      ..addAll(compacted);
    for (final face in faces) {
      _remapLoop(face.outer, remap);
      for (final hole in face.holes) {
        _remapLoop(hole, remap);
      }
    }
  }

  void _removeFromLoop(PolyLoop loop, Set<int> removed) {
    final next = <int>[];
    final nextUvs = <vm.Vector2>[];
    for (var i = 0; i < loop.vertices.length; i++) {
      if (removed.contains(loop.vertices[i])) continue;
      next.add(loop.vertices[i]);
      if (loop.uvs.length == loop.vertices.length) nextUvs.add(loop.uvs[i]);
    }
    loop.vertices
      ..clear()
      ..addAll(next);
    loop.uvs
      ..clear()
      ..addAll(nextUvs);
  }

  void _remapLoop(PolyLoop loop, Map<int, int> remap) {
    for (var i = 0; i < loop.vertices.length; i++) {
      loop.vertices[i] = remap[loop.vertices[i]] ?? loop.vertices[i];
    }
  }

  void _dropDegenerate() {
    for (final face in faces) {
      face.holes.removeWhere((h) => h.vertices.length < 3);
    }
    faces.removeWhere((f) => f.outer.vertices.length < 3);
  }
}

/// The outward Newell normal of [face] in [mesh] (the loop winding defines
/// the direction; zero when degenerate).
vm.Vector3 polyFaceNormal(PolyMesh mesh, PolyFace face) =>
    _newellNormal(face.outer.vertices, (i) => mesh.vertices[i]);

/// The area of the face in the plane of its Newell normal (holes subtract).
double polyFaceArea(PolyMesh mesh, PolyFace face) {
  final n = polyFaceNormal(mesh, face);
  if (n.length2 < 1e-18) return 0;
  final unit = n.normalized();
  final (u, v) = polyFaceBasis(unit);
  final outer = _project(face.outer.vertices, mesh.vertices, u, v);
  var area = _signedArea(outer).abs();
  for (final h in face.holes) {
    final projected = _project(h.vertices, mesh.vertices, u, v);
    area -= _signedArea(projected).abs();
  }
  return area < 0 ? 0 : area;
}

vm.Vector3 _newellNormal(List<int> loop, vm.Vector3 Function(int) position) {
  var x = 0.0, y = 0.0, z = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final a = position(loop[i]);
    final b = position(loop[(i + 1) % loop.length]);
    x += (a.y - b.y) * (a.z + b.z);
    y += (a.z - b.z) * (a.x + b.x);
    z += (a.x - b.x) * (a.y + b.y);
  }
  return vm.Vector3(x, y, z);
}

/// A deterministic orthonormal basis `(u, v)` of the plane with outward
/// [normal], right-handed: `cross(u, v) == normal`. Used for planar UVs and
/// 2D polygon math; stable for any camera/rebuild (depends only on normal).
(vm.Vector3, vm.Vector3) polyFaceBasis(vm.Vector3 normal) {
  final n = normal.length2 < 1e-18
      ? vm.Vector3(0, 1, 0)
      : normal.normalized();
  final ref = n.y.abs() > 0.9 ? vm.Vector3(0, 0, 1) : vm.Vector3(0, 1, 0);
  final u = ref.cross(n);
  u.normalize();
  final v = n.cross(u);
  v.normalize();
  return (u, v);
}

/// Triangulates one face of [mesh]: the outer loop with holes, returning
/// vertex-index triples. Triangles are wound CCW around the face's Newell
/// normal (outward for a correctly ordered loop). Degenerate faces return an
/// empty list; a robust fallback keeps the function total for pathological
/// input (collinear/duplicate rings).
List<(int, int, int)> triangulatePolyFace(PolyMesh mesh, PolyFace face) {
  final normal = polyFaceNormal(mesh, face);
  if (normal.length2 < 1e-18) return const [];
  final (u, v) = polyFaceBasis(normal);
  vm.Vector2 project(int i) {
    final p = mesh.vertices[i];
    return vm.Vector2(p.dot(u), p.dot(v));
  }

  return triangulateLoops(
    outer: face.outer.vertices,
    holes: [for (final h in face.holes) h.vertices],
    project: project,
  );
}

/// Triangulates a planar polygon with holes given as vertex indices and a
/// projection to 2D. The result references the SAME indices (bridges may
/// duplicate them); triangles are CCW in the projection plane. Pure — the
/// core is unit-testable without a mesh.
List<(int, int, int)> triangulateLoops({
  required List<int> outer,
  required List<List<int>> holes,
  required vm.Vector2 Function(int index) project,
}) {
  var ring = _cleanLoop(outer);
  if (ring.length < 3) return const [];
  if (_signedArea(_projectLoop(ring, project)) < 0) {
    ring = ring.reversed.toList();
  }
  final cleanHoles = <List<int>>[];
  for (final hole in holes) {
    var h = _cleanLoop(hole);
    if (h.length < 3) continue;
    if (_signedArea(_projectLoop(h, project)) > 0) {
      h = h.reversed.toList();
    }
    cleanHoles.add(h);
  }
  for (final hole in cleanHoles) {
    ring = _bridgeHole(ring, hole, project);
  }
  final triangles = _earClip(ring, project);
  // Bridges and degenerate rings may leave zero-area triangles; they carry
  // no geometry and would only pollute picking/normals.
  return [
    for (final t in triangles)
      if (_triangleCross(project(t.$1), project(t.$2), project(t.$3)).abs() >
          1e-12)
        t,
  ];
}

double _triangleCross(vm.Vector2 a, vm.Vector2 b, vm.Vector2 c) =>
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

/// Removes consecutive duplicates and a closing duplicate (a ring is stored
/// without repeating its first vertex).
List<int> _cleanLoop(List<int> loop) {
  final out = <int>[];
  for (final i in loop) {
    if (out.isEmpty || out.last != i) out.add(i);
  }
  while (out.length > 1 && out.first == out.last) {
    out.removeLast();
  }
  return out;
}

List<vm.Vector2> _projectLoop(
  List<int> loop,
  vm.Vector2 Function(int) project,
) =>
    [for (final i in loop) project(i)];

List<vm.Vector2> _project(
  List<int> loop,
  List<vm.Vector3> vertices,
  vm.Vector3 u,
  vm.Vector3 v,
) =>
    [
      for (final i in loop)
        vm.Vector2(vertices[i].dot(u), vertices[i].dot(v)),
    ];

double _signedArea(List<vm.Vector2> loop) {
  var sum = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final a = loop[i];
    final b = loop[(i + 1) % loop.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// Joins [hole] into [outer] with a doubled bridge edge. The pair of closest
/// vertices whose midpoint lies inside [outer] and outside the hole is used;
/// nearest pair as a fallback, so the merge never fails.
List<int> _bridgeHole(
  List<int> outer,
  List<int> hole,
  vm.Vector2 Function(int) project,
) {
  final outerPts = _projectLoop(outer, project);
  final holePts = _projectLoop(hole, project);
  var bestOuter = 0;
  var bestHole = 0;
  var bestDistance = double.infinity;
  var found = false;
  // The nearest visible pair first; if no pair passes the midpoint test,
  // fall back to the nearest pair overall (merge must never fail).
  for (var pass = 0; pass < 2 && !found; pass++) {
    for (var i = 0; i < outer.length; i++) {
      for (var j = 0; j < hole.length; j++) {
        final d = (outerPts[i] - holePts[j]).length2;
        if (d >= bestDistance) continue;
        if (pass == 0 &&
            !_bridgeMidpointVisible(outerPts[i], holePts[j], outerPts, holePts)) {
          continue;
        }
        bestDistance = d;
        bestOuter = i;
        bestHole = j;
        found = true;
      }
    }
  }
  final rotated = <int>[
    for (var k = 0; k < hole.length; k++) hole[(bestHole + k) % hole.length],
  ];
  return <int>[
    ...outer.sublist(0, bestOuter + 1),
    ...rotated,
    rotated.first,
    ...outer.sublist(bestOuter),
  ];
}

bool _bridgeMidpointVisible(
  vm.Vector2 a,
  vm.Vector2 b,
  List<vm.Vector2> outer,
  List<vm.Vector2> hole,
) {
  final mid = (a + b) * 0.5;
  if (!_pointInPolygon(mid, outer)) return false;
  if (_holeContains(mid, hole)) return false;
  return true;
}

bool _holeContains(vm.Vector2 p, List<vm.Vector2> hole) {
  // Points on the hole boundary are allowed (the bridge may run along an
  // edge of the hole).
  return _pointInPolygon(p, hole, includeBoundary: false);
}

/// Even-odd ray test; [includeBoundary] true means points on the edge count
/// as inside.
bool _pointInPolygon(
  vm.Vector2 p,
  List<vm.Vector2> polygon, {
  bool includeBoundary = true,
}) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if (includeBoundary && _pointOnSegment(p, a, b)) return true;
    final intersects = ((a.y > p.y) != (b.y > p.y)) &&
        (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
    if (intersects) inside = !inside;
  }
  return inside;
}

bool _pointOnSegment(vm.Vector2 p, vm.Vector2 a, vm.Vector2 b) {
  final cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
  if (cross.abs() > 1e-9) return false;
  final dot = (p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y);
  if (dot < -1e-9) return false;
  final len2 = (b - a).length2;
  return dot <= len2 + 1e-9;
}

/// Ear clipping for a simple (bridged) ring. `loop` may contain duplicated
/// vertices from hole bridges; zero-area ears are skipped, and a degenerate
/// ring is finished with a fan so the function always terminates.
List<(int, int, int)> _earClip(
  List<int> loop,
  vm.Vector2 Function(int) project,
) {
  final ring = List<int>.of(loop);
  final out = <(int, int, int)>[];
  var guard = ring.length * ring.length + 32;
  while (ring.length > 3 && guard-- > 0) {
    var clipped = false;
    for (var i = 0; i < ring.length; i++) {
      final prev = ring[(i - 1 + ring.length) % ring.length];
      final curr = ring[i];
      final next = ring[(i + 1) % ring.length];
      if (prev == curr || curr == next) {
        ring.removeAt(i);
        clipped = true;
        break;
      }
      final a = project(prev), b = project(curr), c = project(next);
      final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
      if (cross <= 1e-12) continue;
      var ear = true;
      for (var k = 0; k < ring.length; k++) {
        if (k == i || k == (i - 1 + ring.length) % ring.length) continue;
        if (k == (i + 1) % ring.length) continue;
        if (_pointInTriangle(project(ring[k]), a, b, c)) {
          ear = false;
          break;
        }
      }
      if (!ear) continue;
      out.add((prev, curr, next));
      ring.removeAt(i);
      clipped = true;
      break;
    }
    if (clipped) continue;
    // No ear found: drop a degenerate (collinear) vertex; if none exists,
    // fan the rest and stop (pathological self-intersecting input).
    var removed = false;
    for (var i = 0; i < ring.length; i++) {
      final a = project(ring[(i - 1 + ring.length) % ring.length]);
      final b = project(ring[i]);
      final c = project(ring[(i + 1) % ring.length]);
      final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
      if (cross.abs() <= 1e-12) {
        ring.removeAt(i);
        removed = true;
        break;
      }
    }
    if (!removed) {
      for (var i = 1; i + 1 < ring.length; i++) {
        out.add((ring[0], ring[i], ring[i + 1]));
      }
      return out;
    }
  }
  if (ring.length == 3) out.add((ring[0], ring[1], ring[2]));
  return out;
}

bool _pointInTriangle(
  vm.Vector2 p,
  vm.Vector2 a,
  vm.Vector2 b,
  vm.Vector2 c,
) {
  double cross(vm.Vector2 p1, vm.Vector2 p2, vm.Vector2 p3) =>
      (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x);
  final d1 = cross(a, b, p);
  final d2 = cross(b, c, p);
  final d3 = cross(c, a, p);
  if (d1 <= 1e-12 || d2 <= 1e-12 || d3 <= 1e-12) return false;
  return true;
}

