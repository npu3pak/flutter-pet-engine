import 'package:vector_math/vector_math.dart' as vm;

import 'scene_node.dart';

/// A container node: groups children so they move and dispose together.
class GroupNode extends SceneNode {
  GroupNode({super.id, super.name, super.layer});

  /// Adds [child] to this group.
  void add(SceneNode child) => linkChild(child);

  /// Removes [child] from this group (the child stays alive), or — called
  /// without arguments — detaches and disposes the group itself.
  @override
  void remove([SceneNode? child]) {
    if (child == null) {
      super.remove();
    } else {
      unlinkChild(child);
    }
  }

  /// Removes every child.
  void removeAll() {
    for (final child in List.of(children)) {
      unlinkChild(child);
    }
  }

  @override
  vm.Aabb3? get worldBounds {
    vm.Aabb3? union;
    for (final child in children) {
      final bounds = child.worldBounds;
      if (bounds == null) continue;
      if (union == null) {
        union = vm.Aabb3.minMax(bounds.min, bounds.max);
      } else {
        union.hull(bounds);
      }
    }
    return union;
  }
}
