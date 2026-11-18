import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/alarm.dart';
import '../../application/assistant/daily_tasks.dart';
import '../../application/assistant/personal_store.dart';
import '../../infrastructure/desktop/native_effects.dart';
import '../stats/stats_style.dart';
import 'calendar_tab.dart';
import 'time_field.dart';

/// Tareas de todos los días con su hora: suenan como alarma y se tachan
/// cada día.
class DailyTasksPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const DailyTasksPanel({super.key, required this.onClose});

  @override
  ConsumerState<DailyTasksPanel> createState() => _DailyTasksPanelState();
}

class _DailyTasksPanelState extends ConsumerState<DailyTasksPanel> {
  final _text = TextEditingController();
  bool _adding = false;

  /// 0: tareas diarias; 1: calendario.
  int _tab = 0;
  int _hour = 8;
  int _minute = 0;
  Set<int> _days = {...allDays};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final added = await ref
        .read(dailyTaskStoreProvider)
        .add(_text.text, _hour, _minute, days: _days, now: DateTime.now());
    if (added == null) return;
    _text.clear();
    setState(() {
      _adding = false;
      _days = {...allDays};
    });
  }

  void _testSound() => _ring();

  void _ring() => ref.read(alarmProvider.notifier).ring([
        ReminderItem('test', '🔔 Prueba de alarma', DateTime.now(), alarm: true)
      ]);

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dailyTaskStoreProvider);
    final now = DateTime.now();
    final today = store.today(now);
    final done = today.where((t) => t.doneToday(now)).length;
    return Container(
      decoration: BoxDecoration(
        color: StatsStyle.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatsStyle.accent, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<int>(
                key: const ValueKey('tasks-tabs'),
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: StatsStyle.textSecondary,
                  selectedForegroundColor: Colors.white,
                  selectedBackgroundColor: StatsStyle.accent,
                ),
                segments: const [
                  ButtonSegment(
                      value: 0,
                      label: Text('⏰ Diarias', style: TextStyle(fontSize: 11))),
                  ButtonSegment(
                      value: 1,
                      label: Text('📅 Calendario',
                          style: TextStyle(fontSize: 11))),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() {
                  _tab = v.first;
                  _adding = false;
                }),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          if (_tab == 1)
            const Expanded(child: CalendarTab())
          else ...[
            if (!_adding && today.isNotEmpty) ...[
              Text('Hoy: $done de ${today.length} hechas',
                  key: const ValueKey('daily-progress'),
                  style: const TextStyle(
                      color: StatsStyle.textSecondary, fontSize: 11)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / today.length,
                  minHeight: 5,
                  backgroundColor: StatsStyle.grid,
                  color: const Color(0xFF34D399),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(child: _adding ? _form() : _list(store, now)),
            const SizedBox(height: 6),
            if (!_adding)
              Row(children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('daily-test-sound'),
                    onPressed: _testSound,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact),
                    child: const Text('🔔 Probar sonido',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('daily-add'),
                    onPressed: () {
                      focusApp();
                      setState(() => _adding = true);
                    },
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact),
                    child:
                        const Text('＋ Añadir', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
          ],
        ],
      ),
    );
  }

  Widget _list(DailyTaskStore store, DateTime now) {
    final tasks = store.tasks;
    if (tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
            'Aún no tienes tareas diarias. Pulsa «Añadir» y elige la hora '
            'y los días: a esa hora sonará una alarma y te diré qué toca.\n\n'
            'También puedes decírmelo: «tarea diaria a las 8 am reunión '
            'virtual» o «alarma de lunes a viernes a las 7 gimnasio».',
            style: TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(right: 4),
      children: [
        for (final t in tasks)
          Padding(
            key: ValueKey('daily-${t.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: t.isToday(now) && t.enabled
                      ? Checkbox(
                          key: ValueKey('daily-done-${t.id}'),
                          value: t.doneToday(now),
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              store.setDone(t.id, v ?? false, now),
                        )
                      : const SizedBox(),
                ),
                SizedBox(
                  width: 58,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(t.time12,
                        style: TextStyle(
                            color: t.enabled
                                ? StatsStyle.textPrimary
                                : StatsStyle.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.enabled
                                ? StatsStyle.textPrimary
                                : StatsStyle.textMuted,
                            fontSize: 12,
                            decoration: t.doneToday(now)
                                ? TextDecoration.lineThrough
                                : null,
                          )),
                      Text(t.daysLabel,
                          style: const TextStyle(
                              color: StatsStyle.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('daily-bell-${t.id}'),
                  tooltip: t.enabled ? 'Silenciar' : 'Activar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => store.setEnabled(t.id, !t.enabled),
                  icon: Text(t.enabled ? '🔔' : '🔕',
                      style: const TextStyle(fontSize: 14)),
                ),
                IconButton(
                  key: ValueKey('daily-delete-${t.id}'),
                  tooltip: 'Borrar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => store.remove(t.id),
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: StatsStyle.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _form() {
    const label = TextStyle(color: StatsStyle.textSecondary, fontSize: 11);
    return ListView(
      children: [
        TextField(
          key: const ValueKey('daily-text'),
          controller: _text,
          autofocus: true,
          onTap: focusApp,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: '¿Qué tienes que hacer? (ej. Reunión virtual)',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
            isDense: true,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 10),
        TimeField(
          keyPrefix: 'daily',
          hour: _hour,
          minute: _minute,
          onChanged: (h, m) => setState(() {
            _hour = h;
            _minute = m;
          }),
        ),
        const SizedBox(height: 8),
        const Text('Días', style: label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            for (final MapEntry(key: d, value: letter) in dayLetters.entries)
              ChoiceChip(
                key: ValueKey('daily-day-$d'),
                label: Text(letter, style: const TextStyle(fontSize: 11)),
                selected: _days.contains(d),
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
                onSelected: (on) => setState(() {
                  _days = {..._days};
                  on ? _days.add(d) : _days.remove(d);
                }),
              ),
          ],
        ),
        Wrap(spacing: 6, children: [
          TextButton(
              onPressed: () => setState(() => _days = {...allDays}),
              child: const Text('Todos', style: TextStyle(fontSize: 11))),
          TextButton(
              onPressed: () => setState(() => _days = {...weekdays}),
              child: const Text('L a V', style: TextStyle(fontSize: 11))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          TextButton(
            onPressed: () => setState(() => _adding = false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('daily-save'),
            onPressed: _save,
            child: const Text('Guardar', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ],
    );
  }
}
