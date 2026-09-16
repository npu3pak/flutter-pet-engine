import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A pooled instanced billboard batch: [BillboardGeometry] + [SpriteMaterial]
/// on one scene [Node]. One draw call for many camera-facing quads — write
/// instances with [setInstance], call [commit], attach with [attachTo].
///
/// The batch is the engine's batching primitive for dynamic content (weather,
/// grass-like fields, particle layers): the owning system decides the facing
/// mode, atlas, blend mode and flipbook grid; per-instance data carries
/// center, size, rotation, linear RGBA, frame and velocity.
class BillboardBatch {
  BillboardBatch({
    required int capacity,
    Texture2D? atlas,
    BillboardFacing facing = BillboardFacing.spherical,
    SpriteBlendMode blendMode = SpriteBlendMode.alpha,
    bool opaque = false,
    double blendOrder = 0.0,
    double velocityStretch = 0.0,
    int flipbookColumns = 1,
    int flipbookRows = 1,
  })  : geometry = BillboardGeometry(capacity: capacity),
        material = SpriteMaterial(colorTexture: atlas) {
    this.facing = facing;
    this.blendMode = blendMode;
    this.opaque = opaque;
    this.blendOrder = blendOrder;
    this.velocityStretch = velocityStretch;
    this.flipbookColumns = flipbookColumns;
    this.flipbookRows = flipbookRows;
    node = Node(name: 'billboard-batch', mesh: Mesh(geometry, material));
  }

  /// The instanced geometry (capacity, facing modes, flipbook grid).
  final BillboardGeometry geometry;

  /// The sprite material (atlas, tint, blend mode, opaque alpha-test).
  final SpriteMaterial material;

  /// The scene node carrying the mesh — attach it with [attachTo].
  late final Node node;

  int get capacity => geometry.capacity;
  int get instanceCount => geometry.instanceCount;

  /// The atlas texture; setting it also adopts the texture's sampler.
  set atlas(Texture2D? value) {
    material.colorTexture = value;
    if (value != null) material.sampler = value.sampledSampler;
  }

  set facing(BillboardFacing value) => geometry.facing = value;
  BillboardFacing get facing => geometry.facing;

  set worldUp(vm.Vector3 value) => geometry.worldUp = value;
  vm.Vector3 get worldUp => geometry.worldUp;

  set velocityStretch(double value) => geometry.velocityStretch = value;
  double get velocityStretch => geometry.velocityStretch;

  set screenParallelYaw(double value) => geometry.screenParallelYaw = value;
  double get screenParallelYaw => geometry.screenParallelYaw;

  set flipbookColumns(int value) => geometry.flipbookColumns = value;
  int get flipbookColumns => geometry.flipbookColumns;

  set flipbookRows(int value) => geometry.flipbookRows = value;
  int get flipbookRows => geometry.flipbookRows;

  set flipbookBlend(bool value) => geometry.flipbookBlend = value;
  bool get flipbookBlend => geometry.flipbookBlend;

  set blendMode(SpriteBlendMode value) => material.blendMode = value;
  SpriteBlendMode get blendMode => material.blendMode;

  /// Opaque alpha-tested batch (depth buffer resolves ordering exactly).
  set opaque(bool value) => material.opaque = value;
  bool get opaque => material.opaque;

  set blendOrder(double value) => material.blendOrder = value;
  double get blendOrder => material.blendOrder;

  /// Writes one instance; call [commit] when done.
  void setInstance(
    int index, {
    required vm.Vector3 center,
    required double width,
    required double height,
    double rotation = 0.0,
    vm.Vector4? color,
    double frame = 0.0,
    vm.Vector3? velocity,
  }) {
    geometry.setInstance(
      index,
      center: center,
      width: width,
      height: height,
      rotation: rotation,
      color: color,
      frame: frame,
      velocity: velocity,
    );
  }

  /// Sets the number of live instances drawn this frame.
  void commit(int count) => geometry.commit(count);

  /// Adds the batch node under [parent] (moves it when already attached
  /// elsewhere).
  void attachTo(Node parent) {
    final current = node.parent;
    if (current == parent) return;
    if (current != null) current.remove(node);
    parent.add(node);
  }

  /// Removes the batch node from its parent (the batch keeps its state).
  void detach() {
    final current = node.parent;
    if (current != null) current.remove(node);
  }

  /// Detaches and releases the material's texture reference.
  void dispose() {
    detach();
    material.colorTexture = null;
  }
}
