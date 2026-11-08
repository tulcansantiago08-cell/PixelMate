import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_detection_controller.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/activity/suggestion.dart';
import 'package:pixelmate/application/activity/suggestion_engine.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_dialogue.dart';
import 'package:pixelmate/application/workday/workday_event.dart';
import 'package:pixelmate/application/workday/workday_notifications.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/activity/detectable_app.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/session/workday_timer.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/activity/suggestion_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

const vscode = ForegroundApp(
    bundleId: 'com.microsoft.VSCode', name: 'Code', executable: 'Electron');
const lol = ForegroundApp(
    bundleId: 'com.riotgames.LeagueofLegends.GameClient',
    name: 'League of Legends');
const minecraftJava = ForegroundApp(name: 'Minecraft 1.21', executable: 'java');
const safari = ForegroundApp(bundleId: 'com.apple.Safari', name: 'Safari');

AppCatalog bundledCatalog() => AppCatalog.parse(
    jsonDecode(File('assets/config/detectable_apps.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  group('catálogo', () {
    final catalog = bundledCatalog();

    test('el archivo incluido es válido y reconoce IDEs y juegos', () {
      expect(catalog.apps.length, greaterThanOrEqualTo(10));
      expect(catalog.identify(vscode)!.category, AppCategory.development);
      expect(catalog.identify(lol)!.name, 'League of Legends');
      expect(catalog.identify(minecraftJava)!.category, AppCategory.gaming);
      expect(catalog.identify(safari), isNull);
      for (final id in [
        'com.jetbrains.intellij',
        'com.jetbrains.intellij.ce',
        'com.jetbrains.pycharm',
        'com.google.android.studio',
        'com.apple.dt.Xcode',
      ]) {
        expect(catalog.identify(ForegroundApp(bundleId: id, name: 'x')),
            isNotNull,
            reason: id);
      }
    });

    test('las apps del usuario se suman y tienen prioridad', () {
      final user = AppCatalog.parse({
        'apps': [
          {
            'name': 'Mi juego',
            'category': 'gaming',
            'bundleIds': ['com.microsoft.VSCode'],
          },
          {'name': 'roto', 'category': 'no-existe'},
        ]
      }, onInvalid: (_) {});
      final merged = catalog.withUserApps(user);
      expect(merged.identify(vscode)!.name, 'Mi juego');
      expect(merged.apps.length, catalog.apps.length + 1);
    });
  });

  group('motor de sugerencias', () {
    final t0 = DateTime.utc(2026, 11, 9, 9);
    late SuggestionEngine engine;

    Suggestion? evaluate(ForegroundApp app, DateTime now,
            {bool enabled = true,
            Set<String> excluded = const {},
            bool active = false}) =>
        engine.evaluate(
            app: app,
            now: now,
            detectionEnabled: enabled,
            excludedApps: excluded,
            sessionActive: active);

    setUp(() => engine = SuggestionEngine(catalog: bundledCatalog()));

    test('sugiere jornada al detectar un IDE', () {
      final s = evaluate(vscode, t0)!;
      expect(s.message, contains('programar'));
      expect(s.options.map((o) => o.action), [
        SuggestionAction.startWork,
        SuggestionAction.startStudy,
        SuggestionAction.dismiss,
        SuggestionAction.neverForApp,
      ]);
    });

    test('sugiere modo gamer al detectar un juego', () {
      final s = evaluate(lol, t0)!;
      expect(s.message, contains('modo gamer'));
      expect(s.options.first.action, SuggestionAction.startGaming);
    });

    test('no repite la misma categoría durante el enfriamiento', () {
      expect(evaluate(vscode, t0), isNotNull);
      expect(evaluate(vscode, t0.add(const Duration(minutes: 30))), isNull);
      // Otra categoría no se ve afectada.
      expect(evaluate(lol, t0.add(const Duration(minutes: 30))), isNotNull);
      expect(evaluate(vscode, t0.add(const Duration(minutes: 61))), isNotNull);
    });

    test('"Ahora no" silencia la categoría 3 horas', () {
      evaluate(vscode, t0);
      engine.dismissed(AppCategory.development, t0);
      expect(evaluate(vscode, t0.add(const Duration(hours: 2))), isNull);
      expect(evaluate(vscode, t0.add(const Duration(hours: 3))), isNotNull);
    });

    test('respeta desactivación, exclusiones y sesiones activas', () {
      expect(evaluate(vscode, t0, enabled: false), isNull);
      expect(evaluate(vscode, t0, excluded: {'com.microsoft.VSCode'}), isNull);
      expect(evaluate(vscode, t0, active: true), isNull);
      expect(evaluate(safari, t0), isNull);
      // Ninguno de los anteriores consumió el enfriamiento.
      expect(evaluate(vscode, t0), isNotNull);
    });
  });

  group('controlador de detección', () {
    late StreamController<ForegroundApp> apps;
    late DetectionSettings settings;
    late WorkdayController workday;
    late ActivityDetectionController detection;
    final t0 = DateTime(2026, 11, 9, 9);
    late DateTime now;

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = DetectionSettings(await SharedPreferences.getInstance());
      apps = StreamController<ForegroundApp>();
      now = t0;
      workday = WorkdayController(
        store: SqliteWorkdayStore.inMemory(),
        now: () => now,
        tickInterval: const Duration(days: 1),
      );
      detection = ActivityDetectionController(
        foregroundApps: apps.stream,
        engine: SuggestionEngine(catalog: bundledCatalog()),
        settings: settings,
        workday: workday,
        now: () => now,
        settle: const Duration(milliseconds: 5),
        autoHide: const Duration(seconds: 30),
      );
      addTearDown(() {
        detection.dispose();
        workday.dispose();
        apps.close();
      });
    });

    test('al pasar rápido de una app a otra solo cuenta la última', () async {
      apps.add(vscode);
      apps.add(safari);
      await settle();
      expect(detection.state, isNull);
    });

    test('elegir "Jornada laboral" inicia la jornada; nunca sin elegir',
        () async {
      apps.add(vscode);
      await settle();
      expect(detection.state, isNotNull);
      expect(workday.state.isActive, isFalse);

      await detection.choose(SuggestionAction.startWork);
      expect(detection.state, isNull);
      expect(workday.state.mode, ActivityMode.work);
    });

    test('"Sí, vamos a jugar" inicia el modo gamer 60/5', () async {
      apps.add(lol);
      await settle();
      await detection.choose(SuggestionAction.startGaming);
      final timer = workday.state.timer!;
      expect(workday.state.mode, ActivityMode.gaming);
      expect(timer.plan[0].duration, const Duration(minutes: 60));
      expect(timer.plan[1].duration, const Duration(minutes: 5));
    });

    test('"Nunca con…" excluye la app y lo recuerda', () async {
      apps.add(vscode);
      await settle();
      await detection.choose(SuggestionAction.neverForApp);
      expect(settings.excludedApps, contains('com.microsoft.VSCode'));
      now = now.add(const Duration(days: 1));
      apps.add(safari);
      apps.add(vscode);
      await settle();
      expect(detection.state, isNull);
    });

    test('desactivar la detección oculta la sugerencia visible', () async {
      apps.add(vscode);
      await settle();
      await settings.setEnabled(false);
      expect(detection.state, isNull);
    });

    test('bienvenida al abrir, reemplazada por una sugerencia concreta',
        () async {
      detection.askWelcome();
      expect(detection.state!.app, isNull);
      expect(detection.state!.message, contains('Buenos días'));
      apps.add(vscode);
      await settle();
      expect(detection.state!.app, vscode);
    });

    test('sin bienvenida si ya hay una sesión en curso', () {
      workday.start(const WorkdayConfig());
      detection.askWelcome();
      expect(detection.state, isNull);
    });
  });

  group('modo gamer: frases y avisos', () {
    final timer = WorkdayTimer.start(
        id: 'g', config: WorkdayConfig.gaming, now: DateTime.utc(2026));

    test('al descanso: descansar la vista con un consejo', () {
      final event = PhaseStarted(timer.plan[1], timer.plan[0]);
      final r = reactionFor(event, mode: ActivityMode.gaming)!;
      expect(r.message, contains('descansar la vista'));
      expect(r.message, contains(eyeBreakTip(1)));
      expect(noticeFor(event, mode: ActivityMode.gaming)!.title,
          '👀 Descanso visual de 5 min');
    });

    test('5 minutos antes avisa que ya casi termina la sesión', () {
      final r = reactionFor(
          FocusEndingSoon(timer.plan[0], const Duration(minutes: 5)),
          mode: ActivityMode.gaming)!;
      expect(r.message, contains('Ya casi terminamos esta sesión'));
    });

    test('el estudio tiene su propio saludo', () {
      expect(reactionFor(const WorkdayStarted(), mode: ActivityMode.study)!
          .message, contains('estudiar'));
    });
  });

  test('el menú de la barra muestra la detección como casilla', () {
    TrayEntry entry(bool enabled) => trayEntries(WorkdayView.none,
            mascotVisible: true, detectionEnabled: enabled)
        .firstWhere((e) => e.action == TrayAction.toggleDetection);
    expect(entry(true).checked, isTrue);
    expect(entry(false).checked, isFalse);
    expect(entry(true).key, isNot(entry(false).key));
  });

  testWidgets('el globo muestra la pregunta y responde al tocar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
    ]);
    addTearDown(container.dispose);
    final detection = container.read(activityDetectionProvider.notifier);
    detection.askWelcome();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionBubble(
          suggestion: container.read(activityDetectionProvider)!,
          onChoose: detection.choose,
        ),
      ),
    ));
    expect(find.textContaining('aventuras'), findsOneWidget);
    await tester.tap(find.text('📚 Estudiar'));
    await tester.pump();
    final view = container.read(workdayControllerProvider);
    expect(view.mode, ActivityMode.study);
    expect(view.timer!.config, WorkdayConfig.study);
    container.read(workdayControllerProvider.notifier).finish();
  });
}
