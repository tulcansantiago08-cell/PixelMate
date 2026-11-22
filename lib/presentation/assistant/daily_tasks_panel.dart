import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/alarm.dart';
import '../../application/assistant/alarm_settings.dart';
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
    _textFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Por qué no se guardó (se muestra encima de «Guardar»).
  String? _problem;
  final _textFocus = FocusNode();

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _problem = 'Escribe qué tienes que hacer.');
      _textFocus.requestFocus();
      return;
    }
    if (_days.isEmpty) {
      setState(() => _problem = 'Elige al menos un día.');
      return;
    }
    final DailyTask? added;
    try {
      added = await ref
          .read(dailyTaskStoreProvider)
          .add(text, _hour, _minute, days: _days, now: DateTime.now());
    } catch (e) {
      appLog('diarias: error al guardar: $e');
      if (mounted) setState(() => _problem = 'No pude guardarla: $e');
      return;
    }
    if (added == null || !mounted) return;
    _text.clear();
    setState(() {
      _adding = false;
      _problem = null;
      _days = {...allDays};
    });
  }

  /// Abre el formulario con el cursor ya en el texto.
  void _openForm() {
    focusApp();
    setState(() {
      _adding = true;
      _problem = null;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _textFocus.requestFocus());
  }

  void _testSound() => _ring();

  void _ring() => ref.read(alarmProvider.notifier).ring(
      [ReminderItem('test', 'Prueba de alarma', DateTime.now(), alarm: true)]);

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dailyTaskStoreProvider);
    final now = DateTime.now();
    final today = store.today(now);
    final done = today.where((t) => t.doneToday(now)).length;
    return Container(
      decoration: StatsStyle.panel(),
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
                      label: Text('Diarias', style: TextStyle(fontSize: 11))),
                  ButtonSegment(
                      value: 1,
                      label:
                          Text('Calendario', style: TextStyle(fontSize: 11))),
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
                  child: TextButton.icon(
                    key: const ValueKey('daily-test-sound'),
                    onPressed: _testSound,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.volume_up_outlined, size: 16),
                    label: const Text('Probar sonido',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('daily-add'),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: _openForm,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact),
                    label: const Text('Añadir', style: TextStyle(fontSize: 12)),
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
            'Sin alarmas.\n'
            'Añade una o dímelo: «alarma de lunes a viernes a las 7 '
            'gimnasio».',
            style: TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
      );
    }
    final sound = alarmSounds[ref.watch(alarmSettingsProvider).sound] ?? '';
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.86,
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      children: [
        for (final t in tasks) _AlarmTile(task: t, now: now, sound: sound),
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
          focusNode: _textFocus,
          autofocus: true,
          onTap: focusApp,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Nombre (ej. Reunión)',
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
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(_problem!,
                key: const ValueKey('daily-problem'),
                style: const TextStyle(color: Colors.amber, fontSize: 11)),
          ),
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

/// Una tarea diaria como tarjeta de alarma: la hora grande, qué es, cuándo
/// se repite, el sonido y el interruptor.
class _AlarmTile extends ConsumerWidget {
  final DailyTask task;
  final DateTime now;
  final String sound;
  const _AlarmTile(
      {required this.task, required this.now, required this.sound});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(dailyTaskStoreProvider);
    final t = task;
    final on = t.enabled;
    final done = t.doneToday(now);
    final dim = on ? 1.0 : 0.45;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    const muted = TextStyle(color: StatsStyle.textMuted, fontSize: 10.5);
    return Opacity(
      key: ValueKey('daily-${t.id}'),
      opacity: dim,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
        decoration: StatsStyle.card(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$h:${t.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: StatsStyle.textPrimary,
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w300)),
                TextSpan(
                    text: t.hour < 12 ? ' a. m.' : ' p. m.',
                    style: const TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 12)),
              ])),
            ),
            const SizedBox(height: 2),
            Text(t.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: StatsStyle.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  decoration: done ? TextDecoration.lineThrough : null,
                )),
            Text(
                'Repetir: ${t.daysLabel == 'De lunes a viernes' ? 'Lun a vie' : t.daysLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted),
            Text('Sonido: $sound',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            const Spacer(),
            Row(children: [
              SizedBox(
                width: 42,
                height: 26,
                child: FittedBox(
                  child: Switch(
                    key: ValueKey('daily-bell-${t.id}'),
                    value: on,
                    activeTrackColor: StatsStyle.accent,
                    onChanged: (v) => store.setEnabled(t.id, v),
                  ),
                ),
              ),
              const Spacer(),
              if (on && t.isToday(now))
                IconButton(
                  key: ValueKey('daily-done-${t.id}'),
                  tooltip: done ? 'Desmarcar' : 'Hecha hoy',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  iconSize: 18,
                  onPressed: () => store.setDone(t.id, !done, now),
                  icon: Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      color: done
                          ? const Color(0xFF34D399)
                          : StatsStyle.textMuted),
                ),
              IconButton(
                key: ValueKey('daily-delete-${t.id}'),
                tooltip: 'Borrar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 17,
                onPressed: () => store.remove(t.id),
                icon: const Icon(Icons.delete_outline,
                    color: StatsStyle.textMuted),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
