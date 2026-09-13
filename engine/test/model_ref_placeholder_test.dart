import 'package:flutter_test/flutter_test.dart';
import 'package:pet_engine_v2/pet_engine_v2.dart';

void main() {
  test('missing model-instance placeholder is bright fuchsia', () {
    final ref = ModelObject(
      id: 'ref_missing',
      name: 'Отсутствующий источник',
      kind: modelRefKind,
      x: 1,
      y: 0,
      z: 2,
      refModelId: 'missing_scene',
      refSize: ModelSize(w: 2, l: 3, h: 4),
    );
    final box = modelRefFootprintBox(ref);
    expect(box.material?.type, MaterialType.color);
    expect(box.material?.color, const [255, 0, 255]);
    expect(box.dim('w', 0), closeTo(2, 1e-9));
    expect(box.dim('d', 0), closeTo(3, 1e-9));
    expect(box.dim('h', 0), closeTo(4, 1e-9));
  });
}
