import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

/// The real Pet sample project (repo root) — the roundtrip/semantics source
/// of truth the engine must stay compatible with.
final Directory petProjectDir =
    Directory('${Directory.current.path}/../projects/Pet');

String _petModel(String id) =>
    File('${petProjectDir.path}/models/$id.json').readAsStringSync();

void main() {
  group('ModelData roundtrip (Pet project)', () {
    test('model_1 and model_2 parse, serialize back identically', () {
      for (final id in ['model_1', 'model_2']) {
        final json = _petModel(id);
        final data = ModelData.fromJson(json, id: id);
        expect(data.id, id);
        expect(data.objects, isNotEmpty);
        final re = data.toJson();
        final json2 = const JsonEncoder.withIndent('  ').convert(re);
        final parsed = ModelData.fromJson(json2, id: id);
        expect(parsed.objects.length, data.objects.length);
        // Roundtrip: re-encoding a parsed model yields the same keys.
        expect(data.toJson(), parsed.toJson());
      }
    });

    test('model_2 exposes gltf cat with its animation selection', () {
      final data = ModelData.fromJson(_petModel('model_2'), id: 'model_2');
      final cat = data.objects.firstWhere((o) => o.isGltfRef);
      expect(cat.gltfName, 'cat');
      expect(cat.anim, contains('Cat_'));
      final csg = data.objects.where((o) => o.isCsg);
      expect(csg, isNotEmpty);
    });

    test('model_2 references model_1 (chair) by id', () {
      final data = ModelData.fromJson(_petModel('model_2'), id: 'model_2');
      final ref = data.objects.firstWhere((o) => o.isModelRef);
      expect(ref.refModelId, 'model_1');
    });
  });

  group('coords conventions', () {
    test('chunkWorld centers and mirrors X', () {
      // Model of 5×5 grid: model x=0 → world x=+(w−1)/2 (X is mirrored);
      // z stays as authored minus the centering offset.
      final a = chunkWorld(0, 0, 5, 5);
      expect(a.x, closeTo(2, 1e-9));
      expect(a.z, closeTo(-2, 1e-9));
      final b = chunkWorld(4, 4, 5, 5);
      expect(b.x, closeTo(-2, 1e-9));
      expect(b.z, closeTo(2, 1e-9));
    });

    test('modelXFromWorld/modelZFromWorld invert chunkWorld', () {
      for (final x in [0.0, 1.5, 4.0]) {
        for (final z in [0.0, 2.5, 4.0]) {
          final w = chunkWorld(x, z, 5, 5);
          expect(modelXFromWorld(w.x, 5), closeTo(x, 1e-9));
          expect(modelZFromWorld(w.z, 5), closeTo(z, 1e-9));
        }
      }
    });
  });

  group('per-axis tile scale', () {
    test('defaults to tileScale and round-trips', () {
      final mat = ModelMaterial(
        type: MaterialType.texture,
        key: 'wall.png',
        stretch: 'tile',
        tileScale: 1.0,
        tileScaleU: 1.0,
        tileScaleV: 0.7,
      );
      final json = mat.toJson();
      expect(json['tileScaleU'], isNull, reason: 'совпадает с tileScale');
      expect(json['tileScaleV'], 0.7);
      final parsed = ModelMaterial.fromJson(json);
      expect(parsed.tileScaleU, 1.0);
      expect(parsed.tileScaleV, 0.7);
    });

    test('copy carries both axes', () {
      final mat = ModelMaterial(
        stretch: 'tile',
        tileScale: 2,
        tileScaleU: 3,
        tileScaleV: 4,
      );
      final copy = ModelMaterial.copy(mat);
      expect(copy.tileScaleU, 3);
      expect(copy.tileScaleV, 4);
    });
  });
}
