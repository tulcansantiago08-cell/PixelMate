import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/code_writer.dart';
import 'package:pixelmate/application/assistant/chat_controller.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/assistant/reminders.dart';
import 'package:pixelmate/application/assistant/video_finder.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/assistant/pending_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Martes 10 de noviembre de 2026, 7:55.
final t0 = DateTime(2026, 11, 10, 7, 55);

/// IA de prueba que siempre responde lo mismo.
class ScriptedAi extends ChatAssistant {
  AssistantReply next;
  int calls = 0;
  ScriptedAi(this.next);
  @override
  String get label => 'IA';
  @override
  bool get supportsImages => false;
  @override
  bool get supportsActions => true;
  @override
  bool get onDevice => true;
  @override
  Future<AssistantReply> reply(String message,
      {required String context, String? imageBase64}) async {
    calls++;
    return next;
  }

  @override
  Future<void> reset() async {}
}

void main() {
  group('ejecutor', () {
    late PersonalStore store;
    late FakeMacActions mac;
    late AssistantExecutor run;
    late FakeVideoFinder videos;
    late FakeCodeWriter coder;

    setUp(() {
      store = PersonalStore();
      mac = FakeMacActions(apps: {'Spotify', 'Calculadora'});
      videos = FakeVideoFinder({
        'Tití me preguntó': const FoundVideo(
            'Cr8K88UcO0s', 'Bad Bunny - Tití Me Preguntó (Video Oficial)'),
      });
      coder = FakeCodeWriter('def sumar(a, b):\n    return a + b\n');
      run = AssistantExecutor(store, mac,
          videos: videos, coder: coder, now: () => t0);
    });

    Future<String> say(String s) => run.run(parseCommand(s, t0)!);

    test('recordatorios: se guardan con su hora; sin hora se pregunta',
        () async {
      expect(await say('recuérdame en 20 minutos llamar a mamá'),
          '⏰ Listo: te recuerdo «llamar a mamá» hoy a las 8:15.');
      expect(await say('recuérdame mañana a las 9 tomar la pastilla'),
          contains('mañana a las 9:00'));
      expect(store.reminders.map((r) => r.text),
          ['llamar a mamá', 'tomar la pastilla']);
      expect(await say('recuérdame comprar pan'), contains('¿Para cuándo?'));
      expect(store.reminders, hasLength(2));
    });

    test('tareas: apuntar, ver, tachar', () async {
      expect(await say('apunta comprar leche'),
          '📝 Apunté «comprar leche». Tienes 1 tarea pendiente.');
      await say('añade a mis tareas pagar la luz');
      final list = await say('¿qué tengo pendiente?');
      expect(list, contains('1. comprar leche'));
      expect(list, contains('2. pagar la luz'));
      expect(await say('marca la 2 como hecha'),
          '✅ ¡Hecho! Taché «pagar la luz». Te quedan 1.');
      expect(await say('ya terminé la 5'), contains('No encuentro la tarea 5'));
      expect(await say('marca la 1 como hecha'),
          contains('¡No te queda nada pendiente!'));
      expect(
          await say('¿qué tengo pendiente?'), '🎉 No tienes nada pendiente.');
    });

    test('abrir: app instalada, web conocida o aviso', () async {
      expect(await say('abre spotify'), '🚀 Abrí Spotify.');
      expect(await say('abre youtube'), '🌐 Abrí youtube.com.');
      expect(await say('abre ejemplo.org'), '🌐 Abrí ejemplo.org.');
      expect(await say('abre la app Fantasma'),
          contains('No encontré «Fantasma»'));
      expect(mac.opened,
          ['Spotify', 'https://www.youtube.com', 'https://ejemplo.org']);
    });

    test('canciones y búsquedas en el navegador pedido', () async {
      expect(await say('abre una canción de Bad Bunny en YouTube en Brave'),
          '🎵 Abrí YouTube en Brave buscando «Bad Bunny». Elige la que quieras y dale ▶️.');
      expect(mac.opened.last,
          'https://www.youtube.com/results?search_query=Bad+Bunny @Brave');
      expect(await say('ábreme una canción en youtube en brave'),
          '🌐 Abrí youtube.com en Brave.');
      expect(await say('busca recetas de pasta en google'),
          '🔎 Abrí Google buscando «recetas de pasta».');
      expect(
          mac.opened.last, 'https://www.google.com/search?q=recetas+de+pasta');
      // Navegador que no está: avisa y usa el de siempre.
      expect(await say('pon Despacito en YouTube en Firefox'),
          startsWith('No encontré Firefox en tu Mac'));
      expect(mac.opened.last,
          'https://www.youtube.com/results?search_query=Despacito');
      // Spotify: en la app si está instalada.
      expect(await say('busca Shakira en spotify'),
          '🎵 Abrí Spotify buscando «Shakira».');
      expect(mac.opened.last, 'spotify:search:Shakira');
    });

    test('"reproduce" abre el primer video, ya sonando', () async {
      expect(await say('reproduce Tití me preguntó en Brave'),
          '▶️ Reproduciendo «Bad Bunny - Tití Me Preguntó (Video Oficial)» en Brave.');
      expect(mac.opened.last,
          'https://www.youtube.com/watch?v=Cr8K88UcO0s @Brave');
      // Si no encuentra el video, abre los resultados.
      expect(await say('reproduce canción inexistente xyz'),
          startsWith('🎵 Abrí YouTube buscando «inexistente xyz»'));
      // "abre … en YouTube" no busca el video: solo los resultados.
      await say('abre una canción de Bad Bunny en YouTube');
      expect(videos.asked, ['Tití me preguntó', 'inexistente xyz']);
      // Spotify: sin cuenta no hay play; se dice claramente.
      expect(await say('reproduce Shakira en spotify'),
          contains('Sin tu cuenta de Spotify no puedo darle play'));
    });

    test('código: lo escribe, lo guarda y lo abre en el editor', () async {
      expect(
          await say(
              'abre visual studio code y haz un script de python para sumar'),
          '💻 Escribí «sumar.py» (Python) y lo abrí en Visual Studio Code. '
          '¡Revísalo antes de ejecutarlo!');
      expect(coder.asked.single, 'python: sumar');
      expect(mac.saved['sumar.py'], contains('def sumar'));

      mac.cancelSave = true;
      expect(await say('haz un script de python para restar'),
          '💻 No guardé el script (cancelaste).');

      final noAi = AssistantExecutor(store, mac,
          coder: FakeCodeWriter(null), now: () => t0);
      expect(await noAi.run(parseCommand('haz un script para sumar', t0)!),
          contains('necesito la IA de Apple'));
    });

    test('calendario: agenda, crear y sin permiso', () async {
      expect(await say('¿qué tengo hoy en el calendario?'),
          '📅 Hoy no tienes eventos en el calendario.');
      final created = await say('crea una reunión con Ana mañana a las 10');
      expect(created, '📅 Creé «Reunión con Ana» mañana de 10:00 a 11:00.');
      expect(mac.calendar.single.start, DateTime(2026, 11, 11, 10));
      expect(await say('crea una reunión de equipo'), contains('¿Para cuándo'));

      mac.calendarAllowed = false;
      expect(await say('¿qué tengo hoy?'), contains('Privacidad y seguridad'));
    });

    test('describeWhen', () {
      expect(describeWhen(DateTime(2026, 11, 10, 17), t0), 'hoy a las 17:00');
      expect(
          describeWhen(DateTime(2026, 11, 11, 9, 5), t0), 'mañana a las 9:05');
      expect(describeWhen(DateTime(2026, 11, 13, 11), t0),
          'el viernes a las 11:00');
      expect(describeWhen(DateTime(2026, 11, 20, 10), t0),
          'el 20 nov a las 10:00');
    });
  });

  test('la IA aporta la orden si las reglas no la entienden', () {
    final c = commandFromAi(
      intent: AssistantIntent.createEvent,
      userText: 'oye, ponme una cita con el doctor mañana a las 10',
      detail: 'cita con el doctor',
      minutes: 0,
      time: '',
      day: 'mañana',
      number: 0,
      hours: 10,
      now: t0,
    );
    expect(c.text, 'Cita con el doctor');
    expect(c.when, DateTime(2026, 11, 11, 10),
        reason: 'la hora sale de la frase');
    final r = commandFromAi(
      intent: AssistantIntent.remind,
      userText: 'oye no me dejes olvidar el pan',
      detail: 'comprar pan',
      minutes: 0,
      time: '18:30',
      day: '',
      number: 0,
      hours: 0,
      now: t0,
    );
    expect(r.when, DateTime(2026, 11, 10, 18, 30), reason: 'hora de la IA');
  });

  group('recordatorios a su hora', () {
    test('avisa cuando toca (también los vencidos con la app cerrada)',
        () async {
      var now = t0;
      final store = PersonalStore();
      await store.addReminder(
          'llamar a mamá', t0.add(const Duration(minutes: 20)));
      await store.addReminder('vencido', t0.subtract(const Duration(hours: 1)));
      final c = ReminderController(store,
          now: () => now, every: const Duration(days: 1));
      addTearDown(c.dispose);
      await c.check();
      expect(c.state!.message, contains('vencido (era para hoy a las 6:55)'));
      expect(store.reminders.single.text, 'llamar a mamá');

      now = t0.add(const Duration(minutes: 20));
      await c.check();
      expect(c.state!.message, '⏰ ¡Recuerda: llamar a mamá!');
      expect(store.reminders, isEmpty);
    });

    test('se guardan entre aperturas', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PersonalStore(prefs).addTask('comprar leche');
      await PersonalStore(prefs).addReminder('x', t0);
      final again = PersonalStore(prefs);
      expect(again.pending.single.text, 'comprar leche');
      expect(again.reminders.single.text, 'x');
      expect(again.describe(), 'Tareas pendientes: 1) comprar leche.');
    });
  });

  group('en el chat', () {
    ProviderContainer make(
        ChatAssistant ai, FakeMacActions mac, PersonalStore store) {
      final c = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        mascotWindowProvider.overrideWithValue(NoopMascotWindow()),
        assistantChoiceProvider.overrideWith((_) async => AssistantChoice(ai)),
        personalStoreProvider.overrideWithValue(store),
        macActionsProvider.overrideWithValue(mac),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('las órdenes claras no pasan por la IA', () async {
      final ai = ScriptedAi(const AssistantReply('¡Hola!'));
      final store = PersonalStore();
      final c = make(ai, FakeMacActions(), store);
      await c.read(chatProvider.notifier).send('apunta comprar leche');
      expect(ai.calls, 0);
      expect(store.pending.single.text, 'comprar leche');
      final m = c.read(chatProvider);
      expect(m.last.isNote, isTrue);
      expect(m.last.text, contains('Apunté «comprar leche»'));
    });

    test('lo que no entienden las reglas lo decide la IA', () async {
      final ai = ScriptedAi(const AssistantReply('Ok',
          action: AssistantAction.addTask, detail: 'llamar al banco'));
      final store = PersonalStore();
      final c = make(ai, FakeMacActions(), store);
      await c
          .read(chatProvider.notifier)
          .send('oye, no se me puede olvidar: tarea de llamar al banco');
      expect(ai.calls, 1);
      expect(store.pending.single.text, 'llamar al banco');
      expect(c.read(chatProvider).last.text, contains('Apunté'),
          reason: 'se muestra lo que pasó, no la respuesta de la IA');
    });

    test('si la IA elige una acción sin que se pida, no se hace', () async {
      final ai = ScriptedAi(const AssistantReply('¡Muy bien, gracias! 😺',
          action: AssistantAction.remind,
          detail: 'comprar leche',
          minutes: 15));
      final store = PersonalStore();
      final c = make(ai, FakeMacActions(), store);
      await c.read(chatProvider.notifier).send('¿cómo estás?');
      expect(store.reminders, isEmpty);
      expect(c.read(chatProvider).last.text, '¡Muy bien, gracias! 😺');
    });

    test('las tareas van en el contexto de la IA', () async {
      String? context;
      final ai = _CapturingAi((c) => context = c);
      final store = PersonalStore();
      await store.addTask('comprar leche');
      final c = make(ai, FakeMacActions(), store);
      await c.read(chatProvider.notifier).send('¿qué me recomiendas hacer?');
      expect(context, contains('Tareas pendientes: 1) comprar leche.'));
    });
  });

  testWidgets('el panel de pendientes: añadir, tachar y borrar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = PersonalStore();
    await store.addReminder(
        'ir al gimnasio', DateTime.now().add(const Duration(hours: 2)));
    await tester.pumpWidget(ProviderScope(
      overrides: [personalStoreProvider.overrideWithValue(store)],
      child: MaterialApp(home: Scaffold(body: PendingPanel(onClose: () {}))),
    ));
    expect(find.textContaining('ir al gimnasio'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('pending-input')), 'comprar pan');
    await tester.tap(find.byKey(const ValueKey('pending-add')));
    await tester.pump();
    expect(find.text('1. comprar pan'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(store.pending, isEmpty);
    expect(find.text('✅ Hechas'), findsOneWidget);

    await tester.tap(find.byTooltip('Borrar').first);
    await tester.pump();
    expect(store.reminders, isEmpty);
  });
}

class _CapturingAi extends ChatAssistant {
  final void Function(String) onContext;
  _CapturingAi(this.onContext);
  @override
  String get label => 'IA';
  @override
  bool get supportsImages => false;
  @override
  bool get supportsActions => true;
  @override
  Future<AssistantReply> reply(String message,
      {required String context, String? imageBase64}) async {
    onContext(context);
    return const AssistantReply('Empieza por la leche 🥛');
  }

  @override
  Future<void> reset() async {}
}
