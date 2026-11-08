import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/chat_controller.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/goals/daily_goal.dart';
import 'package:pixelmate/application/stats/weekly_report.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:pixelmate/presentation/stats/weekly_report_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lunes 2 de noviembre de 2026.
final monday = DateTime(2026, 11, 2);

WorkdayRecord rec(String id, DateTime start, int focusMin,
        {ActivityMode mode = ActivityMode.work, bool completed = false}) =>
    WorkdayRecord(
      id: id,
      mode: mode,
      startedAt: start.toUtc(),
      endedAt: start.add(Duration(minutes: focusMin)).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: Duration(minutes: focusMin),
      effectiveBreak: Duration.zero,
      focusBlocksCompleted: 0,
      cyclesCompleted: 0,
      completed: completed,
    );

final history = [
  // Semana anterior (26 oct – 1 nov): 2 h.
  rec('p', DateTime(2026, 10, 28, 10), 120),
  // Esta semana (2–8 nov): 1 h lunes, 3 h miércoles (2 trabajo + 1
  // estudio), 30 min sábado.
  rec('a', DateTime(2026, 11, 2, 9), 60),
  rec('b', DateTime(2026, 11, 4, 9), 120, completed: true),
  rec('c', DateTime(2026, 11, 4, 15), 60, mode: ActivityMode.study),
  rec('d', DateTime(2026, 11, 7, 11), 30),
];

class _LocalAi extends ChatAssistant {
  int calls = 0;
  String? prompt;
  @override
  String get label => 'IA';
  @override
  bool get supportsImages => false;
  @override
  bool get supportsActions => false;
  @override
  bool get onDevice => true;
  @override
  Future<AssistantReply> reply(String message,
      {required String context, String? imageBase64}) async {
    calls++;
    prompt = message;
    return const AssistantReply('¡Gran semana! El miércoles brillaste.');
  }

  @override
  Future<void> reset() async {}
}

void main() {
  group('cálculo', () {
    test('totales, días activos, metas, XP y comparación', () {
      final r = buildWeeklyReport(
          history: history, weekStart: monday, goal: const Duration(hours: 1));
      expect(r.focus, const Duration(hours: 4, minutes: 30));
      expect(r.previousFocus, const Duration(hours: 2));
      expect(r.change, const Duration(hours: 2, minutes: 30));
      expect(r.activeDays, 3);
      expect(r.sessions, 4);
      expect(r.completed, 1);
      expect(r.goalDays, 2, reason: 'lunes (1 h) y miércoles (3 h)');
      expect(r.bestDay!.day, DateTime(2026, 11, 4));
      expect(r.xp, 60 + 120 + 25 + 60 + 30);
      expect(r.end, DateTime(2026, 11, 8));
      expect(weekRange(r.start, r.end), '2–8 nov');
      expect(weekRange(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
          '28 sep – 4 oct');
    });

    test('sin meta no cuenta días cumplidos; sin sesiones está vacío', () {
      expect(
          buildWeeklyReport(history: history, weekStart: monday).goal, isNull);
      expect(
          buildWeeklyReport(
                  history: history,
                  weekStart: DateTime(2026, 11, 9),
                  goal: Duration.zero)
              .isEmpty,
          isTrue);
    });

    test('el pedido a la IA lleva los números de la semana', () {
      final p = weeklyPrompt(buildWeeklyReport(
          history: history, weekStart: monday, goal: const Duration(hours: 1)));
      expect(p, contains('4 h 30 min de enfoque'));
      expect(p, contains('trabajo 3 h 30 min, estudio 1 h'));
      expect(p, contains('en 3 días y 4 sesiones'));
      expect(p, contains('2 h 30 min más que la semana anterior'));
      expect(p, contains('Cumplí mi meta diaria de 1 h 2 días'));
      expect(p, contains('No elijas ninguna acción'));
    });
  });

  group('cuándo se muestra', () {
    test('lunes a sábado: la semana anterior; domingo tarde: la actual', () {
      expect(weekToReport(DateTime(2026, 11, 9, 9)), monday,
          reason: 'lunes 9: resume la del 2');
      expect(weekToReport(DateTime(2026, 11, 14, 20)), monday,
          reason: 'sábado: aún la anterior');
      expect(weekToReport(DateTime(2026, 11, 8, 17)), DateTime(2026, 10, 26),
          reason: 'domingo antes de las 18');
      expect(weekToReport(DateTime(2026, 11, 8, 18)), monday,
          reason: 'domingo desde las 18: la semana que termina');
    });

    test('nunca dos veces la misma (se recuerda)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WeeklyReportStore(prefs);
      await store.markShown(monday);
      expect(
          weekToReport(DateTime(2026, 11, 8, 19),
              lastShown: WeeklyReportStore(prefs).lastShown),
          isNull,
          reason: 'mostrada el domingo');
      expect(
          weekToReport(DateTime(2026, 11, 9, 9),
              lastShown: WeeklyReportStore(prefs).lastShown),
          isNull,
          reason: 'el lunes no se repite');
      expect(
          weekToReport(DateTime(2026, 11, 16, 9),
              lastShown: WeeklyReportStore(prefs).lastShown),
          DateTime(2026, 11, 9));
    });
  });

  test('el comentario de la IA se genera una vez y se guarda', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final ai = _LocalAi();
    final store = SqliteWorkdayStore.inMemory();
    for (final r in history) {
      store.completeActive(r);
    }
    final c = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(store),
      weeklyReportStoreProvider.overrideWithValue(WeeklyReportStore(prefs)),
      assistantChoiceProvider.overrideWith((_) async => AssistantChoice(ai)),
    ]);
    addTearDown(c.dispose);
    final report = buildWeeklyReport(history: history, weekStart: monday);
    final notifier = c.read(chatProvider.notifier);
    expect(await notifier.commentWeek(report),
        '¡Gran semana! El miércoles brillaste.');
    expect(await notifier.commentWeek(report),
        '¡Gran semana! El miércoles brillaste.');
    expect(ai.calls, 1);
    expect(WeeklyReportStore(prefs).comment(report), isNotNull);

    // Con más sesiones esa semana, el comentario se vuelve a generar.
    final more = buildWeeklyReport(history: [
      ...history,
      rec('e', DateTime(2026, 11, 8, 10), 45),
    ], weekStart: monday);
    await notifier.commentWeek(more);
    expect(ai.calls, 2);
  });

  testWidgets('el panel muestra la semana y el comentario', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SqliteWorkdayStore.inMemory();
    for (final r in history) {
      store.completeActive(r);
    }
    final goal = DailyGoalSettings();
    await goal.setGoal(const Duration(hours: 1));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(store),
        dailyGoalSettingsProvider.overrideWithValue(goal),
        assistantChoiceProvider
            .overrideWith((_) async => AssistantChoice(_LocalAi())),
        weeklyReportWeekProvider.overrideWith((_) => monday),
      ],
      child:
          MaterialApp(home: Scaffold(body: WeeklyReportPanel(onClose: () {}))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('semana · 2–8 nov'), findsOneWidget);
    // Navegar entre semanas.
    await tester.tap(find.byKey(const ValueKey('weekly-prev')));
    await tester.pumpAndSettle();
    expect(find.text('📅 Tu semana · 26 oct – 1 nov'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('weekly-next')));
    await tester.pumpAndSettle();
    expect(find.text('4 h 30 min'), findsOneWidget);
    expect(find.textContaining('▲ 2 h 30 min más que la anterior'),
        findsOneWidget);
    expect(find.textContaining('3 de 7 días activos'), findsOneWidget);
    expect(find.textContaining('4 sesiones · 1 completa'), findsOneWidget);
    expect(find.textContaining('Meta cumplida 2 de 7 días'), findsOneWidget);
    expect(find.textContaining('Mejor día: Miércoles 4 nov'), findsOneWidget);
    expect(find.textContaining('El miércoles brillaste'), findsOneWidget);
  });

  testWidgets('una semana sin sesiones lo dice', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        weeklyReportWeekProvider.overrideWith((_) => monday),
      ],
      child:
          MaterialApp(home: Scaffold(body: WeeklyReportPanel(onClose: () {}))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('no hubo sesiones'), findsOneWidget);
  });

  testWidgets('se abre solo al empezar la semana, y solo una vez',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final week = latestReportableWeek(DateTime.now());
    final store = SqliteWorkdayStore.inMemory()
      ..completeActive(
          rec('w', DateTime(week.year, week.month, week.day + 1, 10), 90));
    final weekly = WeeklyReportStore(prefs);

    Future<void> launch() async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          workdayStoreProvider.overrideWithValue(store),
          detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
          mascotWindowProvider.overrideWithValue(NoopMascotWindow()),
          weeklyReportStoreProvider.overrideWithValue(weekly),
        ],
        child: const MaterialApp(home: MascotWindow()),
      ));
      await tester.pump(const Duration(seconds: 3));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await launch();
    expect(find.byType(WeeklyReportPanel), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(weekly.lastShown, weekKey(week));

    await launch();
    expect(find.byType(WeeklyReportPanel), findsNothing,
        reason: 'ya se mostró esta semana');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('esta semana: no se puede ir al futuro', (tester) async {
    final thisWeek = weekStartOf(DateTime.now());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        weeklyReportWeekProvider.overrideWith((_) => thisWeek),
      ],
      child:
          MaterialApp(home: Scaffold(body: WeeklyReportPanel(onClose: () {}))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('📅 Esta semana'), findsOneWidget);
    final next = tester.widget<IconButton>(find.descendant(
        of: find.byKey(const ValueKey('weekly-next')),
        matching: find.byType(IconButton)));
    expect(next.onPressed, isNull);
  });
}
