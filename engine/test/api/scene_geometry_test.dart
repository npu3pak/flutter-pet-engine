import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('SceneGeometry primitives', () {
    test('cuboid is centered and sized', () {
      final geometry = SceneGeometry.cuboid(vm.Vector3(2, 4, 6));
      final bounds = geometry.localBounds!;
      expect(bounds.min.x, closeTo(-1, 1e-6));
      expect(bounds.max.x, closeTo(1, 1e-6));
      expect(bounds.min.y, closeTo(-2, 1e-6));
      expect(bounds.max.y, closeTo(2, 1e-6));
      expect(bounds.min.z, closeTo(-3, 1e-6));
      expect(bounds.max.z, closeTo(3, 1e-6));
      expect(geometry.data.vertexCount, greaterThan(0));
    });

    test('plane lies in XZ', () {
      final geometry = SceneGeometry.plane(width: 4, depth: 2);
      final bounds = geometry.localBounds!;
      expect(bounds.min.x, closeTo(-2, 1e-6));
      expect(bounds.max.z, closeTo(1, 1e-6));
      expect(bounds.max.y - bounds.min.y, closeTo(0, 1e-6));
    });

    test('cylinder, cone, sphere and ring are centered', () {
      final cylinder = SceneGeometry.cylinder(
        bottomRadius: 1,
        topRadius: 1,
        height: 3,
      );
      final cylinderBounds = cylinder.localBounds!;
      expect(cylinderBounds.max.x, closeTo(1, 1e-6));
      expect(cylinderBounds.max.y - cylinderBounds.min.y, closeTo(3, 1e-6));

      final cone = SceneGeometry.cone(radius: 1, height: 2);
      expect(cone.localBounds!.max.x, closeTo(1, 1e-6));

      final sphere = SceneGeometry.sphere(radius: 2, segments: 16);
      final sphereBounds = sphere.localBounds!;
      expect(sphereBounds.max.x, closeTo(2, 0.05));
      expect(sphereBounds.max.y, closeTo(2, 0.05));

      final ring = SceneGeometry.ring(radius: 1, tubeRadius: 0.25);
      final ringBounds = ring.localBounds!;
      expect(ringBounds.max.x, closeTo(1.25, 1e-6));
      expect(ringBounds.max.y, closeTo(0.25, 1e-6));
    });

    test('rounded box and trapezoid are centered', () {
      final rounded = SceneGeometry.roundedBox(
        size: vm.Vector3(2, 2, 2),
        radius: 0.4,
        segments: 8,
      );
      final roundedBounds = rounded.localBounds!;
      expect(roundedBounds.min.y, closeTo(-1, 1e-6));
      expect(roundedBounds.max.y, closeTo(1, 1e-6));
      expect(roundedBounds.max.x, closeTo(1, 1e-6));

      final trapezoid = SceneGeometry.trapezoid(
        bottomWidth: 2,
        topWidth: 1,
        height: 2,
        depth: 2,
      );
      final trapezoidBounds = trapezoid.localBounds!;
      expect(trapezoidBounds.min.y, closeTo(-1, 1e-6));
      expect(trapezoidBounds.max.y, closeTo(1, 1e-6));
      expect(trapezoidBounds.max.x, closeTo(1, 1e-6));
    });

    test('annulus is flat and sized', () {
      final annulus = SceneGeometry.annulus(innerRadius: 0.5, outerRadius: 1);
      final bounds = annulus.localBounds!;
      expect(bounds.max.x, closeTo(1, 1e-6));
      expect(bounds.max.y - bounds.min.y, closeTo(0, 1e-6));
    });
  });

  group('GeometryBuilder raw vertices', () {
    test('adds vertices and triangles with sticky attributes', () {
      final builder = GeometryBuilder()
        ..setNormal(vm.Vector3(0, 1, 0))
        ..setTexCoord(0.5, 0.25);
      final a = builder.addVertex(vm.Vector3(0, 0, 0));
      final b = builder.addVertex(vm.Vector3(1, 0, 0));
      final c = builder.addVertex(vm.Vector3(0, 0, 1));
      builder.addTriangle(a, b, c);

      final geometry = builder.build();
      expect(builder.vertexCount, 3);
      expect(builder.triangleCount, 1);
      expect(geometry.data.normals![0], 0);
      expect(geometry.data.normals![1], 1);
      expect(geometry.data.texCoords![0], 0.5);
      expect(geometry.data.indices, [0, 1, 2]);
    });

    test('deduplicate reuses identical vertices', () {
      final builder = GeometryBuilder(deduplicate: true)
        ..setNormal(vm.Vector3(0, 1, 0))
        ..setTexCoord(0, 0);
      final a = builder.addVertex(vm.Vector3(1, 1, 1));
      final b = builder.addVertex(vm.Vector3(1, 1, 1));
      expect(a, b);
      expect(builder.vertexCount, 1);
    });
  });

  group('GeometryBuilder operations', () {
    test('addGeometry bakes translation, scale and winding', () {
      final source = SceneGeometry.cuboid(vm.Vector3(1, 1, 1));
      final builder = GeometryBuilder()
        ..addGeometry(
          source,
          vm.Matrix4.translation(vm.Vector3(5, 0, 0)) *
              vm.Matrix4.diagonal3Values(2, 2, 2),
        );
      final bounds = builder.build().localBounds!;
      expect(bounds.min.x, closeTo(4, 1e-6));
      expect(bounds.max.x, closeTo(6, 1e-6));

      final mirrored = GeometryBuilder()
        ..addGeometry(source, vm.Matrix4.diagonal3Values(-1, 1, 1));
      final mirroredIndices = mirrored.build().data.indices!;
      final plainIndices = GeometryBuilder()
        ..addGeometry(source, vm.Matrix4.identity());
      final plain = plainIndices.build().data.indices!;
      expect(mirroredIndices[0], plain[0]);
      expect(mirroredIndices[1], plain[2]);
      expect(mirroredIndices[2], plain[1]);
    });

    test('addTiledPlane anchors UVs to the world origin', () {
      final builder = GeometryBuilder()
        ..addTiledPlane(x: 2, z: 3, width: 4, depth: 2, y: 0, tileSize: 1);
      final data = builder.build().data;
      expect(data.vertexCount, 4);
      expect(data.texCoords![0], 2);
      expect(data.texCoords![1], 3);
      expect(data.texCoords![2], 6);
    });

    test('addWallBox emits four faces without caps', () {
      final builder = GeometryBuilder()
        ..addWallBox(min: vm.Vector3(0, 0, 0), max: vm.Vector3(2, 3, 1));
      expect(builder.vertexCount, 16);
      expect(builder.triangleCount, 8);
    });

    test('addVerticalQuad faces +Z at yaw 0 and can be rotated', () {
      final front = GeometryBuilder()
        ..addVerticalQuad(
          center: vm.Vector3(1, 2, 3),
          width: 2,
          height: 4,
          yaw: 0,
        );
      final frontData = front.build().data;
      expect(frontData.vertexCount, 4);
      expect(frontData.normals![2], closeTo(1, 1e-9));
      final frontBounds = front.build().localBounds!;
      expect(frontBounds.min.y, closeTo(0, 1e-6));
      expect(frontBounds.max.y, closeTo(4, 1e-6));

      final side = GeometryBuilder()
        ..addFacingQuad(
          center: vm.Vector3.zero(),
          width: 1,
          height: 1,
          facing: 'west',
        );
      expect(side.build().data.normals![0], closeTo(1, 1e-9));
    });

    test('addQuad winds inward with an outward normal', () {
      final builder = GeometryBuilder()
        ..addQuad(
          a: vm.Vector3(0, 0, 0),
          b: vm.Vector3(1, 0, 0),
          c: vm.Vector3(1, 1, 0),
          d: vm.Vector3(0, 1, 0),
        );
      final data = builder.build().data;
      expect(data.normals![2], closeTo(1, 1e-9));
      expect(data.indices, [0, 2, 1, 0, 3, 2]);
    });
  });

  group('LineGeometry', () {
    test('stores endpoint pairs and computes bounds', () {
      final geometry = LineGeometry([
        vm.Vector3.zero(),
        vm.Vector3(1, 2, 3),
      ], width: 0.2);
      expect(geometry.segmentCount, 1);
      expect(geometry.data.positions.length, 6);
      final bounds = geometry.localBounds!;
      expect(bounds.min.x, closeTo(-0.1, 1e-6));
      expect(bounds.max.z, closeTo(3.1, 1e-6));
    });

    test('rejects an odd point count', () {
      expect(() => LineGeometry([vm.Vector3.zero()]), throwsArgumentError);
    });
  });
}
