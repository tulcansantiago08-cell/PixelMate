import '../../domain/session/phase_planner.dart';
import '../../domain/session/workday_timer.dart';

/// Sucesos de la jornada a los que la mascota puede reaccionar.
sealed class WorkdayEvent {
  const WorkdayEvent();
}

class WorkdayStarted extends WorkdayEvent {
  const WorkdayStarted();
}

/// Empezó una fase nueva (enfoque o descanso).
class PhaseStarted extends WorkdayEvent {
  final PlannedPhase phase;
  final PlannedPhase? previous;
  const PhaseStarted(this.phase, this.previous);
}

/// Quedan pocos minutos/segundos del enfoque actual.
class FocusEndingSoon extends WorkdayEvent {
  final PlannedPhase phase;
  final Duration threshold;
  const FocusEndingSoon(this.phase, this.threshold);
}

/// Queda poco para terminar la jornada completa.
class WorkdayEndingSoon extends WorkdayEvent {
  final Duration threshold;
  const WorkdayEndingSoon(this.threshold);
}

class WorkdayPaused extends WorkdayEvent {
  const WorkdayPaused();
}

class WorkdayResumed extends WorkdayEvent {
  const WorkdayResumed();
}

class WorkdayFinished extends WorkdayEvent {
  final WorkdayStatus status;
  const WorkdayFinished(this.status);
}
