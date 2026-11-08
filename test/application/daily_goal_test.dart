import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/goals/daily_goal.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/stats/daily_goal_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkdayRecord todayRecord(String id, int focusMin) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 0, 1);
  return WorkdayRecord(
    id: id,
    mode: ActivityMode.work,
    startedAt: start.toUtc(),
    endedAt: start.add(Duration(minutes: focusMin)).toUtc(),
    planned: const Duration(hours: 8),
    effectiveFocus: Duration(minutes: focusMin),
    effectiveBreak: Duration.zero,
    focusBlocksCompleted: 0,
    cyclesCompleted: 0,
    completed: false,
  );
}

void main() {
  const h = Duration(hours: 1);

  group('estado de la meta', () {
    test('fracción, faltante y cumplida', () {
      final s = DailyGoalStatus(done: Duration(minutes: 90), goal: h * 4);
      expect(s.fraction, closeTo(90 / 240, 1e-9));
      expect(s.remaining, const Duration(minutes: 150));
      expect(s.reached, isFalse);
      final done = DailyGoalStatus(done: h * 5, goal: h * 4);
      expect(done.fraction, 1);
      expect(done.remaining, Duration.zero);
      expect(done.reached, isTrue);
    });

    test('solo se celebra al cruzar la meta avanzando', () {
      final before = DailyGoalStatus(done: Duration(minutes: 239), goal: h * 4);
      final after = DailyGoalStatus(done: h * 4, goal: h * 4);
      expect(goalJustReached(before, after), isTrue);
      expect(goalJustReached(null, after), isFalse, reason: 'al abrir la app');
      expect(goalJustReached(after, after), isFalse, reason: 'ya cumplida');
      // Bajar la meta por debajo de lo hecho no cuenta como "cumplirla".
      final lowered =
          DailyGoalStatus(done: Duration(minutes: 239), goal: h * 2);
      expect(goalJustReached(before, lowered), isFalse);
      expect(goalReachedMessage(h * 4), contains('4 h'));
      expect(goalReachedMessage(const Duration(minutes: 90)),
          contains('1 h 30 min'));
    });

    test('la meta se guarda; por defecto 4 h; 0 la desactiva', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(DailyGoalSettings(prefs).goal, h * 4);
      await DailyGoalSettings(prefs).setGoal(h * 2);
      expect(DailyGoalSettings(prefs).goal, h * 2);
      await DailyGoalSettings(prefs).setGoal(Duration.zero);
      expect(DailyGoalSettings(prefs).enabled, isFalse);
    });
  });

  test('el proveedor suma lo de hoy y sigue a la preferencia', () async {
    final store = SqliteWorkdayStore.inMemory();
    store.completeActive(todayRecord('a', 100));
    final settings = DailyGoalSettings();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(store),
      dailyGoalSettingsProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);

    var status = container.read(dailyGoalProvider)!;
    expect(status.done, const Duration(minutes: 100));
    expect(status.goal, h * 4);

    final seen = <bool>[];
    container.listen<DailyGoalStatus?>(
        dailyGoalProvider, (b, a) => seen.add(goalJustReached(b, a)));
    await settings.setGoal(Duration.zero);
    expect(container.read(dailyGoalProvider), isNull);
    await settings.setGoal(const Duration(minutes: 90));
    expect(container.read(dailyGoalProvider)!.reached, isTrue);
    expect(seen, everyElement(isFalse), reason: 'cambiar la meta no celebra');
  });

  testWidgets('la fila muestra lo que falta y cambia la meta', (tester) async {
    final chosen = <Duration>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyGoalRow(
          status: DailyGoalStatus(done: Duration(minutes: 90), goal: h * 4),
          goal: h * 4,
          onGoalChanged: chosen.add,
        ),
      ),
    ));
    expect(find.text('🎯 Faltan 2 h 30 min para tu meta'), findsOneWidget);
    expect(find.text('Meta: 4 h ▾'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 h al día').last);
    await tester.pumpAndSettle();
    expect(chosen, [h * 2]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyGoalRow(
            status: null, goal: Duration.zero, onGoalChanged: chosen.add),
      ),
    ));
    expect(find.text('Sin meta diaria'), findsOneWidget);
    expect(find.text('Poner meta ▾'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
