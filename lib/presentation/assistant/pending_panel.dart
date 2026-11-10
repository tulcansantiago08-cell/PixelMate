import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/assistant_executor.dart';
import '../../application/assistant/personal_store.dart';
import '../stats/stats_style.dart';

/// Tareas y recordatorios: tachar, añadir y borrar sin pasar por el chat.
class PendingPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const PendingPanel({super.key, required this.onClose});

  @override
  ConsumerState<PendingPanel> createState() => _PendingPanelState();
}

class _PendingPanelState extends ConsumerState<PendingPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(personalStoreProvider).addTask(text);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(personalStoreProvider);
    return Container(
      decoration: BoxDecoration(
        color: StatsStyle.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatsStyle.accent, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final pending = store.pending;
          final done = store.done;
          final reminders = store.reminders;
          final now = DateTime.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('📝 Pendientes',
                      style: TextStyle(
                          color: StatsStyle.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close,
                      size: 18, color: StatsStyle.textSecondary),
                ),
              ]),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(right: 4),
                  children: [
                    if (pending.isEmpty && reminders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            '🎉 Nada pendiente. Escribe abajo o dímelo en el '
                            'chat: «apunta comprar pan», «recuérdame en 20 '
                            'minutos…».',
                            style: TextStyle(
                                color: StatsStyle.textSecondary, fontSize: 11)),
                      ),
                    for (var i = 0; i < pending.length; i++)
                      _TaskRow(
                        key: ValueKey('task-${pending[i].id}'),
                        number: i + 1,
                        task: pending[i],
                        onToggle: () => store.setDone(pending[i].id, true),
                        onDelete: () => store.removeTask(pending[i].id),
                      ),
                    if (reminders.isNotEmpty) ...[
                      const _Header('⏰ Recordatorios'),
                      for (final r in reminders)
                        _Row(
                          key: ValueKey('reminder-${r.id}'),
                          leading: const Text('⏰'),
                          text: '${describeWhen(r.due, now)}: ${r.text}',
                          onDelete: () => store.removeReminder(r.id),
                        ),
                    ],
                    if (done.isNotEmpty) ...[
                      const _Header('✅ Hechas'),
                      for (final t in done)
                        _TaskRow(
                          key: ValueKey('task-${t.id}'),
                          task: t,
                          onToggle: () => store.setDone(t.id, false),
                          onDelete: () => store.removeTask(t.id),
                        ),
                    ],
                  ],
                ),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pending-input'),
                    controller: _input,
                    onSubmitted: (_) => _add(),
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Nueva tarea…',
                      hintStyle: const TextStyle(
                          color: StatsStyle.textMuted, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: StatsStyle.surfaceRaised,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('pending-add'),
                  tooltip: 'Añadir tarea',
                  onPressed: _add,
                  icon: const Icon(Icons.add_circle,
                      color: StatsStyle.accent, size: 24),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(text,
            style: const TextStyle(
                color: StatsStyle.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );
}

class _TaskRow extends StatelessWidget {
  final int? number;
  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskRow({
    super.key,
    this.number,
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => _Row(
        leading: SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: task.done,
            onChanged: (_) => onToggle(),
            activeColor: StatsStyle.accent,
            side: const BorderSide(color: StatsStyle.textMuted),
            visualDensity: VisualDensity.compact,
          ),
        ),
        text: number == null ? task.text : '$number. ${task.text}',
        crossed: task.done,
        onDelete: onDelete,
      );
}

class _Row extends StatelessWidget {
  final Widget leading;
  final String text;
  final bool crossed;
  final VoidCallback onDelete;

  const _Row({
    super.key,
    required this.leading,
    required this.text,
    this.crossed = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          leading,
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  color:
                      crossed ? StatsStyle.textMuted : StatsStyle.textPrimary,
                  fontSize: 12,
                  decoration: crossed ? TextDecoration.lineThrough : null,
                )),
          ),
          IconButton(
            tooltip: 'Borrar',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            icon:
                const Icon(Icons.close, size: 14, color: StatsStyle.textMuted),
          ),
        ]),
      );
}
