import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/focus_guard.dart';
import 'package:pixelmate/application/activity/focus_guard_controller.dart';
import 'package:pixelmate/application/activity/suggestion_engine.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/workday_summary.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/activity/detectable_app.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const whatsapp =
    ForegroundApp(bundleId: 'net.whatsapp.WhatsApp', name: 'WhatsApp');
const steam = ForegroundApp(bundleId: 'com.valvesoftware.steam', name: 'Steam');
const vscode = ForegroundApp(bundleId: 'com.microsoft.VSCode', name: 'Code');

const catalog = AppCatalog([
  DetectableApp(
      name: 'WhatsApp',
      category: AppCategory.distraction,
      bundleIds: ['net.whatsapp.WhatsApp']),
  DetectableApp(
      name: 'Steam',
      category: AppCategory.gaming,
      bundleIds: ['com.valvesoftware.steam']),
  DetectableApp(
      name: 'VS Code',
      category: AppCategory.development,
      bundleIds: ['com.microsoft.VSCode']),
]);

class _OnDevice extends ChatAssistant {
  final bool local;
  String? prompt;
  _OnDevice(this.local);
  @override
  String get label => 'x';
  @override
  bool get supportsImages => false;
  @override
  bool get supportsActions => false;
  @override
  bool get onDevice => local;
  @override
  Future<AssistantReply> reply(String message,
      {required String context, String? imageBase64}) async {
    prompt = message;
    return const AssistantReply(' ¡Gran jornada! Descansa la vista. ',
        action: AssistantAction.startWork);
  }

  @override
  Future<void> reset() async {}
}

void main() {
  final t0 = DateTime(2026, 11, 9, 10);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  group('reglas del guardián', () {
    late FocusGuard g;
    setUp(() => g = FocusGuard(catalog: catalog));

    ({Duration spent, bool newEpisode, FocusNudge? nudge}) check(int s,
            {bool focusing = true,
            ActivityMode mode = ActivityMode.work,
            bool enabled = true}) =>
        g.check(now: at(s), focusing: focusing, mode: mode, enabled: enabled);

    test('qué cuenta como distracción según el modo', () {
      final wa = catalog.identify(whatsapp)!;
      final st = catalog.identify(steam)!;
      final code = catalog.identify(vscode)!;
      expect(FocusGuard.distracts(wa, ActivityMode.work), isTrue);
      expect(FocusGuard.distracts(st, ActivityMode.study), isTrue);
      expect(FocusGuard.distracts(code, ActivityMode.work), isFalse);
      expect(FocusGuard.distracts(st, ActivityMode.gaming), isFalse,
          reason: 'en modo juego, jugar es el plan');
      expect(FocusGuard.distracts(wa, ActivityMode.free), isFalse);
      expect(FocusGuard.distracts(wa, null), isFalse);
    });

    test('una mirada rápida no cuenta; quedarse sí, con un aviso', () {
      g.onForeground(whatsapp, at(0));
      expect(check(0).nudge, isNull);
      expect(check(44).nudge, isNull);
      g.onForeground(vscode, at(44)); // volvió a tiempo
      expect(check(60).newEpisode, isFalse);

      g.onForeground(whatsapp, at(100));
      check(100);
      final r = check(146);
      expect(r.nudge?.appName, 'WhatsApp');
      expect(r.newEpisode, isTrue);
      expect(r.spent, const Duration(seconds: 46));
      final next = check(147);
      expect(next.nudge, isNull, reason: 'un aviso por episodio');
      expect(next.newEpisode, isFalse);
      expect(next.spent, const Duration(seconds: 1));
    });

    test('no vigila fuera del enfoque, en pausa o desactivado', () {
      g.onForeground(whatsapp, at(0));
      check(0, focusing: false);
      expect(check(100, focusing: false).nudge, isNull);
      expect(check(200, enabled: false).nudge, isNull);
      expect(check(300, mode: ActivityMode.gaming).nudge, isNull);
      // Vuelve el enfoque: la gracia empieza de nuevo.
      expect(check(400).nudge, isNull);
      expect(check(446).nudge, isNotNull);
    });

    test('como mucho un aviso por app cada 10 min, pero cuenta igual', () {
      g.onForeground(whatsapp, at(0));
      check(0);
      expect(check(50).nudge, isNotNull);
      g.onForeground(vscode, at(60));
      check(60);
      g.onForeground(whatsapp, at(120));
      check(120);
      final again = check(170);
      expect(again.nudge, isNull, reason: 'en silencio 10 min');
      expect(again.newEpisode, isTrue);
      g.onForeground(vscode, at(200));
      g.onForeground(whatsapp, at(700));
      check(700);
      expect(check(750).nudge, isNotNull, reason: 'pasaron los 10 min');
    });
  });

  group('cuenta del día', () {
    test('suma, se guarda y se reinicia al cambiar de día', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = t0;
      final s = FocusGuardSettings(prefs, () => now);
      expect(s.enabled, isTrue);
      await s.record(spent: const Duration(seconds: 46), episode: true);
      await s.record(spent: const Duration(milliseconds: 1500));
      final again = FocusGuardSettings(prefs, () => now);
      expect(again.today.episodes, 1);
      expect(again.today.time, const Duration(milliseconds: 47500));

      now = t0.add(const Duration(days: 1));
      expect(again.today.episodes, 0);
      await again.record(episode: true);
      expect(again.today.episodes, 1);

      await again.setEnabled(false);
      expect(FocusGuardSettings(prefs).enabled, isFalse);
    });
  });

  group('con la jornada y la app real', () {
    test('avisa durante el enfoque y deja de avisar al volver', () async {
      final apps = StreamController<ForegroundApp>.broadcast();
      final settings = FocusGuardSettings();
      final container = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        foregroundAppsProvider.overrideWithValue(apps.stream),
        appCatalogProvider.overrideWithValue(catalog),
        focusGuardSettingsProvider.overrideWithValue(settings),
      ]);
      addTearDown(container.dispose);

      var now = t0;
      final controller = FocusGuardController(
        guard: FocusGuard(catalog: catalog),
        settings: settings,
        foregroundApps: apps.stream,
        now: () => now,
      );
      addTearDown(controller.dispose);
      final workday = container.read(workdayControllerProvider.notifier);
      workday.start(const WorkdayConfig());
      WorkdayView view() => container.read(workdayControllerProvider);

      apps.add(whatsapp);
      await pumpEventQueue();
      controller.onTick(view());
      now = t0.add(const Duration(seconds: 50));
      controller.onTick(view());
      expect(controller.state?.appName, 'WhatsApp');
      expect(settings.today.episodes, 1);
      expect(focusNudgeMessage(controller.state!, view()),
          contains('Veo WhatsApp en pleno enfoque'));

      apps.add(vscode);
      await pumpEventQueue();
      expect(controller.state, isNull, reason: 'volvió al trabajo');
      workday.finish();
      await apps.close();
    });
  });

  test('las distracciones no sugieren un modo', () {
    final engine = SuggestionEngine(catalog: catalog);
    expect(
        engine.evaluate(
            app: whatsapp,
            now: t0,
            detectionEnabled: true,
            excludedApps: const {},
            sessionActive: false),
        isNull);
  });

  test('casilla del guardián en la barra de menú', () {
    TrayEntry entry(bool on) => trayEntries(WorkdayView.none,
            mascotVisible: true, focusGuardEnabled: on)
        .firstWhere((e) => e.action == TrayAction.toggleFocusGuard);
    expect(entry(true).label, 'Guardián del enfoque');
    expect(entry(true).checked, isTrue);
    expect(entry(false).checked, isFalse);
  });

  group('resumen de la jornada', () {
    late WorkdayController workday;
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      ]);
      addTearDown(c.dispose);
      workday = c.read(workdayControllerProvider.notifier);
    });

    test('el pedido incluye lo que pasó en la jornada', () {
      workday.start(WorkdayConfig.study, mode: ActivityMode.study);
      final status = c.read(workdayControllerProvider).status!;
      final prompt = workdaySummaryPrompt(
        status: status,
        mode: ActivityMode.study,
        distractions:
            const DistractionTally(episodes: 2, time: Duration(minutes: 7)),
      );
      expect(prompt, contains('jornada de estudio'));
      expect(prompt, contains('La terminé antes de tiempo'));
      expect(prompt, contains('2 distracciones durante el enfoque (7 min)'));
      expect(
          workdaySummaryPrompt(
              status: status,
              mode: ActivityMode.work,
              distractions: DistractionTally.zero),
          contains('no tuve distracciones'));
      workday.finish();
    });

    test('solo con una IA del propio Mac; ignora acciones', () async {
      final local = _OnDevice(true);
      expect(await summarizeWorkday(local, prompt: 'p', context: 'c'),
          '¡Gran jornada! Descansa la vista.');
      expect(local.prompt, 'p');
      final cloud = _OnDevice(false);
      expect(await summarizeWorkday(cloud, prompt: 'p', context: 'c'), isNull);
      expect(cloud.prompt, isNull, reason: 'no se envía nada a la nube');
      expect(await summarizeWorkday(null, prompt: 'p', context: 'c'), isNull);
    });
  });
}
