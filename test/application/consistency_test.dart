import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/stats/consistency.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/presentation/stats/consistency_row.dart';

DateTime d(int day) => DateTime(2026, 11, day);

WorkdayRecord rec(int day, [int hour = 10]) => WorkdayRecord(
      id: 'r$day-$hour',
      mode: ActivityMode.work,
      startedAt: DateTime(2026, 11, day, hour).toUtc(),
      endedAt: DateTime(2026, 11, day, hour + 1).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: const Duration(minutes: 30),
      effectiveBreak: Duration.zero,
      focusBlocksCompleted: 0,
      cyclesCompleted: 0,
      completed: false,
    );

void main() {
  group('racha amable', () {
    test('cuenta días con sesión en los últimos 7 (hoy incluido)', () {
      final days = activeDaySet([rec(2), rec(3), rec(3, 15), rec(5), rec(8)]);
      final c = consistencyAt(days, DateTime(2026, 11, 8, 20));
      expect(c.today, d(8));
      expect(c.days, [true, true, false, true, false, false, true],
          reason: 'del 2 al 8 de noviembre');
      expect(c.active, 4);
      expect(c.window, 7);
      // Una sesión de hace 8 días ya no cuenta.
      expect(consistencyAt(days, DateTime(2026, 11, 9, 9)).active, 3);
    });

    test('descansar no rompe nada: la ventana solo avanza', () {
      final days = activeDaySet([
        for (final i in [1, 2, 3, 4, 5]) rec(i)
      ]);
      expect(consistencyAt(days, d(7)).active, 5);
      expect(consistencyAt(days, d(8)).active, 4);
    });

    test('logro "Buen ritmo": 5 de 7 días en algún tramo', () {
      final no = activeDaySet([rec(1), rec(3), rec(5), rec(7), rec(9)]);
      expect(hasSteadyWindow(no), isFalse, reason: 'cada dos días: 4 de 7');
      final yes = activeDaySet([rec(1), rec(2), rec(4), rec(6), rec(7)]);
      expect(hasSteadyWindow(yes), isTrue);
      final progress =
          computeProgress([rec(1), rec(2), rec(4), rec(6), rec(7)]);
      expect(progress.unlocked, contains('steady'));
      expect(achievements.map((a) => a.id), contains('steady'));
    });

    test('se celebra al llegar a 5 y a 7, subiendo y el mismo día', () {
      Consistency c(int active, [int day = 8]) =>
          Consistency([for (var i = 0; i < 7; i++) i >= 7 - active], d(day));
      expect(consistencyMilestone(c(4), c(5)), contains('5 de los últimos 7'));
      expect(consistencyMilestone(c(6), c(7)), contains('7 de los últimos 7'));
      expect(consistencyMilestone(null, c(5)), isNull,
          reason: 'al abrir la app no se celebra');
      expect(consistencyMilestone(c(5), c(5)), isNull);
      expect(consistencyMilestone(c(6), c(5)), isNull, reason: 'bajando no');
      expect(consistencyMilestone(c(4, 7), c(5, 8)), isNull,
          reason: 'cambio de día: la ventana se movió, no hubo logro');
      expect(consistencyMilestone(c(5), c(6)), isNull);
    });
  });

  testWidgets('la fila muestra el texto y un punto por día', (tester) async {
    final days = activeDaySet([rec(2), rec(3), rec(5), rec(8)]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ConsistencyRow(consistency: consistencyAt(days, d(8)))),
    ));
    expect(find.text('🌱 4 de los últimos 7 días'), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(7));
    expect(find.byTooltip('Domingo 8 nov: con sesión'), findsOneWidget);
    expect(find.byTooltip('Viernes 6 nov: sin sesión'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home:
          Scaffold(body: ConsistencyRow(consistency: consistencyAt({}, d(8)))),
    ));
    expect(find.text('🌱 Sin sesiones en los últimos 7 días'), findsOneWidget);
  });
}
