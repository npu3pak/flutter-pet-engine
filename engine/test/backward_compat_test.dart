import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';
import 'package:pet_engine_v2/src/api/pick_geometry.dart';
import 'package:pet_engine_v2/src/scene/csg.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Golden snapshots of the behavior that existed before the polyhedron work
/// (branch `feature/polyhedra`). The engine must keep serving old scenes and
/// old API without changes: any diff here is a backward-compatibility break.
///
/// Re-record intentionally (never casually):
/// `fvm flutter test test/backward_compat_test.dart
///  --dart-define=UPDATE_BACKWARD_COMPAT=true`
const bool _update = bool.fromEnvironment('UPDATE_BACKWARD_COMPAT');

final Directory _dir = Directory('test/fixtures/backward_compat');
final Directory petProjectDir =
    Directory('${Directory.current.path}/../projects/Pet');

String _petModel(String id) =>
    File('${petProjectDir.path}/models/$id.json').readAsStringSync();

double _r6(double v) => (v * 1e6).roundToDouble() / 1e6;

void _golden(String name, Object? value) {
  final text = const JsonEncoder.withIndent('  ').convert(value);
  final file = File('${_dir.path}/$name.json');
  if (_update) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$text\n');
    return;
  }
  expect(file.existsSync(), isTrue, reason: 'нет эталона ${file.path}');
  expect(
    text,
    file.readAsStringSync().trimRight(),
    reason: 'эталон $name изменился — сломана обратная совместимость',
  );
}

/// Stable FNV-1a (32-bit) digest — geometry equality without huge fixtures.
String _digest(Iterable<num> values) {
  var h = 0x811C9DC5;
  var i = 0;
  for (final v in values) {
    for (final c in v.toStringAsFixed(5).codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    if ((i++ & 0xFF) == 0) h = (h ^ 0x2C) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

Map<String, Object?> _partDigest(PickPart part) {
  final data = part.geometry.data;
  final positions = <double>[
    for (var i = 0; i < data.positions.length; i++) data.positions[i],
  ];
  final indices = data.indices ?? const <int>[];
  return {
    'faceKey': part.faceKey,
    'side': part.side,
    'vertexCount': data.vertexCount,
    'positionDigest': _digest(positions),
    'indexDigest': _digest(indices),
  };
}

ModelData _model(int w, int l, int h) => ModelData.fromJson(
      jsonEncode({
        'format': 'model_v1',
        'id': 'm',
        'name': 'm',
        'size': {'w': w, 'l': l, 'h': h},
        'objects': <Object>[],
      }),
      id: 'm',
    );

Map<String, Object?> _frame(FlyCameraController fly, int w, int l, int h) {
  fly.frameModel(_model(w, l, h));
  return {
    'eye': [_r6(fly.eye.x), _r6(fly.eye.y), _r6(fly.eye.z)],
    'yaw': _r6(fly.yaw),
    'pitch': _r6(fly.pitch),
  };
}

Map<String, ModelMaterial> _materials() => {
      'texture': ModelMaterial(
        type: MaterialType.texture,
        key: 'wall.png',
        uvDir: 90,
        flipX: true,
        stretch: 'tile',
        tileScale: 2,
        tileScaleU: 1.5,
        tileScaleV: 0.75,
        side: 'both',
      ),
      'color': ModelMaterial(color: [10, 20, 30]),
      'sprite': ModelMaterial(type: MaterialType.sprite, key: 'tree.png'),
    };

void main() {
  group('обратная совместимость: модель и объекты', () {
    test('Pet model_1/model_2 сериализуются канонически', () {
      for (final id in ['model_1', 'model_2']) {
        final data = ModelData.fromJson(_petModel(id), id: id);
        _golden('pet_$id', data.toJson());
      }
    });

    test('сериализация представителей всех старых kind', () {
      final mats = _materials();
      final objects = <String, ModelObject>{
        'cuboid': ModelObject(
          id: 'o1',
          name: 'cuboid',
          kind: 'cuboid',
          x: 1.5,
          y: 2,
          z: -0.25,
          rotY: 45,
          dims: {'w': 2, 'h': 3, 'd': 4},
        ),
        'cuboid_rounded': ModelObject(
          id: 'o2',
          name: 'rounded',
          kind: 'cuboid',
          dims: {'w': 2, 'h': 3, 'd': 4, 'roundR': 0.2, 'roundSegments': 12},
          material: mats['texture'],
        ),
        'trapezoid': ModelObject(
          id: 'o3',
          name: 'trapezoid',
          kind: 'trapezoid',
          dims: {'bottomW': 2, 'bottomD': 3, 'topW': 1, 'topD': 1.5, 'h': 2},
          rotX: 10,
          rotZ: -5,
        ),
        'cylinder': ModelObject(
          id: 'o4',
          name: 'cylinder',
          kind: 'cylinder',
          dims: {'bottomR': 0.5, 'topR': 0.25, 'h': 2, 'segments': 24},
        ),
        'cone': ModelObject(
          id: 'o5',
          name: 'cone',
          kind: 'cylinder',
          dims: {'bottomR': 0.5, 'topR': 0, 'h': 2, 'segments': 16},
        ),
        'plane_h': ModelObject(
          id: 'o6',
          name: 'plane',
          kind: 'plane',
          dims: {'w': 3, 'd': 4, 'vertical': 0},
        ),
        'plane_v': ModelObject(
          id: 'o7',
          name: 'plane',
          kind: 'plane',
          dims: {'w': 3, 'd': 4, 'vertical': 1},
        ),
        'sprite': ModelObject(
          id: 'o8',
          name: 'sprite',
          kind: 'sprite',
          dims: {'w': 1, 'h': 2},
          material: mats['sprite'],
        ),
        'csg': ModelObject(
          id: 'o9',
          name: 'csg',
          kind: csgKind,
          op: csgOpDifference,
          operands: ['o1', 'o2'],
          material: mats['color'],
        ),
        'model_ref': ModelObject(
          id: 'o10',
          name: 'ref',
          kind: modelRefKind,
          refModelId: 'model_1',
          scale: 1.5,
          refSize: ModelSize(w: 3, l: 3, h: 3),
          rotY: 30,
        ),
        'gltf_ref': ModelObject(
          id: 'o11',
          name: 'gltf',
          kind: gltfRefKind,
          gltfName: 'cat',
          scale: 0.5,
          gltfBounds: [-1, 0, -1, 1, 2, 1],
          anim: 'Cat_Walk',
        ),
        'unknown_kind': ModelObject(
          id: 'o12',
          name: 'future',
          kind: 'future_kind',
          dims: {'w': 1, 'h': 2, 'd': 3, 'extra': 7},
          faces: {'+x': mats['color']!},
        ),
      };
      final out = <String, Object>{
        for (final e in objects.entries) e.key: e.value.toJson(),
      };
      _golden('object_kinds', out);

      // Roundtrip: re-encoding a parsed object is stable.
      for (final e in objects.entries) {
        final back = ModelObject.fromJson(
          jsonDecode(jsonEncode(e.value.toJson())),
        );
        expect(back.toJson(), e.value.toJson(), reason: e.key);
      }
    });

    test('faceCorners всех объектов Pet стабильны', () {
      final out = <String, Object?>{};
      for (final id in ['model_1', 'model_2']) {
        final data = ModelData.fromJson(_petModel(id), id: id);
        for (final obj in data.objects) {
          for (final key in facesOf(obj)) {
            out['$id/${obj.id}/$key'] = [
              for (final c in faceCorners(obj, key))
                [_r6(c.x), _r6(c.y), _r6(c.z)],
            ];
          }
        }
      }
      _golden('face_corners', out);
    });

    test('pick-парты всех объектов Pet стабильны', () {
      final models = {
        for (final id in ['model_1', 'model_2'])
          id: ModelData.fromJson(_petModel(id), id: id),
      };
      final out = <String, Object?>{};
      for (final id in ['model_1', 'model_2']) {
        final data = models[id]!;
        for (final obj in data.objects) {
          final parts = buildObjectPickParts(
            data,
            obj,
            billboardYaw: 0.75,
            modelOf: (refId) => models[refId],
          );
          out['$id/${obj.id}'] = [for (final p in parts) _partDigest(p)];
        }
      }
      _golden('pick_parts', out);
    });

    test('представления граней (faceNormalAt/faceCenterAt) стабильны', () {
      final out = <String, Object?>{};
      for (final id in ['model_1', 'model_2']) {
        final data = ModelData.fromJson(_petModel(id), id: id);
        for (final obj in data.objects) {
          for (final key in facesOf(obj)) {
            final center = faceCenterAt(obj, key, billboardYaw: 0.75);
            final normal = faceNormalAt(obj, key, billboardYaw: 0.75);
            out['$id/${obj.id}/$key'] = {
              'center': center == null
                  ? null
                  : [_r6(center.x), _r6(center.y), _r6(center.z)],
              'normal': normal == null
                  ? null
                  : [_r6(normal.x), _r6(normal.y), _r6(normal.z)],
            };
          }
        }
      }
      _golden('face_snap', out);
    });
  });

  group('обратная совместимость: камера', () {
    test('дефолты FlyCameraController и масштабные функции', () {
      final fly = FlyCameraController();
      _golden('fly_defaults', {
        'projection': {
          'fovY': _r6(fly.projection.fovY),
          'near': fly.projection.near,
          'far': fly.projection.far,
        },
        'flySpeed': fly.flySpeed,
        'eye': [_r6(fly.eye.x), _r6(fly.eye.y), _r6(fly.eye.z)],
        'yaw': _r6(fly.yaw),
        'pitch': _r6(fly.pitch),
        'zoomMax_64_64_32': _r6(FlyCameraController.zoomMaxDistance(64, 64, 32)),
        'zoomMax_3_3_3': _r6(FlyCameraController.zoomMaxDistance(3, 3, 3)),
        'focusDistance_10': _r6(FlyCameraController.focusDistance(10)),
      });
    });

    test('frameModel старых размеров стабилен', () {
      final fly = FlyCameraController();
      _golden('frame_model', {
        '3x3x3': _frame(fly, 3, 3, 3),
        '5x7x4': _frame(fly, 5, 7, 4),
        '10x10x3': _frame(fly, 10, 10, 3),
        '64x64x32': _frame(fly, 64, 64, 32),
      });
    });
  });

  group('обратная совместимость: утилиты геометрии', () {
    test('SceneGeometry стандартных примитивов стабильна', () {
      final geometries = <String, SceneGeometry>{
        'cuboid': SceneGeometry.cuboid(vm.Vector3(2, 3, 4)),
        'cylinder': SceneGeometry.cylinder(
          bottomRadius: 0.5,
          topRadius: 0.25,
          height: 2,
          radialSegments: 8,
        ),
        'sphere': SceneGeometry.sphere(radius: 1, segments: 6),
        'ring': SceneGeometry.ring(radius: 0.9, tubeRadius: 0.1, segments: 8),
      };
      _golden('scene_geometry', {
        for (final e in geometries.entries)
          e.key: _partDigest(
            PickPart(e.value),
          ),
      });
    });

    test('триангуляция CSG-листьев стабильна', () {
      final data = ModelData.fromJson(_petModel('model_2'), id: 'model_2');
      final csg = data.objects.firstWhere((o) => o.isCsg);
      final polys = csgEvaluate(csg, data);
      _golden('csg_evaluate', {
        'count': polys.length,
        'faces': {
          for (final p in polys)
            '${p.surface.objId}/${p.surface.faceKey}': [
              for (final v in p.vertices) [_r6(v.x), _r6(v.y), _r6(v.z)],
            ],
        },
      });
    });
  });
}
