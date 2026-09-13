import 'dart:ui' show Color, Image;

import 'package:vector_math/vector_math.dart' as vm;

import '../materials/scene_texture.dart';
import 'scene_node.dart';

/// One layer of a [SkyboxNode]. Layers draw bottom-up in list order.
sealed class SkyboxLayer {
  SkyboxLayer({this.visible = true, this.opacity = 1.0});

  /// Whether the layer is drawn.
  bool visible;

  /// The layer opacity, 0..1.
  double opacity;
}

/// A vertical gradient between two colors.
class SkyboxColorLayer extends SkyboxLayer {
  SkyboxColorLayer({
    required this.topColor,
    required this.bottomColor,
    super.visible,
    super.opacity,
  });

  /// The color at the top of the sky.
  Color topColor;

  /// The color at the horizon.
  Color bottomColor;
}

/// A 360° panorama image.
class SkyboxImageLayer extends SkyboxLayer {
  SkyboxImageLayer({
    required this.image,
    this.offset = 0,
    this.tile = true,
    this.fogColor,
    this.fogStrength = 0,
    super.visible,
    super.opacity,
  });

  /// The panorama image.
  Image image;

  /// The horizontal rotation offset, 0..1 (one full turn).
  double offset;

  /// Whether the image tiles horizontally.
  bool tile;

  /// The fog tint blended into the horizon.
  Color? fogColor;

  /// The fog strength, 0..1.
  double fogStrength;
}

/// A scrolling cloud layer.
class SkyboxCloudsLayer extends SkyboxLayer {
  SkyboxCloudsLayer({
    required this.texture,
    this.scale = 1,
    this.speed = 0.01,
    this.coverage = 0.5,
    this.color = const Color(0xFFFFFFFF),
    super.visible,
    super.opacity,
  });

  /// The cloud texture.
  SceneTexture texture;

  /// The texture scale.
  double scale;

  /// The scroll speed, turns per second.
  double speed;

  /// The cloud coverage, 0..1.
  double coverage;

  /// The cloud tint.
  Color color;
}

/// A procedural star field.
class SkyboxStarsLayer extends SkyboxLayer {
  SkyboxStarsLayer({
    this.count = 300,
    this.brightness = 1,
    super.visible,
    super.opacity,
  });

  /// The number of stars.
  int count;

  /// The star brightness.
  double brightness;
}

/// The sun or the moon.
class SkyboxBodyLayer extends SkyboxLayer {
  SkyboxBodyLayer({
    required this.direction,
    this.size = 1,
    this.color = const Color(0xFFFFFFFF),
    this.moon = false,
    this.glow = 0.5,
    super.visible,
    super.opacity,
  });

  /// The direction of the body from the camera.
  vm.Vector3 direction;

  /// The apparent size.
  double size;

  /// The body color.
  Color color;

  /// Whether the body is the moon instead of the sun.
  bool moon;

  /// The glow strength, 0..1.
  double glow;
}

/// The scene sky: a background color plus an ordered list of layers. The
/// viewport draws it as a background pass behind the scene.
class SkyboxNode extends SceneNode {
  SkyboxNode({
    super.id,
    super.name,
    super.layer,
    this.backgroundColor = const Color(0xFF000000),
  });

  /// The background color drawn when there are no layers.
  Color backgroundColor;

  bool _followCamera = true;

  /// Whether the sky rotates with the camera.
  bool get followCamera => _followCamera;
  set followCamera(bool value) {
    if (_followCamera == value) return;
    _followCamera = value;
    markChanged();
  }

  double _skyRotation = 0;

  /// An extra sky rotation, 0..1 (north = 1/8). Named `skyRotation` so it
  /// does not clash with the node transform rotation.
  double get skyRotation => _skyRotation;
  set skyRotation(double value) {
    if (_skyRotation == value) return;
    _skyRotation = value;
    markChanged();
  }

  final List<SkyboxLayer> _layers = [];

  /// The layers, bottom to top.
  List<SkyboxLayer> get layers => List.unmodifiable(_layers);

  /// Appends a layer on top of the stack.
  void addLayer(SkyboxLayer layer) {
    _layers.add(layer);
    markChanged();
  }

  /// Removes a layer.
  void removeLayer(SkyboxLayer layer) {
    if (_layers.remove(layer)) markChanged();
  }
}
