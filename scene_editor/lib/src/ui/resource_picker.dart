import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'resource_thumb.dart';

/// A compact grid of resource thumbnails for picking a texture/sprite.
/// The selected file gets a highlighted border; tapping calls [onPick].
class ResourcePicker extends StatelessWidget {
  final List<String> files;
  final String rootDir;
  final String? selected;
  final void Function(String name) onPick;

  const ResourcePicker({
    super.key,
    required this.files,
    required this.rootDir,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const Text(
        'Нет ресурсов — добавьте их во вкладке «Ресурсы»',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in files)
          Tooltip(
            message: name,
            child: InkWell(
              onTap: () => onPick(name),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: name == selected
                        ? const Color(0xFF4C9BE8)
                        : const Color(0xFF555B66),
                    width: name == selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: ResourceThumb(path: p.join(rootDir, name)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dialog that picks a sprite from the project (for «Добавить спрайт»).
Future<String?> pickSpriteDialog(
  BuildContext context, {
  required List<String> sprites,
  required String rootDir,
}) {
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: const Text('Выберите спрайт',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 320,
        child: sprites.isEmpty
            ? const Text(
                'Нет спрайтов — добавьте их во вкладке «Ресурсы»',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in sprites)
                    Tooltip(
                      message: name,
                      child: InkWell(
                        onTap: () => Navigator.pop(c, name),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFF555B66), width: 1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: ResourceThumb(
                                path: p.join(rootDir, name)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );
}
