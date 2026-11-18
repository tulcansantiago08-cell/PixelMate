import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mascot/mascot_settings.dart';
import '../mascot/music.dart';

import 'alarm.dart';
import 'alarm_settings.dart';
import 'calendar_notes.dart';
import 'assistant_executor.dart';
import 'daily_tasks.dart';
import 'code_writer.dart';
import 'mac_actions.dart';
import 'personal_store.dart';
import 'video_finder.dart';

/// Avisa los recordatorios a su hora. Los que vencieron con la app cerrada
/// se avisan al abrirla. El estado es el último aviso (un objeto nuevo cada
/// vez, para que quien escucha reaccione).
class ReminderController extends StateNotifier<ReminderAlert?> {
  final PersonalStore _store;
  final DateTime Function() _now;
  Timer? _timer;

  /// Lo que ya avisó (para que quede en el calendario).
  final Future<void> Function(List<ReminderItem> items)? onFired;

  ReminderController(this._store,
      {DateTime Function()? now,
      Duration every = const Duration(seconds: 5),
      this.onFired})
      : _now = now ?? DateTime.now,
        super(null) {
    _timer = Timer.periodic(every, (_) => check());
    scheduleMicrotask(check);
  }

  Future<void> check() async {
    final now = _now();
    final due = await _store.takeDue(now);
    if (due.isEmpty || !mounted) return;
    state = ReminderAlert(due, now);
    await onFired?.call(due);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ReminderAlert {
  final List<ReminderItem> items;
  final DateTime at;
  const ReminderAlert(this.items, this.at);

  /// "⏰ ¡Recuerda: llamar a mamá!" (y si llegaron tarde, desde cuándo).
  String get message {
    String one(ReminderItem r) {
      final late = at.difference(r.due) > const Duration(minutes: 2);
      return late ? '${r.text} (era para ${describeWhen(r.due, at)})' : r.text;
    }

    return items.length == 1
        ? '⏰ ¡Recuerda: ${one(items.single)}!'
        : '⏰ Recordatorios: ${items.map(one).join(' · ')}';
  }
}

final reminderProvider =
    StateNotifierProvider<ReminderController, ReminderAlert?>(
        (ref) => ReminderController(
              ref.watch(personalStoreProvider),
              // Los recordatorios no desaparecen: quedan en el calendario
              // (en gris), el día y la hora en que avisaron.
              onFired: (items) async {
                final calendar = ref.read(calendarStoreProvider);
                for (final r in items) {
                  if (r.repeat != AlarmRepeat.none) continue;
                  await calendar.addRecord('rem-${r.id}', r.text, r.due);
                }
              },
            ));

final assistantExecutorProvider = Provider<AssistantExecutor>((ref) =>
    AssistantExecutor(
        ref.watch(personalStoreProvider), ref.watch(macActionsProvider),
        videos: ref.watch(videoFinderProvider),
        coder: ref.watch(codeWriterProvider),
        daily: ref.read(dailyTaskStoreProvider),
        calendar: ref.read(calendarStoreProvider),
        snoozeMinutes: () => ref.read(alarmSettingsProvider).snoozeMinutes,
        onPlaying: (video) =>
            ref.read(musicProvider.notifier).playedByAssistant(video),
        onDance: (on) => on
            ? ref
                .read(musicProvider.notifier)
                .startDisco(AssistantExecutor.discoLength)
            : ref.read(musicProvider.notifier).stopDancing(),
        onUserName: (name) async {
          await ref.read(mascotSettingsProvider).setUserName(name);
        },
        onWakeWord: (on) async {
          final settings = ref.read(mascotSettingsProvider);
          await settings.setWakeWord(on);
          return settings.name;
        },
        onAlarm: (minutes) {
          final alarms = ref.read(alarmProvider.notifier);
          return minutes == null ? alarms.stop() : alarms.snooze(minutes);
        }));
