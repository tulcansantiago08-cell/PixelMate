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
          ? '¡A estudiar! Yo te aviso del descanso 📚'
          : '¡A trabajar! Yo te aviso del descanso 💼'),
      PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
          SessionPhase.shortBreak => const MascotReaction(
              '¡Buen trabajo! Vamos a descansar un poquito ☕',
              MascotState.resting),
          SessionPhase.longBreak => const MascotReaction(
              '¡Ciclo completo! 🎉 Toca un descanso largo.',
              MascotState.celebrating),
          SessionPhase.focus when prev != null => MascotReaction(
              '¡Ya recuperamos energía! ¿Continuamos? 💪', focusMood(mode)),
          _ => null,
        },
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? const MascotReaction(
              '¡Un último esfuerzo! Ya casi terminamos ⏰', MascotState.alert)
          : const MascotReaction('¡Casi! 👀', MascotState.alert),
      WorkdayEndingSoon(threshold: final t) => t.inMinutes >= 30
          ? const MascotReaction(
              '¡Estamos cerca de completar nuestra jornada!', MascotState.tired)
          : const MascotReaction('¡Lo conseguimos! Ya casi terminamos por hoy.',
              MascotState.tired),
      WorkdayPaused() => const MascotReaction('En pausa. Aquí te espero ⏸️'),
      WorkdayResumed() => const MascotReaction('¡Seguimos! ▶️'),
      WorkdayFinished(status: final s) => s.completedNaturally
          ? const MascotReaction(
              '¡Excelente trabajo hoy! Ahora sí, merecemos descansar 🌙',
              MascotState.celebrating)
          : const MascotReaction(
              'Jornada finalizada. ¡Bien hecho por hoy! 👋', MascotState.idle),
    };

MascotReaction? _gaming(WorkdayEvent event) => switch (event) {
      WorkdayStarted() => const MascotReaction(
          '¡Modo gamer activado! 🎮 Te aviso para descansar la vista.',
          MascotState.gaming),
      PhaseStarted(phase: final p, previous: final prev) => p.kind.isBreak
          ? MascotReaction(
              '¡Buen juego! Es hora de descansar la vista 👀 ${eyeBreakTip(p.index)}',
              MascotState.resting)
          : prev != null
              ? const MascotReaction(
                  '¡Ojos listos! A jugar otra vez 🎮', MascotState.gaming)
              : null,
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? const MascotReaction(
              '¡Ya casi terminamos esta sesión! Prepárate para descansar un poquito.',
              MascotState.alert)
          : const MascotReaction('¡Última jugada! 👀', MascotState.alert),
      WorkdayEndingSoon() => null,
      WorkdayPaused() => const MascotReaction('Partida en pausa ⏸️'),
      WorkdayResumed() => const MascotReaction('¡De vuelta al juego! 🎮'),
      WorkdayFinished() => const MascotReaction(
          '¡GG! Buena sesión. Ahora descansa la vista 🌙',
          MascotState.celebrating),
    };
