import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/domain/session/phase_planner.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';

Duration min(int m) => Duration(minutes: m);

Duration total(List<PlannedPhase> plan) =>
    plan.fold(Duration.zero, (sum, p) => sum + p.duration);

void main() {
  group('WorkdayConfig', () {
    test('valores por defecto de la especificación', () {
      const c = WorkdayConfig();
      expect(c.focus, min(50));
      expect(c.shortBreak, min(10));
      expect(c.longBreak, min(30));
      expect(c.focusesPerCycle, 3);
      expect(c.workday, const Duration(hours: 8));
    });

    test('el descanso largo reemplaza al último corto: ciclo de 200 min', () {
      expect(const WorkdayConfig().cycleLength, min(200));
    });

    test('rechaza configuraciones inválidas', () {
      expect(() => const WorkdayConfig(focus: Duration.zero).validate(),
          throwsArgumentError);
      expect(() => const WorkdayConfig(focusesPerCycle: 0).validate(),
          throwsArgumentError);
      expect(() => const WorkdayConfig(workday: Duration.zero).validate(),
          throwsArgumentError);
      expect(() => WorkdayConfig(shortBreak: min(-1)).validate(),
          throwsArgumentError);
    });

    test('toJson/fromJson conserva los valores', () {
      final c = WorkdayConfig(focus: min(25), workday: min(333));
      expect(WorkdayConfig.fromJson(c.toJson()), c);
    });
  });

  group('planWorkday', () {
    test('primer ciclo sigue el orden enfoque/descanso de la especificación',
        () {
      final plan = planWorkday(const WorkdayConfig());
      expect(plan.take(6).map((p) => p.kind).toList(), [
        SessionPhase.focus,
        SessionPhase.shortBreak,
        SessionPhase.focus,
        SessionPhase.shortBreak,
        SessionPhase.focus,
        SessionPhase.longBreak,
      ]);
      expect(plan.take(6).map((p) => p.duration.inMinutes).toList(),
          [50, 10, 50, 10, 50, 30]);
      expect(plan[6].cycle, 2);
    });

    for (final workday in [...WorkdayConfig.presetWorkdays, min(95), min(7)]) {
      test('la jornada de ${workday.inMinutes} min suma exactamente su duración',
          () {
        final plan = planWorkday(WorkdayConfig(workday: workday));
        expect(total(plan), workday);
        expect(plan.last.end, workday);
      });
    }

    test('las fases son contiguas y con índices consecutivos', () {
      final plan = planWorkday(const WorkdayConfig(workday: Duration(hours: 9)));
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].index, i);
        if (i > 0) expect(plan[i].start, plan[i - 1].end);
      }
    });

    test('8 h: dos ciclos completos + enfoque, descanso y enfoque recortado a 20 min',
        () {
      final plan = planWorkday(const WorkdayConfig());
      final tail = plan.skip(12).toList();
      expect(tail.map((p) => p.kind).toList(), [
        SessionPhase.focus,
        SessionPhase.shortBreak,
        SessionPhase.focus,
      ]);
      expect(tail.last.duration, min(20));
    });

    test('descansos en cero no generan fases vacías', () {
      final plan = planWorkday(const WorkdayConfig(
        shortBreak: Duration.zero,
        longBreak: Duration.zero,
        workday: Duration(hours: 2),
      ));
      expect(plan.every((p) => p.kind == SessionPhase.focus), isTrue);
      expect(total(plan), const Duration(hours: 2));
    });
  });
}
