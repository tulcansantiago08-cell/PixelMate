import 'session_phase.dart';
import 'workday_config.dart';

/// Una fase concreta dentro del plan de la jornada.
class PlannedPhase {
  final int index;
  final SessionPhase kind;

  /// Desplazamiento desde el inicio de la jornada (sin contar pausas).
  final Duration start;
  final Duration duration;

  /// Número de ciclo (empieza en 1) al que pertenece la fase.
  final int cycle;

  const PlannedPhase({
    required this.index,
    required this.kind,
    required this.start,
    required this.duration,
    required this.cycle,
  });

  Duration get end => start + duration;

  @override
  String toString() =>
      'PlannedPhase(#$index ${kind.name} ${start.inMinutes}–${end.inMinutes} min, ciclo $cycle)';
}

/// Genera la secuencia de fases que cubre exactamente la jornada.
///
/// Los descansos cuentan dentro de la jornada. Si la última fase no cabe
/// entera se recorta para que el total sea exactamente [WorkdayConfig.workday].
List<PlannedPhase> planWorkday(WorkdayConfig config) {
  config.validate();

  final phases = <PlannedPhase>[];
  var cursor = Duration.zero;
  var cycle = 1;

  void add(SessionPhase kind, Duration duration) {
    final remaining = config.workday - cursor;
    if (remaining <= Duration.zero || duration <= Duration.zero) return;
    final actual = duration < remaining ? duration : remaining;
    phases.add(PlannedPhase(
      index: phases.length,
      kind: kind,
      start: cursor,
      duration: actual,
      cycle: cycle,
    ));
    cursor += actual;
  }

  while (cursor < config.workday) {
    for (var i = 1; i <= config.focusesPerCycle; i++) {
      add(SessionPhase.focus, config.focus);
      final isLast = i == config.focusesPerCycle;
      add(isLast ? SessionPhase.longBreak : SessionPhase.shortBreak,
          isLast ? config.longBreak : config.shortBreak);
    }
    cycle++;
  }
  return phases;
}
