import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // No .fmat/.fscene/.fstex assets in the engine package — an empty
    // buildMaterials pass keeps the flutter_scene pipeline (DataAssets)
    // initialized the same way the apps do.
    await buildMaterials(
      buildInput: input,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsIfAvailable,
    );
  });
}
