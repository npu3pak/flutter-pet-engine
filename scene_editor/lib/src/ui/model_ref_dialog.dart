import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Dialog that picks a model of the project to place as an instance
/// («Модель» tool): lists every model that may legally be inserted into
/// [app]'s current scene (not the scene itself, and no reference cycles).
/// Returns the chosen model id or null.
Future<String?> pickModelDialog(BuildContext context, AppState app) {
  final store = app.project;
  final containerId = app.currentModelId;
  final models = <({String id, String name, String subtitle, bool allowed})>[];
  if (store != null && containerId != null) {
    for (final id in store.modelIds) {
      final m = store.models[id];
      if (m == null) continue;
      models.add((
        id: id,
        name: m.name,
        subtitle:
            '${m.size.w}×${m.size.l}×${m.size.h} · ${m.objects.length} об.',
        allowed: app.canInsertModel(containerId, id),
      ));
    }
  }
  final candidates = models.where((m) => m.allowed).toList();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF262B34),
      title: const Text('Вставить модель',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: candidates.isEmpty
            ? const Text(
                'Нет моделей для вставки — создайте модель-деталь '
                '(например, кресло) во вкладке «Композиция» и сохраните её.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final m in candidates)
                    ListTile(
                      dense: true,
                      title: Text(
                        m.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                      subtitle: Text(
                        m.subtitle,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      onTap: () => Navigator.pop(c, m.id),
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
