import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/alarm.dart';
import 'package:pixelmate/application/assistant/alarm_settings.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/daily_tasks.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/desktop/sounds.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('los ajustes se guardan y solo aceptan opciones válidas', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = AlarmSettings(prefs);
    expect((s.sound, s.snoozeMinutes, s.leadMinutes), (PetSound.alarm, 5, 0));
    await s.setSound(PetSound.alarmBell);
    await s.setSnoozeMinutes(10);
    await s.setLeadMinutes(15);
    await s.setLeadMinutes(7); // no es una opción: se queda en 15
    await s.setSound(PetSound.focus); // no es de alarma
    final again = AlarmSettings(prefs);
    expect((again.sound, again.snoozeMinutes, again.leadMinutes),
        (PetSound.alarmBell, 10, 15));
  });

  test('la alarma suena con el sonido elegido y pospone lo elegido', () async {
    final store = PersonalStore();
    final sound = NoopSoundPlayer();
    final alarms = AlarmController(store, sound,
        soundFor: () => PetSound.alarmSoft,
        snoozeMinutes: () => 15,
        now: () => DateTime(2026, 11, 18, 8),
        every: const Duration(hours: 1));
    addTearDown(alarms.dispose);
    alarms.ring(
        [ReminderItem('1', 'Reunión', DateTime(2026, 11, 18, 8), alarm: true)]);
    await Future<void>.delayed(Duration.zero);
    expect(sound.played, [PetSound.alarmSoft]);
    await alarms.snooze();
    expect(store.alarms.single.due, DateTime(2026, 11, 18, 8, 15));
  });

  test('avisa unos minutos antes, una sola vez', () async {
    final notes = CalendarStore();
    await notes.add('Dentista', DateTime(2026, 11, 18), hour: 15, minute: 30);
    // Todo el día (ya avisó a las 8): no cuenta para el aviso previo.
    await notes.add('Cumple', DateTime(2026, 11, 18),
        now: DateTime(2026, 11, 18, 15));
    final daily = DailyTaskStore();
    await daily.add('Tomar agua', 15, 35);
    var now = DateTime(2026, 11, 18, 15, 10);
    final alarms = AlarmController(PersonalStore(), NoopSoundPlayer(),
        every: const Duration(hours: 1));
    addTearDown(alarms.dispose);
    final s = CalendarScheduler(notes, alarms,
        now: () => now,
        every: const Duration(hours: 1),
        daily: daily,
        leadMinutes: () => 10);
    addTearDown(s.dispose);
    await s.check();
    expect(s.state, isNull, reason: 'aún faltan 20 minutos');
    now = DateTime(2026, 11, 18, 15, 22);
    await s.check();
    expect(
        s.state!.items.map((i) => i.text), ['en 8 min: Dentista (3:30 p. m.)']);
    now = DateTime(2026, 11, 18, 15, 26);
    await s.check();
    expect(s.state!.items.map((i) => i.text),
        ['en 9 min: Tomar agua (3:35 p. m.)']);
    final before = s.state;
    now = DateTime(2026, 11, 18, 15, 27);
    await s.check();
    expect(identical(s.state, before), isTrue, reason: 'no repite');
  });
}
