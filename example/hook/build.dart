import 'package:hooks/hooks.dart';
import 'package:pet_engine/build_hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    // No .fmat/.fscene/.fstex assets in the example itself — an empty
    // petBuildMaterials pass keeps the shader pipeline (DataAssets)
    // initialized during pub get.
    await petBuildMaterials(buildInput: input, buildOutput: output);
  });
}
