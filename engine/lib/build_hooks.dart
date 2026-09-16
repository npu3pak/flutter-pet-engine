/// Build-hook helpers for games on pet_engine.
///
/// Games call [petBuildMaterials] from their `hook/build.dart` so their
/// `.fmat` shaders compile through the engine's vendored pipeline without the
/// game depending on the fork directly:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:pet_engine/build_hooks.dart';
///
/// void main(List<String> args) {
///   build(args, (input, output) async {
///     await petBuildMaterials(buildInput: input, buildOutput: output);
///   });
/// }
/// ```
library;

import 'package:flutter_scene/build_hooks.dart' as fork;
import 'package:hooks/hooks.dart';

/// Compiles the package's `.fmat` materials into the Flutter GPU shader
/// bundle, using `dataAssetsIfAvailable` so tool passes without DataAssets
/// support fall back to legacy output instead of failing the build.
Future<void> petBuildMaterials({
  required BuildInput buildInput,
  required BuildOutputBuilder buildOutput,
}) {
  return fork.buildMaterials(
    buildInput: buildInput,
    buildOutput: buildOutput,
    assetMode: fork.MaterialAssetMode.dataAssetsIfAvailable,
  );
}
