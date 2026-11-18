import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/alarm.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/desktop/sounds.dart';

void main() {
  // Martes 17 de noviembre de 2026, 9 p. m.
  final now = DateTime(2026, 11, 17, 21);

  group('notas', () {
    test('las de todo el día avisan ese día a las 8', () async {
      final store = CalendarStore();
      final n = (await store.add('Cumpleaños', DateTime(2026, 11, 20),
          color: 4, now: now))!;
      expect((n.allDay, n.at, n.timeLabel),
          (true, DateTime(2026, 11, 20, 8), 'Todo el día'));
      expect(await store.takeDue(DateTime(2026, 11, 20, 7, 59)), isEmpty);
      expect((await store.takeDue(DateTime(2026, 11, 20, 8))).single.text,
          'Cumpleaños');
      expect(await store.takeDue(DateTime(2026, 11, 20, 9)), isEmpty,
          reason: 'avisa una sola vez');
      expect(store.notes.single.notified, isTrue,
          reason: 'queda en el calendario');
    });

    test('si abres el Mac otro día, no avisa de lo que ya pasó', () async {
      final store = CalendarStore();
      await store.add('Ayer', DateTime(2026, 11, 18), now: now);
      expect(await store.takeDue(DateTime(2026, 11, 19, 10)), isEmpty);
    });

    test('abierto más tarde ese día, avisa igual', () async {
      final store = CalendarStore();
      await store.add('Entrega', DateTime(2026, 11, 18), now: now);
      expect((await store.takeDue(DateTime(2026, 11, 18, 15))).single.text,
          'Entrega');
    });

    test('una alarma muy atrasada llega como aviso', () async {
      final store = CalendarStore();
      await store.add('Clase', DateTime(2026, 11, 18),
          hour: 9, alarm: true, now: now);
      final due = await store.takeDue(DateTime(2026, 11, 18, 11));
      expect(due.single.alarm, isFalse);
    });

    test('lo anotado para hoy con la hora pasada no avisa', () async {
      final store = CalendarStore();
      final n = await store.add('Hoy', DateTime(2026, 11, 17), now: now);
      expect(n!.notified, isTrue);
    });

    test('se guarda y se lee', () {
      final n = CalendarNote(
          id: '1',
          text: 'Dentista',
          day: DateTime(2026, 12, 3),
          hour: 15,
          minute: 30,
          alarm: true,
          color: 3,
          macId: 'abc');
      final back = CalendarNote.fromJson(n.toJson());
      expect((back.text, back.at, back.alarm, back.color, back.macId),
          ('Dentista', DateTime(2026, 12, 3, 15, 30), true, 3, 'abc'));
    });

    test('el aviso: suenan las alarmas y lo demás se avisa', () async {
      final store = CalendarStore();
      final alarms = AlarmController(PersonalStore(), NoopSoundPlayer(),
          every: const Duration(hours: 1));
      addTearDown(alarms.dispose);
      await store.add('Cumple', DateTime(2026, 11, 18), now: now);
      await store.add('Reunión', DateTime(2026, 11, 18),
          hour: 8, alarm: true, now: now);
      final t = DateTime(2026, 11, 18, 8);
      final scheduler = CalendarScheduler(store, alarms,
          now: () => t, every: const Duration(hours: 1));
      addTearDown(scheduler.dispose);
      await scheduler.check();
      expect(alarms.state.text, 'Reunión');
      expect(scheduler.debugState!.message, '⏰ ¡Recuerda: hoy es «Cumple»!');
    });

    test('se copia al Calendario del Mac y se borra de los dos', () async {
      final store = CalendarStore();
      final mac = FakeMacActions();
      final n = (await store.add('Cumple', DateTime(2026, 11, 20)))!;
      expect(await copyToMacCalendar(store, mac, n), isNull);
      expect(mac.calendar.single.allDay, isTrue);
      final saved = store.notes.single;
      expect(saved.macId, mac.calendar.single.id);
      await removeNote(store, mac, saved);
      expect(store.notes, isEmpty);
      expect(mac.calendar, isEmpty);
    });

    test('sin permiso para el Calendario del Mac, lo dice', () async {
      final store = CalendarStore();
      final mac = FakeMacActions(calendarAllowed: false);
      final n = (await store.add('Cumple', DateTime(2026, 11, 20)))!;
      expect(await copyToMacCalendar(store, mac, n), calendarDeniedMessage);
      expect(store.notes.single.macId, isNull);
    });

    test('describeDay', () {
      expect(describeDay(DateTime(2026, 11, 17), now), 'hoy');
      expect(describeDay(DateTime(2026, 11, 18), now), 'mañana');
      expect(describeDay(DateTime(2026, 11, 20), now),
          'el viernes 20 de noviembre');
    });
  });

  group('por chat', () {
    ParsedCommand? p(String s) => parseCommand(s, now);

    void expectNote(String phrase, String text, DateTime when,
        {bool allDay = true, bool alarm = false}) {
      final c = p(phrase);
      expect(c?.intent, AssistantIntent.calendarNote, reason: phrase);
      expect((c!.text, c.when, c.allDay, c.play), (text, when, allDay, alarm),
          reason: phrase);
    }

    test('frases', () {
      expectNote('anota en mi calendario el viernes cumpleaños de mamá',
          'Cumpleaños de mamá', DateTime(2026, 11, 20));
      expectNote('Apunta en el calendario el 25 de diciembre Navidad',
          'Navidad', DateTime(2026, 12, 25));
      expectNote('anota en mi calendario examen de cálculo el 3 de diciembre',
          'Examen de cálculo', DateTime(2026, 12, 3));
      expectNote('anótame en el calendario mañana a las 3 dentista', 'Dentista',
          DateTime(2026, 11, 18, 15),
          allDay: false);
      expectNote('pon en mi calendario que el 20 tengo entrega del proyecto',
          'Entrega del proyecto', DateTime(2026, 11, 20));
      expectNote('anota en mi calendario el 5 pagar la luz', 'Pagar la luz',
          DateTime(2026, 12, 5));
      expectNote(
          'agrega al calendario reunión con Ana el lunes a las 9 de la mañana con alarma',
          'Reunión con Ana',
          DateTime(2026, 11, 23, 9),
          allDay: false,
          alarm: true);
      expectNote('anota en el calendario 24/12 cena familiar', 'Cena familiar',
          DateTime(2026, 12, 24));
    });

    test('sin día, pregunta', () async {
      final c = p('anota en mi calendario comprar regalo')!;
      expect((c.intent, c.when), (AssistantIntent.calendarNote, null));
      final ex = AssistantExecutor(PersonalStore(), FakeMacActions(),
          calendar: CalendarStore(), now: () => now);
      expect(await ex.run(c), startsWith('📅 ¿Para qué día anoto'));
    });

    test('ver la agenda sigue funcionando', () {
      expect(p('qué hay en mi calendario')?.intent, AssistantIntent.showAgenda);
    });

    test('el asistente lo anota (y en el Mac si está activado)', () async {
      final notes = CalendarStore();
      await notes.setToMac(true);
      final mac = FakeMacActions();
      final ex = AssistantExecutor(PersonalStore(), mac,
          calendar: notes, now: () => now);
      final reply = await ex
          .run(p('anota en mi calendario el viernes cumpleaños de mamá')!);
      expect(
          reply,
          '📅 Anotado en tu calendario: «Cumpleaños de mamá» el viernes 20 de '
          'noviembre (todo el día; ese día te aviso a las 8:00 a. m.). '
          'También está en el Calendario del Mac.');
      expect(notes.notes.single.color, 1);
      expect(mac.calendar.single.title, 'Cumpleaños de mamá');
    });
  });
}
