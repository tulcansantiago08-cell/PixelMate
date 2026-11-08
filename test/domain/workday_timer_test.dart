import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/session/workday_timer.dart';

Duration min(int m) => Duration(minutes: m);

void main() {
  final t0 = DateTime.utc(2026, 11, 9, 8, 0);
  DateTime at(int minutes) => t0.add(min(minutes));

  WorkdayTimer start([WorkdayConfig config = const WorkdayConfig()]) =>
      WorkdayTimer.start(id: 'j1', config: config, now: t0);

  group('transiciones de enfoque y descanso', () {
    test('al iniciar está en el primer enfoque', () {
      final s = start().statusAt(t0);
      expect(s.state, WorkdayRunState.running);
      expect(s.phase!.kind, SessionPhase.focus);
      expect(s.phaseRemaining, min(50));
      expect(s.nextBreakIn, min(50));
      expect(s.workdayRemaining, const Duration(hours: 8));
    });

    test('a los 50 min empieza el descanso corto', () {
      final s = start().statusAt(at(50));
      expect(s.phase!.kind, SessionPhase.shortBreak);
      expect(s.focusBlocksCompleted, 1);
      expect(s.nextBreakIn, isNull);
    });

    test('a los 170 min empieza el descanso largo y a los 200 un ciclo nuevo',
        () {
      final timer = start();
      expect(timer.statusAt(at(170)).phase!.kind, SessionPhase.longBreak);
      expect(timer.statusAt(at(199)).cyclesCompleted, 0);
      final s = timer.statusAt(at(200));
      expect(s.phase!.kind, SessionPhase.focus);
      expect(s.phase!.cycle, 2);
      expect(s.cyclesCompleted, 1);
      expect(s.focusBlocksCompleted, 3);
    });

    test('el tiempo restante de la jornada incluye los descansos', () {
      final s = start().statusAt(at(60));
      expect(s.workdayRemaining, min(420));
      expect(s.progress, closeTo(60 / 480, 1e-9));
    });

    test('termina sola al cumplir la jornada', () {
      final s = start().statusAt(at(480));
      expect(s.state, WorkdayRunState.finished);
      expect(s.completedNaturally, isTrue);
      expect(s.phase, isNull);
      expect(s.workdayRemaining, Duration.zero);
      // 8 h: 7 enfoques de 50 + uno recortado de 20 = 370 min
      expect(s.effectiveFocus, min(370));
      expect(s.effectiveBreak, min(110));
      expect(s.focusBlocksCompleted, 8);
      expect(s.cyclesCompleted, 2);
    });

    test('mucho después del final sigue terminada y sin pasarse', () {
      final s = start().statusAt(at(2000));
      expect(s.position, const Duration(hours: 8));
      expect(s.progress, 1.0);
    });
  });

  group('pausas y reanudaciones', () {
    test('en pausa el tiempo no avanza', () {
      final timer = start().pause(at(20));
      final s = timer.statusAt(at(45));
      expect(s.state, WorkdayRunState.paused);
      expect(s.phaseElapsed, min(20));
    });

    test('al reanudar, la pausa alarga la jornada', () {
      final timer = start().pause(at(20)).resume(at(35));
      expect(timer.statusAt(at(64)).phase!.kind, SessionPhase.focus);
      expect(timer.statusAt(at(65)).phase!.kind, SessionPhase.shortBreak);
      expect(timer.statusAt(at(480)).state, WorkdayRunState.running);
      expect(timer.statusAt(at(495)).state, WorkdayRunState.finished);
    });

    test('varias pausas se acumulan', () {
      final timer = start()
          .pause(at(10))
          .resume(at(15))
          .pause(at(30))
          .resume(at(40));
      expect(timer.statusAt(at(40)).position, min(25));
    });

    test('pausar dos veces o reanudar sin pausa no cambia nada', () {
      final timer = start().pause(at(10)).pause(at(20));
      expect(timer.pausedAt, at(10));
      final running = start();
      expect(identical(running.resume(at(5)), running), isTrue);
    });

    test('si el reloj del sistema retrocede no hay tiempo negativo', () {
      final timer = start();
      expect(timer.statusAt(t0.subtract(min(30))).position, Duration.zero);
    });
  });

  group('saltar y finalizar', () {
    test('saltar el enfoque pasa al descanso y no cuenta como efectivo', () {
      final timer = start().skipPhase(at(30));
      final s = timer.statusAt(at(30));
      expect(s.phase!.kind, SessionPhase.shortBreak);
      expect(s.phaseRemaining, min(10));
      expect(s.effectiveFocus, min(30));
      expect(s.focusBlocksCompleted, 0);
    });

    test('saltar adelanta el final de la jornada', () {
      final timer = start().skipPhase(at(30)); // salta 20 min
      expect(timer.statusAt(at(459)).state, WorkdayRunState.running);
      expect(timer.statusAt(at(460)).state, WorkdayRunState.finished);
    });

    test('saltar un descanso estando en pausa sigue en pausa en el enfoque',
        () {
      final timer = start().pause(at(55)).skipPhase(at(58));
      final s = timer.statusAt(at(90));
      expect(s.state, WorkdayRunState.paused);
      expect(s.phase!.kind, SessionPhase.focus);
      expect(s.phaseElapsed, Duration.zero);
    });

    test('finalizar manualmente congela el estado y no es natural', () {
      final timer = start().finish(at(100));
      final s = timer.statusAt(at(300));
      expect(s.state, WorkdayRunState.finished);
      expect(s.completedNaturally, isFalse);
      expect(s.position, min(100));
      expect(s.effectiveFocus, min(90));
    });

    test('no se puede reanudar ni saltar una jornada finalizada', () {
      final timer = start().pause(at(10)).finish(at(20));
      expect(identical(timer.resume(at(30)), timer), isTrue);
      expect(identical(timer.skipPhase(at(30)), timer), isTrue);
      expect(timer.statusAt(at(30)).position, min(10));
    });
  });

  group('recuperación tras cerrar la app', () {
    WorkdayTimer roundTrip(WorkdayTimer t) => WorkdayTimer.fromJson(
        jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);

    test('restaurar en otro momento da el mismo estado', () {
      final original =
          start().pause(at(10)).resume(at(20)).skipPhase(at(70));
      final restored = roundTrip(original);
      for (final m in [0, 45, 70, 130, 300, 600]) {
        final a = original.statusAt(at(m));
        final b = restored.statusAt(at(m));
        expect(b.position, a.position, reason: 'minuto $m');
        expect(b.phase?.index, a.phase?.index, reason: 'minuto $m');
        expect(b.effectiveFocus, a.effectiveFocus, reason: 'minuto $m');
      }
    });

    test('una sesión en pausa se restaura en pausa', () {
      final restored = roundTrip(start().pause(at(15)));
      expect(restored.statusAt(at(200)).state, WorkdayRunState.paused);
      expect(restored.statusAt(at(200)).position, min(15));
    });

    test('el tiempo con el Mac en reposo o la app cerrada cuenta', () {
      // La app se cerró al minuto 30 y se abrió al minuto 90.
      final restored = roundTrip(start());
      final s = restored.statusAt(at(90));
      expect(s.phase!.kind, SessionPhase.focus);
      expect(s.phase!.index, 2);
      expect(s.phaseElapsed, min(30));
    });

    test('rechaza instantáneas de una versión desconocida', () {
      final json = start().toJson()..['version'] = 99;
      expect(() => WorkdayTimer.fromJson(json), throwsFormatException);
    });
  });

  test('nextTransitionAt indica cuándo acaba la fase actual', () {
    expect(start().nextTransitionAt(at(10)), at(50));
    expect(start().pause(at(10)).nextTransitionAt(at(12)), isNull);
  });
}
