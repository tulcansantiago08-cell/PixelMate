part of 'settings_panel.dart';

// Cómo suenan las alarmas.

/// Cómo suenan las alarmas: sonido (se oye al elegirlo), lo que se pospone
/// y el aviso previo de las tareas con hora.
class _AlarmOptions extends ConsumerWidget {
  const _AlarmOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(alarmSettingsProvider);
    Widget row(String label, Widget field) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12))),
            field,
          ]),
        );
    DropdownButton<T> pick<T>(String key, T value, Map<T, String> options,
            ValueChanged<T> onChanged) =>
        DropdownButton<T>(
          key: ValueKey(key),
          value: value,
          isDense: true,
          dropdownColor: StatsStyle.surfaceRaised,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: [
            for (final MapEntry(:key, :value) in options.entries)
              DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
    return Column(children: [
      row(
          'Sonido de alarma',
          pick('settings-alarm-sound', alarms.sound, alarmSounds, (s) {
            alarms.setSound(s);
            ref.read(soundPlayerProvider).play(s);
          })),
      row(
          'Posponer',
          pick(
              'settings-alarm-snooze',
              alarms.snoozeMinutes,
              {for (final m in snoozeChoices) m: '$m min'},
              alarms.setSnoozeMinutes)),
      row(
          'Avisarme antes',
          pick(
              'settings-alarm-lead',
              alarms.leadMinutes,
              {for (final m in leadChoices) m: m == 0 ? 'No' : '$m min antes'},
              alarms.setLeadMinutes)),
    ]);
  }
}
