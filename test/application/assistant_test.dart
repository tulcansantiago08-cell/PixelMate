import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_actions.dart';
import 'package:pixelmate/application/assistant/assistant_context.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/chat_controller.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/goals/daily_goal.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/infrastructure/assistant/apple_assistant.dart';
import 'package:pixelmate/infrastructure/assistant/assistant_setup.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/chat/chat_bubble.dart';

/// IA de prueba: responde lo que se le indique y guarda lo que recibió.
class FakeAssistant extends ChatAssistant {
  AssistantReply next = const AssistantReply('¡Hola!');
  Object? error;
  final bool images;
  final bool actions;
  final received = <(String, String, String?)>[];
  var prewarmed = 0;

  FakeAssistant({this.images = false, this.actions = true});

  @override
  String get label => 'Prueba';
  @override
  bool get supportsImages => images;
  @override
  bool get supportsActions => actions;

  @override
  Future<AssistantReply> reply(String message,
      {required String context, String? imageBase64}) async {
    received.add((message, context, imageBase64));
    if (error != null) throw error!;
    return next;
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> prewarm() async => prewarmed++;
}

ProviderContainer makeContainer(ChatAssistant? assistant,
    {String? problem, Future<String> Function()? capture}) {
  final c = ProviderContainer(overrides: [
    workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
    mascotWindowProvider.overrideWithValue(NoopMascotWindow()),
    dailyGoalSettingsProvider.overrideWithValue(DailyGoalSettings()),
    assistantChoiceProvider
        .overrideWith((_) async => AssistantChoice(assistant, problem)),
    screenCaptureProvider.overrideWithValue(capture),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contexto para la IA', () {
    test('sin jornada: hora, meta y nivel', () {
      final c = makeContainer(null);
      final text = describeContext(
        now: DateTime(2026, 11, 8, 9, 5),
        workday: c.read(workdayControllerProvider),
        goal: const DailyGoalStatus(
            done: Duration(minutes: 90), goal: Duration(hours: 4)),
        progress: const PlayerProgress(xp: 400, unlocked: {}),
      );
      expect(text, contains('Hora: 09:05.'));
      expect(text, contains('No hay jornada en curso.'));
      expect(text, contains('Enfoque de hoy: 1 h 30 min de una meta de 4 h.'));
      expect(
          text,
          contains('Nivel 3 («Aprendiz curioso»), 400 XP; '
              'faltan 200 XP para el nivel 4.'));
    });

    test('con jornada: modo, fase, tiempo restante y pausa', () {
      final c = makeContainer(null);
      c
          .read(workdayControllerProvider.notifier)
          .start(WorkdayConfig.study, mode: ActivityMode.study);
      var text = describeContext(
        now: DateTime(2026, 11, 8, 9),
        workday: c.read(workdayControllerProvider),
        goal: null,
        progress: PlayerProgress.empty,
      );
      expect(text, contains('Jornada de estudio en curso.'));
      expect(text, contains('Fase: enfoque (ciclo 1); quedan'));
      expect(text, contains('Sin meta diaria.'));

      c.read(workdayControllerProvider.notifier).pause();
      text = describeContext(
        now: DateTime(2026, 11, 8, 9),
        workday: c.read(workdayControllerProvider),
        goal: const DailyGoalStatus(
            done: Duration(hours: 5), goal: Duration(hours: 4)),
        progress: PlayerProgress.empty,
      );
      expect(text, contains('(en pausa)'));
      expect(text, contains('(meta cumplida)'));
      c.read(workdayControllerProvider.notifier).finish();
    });
  });

  group('acciones pedidas por la IA', () {
    late ProviderContainer c;
    late DailyGoalSettings goal;
    var statsOpened = 0;

    setUp(() {
      c = makeContainer(null);
      goal = c.read(dailyGoalSettingsProvider);
      statsOpened = 0;
    });

    String? run(AssistantAction action, {int hours = 0}) => runAssistantAction(
          AssistantReply('ok', action: action, hours: hours),
          workday: c.read(workdayControllerProvider.notifier),
          view: c.read(workdayControllerProvider),
          goal: goal,
          openStats: () => statsOpened++,
        );

    test('el nombre del modelo se traduce; lo desconocido no hace nada', () {
      expect(AssistantAction.parse('cambiarMeta'), AssistantAction.setGoal);
      expect(AssistantAction.parse('borrarTodo'), AssistantAction.none);
      expect(AssistantAction.parse(null), AssistantAction.none);
      expect(run(AssistantAction.none), isNull);
    });

    test('iniciar con las horas pedidas o la duración del modo', () {
      expect(run(AssistantAction.startStudy, hours: 2),
          '▶️ Empecé una jornada de estudio de 2 h.');
      final view = c.read(workdayControllerProvider);
      expect(view.mode, ActivityMode.study);
      expect(view.timer!.config.workday, const Duration(hours: 2));
      expect(view.timer!.config.focus, WorkdayConfig.study.focus);

      expect(run(AssistantAction.startWork), 'ℹ️ Ya hay una jornada en curso.',
          reason: 'no reemplaza la jornada actual');
      c.read(workdayControllerProvider.notifier).finish();
    });

    test('pausar, reanudar y terminar solo cuando corresponde', () {
      expect(run(AssistantAction.pause), isNull, reason: 'no hay jornada');
      expect(run(AssistantAction.finish), isNull);
      run(AssistantAction.startGaming);
      expect(c.read(workdayControllerProvider).timer!.config.workday,
          WorkdayConfig.gaming.workday);
      expect(run(AssistantAction.resume), isNull, reason: 'no está en pausa');
      expect(run(AssistantAction.pause), '⏸️ Pausé la jornada.');
      expect(run(AssistantAction.pause), isNull, reason: 'ya en pausa');
      expect(run(AssistantAction.resume), '▶️ Reanudé la jornada.');
      expect(run(AssistantAction.finish), '⏹️ Terminé la jornada.');
      expect(c.read(workdayControllerProvider).isActive, isFalse);
    });

    test('meta y estadísticas', () {
      expect(run(AssistantAction.setGoal), isNull, reason: 'sin horas');
      expect(run(AssistantAction.setGoal, hours: 3),
          '🎯 Tu meta diaria ahora es de 3 h.');
      expect(goal.goal, const Duration(hours: 3));
      expect(run(AssistantAction.setGoal, hours: 40),
          '🎯 Tu meta diaria ahora es de 12 h.',
          reason: 'se limita a 12 h');
      expect(run(AssistantAction.openStats), '📊 Abrí tus estadísticas.');
      expect(statsOpened, 1);
    });
  });

  group('qué IA se usa', () {
    final apple = FakeAssistant();
    final claude = FakeAssistant(images: true, actions: false);

    test('Apple primero; si no, Claude; si no, el motivo', () {
      expect(
          chooseAssistant(
                  apple: AppleAiAvailability.available,
                  appleAssistant: apple,
                  claude: claude)
              .assistant,
          apple);
      expect(
          chooseAssistant(
                  apple: AppleAiAvailability.appleIntelligenceNotEnabled,
                  appleAssistant: apple,
                  claude: claude)
              .assistant,
          claude);
      final none = chooseAssistant(
          apple: AppleAiAvailability.appleIntelligenceNotEnabled,
          appleAssistant: apple);
      expect(none.assistant, isNull);
      expect(none.problem, contains('activa Apple Intelligence'));
      for (final a in AppleAiAvailability.values) {
        expect(a.problem == null, a == AppleAiAvailability.available);
      }
    });
  });

  group('canal con la IA de Apple', () {
    const channel = MethodChannel('com.pixelmate/apple_ai');
    final calls = <MethodCall>[];

    void mock(Future<Object?> Function(MethodCall) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });

    setUp(calls.clear);
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('envía instrucciones y contexto; traduce la respuesta', () async {
      mock((call) async => call.method == 'availability'
          ? 'available'
          : {'reply': ' ¡Quedan 14 min! ', 'action': 'pausar', 'hours': 0});
      expect(
          await AppleAssistant.availability(), AppleAiAvailability.available);
      final r = await AppleAssistant()
          .reply('¿Cuánto falta?', context: 'Fase: enfoque.');
      expect(r.text, '¡Quedan 14 min!');
      expect(r.action, AssistantAction.pause);
      final args = calls.last.arguments as Map;
      expect(args['instructions'], assistantInstructions);
      expect(args['prompt'],
          'Estado actual de la app: Fase: enfoque.\n\nUsuario: ¿Cuánto falta?');
    });

    test('los errores nativos llegan como mensajes amables', () async {
      mock((_) async => throw PlatformException(code: 'guardrail'));
      expect(
          () => AppleAssistant().reply('x', context: ''),
          throwsA(isA<AssistantException>().having(
              (e) => e.message, 'message', contains('Prefiero no responder'))));
    });

    test('sin el plugin nativo: no compatible', () async {
      mock((_) async => throw MissingPluginException());
      expect(
          await AppleAssistant.availability(), AppleAiAvailability.unsupported);
    });
  });

  group('chat', () {
    test('sin IA explica cómo activarla', () async {
      final c = makeContainer(null, problem: 'Activa Apple Intelligence.');
      await c.read(chatProvider.notifier).send('hola');
      final m = c.read(chatProvider);
      expect(
          m.map((e) => e.text).skip(1), ['hola', 'Activa Apple Intelligence.']);
    });

    test('responde con contexto y ejecuta la acción pedida', () async {
      final ai = FakeAssistant()
        ..next = const AssistantReply('¡Listo! 🎯',
            action: AssistantAction.setGoal, hours: 3);
      final c = makeContainer(ai);
      await c.read(chatProvider.notifier).send('Pon mi meta en 3 horas');

      expect(ai.received.single.$1, 'Pon mi meta en 3 horas');
      expect(ai.received.single.$2, contains('No hay jornada en curso.'));
      final m = c.read(chatProvider);
      expect(m[m.length - 2].text, '¡Listo! 🎯');
      expect(m.last.isNote, isTrue);
      expect(m.last.text, '🎯 Tu meta diaria ahora es de 3 h.');
      expect(c.read(dailyGoalSettingsProvider).goal, const Duration(hours: 3));
      expect(c.read(chatProvider.notifier).isLoading, isFalse);
    });

    test('"ver estadísticas" abre el panel', () async {
      final ai = FakeAssistant()
        ..next =
            const AssistantReply('Mira 📊', action: AssistantAction.openStats);
      final c = makeContainer(ai);
      await c.read(chatProvider.notifier).send('muéstrame mis estadísticas');
      await pumpEventQueue();
      expect(c.read(mascotPanelProvider), MascotPanel.stats);
    });

    test('una IA sin acciones (Claude) no toca nada', () async {
      final ai = FakeAssistant(actions: false)
        ..next = const AssistantReply('ok', action: AssistantAction.startWork);
      final c = makeContainer(ai);
      await c.read(chatProvider.notifier).send('empieza');
      expect(c.read(workdayControllerProvider).isActive, isFalse);
      expect(c.read(chatProvider).last.isNote, isFalse);
    });

    test('la captura solo va a una IA que ve imágenes', () async {
      var captured = 0;
      final apple = FakeAssistant();
      var c = makeContainer(apple, capture: () async {
        captured++;
        return 'IMG';
      });
      await c.read(chatProvider.notifier).send('', withScreenshot: true);
      expect(captured, 0, reason: 'nunca se captura si no se va a usar');
      expect(apple.received, isEmpty);
      expect(
          c.read(chatProvider).last.text, contains('no puedo ver tu pantalla'));

      final claude = FakeAssistant(images: true, actions: false);
      c = makeContainer(claude, capture: () async {
        captured++;
        return 'IMG';
      });
      await c.read(chatProvider.notifier).send('', withScreenshot: true);
      expect(captured, 1);
      expect(claude.received.single.$3, 'IMG');
      expect(c.read(chatProvider).firstWhere((m) => m.isUser).hasImage, isTrue);
    });

    test('un error se muestra como mensaje y el chat sigue', () async {
      final ai = FakeAssistant()
        ..error = const AssistantException('Algo falló 😵');
      final c = makeContainer(ai);
      await c.read(chatProvider.notifier).send('hola');
      expect(c.read(chatProvider).last.text, 'Algo falló 😵');
      expect(c.read(chatProvider.notifier).isLoading, isFalse);
    });
  });

  testWidgets('el chat muestra qué IA responde y oculta 📷 si no ve imágenes',
      (tester) async {
    final ai = FakeAssistant();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        assistantChoiceProvider.overrideWith((_) async => AssistantChoice(ai)),
      ],
      child: const MaterialApp(
          home: Scaffold(
              body: SizedBox(width: 300, height: 400, child: ChatBubble()))),
    ));
    await tester.pump();
    expect(find.text('Prueba'), findsOneWidget);
    expect(find.byIcon(Icons.screenshot), findsNothing);
    expect(ai.prewarmed, 1, reason: 'al abrir el chat se precarga el modelo');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
