import '../activity/activity_mode.dart';

/// Representa una sesión de trabajo/estudio/juego.
class Session {
  final String id;
  final ActivityMode mode;
  final DateTime startedAt;
  final Duration plannedDuration;
  final Duration focusDuration;
  final Duration shortBreakDuration;
  final Duration longBreakDuration;
  final int cyclesBeforeLongBreak;

  DateTime? endedAt;
  bool completed;
  int cyclesCompleted;
  Duration effectiveDuration;

  Session({
    required this.id,
    required this.mode,
    required this.startedAt,
    required this.plannedDuration,
    this.focusDuration = const Duration(minutes: 50),
    this.shortBreakDuration = const Duration(minutes: 10),
    this.longBreakDuration = const Duration(minutes: 30),
    this.cyclesBeforeLongBreak = 3,
    this.completed = false,
    this.cyclesCompleted = 0,
    this.effectiveDuration = Duration.zero,
  });

  /// Calcula el número total de ciclos para cubrir [plannedDuration].
  int get totalCycles {
    final cycleLength = focusDuration + shortBreakDuration;
    final longBreakCycle = cycleLength * cyclesBeforeLongBreak + longBreakDuration;
    if (longBreakCycle.inSeconds == 0) return 0;
    return (plannedDuration.inSeconds / longBreakCycle.inSeconds * cyclesBeforeLongBreak).ceil();
  }

  Session copyWith({
    bool? completed,
    int? cyclesCompleted,
    Duration? effectiveDuration,
    DateTime? endedAt,
  }) {
    return Session(
      id: id,
      mode: mode,
      startedAt: startedAt,
      plannedDuration: plannedDuration,
      focusDuration: focusDuration,
      shortBreakDuration: shortBreakDuration,
      longBreakDuration: longBreakDuration,
      cyclesBeforeLongBreak: cyclesBeforeLongBreak,
      completed: completed ?? this.completed,
      cyclesCompleted: cyclesCompleted ?? this.cyclesCompleted,
      effectiveDuration: effectiveDuration ?? this.effectiveDuration,
    )..endedAt = endedAt ?? this.endedAt;
  }
}
