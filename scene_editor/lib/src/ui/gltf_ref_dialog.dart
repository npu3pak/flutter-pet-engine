import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'package:pet_engine/pet_engine.dart';

/// Dialog that picks a glTF/GLB resource of the project's `3d_models/`
/// catalog to place as an instance («GLB/GLTF» tool and «Заменить ресурс»):
/// lists every imported model with its storage format and size. Returns the
/// chosen catalog name or null.
Future<String?> pickGltfDialog(
  BuildContext context,
  AppState app, {
  String title = 'Вставить GLB/GLTF',
  String? excludeName,
}) {
  final gltf = app.project == null ? null : app.model3d;
  final items = gltf?.items ?? const <Model3dEntry>[];
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: items.isEmpty
            ? const Text(
                'Нет импортированных моделей. Добавьте .glb или .gltf '
                'во вкладке «Ресурсы» — кнопка «Импортировать модель».',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final e in items)
                    if (e.name != excludeName)
                      ListTile(
                        dense: true,
                        title: Text(
                          e.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${e.kindLabel} • ${e.sizeLabel} — ${e.entryFileName}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                        onTap: () => Navigator.pop(c, e.name),
                      ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}
