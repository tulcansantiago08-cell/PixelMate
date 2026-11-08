import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/stats/activity_stats.dart';
import 'package:pixelmate/application/stats/stats_providers.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/stats/stats_panel.dart';
import 'package:pixelmate/presentation/stats/stats_style.dart';

WorkdayRecord rec(
  String id,
  ActivityMode mode,
  DateTime localStart, {
  int focusMin = 60,
  int breakMin = 10,
  bool completed = true,
  int cycles = 0,
}) =>
    WorkdayRecord(
      id: id,
      mode: mode,
      startedAt: localStart.toUtc(),
      endedAt: localStart.add(Duration(minutes: focusMin + breakMin)).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: Duration(minutes: focusMin),
      effectiveBreak: Duration(minutes: breakMin),
      focusBlocksCompleted: 1,
      cyclesCompleted: cycles,
      completed: completed,
    );

void main() {
  // Miércoles 11 de noviembre de 2026, 15:00 hora local.
  final now = DateTime(2026, 11, 11, 15);

  final history = [
    rec('hoy-trabajo', ActivityMode.work, DateTime(2026, 11, 11, 9),
        focusMin: 150, cycles: 1),
    rec('hoy-juego', ActivityMode.gaming, DateTime(2026, 11, 11, 13),
        focusMin: 60, breakMin: 5, completed: false),
    rec('lunes-estudio', ActivityMode.study, DateTime(2026, 11, 9, 18),
        focusMin: 90),
    rec('domingo-pasado', ActivityMode.work, DateTime(2026, 11, 8, 10)),
    rec('octubre', ActivityMode.work, DateTime(2026, 10, 30, 10)),
  ];

  group('límites de periodo', () {
    test('la semana empieza el lunes', () {
      expect(periodStart(StatsPeriod.week, now), DateTime(2026, 11, 9));
      expect(periodStart(StatsPeriod.week, DateTime(2026, 11, 15, 23)),
          DateTime(2026, 11, 9));
      expect(periodStart(StatsPeriod.week, DateTime(2026, 11, 16)),
          DateTime(2026, 11, 16));
    });

    test('el mes y el día', () {
      expect(periodStart(StatsPeriod.month, now), DateTime(2026, 11));
      expect(periodEnd(StatsPeriod.month, DateTime(2026, 12)), DateTime(2027));
      expect(periodStart(StatsPeriod.today, now), DateTime(2026, 11, 11));
    });
  });

  group('cálculo', () {
    test('hoy separa trabajo, estudio y juego', () {
      final s =
          computeStats(period: StatsPeriod.today, now: now, history: history);
      expect(s.sessions.map((r) => r.id), ['hoy-juego', 'hoy-trabajo']);
      expect(s.totals(ActivityMode.work).focus, const Duration(minutes: 150));
      expect(s.totals(ActivityMode.work).cycles, 1);
      expect(s.totals(ActivityMode.gaming).focus, const Duration(minutes: 60));
      expect(s.totals(ActivityMode.gaming).completed, 0);
      expect(s.totals(ActivityMode.study).sessions, 0);
      expect(s.totalFocus, const Duration(minutes: 210));
      expect(s.days, isEmpty);
    });

    test('la semana tiene 7 días y cuenta los días activos', () {
      final s =
          computeStats(period: StatsPeriod.week, now: now, history: history);
      expect(s.days, hasLength(7));
      expect(s.days.first.day, DateTime(2026, 11, 9));
      expect(s.activeDays, 2); // lunes y miércoles
      expect(s.days[0].focusByMode[ActivityMode.study],
          const Duration(minutes: 90));
      expect(s.days[2].total, const Duration(minutes: 210));
      expect(s.sessions.map((r) => r.id), isNot(contains('domingo-pasado')));
    });

    test('el mes excluye otros meses', () {
      final s =
          computeStats(period: StatsPeriod.month, now: now, history: history);
      expect(s.days, hasLength(30));
      expect(s.sessions, hasLength(4));
      expect(s.sessions.map((r) => r.id), isNot(contains('octubre')));
    });

    test('la sesión en curso cuenta en tiempo real', () {
      final live = rec('live', ActivityMode.work, DateTime(2026, 11, 11, 14),
          focusMin: 40, completed: false);
      final s = computeStats(
          period: StatsPeriod.today, now: now, history: history, live: live);
      expect(s.totals(ActivityMode.work).focus, const Duration(minutes: 190));
      expect(s.sessions.first.id, 'live');
    });

    test('sin datos', () {
      final s =
          computeStats(period: StatsPeriod.week, now: now, history: const []);
      expect(s.isEmpty, isTrue);
      expect(s.activeDays, 0);
      expect(s.totalFocus, Duration.zero);
    });
  });

  test('formato de tiempo dedicado (redondea hacia abajo)', () {
    expect(formatSpent(Duration.zero), '0 min');
    expect(formatSpent(const Duration(seconds: 40)), '<1 min');
    expect(formatSpent(const Duration(minutes: 59, seconds: 59)), '59 min');
    expect(formatSpent(const Duration(hours: 2, minutes: 10)), '2 h 10 min');
    expect(formatSpent(const Duration(hours: 3)), '3 h');
    expect(sessionWhen(DateTime(2026, 11, 11, 9, 5), now), 'Hoy 09:05');
    expect(sessionWhen(DateTime(2026, 11, 10, 18, 40), now), 'Ayer 18:40');
    expect(sessionWhen(DateTime(2026, 11, 2, 7, 0), now), '2 nov 07:00');
  });

  test('la barra de menú tiene acceso a estadísticas', () {
    expect(
        trayEntries(WorkdayView.none, mascotVisible: true).map((e) => e.action),
        contains(TrayAction.showStats));
  });

  testWidgets('el panel muestra los totales y cambia de periodo',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = SqliteWorkdayStore.inMemory();
    final today = DateTime.now();
    store.completeActive(rec('a', ActivityMode.work,
        DateTime(today.year, today.month, today.day, 0, 1),
        focusMin: 125));
    var closed = false;

    await tester.pumpWidget(ProviderScope(
      overrides: [workdayStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(body: StatsPanel(onClose: () => closed = true)),
      ),
    ));

    expect(find.text('2 h 5 min'), findsWidgets);
    expect(find.text('Trabajo'), findsOneWidget);
    expect(find.text('Estudio'), findsOneWidget);
    expect(find.text('Juego'), findsOneWidget);
    expect(find.textContaining('✓ completa'), findsOneWidget);
    expect(find.textContaining('máx.'), findsNothing); // "Hoy" no tiene gráfico

    await tester.tap(find.text('Semana'));
    await tester.pump();
    expect(find.textContaining('máx. 3 h'), findsOneWidget);
    expect(find.textContaining('1 día activo'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    expect(closed, isTrue);

    // El periodo elegido es estado compartido (se recuerda al reabrir).
    final container =
        ProviderScope.containerOf(tester.element(find.byType(StatsPanel)));
    expect(container.read(statsPeriodProvider), StatsPeriod.week);
  });
}
