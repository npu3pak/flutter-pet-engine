// A private field behind a public parameter cannot use an initializing formal.
// ignore_for_file: prefer_initializing_formals

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// How screen-pixel line widths are expanded into triangles.
enum LineWidthBackend {
  /// GPU vertex-shader expansion (`LineSegmentsGeometry`): macOS, iOS,
  /// iPadOS and Android.
  shader,

  /// CPU expansion into camera-facing triangles: Windows and Linux (their
  /// shader compilation is too slow for the GPU path) and the debug fallback
  /// that visual checks can force on any platform.
  polyline,
}

LineWidthBackend _lineWidthBackend = defaultLineWidthBackend();

/// The backend used to expand screen-pixel line widths.
LineWidthBackend get lineWidthBackend => _lineWidthBackend;

/// Overrides the screen-pixel line backend at runtime (debug and tests).
/// [initializeEngine] sets the platform default at startup.
void setLineWidthBackend(LineWidthBackend backend) {
  _lineWidthBackend = backend;
}

/// The platform default: the CPU polyline expansion on Windows and Linux,
/// the GPU shader on every other platform.
LineWidthBackend defaultLineWidthBackend() => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.linux => LineWidthBackend.polyline,
  _ => LineWidthBackend.shader,
};

/// A batch of disconnected line segments (pairs of endpoints), expanded to
/// camera-facing ribbons at draw time.
///
/// The [segments] list is a flat list of endpoint pairs: `[a0, b0, a1, b1,
/// ...]`. [width] is the world-space ribbon width; [widthPx] switches the
/// ribbon to a constant screen-pixel width that does not depend on the camera
/// distance (1 px is the default the wireframe helpers use).
class LineGeometry {
  LineGeometry(
    List<vm.Vector3> segments, {
    double width = 0.01,
    double? widthPx,
  }) : _points = List.unmodifiable(segments),
       _width = width,
       _widthPx = widthPx {
    if (_points.length.isOdd) {
      throw ArgumentError.value(
        segments.length,
        'segments',
        'Expected an even number of points (endpoint pairs).',
      );
    }
  }

  final List<vm.Vector3> _points;

  double _width;

  /// The ribbon width in world units (used when [widthPx] is null). Changing
  /// it applies on the next frame (the fork geometry setter is live) and
  /// updates [localBounds].
  double get width => _width;
  set width(double value) {
    if (_width == value) return;
    _width = value;
    _shader?.width = value;
  }

  double? _widthPx;

  /// The ribbon width in screen pixels, or null for the world-space [width].
  /// The width stays constant at any camera distance; it is expanded by the
  /// GPU shader or the CPU polyline backend (see [lineWidthBackend]).
  double? get widthPx => _widthPx;
  set widthPx(double? value) {
    if (_widthPx == value) return;
    _widthPx = value;
    _revision++;
    _shader = null;
    _cpu = null;
  }

  int _revision = 0;

  /// Bumped when the compiled geometry must be re-created (the width mode
  /// changed). Plumbing for `LineNode`.
  @internal
  int get revision => _revision;

  double _pixelScale = 0.0;

  /// Updates the world size of one logical pixel at distance 1 for the active
  /// perspective camera; used by the shader backend. Plumbing for the
  /// controller.
  @internal
  void setPixelScale(double value) {
    _pixelScale = value;
    _shader?.pixelScale = value;
  }

  /// The number of segments in the batch.
  int get segmentCount => _points.length ~/ 2;

  LineSegmentData? _data;

  /// The pure CPU segment data. Plumbing only.
  LineSegmentData get data {
    final existing = _data;
    if (existing != null) return existing;
    final positions = Float32List(_points.length * 3);
    for (var i = 0; i < _points.length; i++) {
      final point = _points[i];
      positions[i * 3] = point.x;
      positions[i * 3 + 1] = point.y;
      positions[i * 3 + 2] = point.z;
    }
    final data = LineSegmentData(positions: positions);
    _data = data;
    return data;
  }

  LineSegmentsGeometry? _shader;
  MeshGeometry? _cpu;

  /// The compiled fork geometry. Plumbing only; built lazily. With [widthPx]
  /// set the type follows [lineWidthBackend]: the GPU shader expansion or an
  /// updatable CPU mesh refreshed by [updateForCamera].
  Geometry get raw {
    final pixel = _widthPx;
    if (pixel != null && lineWidthBackend == LineWidthBackend.polyline) {
      return _cpu ??= MeshGeometry.fromMeshData(
        _placeholderData,
        storage: GeometryStorage.updatable,
      );
    }
    return _shader ??= LineSegmentsGeometry(
      data,
      width: _width,
      pixelWidth: pixel,
      pixelScale: _pixelScale,
    );
  }

  /// A zeroed mesh with the exact vertex count of the CPU expansion, so the
  /// per-frame [updateForCamera] can replace the buffers in place.
  MeshData get _placeholderData => MeshData(
    positions: Float32List(segmentCount * 6 * 3),
    vertexCount: segmentCount * 6,
    normals: Float32List(segmentCount * 6 * 3),
  );

  /// Refreshes the CPU-expanded ribbons for the current camera. A no-op for
  /// the shader backend, world-space widths, an empty viewport, or before
  /// [raw] was built.
  @internal
  void updateForCamera(
    vm.Matrix4 viewProjection,
    vm.Vector3 cameraPosition,
    Size viewportSize,
  ) {
    final pixel = _widthPx;
    final mesh = _cpu;
    if (pixel == null ||
        mesh == null ||
        lineWidthBackend != LineWidthBackend.polyline ||
        viewportSize.isEmpty) {
      return;
    }
    final expanded = expandLineSegments(
      _points,
      widthPx: pixel,
      viewProjection: viewProjection,
      cameraPosition: cameraPosition,
      viewportSize: viewportSize,
    );
    mesh.updatePositions(expanded.positions);
    mesh.updateNormals(expanded.normals);
  }

  /// The local-space axis-aligned bounds, or null when there are no points.
  vm.Aabb3? get localBounds {
    if (_points.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (final point in _points) {
      if (point.x < minX) minX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.z < minZ) minZ = point.z;
      if (point.x > maxX) maxX = point.x;
      if (point.y > maxY) maxY = point.y;
      if (point.z > maxZ) maxZ = point.z;
    }
    final pad = _widthPx != null ? 0.0 : _width * 0.5;
    return vm.Aabb3.minMax(
      vm.Vector3(minX - pad, minY - pad, minZ - pad),
      vm.Vector3(maxX + pad, maxY + pad, maxZ + pad),
    );
  }
}
