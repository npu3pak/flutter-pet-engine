import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine/pet_engine.dart';
import 'package:pet_engine/src/scene/model_renderer.dart' show ModelRenderer;
import 'package:pet_engine/src/services/texture_cache.dart' show TextureCache;
import 'package:vector_math/vector_math.dart' as vm;

/// Headless checks of the rotate fast path (`updateObjectTransforms` with
/// `rotated`). The renderer's nodes are registered by hand: building real
/// geometry needs Flutter GPU, while the transform math and the node
/// application are pure.

ModelMaterial get _material =>
    ModelMaterial(type: MaterialType.color, color: const [200, 120, 60]);

ModelObject _box(
  String id, {
  double x = 0,
  double y = 0,
  double z = 0,
  double rotX = 0,
  double rotY = 0,
  double rotZ = 0,
  double w = 1,
  double h = 1,
  double d = 1,
  double roundR = 0,
}) =>
    ModelObject(
      id: id,
      name: id,
      kind: 'cuboid',
      x: x,
      y: y,
      z: z,
      rotX: rotX,
      rotY: rotY,
      rotZ: rotZ,
      dims: {
        'w': w,
        'h': h,
        'd': d,
        if (roundR > 0) 'roundR': roundR,
      },
      material: _material,
    );

ModelObject _ref(String id, {double x = 1, double z = 2}) => ModelObject(
      id: id,
      name: id,
      kind: 'model',
      x: x,
      z: z,
      refModelId: 'src',
      refSize: ModelSize(w: 3, l: 3, h: 3),
    );

ModelData _doc() => ModelData(
      id: 'm',
      name: 'm',
      size: ModelSize(w: 5, l: 4, h: 3),
      objects: [
        _box('solid', x: 0, z: 0),
        _ref('ref'),
        _box('round', x: 3, z: 3, w: 2, h: 1, d: 1, roundR: 0.3),
      ],
    );

/// The model-space rotation step `R_new · R_old⁻¹` used by the editor.
vm.Matrix4 _step(ModelObject o, void Function() mutate) {
  final before = objectRotation(o);
  mutate();
  return objectRotation(o) * (before.clone()..invert());
}

/// The world anchor of an object (`chunkWorld` maps the model cell).
vm.Vector3 _anchor(ModelObject o, ModelData doc) {
  final a = chunkWorld(o.x, o.z, doc.size.w, doc.size.l);
  return vm.Vector3(a.x, o.y, a.z);
}

vm.Matrix4 _about(vm.Vector3 anchor, vm.Matrix4 step) =>
    vm.Matrix4.translation(anchor) *
    step *
    vm.Matrix4.translation(-anchor);

void _expectMatrixClose(vm.Matrix4 a, vm.Matrix4 b, {double eps = 1e-6}) {
  for (var i = 0; i < 16; i++) {
    expect(a.storage[i], closeTo(b.storage[i], eps), reason: 'index $i');
  }
}

/// Registers a fake node for [id] (no geometry, no GPU).
Node _register(ModelRenderer renderer, String id) {
  final node = Node(name: 'fake:$id');
  renderer.elementNodes.putIfAbsent(id, () => []).add(node);
  renderer.elementOfNode[node] = id;
  return node;
}

void main() {
  test('rotation prefixes map renderer-style chains onto the new rotation', () {
    // Solid/instance chains: world = T(anchor)·R·S·L. The fast path must
    // reproduce the same result as recomputing the chain from the document.
    for (final axis in ['x', 'y', 'z']) {
      final doc = _doc();
      final o = doc.objectById('solid')!..rotX = 12..rotY = 34..rotZ = 56;
      final anchor = _anchor(o, doc);
      final scale = vm.Matrix4.diagonal3Values(1.7, 1.7, 1.7);
      final local = vm.Matrix4.translation(vm.Vector3(0.3, 0.4, 0.5));
      final oldChain =
          vm.Matrix4.translation(anchor) * objectRotation(o) * scale * local;
      final step = _step(o, () {
        switch (axis) {
          case 'x':
            o.rotX += 30;
          case 'y':
            o.rotY += 70;
          case 'z':
            o.rotZ -= 45;
        }
      });
      final newChain =
          vm.Matrix4.translation(anchor) * objectRotation(o) * scale * local;
      _expectMatrixClose(_about(anchor, step) * oldChain, newChain);
    }
  });

  test('baked mirrored geometry needs the conjugated rotation step', () {
    // Top-level csg/rounded vertices are baked as F(p) = M·p + c with the
    // model→world X mirror M about the grid center (see `_polyGroupMesh`).
    // Rotating the model-space chain must equal the conjugated world prefix
    // acting on the old baked matrix.
    final doc = _doc();
    final o = doc.objectById('round')!..rotX = 10..rotY = 20..rotZ = 30;
    final anchor = _anchor(o, doc);
    final mirror = vm.Matrix4.diagonal3Values(-1, 1, 1);
    final originX = (doc.size.w - 1) / 2;
    final originZ = (doc.size.l - 1) / 2;
    final bakeMap =
        vm.Matrix4.translation(vm.Vector3(originX, 0, -originZ)) * mirror;
    vm.Matrix4 baked() =>
        bakeMap *
        vm.Matrix4.translation(vm.Vector3(o.x, o.y, o.z)) *
        objectRotation(o);

    final oldBaked = baked();
    final step = _step(o, () => o.rotY += 90);
    final newBaked = baked();

    final conjugated = mirror * step * mirror;
    _expectMatrixClose(_about(anchor, conjugated) * oldBaked, newBaked);
    // The un-conjugated prefix rotates the wrong way for a Y step: the two
    // results must differ (otherwise mirroring convention is untested).
    final plain = _about(anchor, step) * oldBaked;
    var diff = 0.0;
    for (var i = 0; i < 16; i++) {
      diff += (plain.storage[i] - newBaked.storage[i]).abs();
    }
    expect(diff, greaterThan(1e-3));
  });

  test('updateObjectTransforms prefixes registered nodes per kind', () {
    final doc = _doc();
    final renderer = ModelRenderer(TextureCache(), mergeStatic: false);

    final solidNode = _register(renderer, 'solid');
    final refNode = _register(renderer, 'ref');
    final roundNode = _register(renderer, 'round');

    final solidStep = _step(doc.objectById('solid')!, () {
      doc.objectById('solid')!.rotY = 45;
    });
    final refStep = _step(doc.objectById('ref')!, () {
      doc.objectById('ref')!.rotY = 90;
    });
    final roundStep = _step(doc.objectById('round')!, () {
      doc.objectById('round')!.rotY = 30;
    });

    final updated = renderer.updateObjectTransforms(
      doc,
      rotated: {
        'solid': solidStep,
        'ref': refStep,
        'round': roundStep,
      },
    );
    expect(updated, isTrue);

    // Solid and instance chains take the step as is; the baked rounded node
    // gets the mirror-conjugated prefix.
    final mirror = vm.Matrix4.diagonal3Values(-1, 1, 1);
    _expectMatrixClose(
      solidNode.localTransform,
      _about(_anchor(doc.objectById('solid')!, doc), solidStep),
    );
    _expectMatrixClose(
      refNode.localTransform,
      _about(_anchor(doc.objectById('ref')!, doc), refStep),
    );
    _expectMatrixClose(
      roundNode.localTransform,
      _about(_anchor(doc.objectById('round')!, doc), mirror * roundStep * mirror),
    );
  });

  test('rotating an instance shifts its interactive billboard chains', () {
    final doc = _doc();
    final renderer = ModelRenderer(TextureCache(), mergeStatic: false);
    final refNode = _register(renderer, 'ref');
    final billboard = Node(name: 'sprite');
    final chain = vm.Matrix4.translation(vm.Vector3(0.5, 1, -0.5));
    renderer.instanceBillboards.add((billboard, chain));
    renderer.elementOfNode[billboard] = 'ref';
    expect(renderer.elementOfNode[refNode], 'ref');

    final o = doc.objectById('ref')!;
    final step = _step(o, () => o.rotY = 90);
    renderer.updateObjectTransforms(doc, rotated: {'ref': step});

    final anchor = _anchor(o, doc);
    final expected =
        _about(anchor, step) * chain;
    _expectMatrixClose(renderer.instanceBillboards.single.$2, expected);
  });
}
