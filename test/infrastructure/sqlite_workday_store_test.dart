import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/session/workday_timer.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 9, 8);
  DateTime at(int m) => t0.add(Duration(minutes: m));

  WorkdayTimer timer() =>
      WorkdayTimer.start(id: 'j1', config: const WorkdayConfig(), now: t0);

  test('sin jornada activa devuelve null', () {
    expect(SqliteWorkdayStore.inMemory().loadActive(), isNull);
  });

  test('guarda y recupera la jornada activa con pausas y saltos', () {
    final store = SqliteWorkdayStore.inMemory();
    final t = timer().pause(at(10)).resume(at(20)).skipPhase(at(30));
    store.saveActive(ActiveWorkday(ActivityMode.study, t));

    final loaded = store.loadActive()!;
    expect(loaded.mode, ActivityMode.study);
    expect(loaded.timer.statusAt(at(100)).position,
        t.statusAt(at(100)).position);
  });

  test('solo existe una jornada activa', () {
    final store = SqliteWorkdayStore.inMemory();
    store.saveActive(ActiveWorkday(ActivityMode.work, timer()));
    store.saveActive(ActiveWorkday(ActivityMode.work, timer().pause(at(5))));
    expect(store.loadActive()!.timer.pausedAt, at(5));
  });

  test('completar guarda el historial y borra la activa', () {
    final store = SqliteWorkdayStore.inMemory();
    final t = timer().finish(at(100));
    store.saveActive(ActiveWorkday(ActivityMode.work, t));
    store.completeActive(WorkdayRecord.fromTimer(ActivityMode.work, t, at(100)));

    expect(store.loadActive(), isNull);
    final history = store.history();
    expect(history, hasLength(1));
    final r = history.single;
    expect(r.id, 'j1');
    expect(r.completed, isFalse);
    expect(r.effectiveFocus, const Duration(minutes: 90));
    expect(r.endedAt, at(100));
    expect(r.planned, const Duration(hours: 8));
  });

  test('una jornada completa registra la hora real de fin', () {
    final t = timer().pause(at(10)).resume(at(25));
    final r = WorkdayRecord.fromTimer(ActivityMode.work, t, at(600));
    expect(r.completed, isTrue);
    expect(r.endedAt, at(495)); // 480 de plan + 15 de pausa
  });

  test('history filtra por fecha', () {
    final store = SqliteWorkdayStore.inMemory();
    for (final (id, day) in [('a', 1), ('b', 5)]) {
      final t = WorkdayTimer.start(
              id: id,
              config: const WorkdayConfig(),
              now: DateTime.utc(2026, 11, day, 8))
          .finish(DateTime.utc(2026, 11, day, 9));
      store.completeActive(WorkdayRecord.fromTimer(
          ActivityMode.work, t, DateTime.utc(2026, 11, day, 9)));
    }
    expect(store.history(since: DateTime.utc(2026, 11, 3)).map((r) => r.id),
        ['b']);
  });

  test('una jornada activa dañada se descarta sin romper la app', () {
    final db = sqlite3.openInMemory();
    final store = SqliteWorkdayStore(db);
    db.execute(
        "INSERT INTO active_workday (slot, mode, timer_json) VALUES (1, 'work', '{roto')");
    expect(store.loadActive(), isNull);
    expect(store.loadActive(), isNull);
  });

  test('los datos persisten al cerrar y reabrir el archivo', () {
    final dir = Directory.systemTemp.createTempSync('pixelmate_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/pixelmate.db';

    final first = SqliteWorkdayStore.open(path);
    first.saveActive(ActiveWorkday(ActivityMode.work, timer()));
    first.close();

    final second = SqliteWorkdayStore.open(path);
    expect(second.loadActive()!.timer.id, 'j1');
    second.close();
  });
}
