import '../../domain/mascot/mascot_state.dart';
import '../../domain/session/session_phase.dart';
import 'workday_event.dart';

/// Reacción de la mascota ante un suceso de la jornada.
class MascotReaction {
  final String message;
  final MascotState? mood;

  const MascotReaction(this.message, [this.mood]);
}

/// Traduce sucesos de la jornada a frases y estados de la mascota.
/// Devuelve `null` cuando la mascota no debe interrumpir.
MascotReaction? reactionFor(WorkdayEvent event) => switch (event) {
      WorkdayStarted() =>
        const MascotReaction('¡A trabajar! Yo te aviso del descanso 💼'),
      PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
          SessionPhase.shortBreak => const MascotReaction(
              '¡Buen trabajo! Vamos a descansar un poquito ☕',
              MascotState.resting),
          SessionPhase.longBreak => const MascotReaction(
              '¡Ciclo completo! 🎉 Toca un descanso largo.',
              MascotState.celebrating),
          SessionPhase.focus when prev != null => const MascotReaction(
              '¡Ya recuperamos energía! ¿Continuamos? 💪',
              MascotState.working),
          _ => null,
        },
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? const MascotReaction('¡Un último esfuerzo! Ya casi terminamos ⏰',
              MascotState.alert)
          : const MascotReaction('¡Casi! 👀', MascotState.alert),
      WorkdayEndingSoon(threshold: final t) => t.inMinutes >= 30
          ? const MascotReaction('¡Estamos cerca de completar nuestra jornada!',
              MascotState.tired)
          : const MascotReaction(
              '¡Lo conseguimos! Ya casi terminamos por hoy.', MascotState.tired),
      WorkdayPaused() => const MascotReaction('En pausa. Aquí te espero ⏸️'),
      WorkdayResumed() => const MascotReaction('¡Seguimos! ▶️'),
      WorkdayFinished(status: final s) => s.completedNaturally
          ? const MascotReaction(
              '¡Excelente trabajo hoy! Ahora sí, merecemos descansar 🌙',
              MascotState.celebrating)
          : const MascotReaction(
              'Jornada finalizada. ¡Bien hecho por hoy! 👋',
              MascotState.idle),
    };
