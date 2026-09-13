/// Render layers of a [SceneNode] and layer masks of a view.
///
/// The bits are public constants so applications never touch the fork's
/// layer numbers. `base` is the default layer of every node; `overlay` and
/// `top` are the editor's service layers (outlines, grid, gizmos).
abstract final class SceneLayer {
  /// The default layer: everything a normal scene view draws.
  static const int base = 1 << 0;

  /// Outlines, labels, grid — drawn by a dedicated overlay view.
  static const int overlay = 1 << 1;

  /// Gizmos drawn above everything.
  static const int top = 1 << 2;

  /// Every layer.
  static const int all = 0xFFFFFFFF;
}
