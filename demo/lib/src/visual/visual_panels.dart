import 'package:flutter/material.dart';

import '../features/feature_registry.dart';
import 'visual_tests.dart';

/// Список проверок: статусы, фильтр «показать все», выбор фичи.
class ChecklistPanel extends StatelessWidget {
  const ChecklistPanel({
    super.key,
    required this.features,
    required this.store,
    required this.selectedId,
    required this.showAll,
    required this.onShowAllChanged,
    required this.onSelect,
  });

  final List<FeatureSpec> features;
  final VisualTestStore store;
  final String? selectedId;
  final bool showAll;
  final ValueChanged<bool> onShowAllChanged;
  final ValueChanged<FeatureSpec> onSelect;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final spec in features)
        if (showAll || store.statusOf(spec.id) != VisualStatus.ok) spec,
    ];
    return Container(
      color: const Color(0xFF1B1F26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Text(
              'Визуальная проверка',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Показать все',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Switch(
                  key: const Key('checklist-show-all'),
                  value: showAll,
                  onChanged: onShowAllChanged,
                ),
              ],
            ),
          ),
          const Divider(height: 12, color: Colors.white12),
          Expanded(
            child: ListView(
              key: const Key('checklist-list'),
              children: [
                for (final spec in visible) _tile(spec),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Нет проверок для показа.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              store.loadError ??
                  'Файл: ${store.path}\nПроверено: '
                      '${features.where((f) => store.statusOf(f.id) == VisualStatus.ok).length}'
                      ' из ${features.length}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(FeatureSpec spec) {
    final status = store.statusOf(spec.id);
    final (label, color) = switch (status) {
      VisualStatus.ok => ('проверена', Colors.greenAccent),
      VisualStatus.issue => ('есть замечания', Colors.redAccent),
      VisualStatus.notChecked => ('не проверена', Colors.white54),
    };
    final selected = spec.id == selectedId;
    return Material(
      color: selected ? const Color(0xFF2C3340) : Colors.transparent,
      child: InkWell(
        key: Key('check-${spec.id}'),
        onTap: () => onSelect(spec),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'фаза ${spec.phase} · $label',
                style: TextStyle(color: color, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Анкета фичи: что демонстрируется, что проверить и два варианта ответа.
class QuestionnairePanel extends StatefulWidget {
  const QuestionnairePanel({
    super.key,
    required this.spec,
    required this.store,
    required this.version,
    required this.onChanged,
  });

  final FeatureSpec spec;
  final VisualTestStore store;
  final String version;
  final VoidCallback onChanged;

  @override
  State<QuestionnairePanel> createState() => _QuestionnairePanelState();
}

class _QuestionnairePanelState extends State<QuestionnairePanel> {
  final TextEditingController _comment = TextEditingController();
  bool _issueOpen = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _answer(bool ok) {
    final error = widget.store.setCheck(
      featureId: widget.spec.id,
      ok: ok,
      comment: ok ? '' : _comment.text.trim(),
      phase: widget.spec.phase,
      version: widget.version,
    );
    setState(() => _issueOpen = false);
    widget.onChanged();
    _toast(error ?? (ok ? 'Фича отмечена проверенной' : 'Замечание сохранено'));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.store.check(widget.spec.id);
    return Container(
      color: const Color(0xFF1B1F26),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.spec.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Что демонстрируется',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.spec.description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Что нужно проверить',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final check in widget.spec.checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    Expanded(
                      child: Text(
                        check,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('answer-ok'),
                  onPressed: () => _answer(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Корректно'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('answer-issue'),
                  onPressed: () => setState(() => _issueOpen = true),
                  icon: const Icon(Icons.bug_report, size: 18),
                  label: const Text('Есть замечание'),
                ),
              ],
            ),
            if (_issueOpen) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('issue-text'),
                controller: _comment,
                minLines: 3,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Опишите, что не так',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              FilledButton(
                key: const Key('issue-save'),
                onPressed: () => _answer(false),
                child: const Text('Сохранить замечание'),
              ),
            ],
            if (record != null) ...[
              const Divider(height: 20),
              Text(
                record.status == CheckStatus.ok
                    ? 'Ответ: корректно (${record.version})'
                    : 'Ответ: есть замечание (${record.version})',
                style: TextStyle(
                  color: record.status == CheckStatus.ok
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 11,
                ),
              ),
              if (record.comment.isNotEmpty)
                Text(
                  record.comment,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Журнал замечаний фичи: список, история, кнопки состояния и форма.
class BugPanel extends StatefulWidget {
  const BugPanel({
    super.key,
    required this.spec,
    required this.store,
    required this.version,
    required this.onChanged,
  });

  final FeatureSpec spec;
  final VisualTestStore store;
  final String version;
  final VoidCallback onChanged;

  @override
  State<BugPanel> createState() => _BugPanelState();
}

class _BugPanelState extends State<BugPanel> {
  final TextEditingController _newBug = TextEditingController();
  final TextEditingController _message = TextEditingController();
  String? _selectedId;
  bool _newBugOpen = false;

  @override
  void dispose() {
    _newBug.dispose();
    _message.dispose();
    super.dispose();
  }

  void _report() {
    final text = _newBug.text.trim();
    if (text.isEmpty) return;
    final error = widget.store.reportBug(
      featureId: widget.spec.id,
      text: text,
      version: widget.version,
    );
    _newBug.clear();
    setState(() => _newBugOpen = false);
    widget.onChanged();
    _toast(error ?? 'Замечание добавлено');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bugs = widget.store.bugsOf(widget.spec.id)
      ..sort((a, b) {
        if (a.status != b.status) return a.status == BugStatus.open ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final selected = _selectedId == null
        ? (bugs.isEmpty ? null : bugs.first)
        : widget.store.bug(_selectedId!);
    return Material(
      color: const Color(0xFF1B1F26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Text(
              'Журнал замечаний',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              widget.spec.title,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(
              key: const Key('bug-new'),
              onPressed: () => setState(() => _newBugOpen = !_newBugOpen),
              icon: const Icon(Icons.bug_report, size: 18),
              label: const Text('Сообщить о проблеме'),
            ),
          ),
          if (_newBugOpen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  TextField(
                    key: const Key('bug-new-text'),
                    controller: _newBug,
                    minLines: 3,
                    maxLines: null,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Опишите проблему',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton(
                    key: const Key('bug-new-save'),
                    onPressed: _report,
                    child: const Text('Зафиксировать'),
                  ),
                ],
              ),
            ),
          const Divider(height: 12, color: Colors.white12),
          Expanded(
            child: bugs.isEmpty
                ? const Center(
                    child: Text(
                      'Замечаний нет',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView(
                    children: [
                      for (final bug in bugs)
                        ListTile(
                          key: Key('bug-${bug.id}'),
                          dense: true,
                          selected: bug.id == selected?.id,
                          selectedTileColor: const Color(0xFF2C3340),
                          leading: Icon(
                            Icons.bug_report,
                            size: 18,
                            color: bug.status == BugStatus.open
                                ? Colors.redAccent
                                : Colors.white38,
                          ),
                          title: Text(
                            bug.events.first.text.isEmpty
                                ? bug.id
                                : bug.events.first.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Text(
                            bug.status == BugStatus.open
                                ? 'открыто'
                                : 'исправлено',
                            style: TextStyle(
                              color: bug.status == BugStatus.open
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                              fontSize: 10,
                            ),
                          ),
                          onTap: () => setState(() => _selectedId = bug.id),
                        ),
                    ],
                  ),
          ),
          if (selected != null) ...[
            const Divider(height: 1, color: Colors.white12),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selected.id} · ${selected.featureId}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final event in selected.events)
                      if (event.author != 'agent') _event(event),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (selected.status == BugStatus.open)
                          fcAction('Баг исправлен', () {
                            final error = widget.store.markFixed(
                              bugId: selected.id,
                              version: widget.version,
                            );
                            widget.onChanged();
                            _toast(error ?? 'Замечание помечено исправленным');
                          }, key: const Key('bug-fixed')),
                        if (selected.status == BugStatus.fixed)
                          fcAction('Баг вернулся', () {
                            final error = widget.store.reopenBug(
                              bugId: selected.id,
                              text: _message.text.trim(),
                              version: widget.version,
                            );
                            _message.clear();
                            widget.onChanged();
                            _toast(error ?? 'Замечание снова открыто');
                          }, key: const Key('bug-reopen')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('bug-message'),
                      controller: _message,
                      minLines: 1,
                      maxLines: null,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Дописать сообщение',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.tonal(
                      key: const Key('bug-message-save'),
                      onPressed: () {
                        final text = _message.text.trim();
                        if (text.isEmpty) return;
                        final error = widget.store.addMessage(
                          bugId: selected.id,
                          text: text,
                          version: widget.version,
                        );
                        _message.clear();
                        widget.onChanged();
                        _toast(error ?? 'Сообщение добавлено');
                      },
                      child: const Text('Дописать'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _event(BugEvent event) {
    final label = switch (event.kind) {
      BugEventKind.reported => 'сообщено',
      BugEventKind.fixed => 'исправлено',
      BugEventKind.reopened => 'открыто снова',
      BugEventKind.message => 'сообщение',
      BugEventKind.note => 'заметка',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${event.at.toLocal().toString().substring(0, 16)} · $label',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          if (event.text.isNotEmpty)
            Text(
              event.text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          if (event.version.isNotEmpty)
            Text(
              event.version,
              style: const TextStyle(color: Colors.white24, fontSize: 9),
            ),
        ],
      ),
    );
  }

  Widget fcAction(String label, VoidCallback onPressed, {Key? key}) {
    return OutlinedButton(
      key: key,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
