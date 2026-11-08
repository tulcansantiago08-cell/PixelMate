import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_dialogue.dart';
import 'package:pixelmate/application/workday/workday_event.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/session/workday_timer.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 9, 8);
  late DateTime now;
  late SqliteWorkdayStore store;
  late List<WorkdayEvent> events;

  void advance(int minutes, {int seconds = 0}) =>
      now = now.add(Duration(minutes: minutes, seconds: seconds));

  WorkdayController makeController() {
    final c = WorkdayController(
      store: store,
      now: () => now,
      newId: () => 'j1',
      tickInterval: const Duration(days: 1), // las pruebas llaman a refresh()
    );
    c.events.listen(events.add);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    now = t0;
    store = SqliteWorkdayStore.inMemory();
    events = [];
  });

  test('iniciar crea la jornada, la guarda y avisa', () async {
    final c = makeController();
    c.start(const WorkdayConfig(), mode: ActivityMode.study);
    await pumpEventQueue();

    expect(c.state.isActive, isTrue);
    expect(c.state.mode, ActivityMode.study);
    expect(c.state.status!.phase!.kind, SessionPhase.focus);
    expect(store.loadActive()!.timer.id, 'j1');
    expect(events.whereType<WorkdayStarted>(), hasLength(1));
  });

  test('no permite dos jornadas a la vez', () {
    final c = makeController();
    c.start(const WorkdayConfig());
    expect(() => c.start(const WorkdayConfig()), throwsStateError);
  });

  test('avisa a 5 min y a 30 s del fin del enfoque, una sola vez', () async {
    final c = makeController()..start(const WorkdayConfig());
    advance(44);
    c.refresh();
    advance(1);
    c.refresh();
    c.refresh();
    advance(4, seconds: 30);
    c.refresh();
    c.refresh();
    await pumpEventQueue();

    final warnings = events.whereType<FocusEndingSoon>().toList();
    expect(warnings.map((w) => w.threshold), [
      const Duration(minutes: 5),
      const Duration(seconds: 30),
    ]);
  });

  test('si se cruzan dos umbrales a la vez solo avisa el más cercano',
      () async {
    final c = makeController()..start(const WorkdayConfig());
    advance(49, seconds: 45); // p. ej. el Mac estuvo en reposo
    c.refresh();
    c.refresh();
    await pumpEventQueue();
    expect(events.whereType<FocusEndingSoon>().map((w) => w.threshold),
        [const Duration(seconds: 30)]);
  });

  test('emite el cambio de fase al entrar al descanso', () async {
    final c = makeController()..start(const WorkdayConfig());
    advance(50);
    c.refresh();
    await pumpEventQueue();
    final change = events.whereType<PhaseStarted>().single;
    expect(change.phase.kind, SessionPhase.shortBreak);
    expect(reactionFor(change)!.message, contains('descansar'));
  });

  test('pausar y reanudar se guardan y emiten un aviso cada uno', () async {
    final c = makeController()..start(const WorkdayConfig());
    advance(10);
    c.pause();
    c.pause();
    expect(store.loadActive()!.timer.pausedAt, isNotNull);
    advance(10);
    c.resume();
    await pumpEventQueue();
    expect(events.whereType<WorkdayPaused>(), hasLength(1));
    expect(events.whereType<WorkdayResumed>(), hasLength(1));
    expect(c.state.status!.position, const Duration(minutes: 10));
  });

  test('finalizar registra el historial y deja la mascota libre', () async {
    final c = makeController()..start(const WorkdayConfig());
    advance(30);
    c.finish();
    await pumpEventQueue();

    expect(c.state.isActive, isFalse);
    expect(store.loadActive(), isNull);
    expect(store.history().single.completed, isFalse);
    final done = events.whereType<WorkdayFinished>().single;
    expect(done.status.completedNaturally, isFalse);
  });

  test('al cumplir la jornada se registra como completada', () async {
    final c = makeController()
      ..start(const WorkdayConfig(workday: Duration(minutes: 60)));
    advance(56);
    c.refresh();
    advance(4);
    c.refresh();
    await pumpEventQueue();
    expect(c.state.isActive, isFalse);
    expect(store.history().single.completed, isTrue);
    expect(events.whereType<WorkdayEndingSoon>(), isNotEmpty);
  });

  group('recuperación al abrir la app', () {
    test('retoma la jornada guardada sin repetir avisos pasados', () async {
      makeController().start(const WorkdayConfig());
      await pumpEventQueue();
      events.clear();

      advance(77); // la app estuvo cerrada; ahora en el 2.º enfoque, faltan 33
      final reopened = makeController();
      reopened.refresh();
      await pumpEventQueue();

      expect(reopened.state.isActive, isTrue);
      expect(reopened.state.status!.phase!.index, 2);
      expect(events, isEmpty);
    });

    test('si terminó mientras estaba cerrada, la registra al abrir', () async {
      makeController().start(const WorkdayConfig(workday: Duration(hours: 1)));
      advance(300);
      final reopened = makeController();
      await pumpEventQueue();
      expect(reopened.state.isActive, isFalse);
      expect(store.history().single.completed, isTrue);
    });

    test('una jornada en pausa sigue en pausa', () {
      makeController()
        ..start(const WorkdayConfig())
        ..pause();
      advance(500);
      final reopened = makeController();
      expect(reopened.state.status!.state, WorkdayRunState.paused);
    });
  });

  test('cada suceso tiene una reacción o se ignora sin fallar', () {
    final c = makeController()..start(const WorkdayConfig());
    final phase = c.state.timer!.plan[1];
    for (final e in <WorkdayEvent>[
      const WorkdayStarted(),
      PhaseStarted(phase, null),
      FocusEndingSoon(phase, const Duration(minutes: 5)),
      const WorkdayEndingSoon(Duration(minutes: 30)),
      const WorkdayPaused(),
      const WorkdayResumed(),
      WorkdayFinished(c.state.status!),
    ]) {
      expect(() => reactionFor(e), returnsNormally);
    }
  });
}
