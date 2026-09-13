import 'package:flutter_test/flutter_test.dart';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:scene_editor/src/scene/light_renderer.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  group('rotationAlignY', () {
    vm.Vector3 apply(vm.Vector3 dir) =>
        rotationAlignY(dir).transform3(vm.Vector3(0, 1, 0));

    test('maps local +Y onto the aim direction', () {
      const cases = [
        [0.0, -1.0, 0.0],
        [0.0, 1.0, 0.0],
        [1.0, 0.0, 0.0],
        [-1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, -1.0],
        [-0.4, -0.85, -0.35],
        [0.6, 0.3, -0.8],
      ];
      for (final c in cases) {
        final dir = vm.Vector3(c[0], c[1], c[2]).normalized();
        final got = apply(dir);
        expect(got.distanceTo(dir), lessThan(1e-6),
            reason: 'for dir $dir got $got');
      }
    });

    test('rotationAlignY is an orthonormal rotation', () {
      final m = rotationAlignY(vm.Vector3(-0.4, -0.85, -0.35));
      final t = vm.Matrix3.copy(m.getRotation());
      expect(t.determinant().abs(), closeTo(1.0, 1e-6));
      vm.Vector3 col(int c) =>
          vm.Vector3(t.entry(0, c), t.entry(1, c), t.entry(2, c));
      for (var c = 0; c < 3; c++) {
        expect(col(c).length, closeTo(1.0, 1e-6));
      }
      expect(col(0).cross(col(1)).distanceTo(col(2)), lessThan(1e-6));
    });
  });

  group('light direction angles', () {
    test('azimuth/elevation roundtrip', () {
      const cases = [
        [0.0, -1.0, 0.0],
        [0.0, 1.0, 0.0],
        [1.0, 0.0, 0.0],
        [-1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 0.0, -1.0],
        [-0.4, -0.85, -0.35],
        [0.35, 0.6, -0.7],
      ];
      for (final c in cases) {
        final dir = vm.Vector3(c[0], c[1], c[2]).normalized();
        final (az, el) = lightDirToAngles(dir.x, dir.y, dir.z);
        final back = lightAnglesToDir(az, el);
        expect(back.distanceTo(dir), lessThan(1e-6),
            reason: 'for dir $dir angles ($az, $el) gave $back');
      }
    });

    test('conventions: +Z is azimuth 0, straight up is elevation 90', () {
      expect(lightDirToAngles(0, 0, 1).$1, closeTo(0, 1e-9));
      expect(lightDirToAngles(1, 0, 0).$1, closeTo(90, 1e-9));
      expect(lightDirToAngles(0, -1, 0).$2, closeTo(-90, 1e-9));
      expect(lightDirToAngles(0, 1, 0).$2, closeTo(90, 1e-9));
      expect(lightDirToAngles(0, 0, -1).$1, closeTo(180, 1e-9));
    });
  });

  group('srgbToLinear', () {
    test('converts sRGB to the engine linear space', () {
      final black = srgbToLinear(0, 0, 0);
      expect(black.length2, 0);
      final white = srgbToLinear(1, 1, 1);
      expect(white.x, closeTo(1.0, 1e-6));
      final mid = srgbToLinear(0.5, 0.5, 0.5);
      expect(mid.x, closeTo(0.214, 1e-3));
      // The linear value of a 0.5 sRGB channel is below 0.5.
      expect(mid.x, lessThan(0.5));
    });
  });

  group('lightAnchor', () {
    test('mirrors the model position into world coordinates', () {
      final light = ModelLight(
        id: 'l1',
        kind: lightKindPoint,
        x: 1,
        y: 2,
        z: 1,
      );
      // Model (3×3): world x mirrors the column offset from the center —
      // the center column stays at world 0.
      final a = lightAnchor(light, 3, 3);
      expect(a.y, 2);
      expect(a.x.abs(), lessThan(1e-9));
      expect(a.z.abs(), lessThan(1e-9));
      // A corner cell of a 3×3 model sits one world unit out.
      final corner = ModelLight(
        id: 'l2',
        kind: lightKindPoint,
        x: 0,
        y: 1,
        z: 0,
      );
      final c = lightAnchor(corner, 3, 3);
      expect(c.x, closeTo(1, 1e-9)); // mirrored: column 0 → world +1
      expect(c.z, closeTo(-1, 1e-9));
    });
  });

  group('light defaults', () {
    test('kind labels and per-kind intensities', () {
      expect(lightKindLabel(lightKindPoint), 'Точечный свет');
      expect(lightKindLabel(lightKindDirectional), 'Направленный свет');
      expect(lightDefaultIntensity(lightKindDirectional),
          isNot(lightDefaultIntensity(lightKindPoint)));
    });
  });
}
