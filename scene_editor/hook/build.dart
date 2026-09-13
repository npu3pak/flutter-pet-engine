import 'package:hooks/hooks.dart';
import 'package:pet_engine_v2/build_hooks.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    // Нет .fmat/.fscene/.fstex в самом редакторе — пустой прогон
    // petBuildMaterials инициализирует шейдерный пайплайн (DataAssets)
    // во время pub get.
    await petBuildMaterials(buildInput: input, buildOutput: output);
  });
}
