import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// The user's decision in the unsaved-changes dialog.
enum UnsavedChoice { save, discard, cancel }

/// Asks what to do with unsaved document changes before an action replaces
/// or closes the current project/model. Returns true when the action may
/// proceed (the project was saved or the changes were explicitly dropped),
/// false when the user cancelled.
///
/// No dialog is shown when there is nothing unsaved.
Future<bool> confirmUnsavedChanges(BuildContext context, AppState app) async {
  if (!app.hasUnsavedChanges) return true;
  final choice = await showDialog<UnsavedChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Несохранённые изменения'),
      content: const Text(
        'В проекте есть изменения, которые ещё не сохранены. '
        'Сохранить их перед продолжением?',
      ),
      actions: [
        TextButton(
          key: const Key('unsaved-cancel'),
          onPressed: () =>
              Navigator.pop(dialogContext, UnsavedChoice.cancel),
          child: const Text('Отмена'),
        ),
        TextButton(
          key: const Key('unsaved-discard'),
          onPressed: () =>
              Navigator.pop(dialogContext, UnsavedChoice.discard),
          child: const Text('Не сохранять'),
        ),
        FilledButton(
          key: const Key('unsaved-save'),
          onPressed: () => Navigator.pop(dialogContext, UnsavedChoice.save),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  switch (choice) {
    case UnsavedChoice.save:
      return app.saveAll();
    case UnsavedChoice.discard:
      return true;
    default:
      return false;
  }
}
