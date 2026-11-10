import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/activity/focus_guard.dart';
import 'package:pixelmate/application/activity/focus_guard_controller.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/chat_controller.dart';
import 'package:pixelmate/application/desktop/login_item.dart';
import 'package:pixelmate/application/desktop/sounds.dart';
import 'package:pixelmate/application/desktop/global_shortcut.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/goals/daily_goal.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/mascot/pet_kind.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:pixelmate/presentation/onboarding/welcome_panel.dart';
import 'package:pixelmate/presentation/settings/settings_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LocalAi extends ChatAssistant {
  @override
  String get label => 'IA de Apple · en tu Mac';
  @override
  bool get supportsImages => false;
  @override
  bool get supportsActions => true;
  @override
  bool get onDevice => true;
  @override
  Future<AssistantReply> reply(String message,
          {required String context, String? imageBase64}) async =>
      const AssistantReply('ok');
  @override
  Future<void> reset() async {}
}

/// La mascota anima en bucle: no se puede usar pumpAndSettle.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class Env {
  final MascotSettings mascot;
  final DailyGoalSettings goal;
  final FocusGuardSettings guard;
  final DetectionSettings detection;
  final LaunchAtLogin launch;
  final NoopLoginItem login;
  final NoopMascotWindow window = NoopMascotWindow();
  Env(this.mascot, this.goal, this.guard, this.detection, this.login)
      : launch = LaunchAtLogin(login);

  static Future<Env> create({bool grant = true, bool onboarded = true}) async {
    SharedPreferences.setMockInitialValues(
        onboarded ? {'onboarding.done': true} : {});
    final prefs = await SharedPreferences.getInstance();
    final login = NoopLoginItem(supported: true, grant: grant);
    final env = Env(MascotSettings(prefs), DailyGoalSettings(prefs),
        FocusGuardSettings(prefs), DetectionSettings(prefs), login);
    await env.launch.load();
    return env;
  }

  List<Override> get overrides => [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        mascotSettingsProvider.overrideWithValue(mascot),
        dailyGoalSettingsProvider.overrideWithValue(goal),
        focusGuardSettingsProvider.overrideWithValue(guard),
        detectionSettingsProvider.overrideWithValue(detection),
        launchAtLoginProvider.overrideWithValue(launch),
        mascotWindowProvider.overrideWithValue(window),
        assistantChoiceProvider
            .overrideWith((_) async => AssistantChoice(_LocalAi())),
      ];
}

Future<void> pumpPanel(WidgetTester tester, Env env, Widget panel) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides,
    child: MaterialApp(home: Scaffold(body: panel)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('abrir al iniciar sesión', () {
    test('estado compartido; avisa si macOS pide aprobarlo', () async {
      final ok = LaunchAtLogin(NoopLoginItem(supported: true));
      await ok.load();
      expect(ok.supported, isTrue);
      expect(await ok.setEnabled(true), isTrue);
      expect(ok.enabled, isTrue);
      expect(await ok.setEnabled(false), isTrue);

      final blocked =
          LaunchAtLogin(NoopLoginItem(supported: true, grant: false));
      await blocked.load();
      expect(await blocked.setEnabled(true), isFalse);
      expect(blocked.enabled, isFalse);

      final none = LaunchAtLogin(NoopLoginItem());
      await none.load();
      expect(none.supported, isFalse);
    });
  });

  testWidgets('Ajustes cambia cada opción', (tester) async {
    final env = await Env.create(grant: false);
    var welcome = 0;
    await pumpPanel(tester, env,
        SettingsPanel(onClose: () {}, onShowWelcome: () => welcome++));

    expect(find.text('Pixel ✏️'), findsOneWidget);
    // Especie: el perro (Nv. 5) y el zorro (Nv. 10) aún están bloqueados.
    expect(find.text('Perro · Nv. 5'), findsOneWidget);
    expect(find.text('Zorro · Nv. 10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('species-dog')));
    await tester.pumpAndSettle();
    expect(env.mascot.species, PetKind.cat, reason: 'bloqueado: no cambia');
    // El aura se ve bloqueada hasta el nivel 20.
    expect(find.text('🔒 Se desbloquea en el nivel 20.'), findsOneWidget);
    final aura =
        tester.widget<Switch>(find.byKey(const ValueKey('settings-aura')));
    expect(aura.onChanged, isNull);
    expect(aura.value, isFalse);
    // Cada interruptor, bajando hasta él (están en este orden).
    for (final key in [
      'walk',
      'guard',
      'deepfocus',
      'wellness',
      'night',
      'detection'
    ]) {
      final f = find.byKey(ValueKey('settings-$key'));
      await tester.scrollUntilVisible(f, 80,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
    expect(env.mascot.walkEnabled, isFalse);
    expect(env.guard.enabled, isFalse);
    expect(env.mascot.deepFocus, isTrue, reason: 'apagado por defecto');
    expect(env.mascot.wellnessTips, isFalse);
    expect(env.mascot.nightReminders, isFalse);
    expect(env.detection.enabled, isFalse);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-goal')), -100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 150));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 h al día').last);
    await tester.pumpAndSettle();
    expect(env.goal.goal, const Duration(hours: 2));
    expect(find.text('2 h ▾'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-login')), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-login')));
    await tester.pumpAndSettle();
    expect(env.launch.enabled, isFalse);
    expect(find.textContaining('Ítems de inicio'), findsOneWidget,
        reason: 'explica dónde aprobarlo');

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-rename')), -100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('settings-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pet-name-field')), 'Luna');
    await tester.tap(find.byKey(const ValueKey('pet-name-save')));
    await tester.pumpAndSettle();
    expect(env.mascot.name, 'Luna');
    expect(find.text('Luna ✏️'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-welcome')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.textContaining('IA de Apple · en tu Mac: gratis'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-welcome')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-welcome')));
    expect(welcome, 1);
  });

  testWidgets('la bienvenida pide nombre, meta y arranque', (tester) async {
    final env = await Env.create(onboarded: false);
    var done = 0;
    await pumpPanel(tester, env, WelcomePanel(onDone: () => done++));

    expect(find.text('¡Hola! 🐾'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('welcome-name')), 'Nube');
    await tester.tap(find.byKey(const ValueKey('welcome-next')));
    await tester.pumpAndSettle();
    expect(env.mascot.name, 'Nube');
    expect(find.text('Encantado, soy Nube 😺'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('welcome-goal-3')));
    await tester.pumpAndSettle();
    expect(env.goal.goal, const Duration(hours: 3));
    await tester.tap(find.byKey(const ValueKey('welcome-next')));
    await tester.pumpAndSettle();

    expect(find.textContaining('gratis y sin internet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome-login')));
    await tester.pumpAndSettle();
    expect(env.launch.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('welcome-next')));
    await tester.pumpAndSettle();

    expect(find.text('¡Listo! Así me usas'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-skip')), findsNothing);
    await tester.tap(find.text('¡Empecemos!'));
    expect(done, 1);
  });

  testWidgets('se puede saltar', (tester) async {
    final env = await Env.create(onboarded: false);
    var done = 0;
    await pumpPanel(tester, env, WelcomePanel(onDone: () => done++));
    await tester.tap(find.byKey(const ValueKey('welcome-skip')));
    expect(done, 1);
    expect(env.mascot.name, 'Pixel', reason: 'sin cambios');
  });

  testWidgets('la primera vez aparece la bienvenida, y solo esa vez',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await Env.create(onboarded: false);
    expect(env.mascot.onboardingDone, isFalse);

    Future<void> launch() async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: env.overrides,
        child: const MaterialApp(home: MascotWindow()),
      ));
      await tester.pump(const Duration(seconds: 3));
      await frames(tester);
    }

    await launch();
    expect(find.byType(WelcomePanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome-skip')));
    await frames(tester);
    expect(find.byType(WelcomePanel), findsNothing);
    expect(env.mascot.onboardingDone, isTrue);
    expect(find.textContaining('Encantado de conocerte'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));

    await launch();
    expect(find.byType(WelcomePanel), findsNothing,
        reason: 'la segunda vez ya no');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('Ajustes cabe en la ventana real de la mascota', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = await Env.create();
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides,
      child: const MaterialApp(home: MascotWindow()),
    ));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MascotWindow)));
    container.read(mascotPanelProvider.notifier).state = MascotPanel.settings;
    await frames(tester);
    expect(find.byType(SettingsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-welcome')), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-welcome')));
    await frames(tester, 4);
    await tester.tap(find.byKey(const ValueKey('settings-welcome')));
    await frames(tester);
    expect(find.byType(WelcomePanel), findsOneWidget,
        reason: 'se puede volver a ver la bienvenida');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('Extras: atajo y sonidos', (tester) async {
    final env = await Env.create();
    final shortcut = ShortcutSettings();
    final sound = SoundSettings();
    final player = NoopSoundPlayer();
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides,
        shortcutSettingsProvider.overrideWithValue(shortcut),
        soundSettingsProvider.overrideWithValue(sound),
        soundPlayerProvider.overrideWithValue(player),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SettingsPanel(onClose: () {}, onShowWelcome: () {}))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Atajo ⌃⌥P para abrir el chat'), findsOneWidget);
    expect(shortcut.enabled, isTrue, reason: 'activado por defecto');
    shortcut.reportWorking(false);
    await tester.pump();
    expect(find.text('⚠️ Otra app ya usa ⌃⌥P.'), findsOneWidget);

    expect(sound.enabled, isFalse, reason: 'apagados por defecto');
    expect(find.byKey(const ValueKey('settings-sound-test')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-sound')));
    await tester.pumpAndSettle();
    expect(sound.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings-sound-test')));
    expect(player.played, [PetSound.level]);

    await tester.tap(find.byKey(const ValueKey('settings-shortcut')));
    await tester.pumpAndSettle();
    expect(shortcut.enabled, isFalse);
  });

  test('"Ajustes…" en la barra de menú', () {
    final entries = trayEntries(WorkdayView.none, mascotVisible: true);
    expect(entries.map((e) => e.action), contains(TrayAction.showSettings));
    expect(MascotPanel.values, contains(MascotPanel.settings));
  });
}
