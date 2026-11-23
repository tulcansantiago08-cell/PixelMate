import '../../core/i18n/language.dart';

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
      case SessionPhase.focus:      return tr('Enfoque', 'Focus');
      case SessionPhase.shortBreak: return tr('Descanso corto', 'Short break');
      case SessionPhase.longBreak:  return tr('Descanso largo', 'Long break');
      case SessionPhase.idle:       return tr('Inactivo', 'Idle');
    }
  }

  bool get isBreak =>
      this == SessionPhase.shortBreak || this == SessionPhase.longBreak;
}
