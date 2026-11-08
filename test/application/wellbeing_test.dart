import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/workday/wellbeing.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/mascot/pet_species.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('rota los consejos sin repetir seguidos, distintos en corto y largo',
      () {
    final coach = WellnessCoach();
    final shorts = [
      for (var i = 0; i < WellnessTip.short.length; i++)
        coach.next(SessionPhase.shortBreak)
    ];
    expect(shorts.toSet(), WellnessTip.short.toSet(),
        reason: 'pasa por todos antes de repetir');
    expect(coach.next(SessionPhase.shortBreak), shorts.first);
    expect(coach.next(SessionPhase.longBreak), WellnessTip.walk,
        reason: 'el largo empieza por caminar');
    expect(coach.next(SessionPhase.focus), isNull);
  });

  test('cada consejo tiene emoji, texto y, si toca, animación', () {
    for (final t in WellnessTip.values) {
      expect(t.message, startsWith(t.emoji));
      expect(t.text, isNotEmpty);
    }
    expect(WellnessTip.stretch.animation, PetAnimation.stretch);
    expect(WellnessTip.eyes.message, contains('20-20-20'));
    expect(WellnessTip.long, contains(WellnessTip.walk));
    expect(WellnessTip.short, isNot(contains(WellnessTip.walk)),
        reason: 'caminar es para el descanso largo');
  });

  test('la preferencia se guarda (activada por defecto)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(MascotSettings(prefs).wellnessTips, isTrue);
    await MascotSettings(prefs).setWellnessTips(false);
    expect(MascotSettings(prefs).wellnessTips, isFalse);
  });

  Future<ProviderContainer> launch(WidgetTester tester,
      {bool tips = true}) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = MascotSettings();
    await settings.setWellnessTips(tips);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
        mascotWindowProvider.overrideWithValue(NoopMascotWindow()),
        mascotSettingsProvider.overrideWithValue(settings),
      ],
      child: const MaterialApp(home: MascotWindow()),
    ));
    await tester.pump(const Duration(seconds: 4)); // saludo inicial
    return ProviderScope.containerOf(tester.element(find.byType(MascotWindow)));
  }

  testWidgets('al empezar el descanso, después del aviso, llega el consejo',
      (tester) async {
    final c = await launch(tester);
    final workday = c.read(workdayControllerProvider.notifier);
    // La pregunta de bienvenida (su saludo cambia con la hora).
    expect(find.text('💼 Trabajar'), findsOneWidget);
    workday.start(const WorkdayConfig());
    await tester.pump();
    expect(find.text('💼 Trabajar'), findsNothing,
        reason: 'al empezar la jornada se quita la pregunta de bienvenida');
    await tester.pump(const Duration(seconds: 7));
    workday.skipPhase(); // enfoque -> descanso corto
    await tester.pump();
    expect(find.textContaining('Vamos a descansar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.textContaining(WellnessTip.short.first.text), findsOneWidget);
    workday.finish();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('desactivado, no hay consejo; en modo juego tampoco',
      (tester) async {
    final c = await launch(tester, tips: false);
    final workday = c.read(workdayControllerProvider.notifier);
    workday.start(const WorkdayConfig());
    await tester.pump(const Duration(seconds: 7));
    workday.skipPhase();
    await tester.pump(const Duration(seconds: 8));
    for (final t in WellnessTip.values) {
      expect(find.textContaining(t.text), findsNothing);
    }
    workday.finish();
    await tester.pump(const Duration(seconds: 7));

    await c.read(mascotSettingsProvider).setWellnessTips(true);
    workday.start(WorkdayConfig.gaming, mode: ActivityMode.gaming);
    await tester.pump(const Duration(seconds: 7));
    workday.skipPhase();
    await tester.pump(const Duration(seconds: 8));
    for (final t in WellnessTip.values) {
      expect(find.textContaining(t.text), findsNothing);
    }
    workday.finish();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });
}
