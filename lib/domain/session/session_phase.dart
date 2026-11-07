/// Fase actual dentro de un ciclo Pomodoro.
enum SessionPhase {
  focus,
  shortBreak,
  longBreak,
  idle,
}

extension SessionPhaseX on SessionPhase {
  String get displayName {
    switch (this) {
      case SessionPhase.focus:      return 'Enfoque';
      case SessionPhase.shortBreak: return 'Descanso corto';
      case SessionPhase.longBreak:  return 'Descanso largo';
      case SessionPhase.idle:       return 'Inactivo';
    }
  }

  bool get isBreak =>
      this == SessionPhase.shortBreak || this == SessionPhase.longBreak;
}
