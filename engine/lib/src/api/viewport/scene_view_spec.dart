import '../controllers/camera_controller.dart';
import '../scene_layer.dart';

/// One view (render pass) of the viewport: which layers it draws, its order
/// and the camera it uses.
///
/// Most applications need a single view (the default). The editor uses three:
/// the scene, an overlay for outlines and a top view for gizmos.
class SceneViewSpec {
  const SceneViewSpec({required this.layerMask, this.order = 0, this.camera});

  /// The main scene view: every layer except the editor overlays.
  factory SceneViewSpec.main({CameraController? camera}) => SceneViewSpec(
    layerMask: SceneLayer.all & ~(SceneLayer.overlay | SceneLayer.top),
    camera: camera,
  );

  /// The overlay view (outlines, labels, grid).
  factory SceneViewSpec.overlay({CameraController? camera}) =>
      SceneViewSpec(layerMask: SceneLayer.overlay, order: 1, camera: camera);

  /// The top view (gizmos above everything).
  factory SceneViewSpec.top({CameraController? camera}) =>
      SceneViewSpec(layerMask: SceneLayer.top, order: 2, camera: camera);

  /// A custom view with an explicit layer mask.
  factory SceneViewSpec.layer(
    int layerMask, {
    int order = 0,
    CameraController? camera,
  }) => SceneViewSpec(layerMask: layerMask, order: order, camera: camera);

  /// The bit mask of the layers this view draws.
  final int layerMask;

  /// Draw order: smaller first, larger on top.
  final int order;

  /// The camera of the view, or null for the controller's active camera.
  final CameraController? camera;
}
