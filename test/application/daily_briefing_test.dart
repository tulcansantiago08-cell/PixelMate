import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/daily_briefing.dart';
import 'package:pixelmate/application/assistant/daily_tasks.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Miércoles 18 de noviembre de 2026.
  final day = DateTime(2026, 11, 18);

  Future<(CalendarStore, DailyTaskStore, PersonalStore)> stores() async {
    final notes = CalendarStore();
    await notes.add('Cumple de Ana', day, color: 4);
    await notes.add('Dentista', day, hour: 15, minute: 30, alarm: true);
    await notes.add('Otro día', DateTime(2026, 11, 19));
    await notes.addRecord('rem-1', 'Ya avisó', DateTime(2026, 11, 18, 7));
    final daily = DailyTaskStore();
    await daily.add('Tomar agua', 10, 0);
    await daily.add('Gimnasio', 7, 0, days: {6, 7});
    final personal = PersonalStore();
    await personal.addReminder('Llamar a mamá', DateTime(2026, 11, 18, 18));
    await personal.addTask('Estudiar');
    return (notes, daily, personal);
  }

  test('la agenda junta todo, por hora', () async {
    final (notes, daily, personal) = await stores();
    final items = agendaFor(day,
        notes: notes,
        daily: daily,
        reminders: personal.reminders,
        macEvents: [
          CalendarEvent(
              'Reunión', DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 10),
              id: 'm1'),
        ]);
    expect(items.map((i) => i.toString()), [
      'Todo el día Cumple de Ana',
      '9:00 a. m. Reunión',
      '10:00 a. m. Tomar agua (diaria)',
      '3:30 p. m. Dentista 🔔',
      '6:00 p. m. Llamar a mamá',
    ]);
  });

  test('el mensaje', () {
    expect(
        briefingMessage(
            userName: 'Santi',
            items: const [AgendaItem('9:00 a. m.', 'Reunión', 540)],
            pending: 2),
        '☀️ ¡Buenos días, Santi! Hoy tienes:\n• 9:00 a. m. · Reunión\n'
        '📝 Tienes 2 tareas pendientes.');
    expect(briefingMessage(items: const []),
        '☀️ ¡Buenos días! Hoy no tienes nada anotado. ¿Qué te gustaría lograr?');
  });

  test('una vez al día, desde las 6 y si está activado', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 18, 5, 30);
    var on = true;
    final c = BriefingController(prefs,
        enabled: () => on,
        compose: (_) async => 'Hola',
        now: () => now,
        every: const Duration(hours: 1));
    addTearDown(c.dispose);
    expect(await c.check(), isFalse, reason: 'antes de las 6');
    now = DateTime(2026, 11, 18, 7);
    expect(await c.check(), isTrue);
    expect(c.state, 'Hola');
    expect(await c.check(), isFalse, reason: 'ya lo dio hoy');
    now = DateTime(2026, 11, 19, 8);
    on = false;
    expect(await c.check(), isFalse, reason: 'desactivado');
    on = true;
    expect(await c.check(), isTrue);
  });

  test('«¿qué tengo hoy?» muestra toda la agenda', () async {
    final (notes, daily, personal) = await stores();
    final ex = AssistantExecutor(personal, FakeMacActions(),
        calendar: notes, daily: daily, now: () => DateTime(2026, 11, 18, 8));
    final reply = await ex.run(parseCommand('qué tengo hoy', day)!);
    expect(reply, startsWith('📅 Hoy:\n• Todo el día · Cumple de Ana'));
    expect(reply, contains('• 6:00 p. m. · Llamar a mamá'));
  });
}
