import '../../domain/activity/activity_mode.dart';
import '../../domain/mascot/mascot_state.dart';
import '../../domain/session/session_phase.dart';
import 'workday_event.dart';

/// Reacción de la mascota ante un suceso de la jornada.
class MascotReaction {
  final String message;
  final MascotState? mood;

  const MascotReaction(this.message, [this.mood]);
}

/// Estado de la mascota mientras dura el enfoque, según el modo.
MascotState focusMood(ActivityMode mode) => switch (mode) {
      ActivityMode.study => MascotState.studying,
      ActivityMode.gaming => MascotState.gaming,
      _ => MascotState.working,
    };

/// Consejos de descanso visual, rotando por fase.
const eyeBreakTips = [
  'Mira algo a más de 6 metros durante 20 segundos.',
  'Parpadea despacio 10 veces.',
  'Levántate de la silla y camina un poco.',
  'Cierra los ojos y relájalos un momento.',
  'Estira el cuello, los hombros y las muñecas.',
];

String eyeBreakTip(int phaseIndex) =>
    eyeBreakTips[(phaseIndex ~/ 2) % eyeBreakTips.length];

/// Traduce sucesos de la jornada a frases y estados de la mascota.
/// Devuelve `null` cuando la mascota no debe interrumpir.
MascotReaction? reactionFor(WorkdayEvent event,
        {ActivityMode mode = ActivityMode.work}) =>
    mode == ActivityMode.gaming ? _gaming(event) : _work(event, mode);

MascotReaction? _work(WorkdayEvent event, ActivityMode mode) => switch (event) {
      WorkdayStarted() => MascotReaction(mode == ActivityMode.study
          ? 'A estudiar. Te aviso del descanso.'
          : 'A trabajar. Te aviso del descanso.'),
      PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
          SessionPhase.shortBreak => const MascotReaction(
              'Buen bloque. Toca descansar.', MascotState.resting),
          SessionPhase.longBreak => const MascotReaction(
              'Ciclo completo. Descanso largo.', MascotState.celebrating),
          SessionPhase.focus when prev != null =>
            MascotReaction('Descanso terminado. Seguimos.', focusMood(mode)),
          _ => null,
        },
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? const MascotReaction('Último tramo del bloque.', MascotState.alert)
          : const MascotReaction('Casi.', MascotState.alert),
      WorkdayEndingSoon(threshold: final t) => t.inMinutes >= 30
          ? const MascotReaction(
              'Queda poco para terminar la jornada.', MascotState.tired)
          : const MascotReaction('Casi terminas por hoy.', MascotState.tired),
      WorkdayPaused() => const MascotReaction('En pausa.'),
      WorkdayResumed() => const MascotReaction('Seguimos.'),
      WorkdayFinished(status: final s) => s.completedNaturally
          ? const MascotReaction(
              'Jornada completa. Buen trabajo.', MascotState.celebrating)
          : const MascotReaction('Jornada terminada.', MascotState.idle),
    };

MascotReaction? _gaming(WorkdayEvent event) => switch (event) {
      WorkdayStarted() => const MascotReaction(
          'Modo juego. Te aviso para descansar la vista.', MascotState.gaming),
      PhaseStarted(phase: final p, previous: final prev) => p.kind.isBreak
          ? MascotReaction('Pausa para la vista. ${eyeBreakTip(p.index)}',
              MascotState.resting)
          : prev != null
              ? const MascotReaction(
                  'Vista descansada. A jugar.', MascotState.gaming)
              : null,
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? const MascotReaction(
              'Queda poco de esta sesión.', MascotState.alert)
          : const MascotReaction('Última jugada.', MascotState.alert),
      WorkdayEndingSoon() => null,
      WorkdayPaused() => const MascotReaction('Partida en pausa.'),
      WorkdayResumed() => const MascotReaction('De vuelta al juego.'),
      WorkdayFinished() => const MascotReaction(
          'Buena sesión. Descansa la vista.', MascotState.celebrating),
    };
