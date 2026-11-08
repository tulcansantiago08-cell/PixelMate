import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_timer.dart';

/// Jornada en curso junto con el modo en que se inició.
class ActiveWorkday {
  final ActivityMode mode;
  final WorkdayTimer timer;

  const ActiveWorkday(this.mode, this.timer);
}

/// Registro de una jornada terminada, para el historial y las estadísticas.
class WorkdayRecord {
  final String id;
  final ActivityMode mode;
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration planned;
  final Duration effectiveFocus;
  final Duration effectiveBreak;
  final int focusBlocksCompleted;
  final int cyclesCompleted;

  /// `false` si el usuario la finalizó antes de tiempo.
  final bool completed;

  const WorkdayRecord({
    required this.id,
    required this.mode,
    required this.startedAt,
    required this.endedAt,
    required this.planned,
    required this.effectiveFocus,
    required this.effectiveBreak,
    required this.focusBlocksCompleted,
    required this.cyclesCompleted,
    required this.completed,
  });

  factory WorkdayRecord.fromTimer(
      ActivityMode mode, WorkdayTimer timer, DateTime now) {
    final status = timer.statusAt(now);
    // Momento real de fin: si terminó sola, inicio + pausas + plan − saltos.
    final endedAt = timer.finishedAt ??
        timer.startedAt.add(timer.pausedTotal +
            timer.config.workday -
            timer.skips.fold(Duration.zero, (sum, s) => sum + s.duration));
    return WorkdayRecord(
      id: timer.id,
      mode: mode,
      startedAt: timer.startedAt,
      endedAt: endedAt.isAfter(now.toUtc()) ? now.toUtc() : endedAt,
      planned: timer.config.workday,
      effectiveFocus: status.effectiveFocus,
      effectiveBreak: status.effectiveBreak,
      focusBlocksCompleted: status.focusBlocksCompleted,
      cyclesCompleted: status.cyclesCompleted,
      completed: status.completedNaturally,
    );
  }
}

/// Persistencia de jornadas. La implementación real usa SQLite.
abstract class WorkdayStore {
  ActiveWorkday? loadActive();

  void saveActive(ActiveWorkday active);

  /// Guarda el registro y borra la jornada activa en una sola operación.
  void completeActive(WorkdayRecord record);

  List<WorkdayRecord> history({DateTime? since});
}
