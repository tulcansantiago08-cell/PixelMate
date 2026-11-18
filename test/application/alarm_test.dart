import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/alarm.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/daily_tasks.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/desktop/sounds.dart';
import 'package:pixelmate/presentation/assistant/alarm_card.dart';
import 'package:pixelmate/presentation/assistant/calendar_tab.dart';
import 'package:pixelmate/presentation/assistant/daily_tasks_panel.dart';

void main() {
  // Martes 17 de noviembre de 2026, 22:00.
  final now = DateTime(2026, 11, 17, 22);
  ParsedCommand? p(String text) => parseCommand(text, now, petName: 'James');

  group('poner alarmas', () {
    for (final (text, what, at, repeat) in [
      (
        'Pon una alarma a las 8 am reunión virtual',
        'reunión virtual',
        DateTime(2026, 11, 18, 8),
        null
      ),
      (
        'Alarma a las 8 reunión virtual',
        'reunión virtual',
        DateTime(2026, 11, 18, 8),
        null
      ),
      (
        'Oye James, ponme una alarma mañana a las 8 de la mañana para la '
            'reunión virtual.',
        'reunión virtual',
        DateTime(2026, 11, 18, 8),
        null
      ),
      (
        'Despiértame a las 6:30',
        '¡Hora de levantarse! ☀️',
        DateTime(2026, 11, 18, 6, 30),
        null
      ),
      (
        'Alarma todos los días a las 7 tomar la pastilla',
        'tomar la pastilla',
        DateTime(2026, 11, 18, 7),
        'daily'
      ),
      (
        'Pon una alarma de lunes a viernes a las 7 am gimnasio',
        'gimnasio',
        DateTime(2026, 11, 18, 7),
        'weekdays'
      ),
      (
        'Recuérdame a las 9 con alarma llamar a mamá',
        'llamar a mamá',
        DateTime(2026, 11, 18, 9),
        null
      ),
      (
        'Pon una alarma en 10 minutos',
        'Alarma',
        DateTime(2026, 11, 17, 22, 10),
        null
      ),
    ]) {
      test(text, () {
        final c = p(text)!;
        expect(c.intent, AssistantIntent.alarm);
        expect(c.text, what);
        expect(c.when, at);
        expect(c.repeat, repeat);
      });
    }

    test('como lo dices de verdad', () {
      final evening = DateTime(2026, 11, 17, 20, 20);
      var c = parseCommand(
          'Dame una alarma a las 8 y 28 pm de hoy que se llame hacer aseo',
          evening)!;
      expect((
        c.intent,
        c.text,
        c.when
      ), (
        AssistantIntent.alarm,
        'hacer aseo',
        DateTime(2026, 11, 17, 20, 28)
      ));
      c = parseCommand(
          'A las 9 y 19 am dame una alarma para tomar la pastilla', evening)!;
      expect((
        c.intent,
        c.text,
        c.when
      ), (
        AssistantIntent.alarm,
        'tomar la pastilla',
        DateTime(2026, 11, 18, 9, 19)
      ));
      c = parseCommand(
          'Hazme una alarma a las 7:45 llamada gimnasio', evening)!;
      expect((c.text, c.when), ('gimnasio', DateTime(2026, 11, 18, 7, 45)));
      expect(
          parseWhen('a las 9 y 20 am', evening), DateTime(2026, 11, 18, 9, 20));
    });

    test('sin mañana ni tarde, la hora más próxima', () {
      final morning = DateTime(2026, 11, 17, 10);
      expect(parseCommand('Alarma a las 3 llamar', morning)?.when,
          DateTime(2026, 11, 17, 15));
      expect(parseCommand('Alarma a las 11 café', morning)?.when,
          DateTime(2026, 11, 17, 11));
    });

    test('apagar, posponer y borrar', () {
      expect(p('Apaga la alarma')?.intent, AssistantIntent.alarmStop);
      expect(p('Apágala')?.intent, AssistantIntent.alarmStop);
      expect(p('Pospón 10 minutos')?.number, 10);
      expect(p('5 minutos más')?.intent, AssistantIntent.alarmSnooze);
      expect(p('Pospón la alarma')?.number, isNull);
      expect(p('Quita la alarma de las 8')?.number, 800);
      expect(p('Borra la alarma de la reunión')?.intent,
          AssistantIntent.alarmDelete);
      expect(p('Ya'), isNull, reason: 'una charla no apaga nada');
    });
  });

  group('repetición', () {
    test('diaria y de lunes a viernes', () async {
      final store = PersonalStore();
      await store.addReminder('pastilla', DateTime(2026, 11, 18, 7),
          alarm: true, repeat: AlarmRepeat.daily);
      await store.addReminder('gym', DateTime(2026, 11, 20, 7), // viernes
          alarm: true,
          repeat: AlarmRepeat.weekdays);
      final due = await store.takeDue(DateTime(2026, 11, 20, 7, 1));
      expect(due.map((r) => r.text), ['pastilla', 'gym']);
      final next = {for (final r in store.alarms) r.text: r.due};
      expect(next['pastilla'], DateTime(2026, 11, 21, 7));
      expect(next['gym'], DateTime(2026, 11, 23, 7), reason: 'lunes');
    });

    test('se guarda y se carga', () {
      final r = ReminderItem('1', 'x', DateTime(2026, 1, 1, 8),
          alarm: true, repeat: AlarmRepeat.weekdays);
      final back = ReminderItem.fromJson(r.toJson());
      expect(back.alarm, isTrue);
      expect(back.repeat, AlarmRepeat.weekdays);
      expect(
          ReminderItem.fromJson(ReminderItem('2', 'y', DateTime(2026)).toJson())
              .alarm,
          isFalse);
    });
  });

  group('al sonar', () {
    late PersonalStore store;
    late NoopSoundPlayer sound;
    late List<String> spoken;
    late AlarmController alarms;
    final item = ReminderItem('1', 'Reunión virtual', DateTime(2026, 11, 18, 8),
        alarm: true);

    setUp(() {
      store = PersonalStore();
      sound = NoopSoundPlayer();
      spoken = [];
      alarms = AlarmController(store, sound,
          speak: spoken.add,
          now: () => DateTime(2026, 11, 18, 8),
          every: const Duration(milliseconds: 20),
          maxRing: const Duration(milliseconds: 200));
    });
    tearDown(() => alarms.dispose());

    test('suena hasta apagarla y lo dice', () async {
      alarms.ring([item]);
      expect(alarms.state.active, isTrue);
      expect(spoken.single, 'Son las 8:00. Reunión virtual.');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(sound.played.where((s) => s == PetSound.alarm).length,
          greaterThan(2));
      expect(await alarms.stop(), isTrue);
      final count = sound.played.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sound.played.length, count, reason: 'ya no suena');
      expect(await alarms.stop(), isFalse);
    });

    test('se calla sola si nadie la apaga', () async {
      alarms.ring([item]);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(alarms.state.active, isFalse);
    });

    test('una alarma nueva suena su tiempo completo', () async {
      alarms.ring([item]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      alarms.ring([
        ReminderItem('2', 'Tomar agua', DateTime(2026, 11, 18, 8), alarm: true)
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(alarms.state.active, isTrue, reason: 'la segunda acaba de entrar');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(alarms.state.active, isFalse);
    });

    test('una alarma muy atrasada llega como aviso, sin sonar', () async {
      await store.addReminder('Reunión', DateTime(2026, 11, 18, 8),
          alarm: true);
      await store.addReminder('Clase', DateTime(2026, 11, 18, 10), alarm: true);
      final due = await store.takeDue(DateTime(2026, 11, 18, 10, 5));
      expect([for (final r in due) (r.text, r.alarm)],
          [('Reunión', false), ('Clase', true)]);
    });

    test('posponer la vuelve a programar', () async {
      alarms.ring([item]);
      expect(await alarms.snooze(10), isTrue);
      expect(alarms.state.active, isFalse);
      expect(store.alarms.single.due, DateTime(2026, 11, 18, 8, 10));
    });
  });

  group('ejecutor', () {
    late PersonalStore store;
    late AssistantExecutor run;
    int? lastAction = -1;
    bool ringing = false;

    setUp(() {
      store = PersonalStore();
      ringing = false;
      run = AssistantExecutor(store, FakeMacActions(),
          now: () => now,
          onAlarm: (minutes) async {
            lastAction = minutes;
            final was = ringing;
            ringing = false;
            return was;
          });
    });

    test('pone, lista y borra alarmas', () async {
      expect(
          await run.run(p('Pon una alarma a las 8 am reunión virtual')!),
          '⏰ Alarma puesta mañana a las 8:00: «reunión virtual». Sonará hasta '
          'que la apagues.');
      expect(
          await run.run(p('Alarma todos los días a las 7 tomar la pastilla')!),
          contains('y luego todos los días'));
      expect(await run.run(p('¿Qué tengo pendiente?')!),
          contains('🔔 mañana a las 7:00 (todos los días): tomar la pastilla'));
      expect(await run.run(p('Quita la alarma de las 8')!),
          contains('¿Quito la alarma'));
      expect(await run.confirm(true), contains('Quité la alarma'));
      expect(store.alarms.single.text, 'tomar la pastilla');
      await run.run(p('Borra la alarma de la pastilla')!);
      expect(await run.confirm(true), contains('Quité'));
      expect(store.alarms, isEmpty);
    });

    test('sin hora, la pregunta', () async {
      expect(await run.run(p('Pon una alarma')!), contains('¿A qué hora'));
    });

    test('apagar y posponer la que suena', () async {
      expect(await run.run(p('Apaga la alarma')!), contains('No hay'));
      ringing = true;
      expect(await run.run(p('Apaga la alarma')!), '🔕 Alarma apagada.');
      expect(lastAction, isNull);
      ringing = true;
      expect(await run.run(p('Pospón 10 minutos')!), contains('10 minutos'));
      expect(lastAction, 10);
      ringing = true;
      expect(await run.run(p('Silencia')!), '🔕 Alarma apagada.');
    });
  });

  group('tareas diarias', () {
    test('el revisor sigue vivo después de añadir tareas', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = container.read(dailyTaskSchedulerProvider);
      await container.read(dailyTaskStoreProvider).add('Agua', 8, 0);
      await Future<void>.delayed(Duration.zero);
      expect(
          identical(container.read(dailyTaskSchedulerProvider), first), isTrue);
    });

    test('la del minuto actual suena hoy', () async {
      final store = DailyTaskStore();
      final now = DateTime(2026, 11, 18, 9, 50, 20);
      final t = await store.add('Probar', 9, 50, now: now);
      expect(t!.rangOn, isNull);
      expect((await store.takeDue(now)).single.text, 'Probar');
      final old = await store.add('Antes', 9, 49, now: now);
      expect(old!.rangOn, dayKey(now));
    });

    test('suenan a su hora, una vez al día, y no tarde', () async {
      final store = DailyTaskStore();
      final reunion = (await store.add('Reunión virtual', 8, 0,
          days: weekdays, now: DateTime(2026, 11, 17, 7)))!;
      await store.add('Gimnasio', 18, 0, now: DateTime(2026, 11, 17, 7));
      // Antes de la hora: nada.
      expect(await store.takeDue(DateTime(2026, 11, 17, 7, 59)), isEmpty);
      // A su hora: suena una vez.
      final due = await store.takeDue(DateTime(2026, 11, 17, 8, 0, 10));
      expect(due.map((t) => t.text), ['Reunión virtual']);
      expect(await store.takeDue(DateTime(2026, 11, 17, 8, 1)), isEmpty);
      // Hecha hoy: se tacha y al día siguiente vuelve a tocar.
      await store.setDone(reunion.id, true, DateTime(2026, 11, 17, 8, 5));
      expect(store.byId(reunion.id)!.doneToday(DateTime(2026, 11, 17, 12)),
          isTrue);
      expect(store.byId(reunion.id)!.doneToday(DateTime(2026, 11, 18, 7)),
          isFalse);
      expect((await store.takeDue(DateTime(2026, 11, 18, 8))).single.text,
          'Reunión virtual');
      // Sábado: no es de lunes a viernes.
      expect(await store.takeDue(DateTime(2026, 11, 21, 8)), isEmpty);
      // Si abres el Mac dos horas después, no suena tarde.
      expect(await store.takeDue(DateTime(2026, 11, 17, 20, 30)), isEmpty);
    });

    test('añadida después de su hora, empieza mañana', () async {
      final store = DailyTaskStore();
      await store.add('Agua', 9, 0, now: DateTime(2026, 11, 17, 10));
      expect(await store.takeDue(DateTime(2026, 11, 17, 10, 1)), isEmpty);
      expect(await store.takeDue(DateTime(2026, 11, 18, 9, 1)), hasLength(1));
    });

    test('se guarda y se carga; etiquetas de días', () {
      const t =
          DailyTask(id: '1', text: 'x', hour: 7, minute: 5, days: {1, 3, 5});
      final back = DailyTask.fromJson(t.toJson());
      expect(back.days, {1, 3, 5});
      expect(back.time, '07:05');
      expect(back.daysLabel, 'L X V');
      expect(back.time12, '7:05 a. m.');
      expect(clock12(21, 10), '9:10 p. m.');
      expect(clock12(0, 30), '12:30 a. m.');
      expect(clock12(12, 0), '12:00 p. m.');
      expect(
          const DailyTask(
                  id: '2', text: 'y', hour: 1, minute: 0, days: weekdays)
              .daysLabel,
          'De lunes a viernes');
    });

    test('el programador hace sonar la alarma', () async {
      final store = DailyTaskStore();
      await store.add('Reunión', 8, 0, now: DateTime(2026, 11, 17, 7));
      final alarms = AlarmController(PersonalStore(), NoopSoundPlayer(),
          every: const Duration(hours: 1));
      final scheduler = DailyTaskScheduler(store, alarms,
          now: () => DateTime(2026, 11, 17, 8, 0, 20),
          every: const Duration(hours: 1));
      await scheduler.check();
      expect(alarms.state.ringing.single.id, startsWith('daily-'));
      scheduler.dispose();
      alarms.dispose();
    });

    test('por chat: «tarea diaria…» y las alarmas que se repiten', () async {
      final store = DailyTaskStore();
      final run = AssistantExecutor(PersonalStore(), FakeMacActions(),
          daily: store, now: () => now);
      final c = p('Agrega una tarea diaria a las 8 am reunión virtual')!;
      expect((c.intent, c.text, c.repeat),
          (AssistantIntent.alarm, 'reunión virtual', 'daily'));
      expect(await run.run(c), contains('Tarea diaria guardada'));
      await run.run(p('Alarma de lunes a viernes a las 7 am gimnasio')!);
      expect(store.tasks.map((t) => (t.time, t.text, t.daysLabel)), [
        ('07:00', 'gimnasio', 'De lunes a viernes'),
        ('08:00', 'reunión virtual', 'Todos los días'),
      ]);
    });
  });

  testWidgets('la tarjeta apaga y pospone', (tester) async {
    final store = PersonalStore();
    final container = ProviderContainer(overrides: [
      personalStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    container.read(alarmProvider.notifier).ring([
      ReminderItem('1', 'Reunión virtual', DateTime(2026, 11, 18, 8),
          alarm: true)
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AlarmCard())),
    ));
    expect(find.text('8:00'), findsOneWidget);
    expect(find.text('Reunión virtual'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alarm-snooze')));
    await tester.pump();
    expect(container.read(alarmProvider).active, isFalse);
    expect(store.alarms.single.text, 'Reunión virtual');
    container.read(alarmProvider.notifier).ring([store.alarms.single]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm-stop')));
    await tester.pump();
    expect(container.read(alarmProvider).active, isFalse);
  });

  testWidgets('panel de tareas diarias: añadir, tachar y probar sonido',
      (tester) async {
    final store = DailyTaskStore();
    final container = ProviderContainer(overrides: [
      dailyTaskStoreProvider.overrideWith((_) => store),
    ]);
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(284, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: DailyTasksPanel(onClose: () {}))),
    ));
    expect(find.textContaining('Aún no tienes tareas diarias'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('daily-text')), 'Reunión virtual');
    // Minutos escritos: 8:53.
    await tester.enterText(find.byKey(const ValueKey('daily-minute')), '53');
    // Solo de lunes a viernes.
    await tester.tap(find.text('L a V'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('daily-save')));
    await tester.pumpAndSettle();
    final task = store.tasks.single;
    expect((task.text, task.time, task.daysLabel),
        ('Reunión virtual', '08:53', 'De lunes a viernes'));
    expect(find.text('Reunión virtual'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('daily-bell-${task.id}')));
    await tester.pump();
    expect(store.byId(task.id)!.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('daily-test-sound')));
    await tester.pump();
    expect(container.read(alarmProvider).active, isTrue);
    await container.read(alarmProvider.notifier).stop();
  });

  testWidgets('calendario: anotar con hora, alarma y color', (tester) async {
    final notes = CalendarStore();
    final container = ProviderContainer(overrides: [
      personalStoreProvider.overrideWithValue(PersonalStore()),
      dailyTaskStoreProvider.overrideWith((_) => DailyTaskStore()),
      calendarStoreProvider.overrideWith((_) => notes),
    ]);
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(284, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(body: CalendarTab(today: DateTime(2026, 11, 17, 21)))),
    ));
    expect(find.text('Noviembre 2026'), findsOneWidget);
    expect(find.text('Martes 17 de noviembre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-day-20')));
    await tester.pump();
    expect(find.text('Viernes 20 de noviembre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cal-text')), 'Entrega profe Mideros');
    await tester.tap(find.byKey(const ValueKey('cal-color-2'))); // verde
    await tester.ensureVisible(find.byKey(const ValueKey('cal-allday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cal-allday')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cal-minute')));
    await tester.enterText(find.byKey(const ValueKey('cal-minute')), '50');
    await tester.ensureVisible(find.byKey(const ValueKey('cal-alarm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cal-alarm')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('cal-save')));
    await tester.tap(find.byKey(const ValueKey('cal-save')));
    await tester.pumpAndSettle();
    final n = notes.notes.single;
    expect((n.text, n.at, n.alarm, n.color),
        ('Entrega profe Mideros', DateTime(2026, 11, 20, 9, 50), true, 2));
    expect(find.text('9:50 a. m.'), findsOneWidget);

    // Una de todo el día.
    await tester.tap(find.byKey(const ValueKey('cal-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cal-text')), 'Cumpleaños de mamá');
    await tester.ensureVisible(find.byKey(const ValueKey('cal-save')));
    await tester.tap(find.byKey(const ValueKey('cal-save')));
    await tester.pumpAndSettle();
    expect(notes.onDay(DateTime(2026, 11, 20)).first.allDay, isTrue);
    expect(find.text('Todo el día'), findsOneWidget);

    // Escribir directo al elegir un día: nota de todo el día, rosa.
    await tester.tap(find.byKey(const ValueKey('cal-day-25')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cal-color-4')));
    await tester.enterText(
        find.byKey(const ValueKey('cal-quick')), 'Pagar la luz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final quick = notes.onDay(DateTime(2026, 11, 25)).single;
    expect((quick.text, quick.allDay, quick.color), ('Pagar la luz', true, 4));
    expect(find.text('Pagar la luz'), findsOneWidget);

    // Tocar una nota la abre para cambiarla.
    await tester.tap(find.text('Pagar la luz'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar la nota'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('cal-text')), 'Pagar la luz y el agua');
    await tester.ensureVisible(find.byKey(const ValueKey('cal-repeat-yearly')));
    await tester.tap(find.byKey(const ValueKey('cal-repeat-yearly')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('cal-save')));
    await tester.tap(find.byKey(const ValueKey('cal-save')));
    await tester.pumpAndSettle();
    final edited = notes.byId(quick.id)!;
    expect((edited.text, edited.repeat),
        ('Pagar la luz y el agua', NoteRepeat.yearly));

    // Un día que ya pasó no deja anotar.
    await tester.tap(find.byKey(const ValueKey('cal-day-10')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cal-add')), findsNothing);
    expect(find.byKey(const ValueKey('cal-quick')), findsNothing);

    // Mes siguiente.
    await tester.tap(find.byKey(const ValueKey('cal-next')));
    await tester.pump();
    expect(find.text('Diciembre 2026'), findsOneWidget);
  });
}
