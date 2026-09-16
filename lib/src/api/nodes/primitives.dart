// Private fields behind public getters/setters cannot use initializing
// formals in named parameters.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/geometry_builder.dart';
import '../geometry/line_geometry.dart';
import '../geometry/scene_geometry.dart';
import '../materials/scene_material.dart';
import '../materials/scene_texture.dart';
import 'mesh_helpers.dart';
import 'scene_node.dart';

/// How a [SpriteNode]'s card is oriented in the world.
enum SpriteOrientation { vertical, floor, ceiling, wall }

/// A parametric box.
class BoxNode extends SceneNode {
  BoxNode({
    super.id,
    super.name,
    super.layer,
    vm.Vector3? size,
    double roundR = 0,
    int roundSegments = 0,
    SceneMaterial? material,
  }) : _size = size ?? vm.Vector3(1, 1, 1),
       _roundR = roundR,
       _roundSegments = roundSegments {
    if (material != null) this.material = material;
  }

  vm.Vector3 _size;

  /// The box extents (full width, height and depth).
  vm.Vector3 get size => _size;
  set size(vm.Vector3 value) {
    if (_size == value) return;
    _size = value;
    _geometry = null;
    markChanged();
  }

  double _roundR;

  /// The corner rounding radius (0 = sharp corners).
  double get roundR => _roundR;
  set roundR(double value) {
    if (_roundR == value) return;
    _roundR = value;
    _geometry = null;
    markChanged();
  }

  int _roundSegments;

  /// The tessellation of the rounding arcs (0 = engine default).
  int get roundSegments => _roundSegments;
  set roundSegments(int value) {
    if (_roundSegments == value) return;
    _roundSegments = value;
    _geometry = null;
    markChanged();
  }

  SceneGeometry? _geometry;

  /// The box geometry (rebuilt when the parameters change).
  SceneGeometry get geometry {
    final existing = _geometry;
    if (existing != null) return existing;
    final built = roundR > 0
        ? SceneGeometry.roundedBox(
            size: _size,
            radius: roundR,
            segments: roundSegments <= 0 ? 16 : roundSegments,
          )
        : SceneGeometry.cuboid(_size);
    _geometry = built;
    return built;
  }

  @override
  Iterable<SceneGeometry> get pickGeometries => [geometry];

  @override
  vm.Aabb3? get localBounds => geometry.localBounds;

  SceneGeometry? _syncedGeometry;
  SceneMaterial? _syncedMaterial;

  @override
  void syncToEngine() {
    final geometry = this.geometry;
    final material = effectiveMaterial(this.material);
    if (engine.mesh != null &&
        identical(_syncedGeometry, geometry) &&
        identical(_syncedMaterial, material)) {
      return;
    }
    _syncedGeometry = geometry;
    _syncedMaterial = material;
    engine.mesh = nodeEngineMesh(geometry.raw, material);
  }
}

/// A flat rectangle, horizontal (XZ) or vertical (XY, facing +Z).
class PlaneNode extends SceneNode {
  PlaneNode({
    super.id,
    super.name,
    super.layer,
    required double width,
    required double depth,
    bool vertical = false,
    SceneMaterial? material,
  }) : _width = width,
       _depth = depth,
       _vertical = vertical {
    if (material != null) this.material = material;
  }

  double _width;

  /// The extent along the plane's first axis.
  double get width => _width;
  set width(double value) {
    if (_width == value) return;
    _width = value;
    _geometry = null;
    markChanged();
  }

  double _depth;

  /// The extent along the plane's second axis.
  double get depth => _depth;
  set depth(double value) {
    if (_depth == value) return;
    _depth = value;
    _geometry = null;
    markChanged();
  }

  bool _vertical;

  /// Whether the plane stands upright instead of lying flat.
  bool get vertical => _vertical;
  set vertical(bool value) {
    if (_vertical == value) return;
    _vertical = value;
    _geometry = null;
    markChanged();
  }

  SceneGeometry? _geometry;

  /// The plane geometry (rebuilt when the parameters change).
  SceneGeometry get geometry {
    final existing = _geometry;
    if (existing != null) return existing;
    final built = _vertical
        ? (GeometryBuilder()..addVerticalQuad(
                center: vm.Vector3.zero(),
                width: _width,
                height: _depth,
                yaw: 0,
              ))
              .build()
        : SceneGeometry.plane(width: _width, depth: _depth);
    _geometry = built;
    return built;
  }

  @override
  Iterable<SceneGeometry> get pickGeometries => [geometry];

  @override
  vm.Aabb3? get localBounds => geometry.localBounds;

  SceneGeometry? _syncedGeometry;
  SceneMaterial? _syncedMaterial;

  @override
  void syncToEngine() {
    final geometry = this.geometry;
    final material = effectiveMaterial(this.material);
    if (engine.mesh != null &&
        identical(_syncedGeometry, geometry) &&
        identical(_syncedMaterial, material)) {
      return;
    }
    _syncedGeometry = geometry;
    _syncedMaterial = material;
    engine.mesh = nodeEngineMesh(geometry.raw, material);
  }
}

/// One geometry/material pair of a multi-material [MeshNode].
class MeshPart {
  MeshPart({required this.geometry, required this.material});

  SceneGeometry geometry;
  SceneMaterial material;
}

/// A node with arbitrary geometry, optionally multi-material.
class MeshNode extends SceneNode {
  MeshNode({
    super.id,
    super.name,
    super.layer,
    required SceneGeometry geometry,
    SceneMaterial? material,
  }) : _parts = [
         MeshPart(
           geometry: geometry,
           material: material ?? SceneMaterial.pbr(),
         ),
       ] {
    _parts.first.material.addListener(_onPartMaterialChanged);
  }

  final List<MeshPart> _parts;

  /// The first part's geometry; assigning replaces it.
  SceneGeometry get geometry => _parts.first.geometry;
  set geometry(SceneGeometry value) {
    if (identical(_parts.first.geometry, value)) return;
    _parts.first.geometry = value;
    markChanged();
  }

  /// The material of the first part; assigning replaces it.
  @override
  SceneMaterial get material => _parts.first.material;
  @override
  set material(SceneMaterial value) {
    final old = _parts.first.material;
    if (identical(old, value)) return;
    old.removeListener(_onPartMaterialChanged);
    _parts.first.material = value;
    value.addListener(_onPartMaterialChanged);
    markChanged();
  }

  /// The geometry/material pairs of this node.
  List<MeshPart> get parts => List.unmodifiable(_parts);

  @override
  Iterable<SceneGeometry> get pickGeometries => [
    for (final part in _parts) part.geometry,
  ];

  /// Appends another geometry/material pair (one draw item per part).
  void addPart(SceneGeometry geometry, SceneMaterial material) {
    _parts.add(MeshPart(geometry: geometry, material: material));
    material.addListener(_onPartMaterialChanged);
    markChanged();
  }

  void _onPartMaterialChanged() {
    invalidateEffectiveMaterials();
    markChanged();
  }

  @override
  vm.Aabb3? get localBounds {
    vm.Aabb3? union;
    for (final part in _parts) {
      final bounds = part.geometry.localBounds;
      if (bounds == null) continue;
      if (union == null) {
        union = vm.Aabb3.minMax(bounds.min, bounds.max);
      } else {
        union.hull(bounds);
      }
    }
    return union;
  }

  List<Object>? _syncedParts;

  @override
  void syncToEngine() {
    final signature = [
      for (final part in _parts) ...[
        part.geometry,
        effectiveMaterial(part.material),
      ],
    ];
    if (engine.mesh != null && listEquals(signature, _syncedParts)) return;
    _syncedParts = signature;
    if (_parts.length == 1) {
      engine.mesh = nodeEngineMesh(geometry.raw, effectiveMaterial(material));
      return;
    }
    engine.mesh = nodeEngineMeshParts([
      for (final part in _parts)
        (part.geometry.raw, effectiveMaterial(part.material)),
    ]);
  }

  @override
  void dispose() {
    for (final part in _parts) {
      part.material.removeListener(_onPartMaterialChanged);
    }
    super.dispose();
  }
}

/// A vertical card with a texture: billboard or fixed, with an orientation.
class SpriteNode extends SceneNode {
  SpriteNode({
    super.id,
    super.name,
    super.layer,
    SceneTexture? texture,
    this.width = 1,
    this.height = 1,
    double yaw = 0,
    this.billboard = false,
    SpriteOrientation orientation = SpriteOrientation.vertical,
  }) : _yaw = yaw,
       _orientation = orientation {
    material = SceneMaterial.unlit(
      texture: texture,
      doubleSided: true,
      alphaMode: SceneAlphaMode.blend,
    );
    engine.transform = _spriteMatrix(vm.Vector3.zero(), _yaw, _orientation);
  }

  SceneTexture? _texture;

  /// The card texture, or null for a flat color.
  SceneTexture? get texture => _texture;
  set texture(SceneTexture? value) {
    if (identical(_texture, value)) return;
    _texture = value;
    material.texture = value;
    markChanged();
  }

  double width;
  double height;

  double _yaw;

  /// The card's yaw around Y in radians (its authored facing when not a
  /// billboard).
  double get yaw => _yaw;
  set yaw(double value) {
    if (_yaw == value) return;
    _yaw = value;
    _reorient();
  }

  /// Whether the card turns to the camera every frame.
  bool billboard;

  SpriteOrientation _orientation;

  /// How the card is oriented in the world.
  SpriteOrientation get orientation => _orientation;
  set orientation(SpriteOrientation value) {
    if (_orientation == value) return;
    _orientation = value;
    _reorient();
  }

  /// Reorients the billboard to a new yaw (called by the frame loop).
  @internal
  void reorientBillboard(double yaw) {
    if (_yaw == yaw) return;
    _yaw = yaw;
    _reorient();
  }

  void _reorient() {
    final position = transform.getTranslation();
    engine.transform = _spriteMatrix(position, _yaw, _orientation);
    markChanged();
  }

  SceneGeometry? _geometry;

  /// The card quad.
  SceneGeometry get geometry =>
      _geometry ??= SceneGeometry.plane(width: width, depth: height);

  @override
  Iterable<SceneGeometry> get pickGeometries => [geometry];

  @override
  vm.Aabb3? get localBounds => geometry.localBounds;

  SceneGeometry? _syncedGeometry;
  SceneMaterial? _syncedMaterial;

  @override
  void syncToEngine() {
    final geometry = this.geometry;
    final material = effectiveMaterial(this.material);
    if (engine.mesh != null &&
        identical(_syncedGeometry, geometry) &&
        identical(_syncedMaterial, material)) {
      return;
    }
    _syncedGeometry = geometry;
    _syncedMaterial = material;
    engine.mesh = nodeEngineMesh(geometry.raw, material);
  }

  static vm.Matrix4 _spriteMatrix(
    vm.Vector3 position,
    double yaw,
    SpriteOrientation orientation,
  ) {
    final mirror = vm.Matrix4.diagonal3Values(-1, 1, 1);
    final rotation = switch (orientation) {
      SpriteOrientation.vertical ||
      SpriteOrientation.wall => vm.Matrix4.rotationX(math.pi / 2),
      SpriteOrientation.floor => vm.Matrix4.identity(),
      SpriteOrientation.ceiling => vm.Matrix4.rotationX(math.pi),
    };
    return vm.Matrix4.translation(position) *
        mirror *
        vm.Matrix4.rotationY(yaw) *
        rotation;
  }
}

/// A batch of colored line segments.
class LineNode extends SceneNode {
  LineNode({
    super.id,
    super.name,
    super.layer,
    required this.geometry,
    Color color = const Color(0xFFFFFFFF),
    double? width,
    double? widthPx,
  }) : _color = color {
    if (width != null) geometry.width = width;
    if (widthPx != null) geometry.widthPx = widthPx;
    material = SceneMaterial.unlit(color: color, doubleSided: true);
  }

  /// The line segments.
  final LineGeometry geometry;

  /// The line width in world units; the geometry owns it.
  double get width => geometry.width;
  set width(double value) {
    if (geometry.width == value) return;
    geometry.width = value;
    markChanged();
  }

  /// The line width in screen pixels, or null for the world-space [width].
  /// Constant at any camera distance (the wireframe overlay uses 1 px by
  /// default).
  double? get widthPx => geometry.widthPx;
  set widthPx(double? value) {
    if (geometry.widthPx == value) return;
    geometry.widthPx = value;
    markChanged();
  }

  Color _color;

  /// The line color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    material.color = value;
    markChanged();
  }

  @override
  vm.Aabb3? get localBounds => geometry.localBounds;

  LineGeometry? _syncedGeometry;
  SceneMaterial? _syncedMaterial;
  int _syncedRevision = -1;

  @override
  void syncToEngine() {
    final geometry = this.geometry;
    final material = effectiveMaterial(this.material);
    if (engine.mesh != null &&
        identical(_syncedGeometry, geometry) &&
        identical(_syncedMaterial, material) &&
        _syncedRevision == geometry.revision) {
      return;
    }
    _syncedGeometry = geometry;
    _syncedMaterial = material;
    _syncedRevision = geometry.revision;
    // Screen-pixel widths need the current camera before the first draw.
    scene?.refreshScreenSpaceLine(this);
    engine.mesh = nodeEngineMesh(geometry.raw, material);
  }
}

/// A flat colored ring (an annulus) — markers and target rings.
class RingNode extends SceneNode {
  RingNode({
    super.id,
    super.name,
    super.layer,
    double radius = 0.3,
    double thickness = 0.05,
    Color color = const Color(0xFFFFFFFF),
  }) : _radius = radius,
       _thickness = thickness,
       _color = color {
    material = SceneMaterial.unlit(
      color: color,
      doubleSided: true,
      alphaMode: SceneAlphaMode.blend,
    );
  }

  double _radius;

  /// The outer radius of the ring.
  double get radius => _radius;
  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    _geometry = null;
    markChanged();
  }

  double _thickness;

  /// The ring width (outer radius minus inner radius).
  double get thickness => _thickness;
  set thickness(double value) {
    if (_thickness == value) return;
    _thickness = value;
    _geometry = null;
    markChanged();
  }

  Color _color;

  /// The ring color.
  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    material.color = value;
    markChanged();
  }

  SceneGeometry? _geometry;

  /// The annulus geometry.
  SceneGeometry get geometry {
    final existing = _geometry;
    if (existing != null) return existing;
    final inner = (_radius - _thickness).clamp(0.0, _radius);
    final built = SceneGeometry.annulus(
      innerRadius: inner,
      outerRadius: _radius,
    );
    _geometry = built;
    return built;
  }

  @override
  Iterable<SceneGeometry> get pickGeometries => [geometry];

  @override
  vm.Aabb3? get localBounds => geometry.localBounds;

  SceneGeometry? _syncedGeometry;
  SceneMaterial? _syncedMaterial;

  @override
  void syncToEngine() {
    final geometry = this.geometry;
    final material = effectiveMaterial(this.material);
    if (engine.mesh != null &&
        identical(_syncedGeometry, geometry) &&
        identical(_syncedMaterial, material)) {
      return;
    }
    _syncedGeometry = geometry;
    _syncedMaterial = material;
    engine.mesh = nodeEngineMesh(geometry.raw, material);
  }
}
