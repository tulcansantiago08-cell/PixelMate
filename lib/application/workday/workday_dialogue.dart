import '../../core/i18n/language.dart';
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
List<String> get eyeBreakTips => [
      tr('Mira algo a más de 6 metros durante 20 segundos.', 'Look at something more than 20 feet away for 20 seconds.'),
      tr('Parpadea despacio 10 veces.', 'Blink slowly 10 times.'),
      tr('Levántate de la silla y camina un poco.', 'Get up from your chair and walk a bit.'),
      tr('Cierra los ojos y relájalos un momento.', 'Close your eyes and relax them for a moment.'),
      tr('Estira el cuello, los hombros y las muñecas.', 'Stretch your neck, shoulders and wrists.'),
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
          ? tr('A estudiar. Te aviso del descanso.', "Study time. I'll let you know when it's break time.")
          : tr('A trabajar. Te aviso del descanso.', "Work time. I'll let you know when it's break time.")),
      PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
          SessionPhase.shortBreak => MascotReaction(
              tr('Buen bloque. Toca descansar.', 'Good block. Time to rest.'), MascotState.resting),
          SessionPhase.longBreak => MascotReaction(
              tr('Ciclo completo. Descanso largo.', 'Cycle complete. Long break.'), MascotState.celebrating),
          SessionPhase.focus when prev != null =>
            MascotReaction(tr('Descanso terminado. Seguimos.', "Break over. Let's keep going."), focusMood(mode)),
          _ => null,
        },
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? MascotReaction(tr('Último tramo del bloque.', 'Last stretch of the block.'), MascotState.alert)
          : MascotReaction(tr('Casi.', 'Almost.'), MascotState.alert),
      WorkdayEndingSoon(threshold: final t) => t.inMinutes >= 30
          ? MascotReaction(
              tr('Queda poco para terminar la jornada.', 'The workday is almost over.'), MascotState.tired)
          : MascotReaction(tr('Casi terminas por hoy.', "You're almost done for today."), MascotState.tired),
      WorkdayPaused() => MascotReaction(tr('En pausa.', 'Paused.')),
      WorkdayResumed() => MascotReaction(tr('Seguimos.', "Let's keep going.")),
      WorkdayFinished(status: final s) => s.completedNaturally
          ? MascotReaction(
              tr('Jornada completa. Buen trabajo.', 'Workday complete. Good job.'), MascotState.celebrating)
          : MascotReaction(tr('Jornada terminada.', 'Workday over.'), MascotState.idle),
    };

MascotReaction? _gaming(WorkdayEvent event) => switch (event) {
      WorkdayStarted() => MascotReaction(
          tr('Modo juego. Te aviso para descansar la vista.', "Game mode. I'll remind you to rest your eyes."), MascotState.gaming),
      PhaseStarted(phase: final p, previous: final prev) => p.kind.isBreak
          ? MascotReaction(tr('Pausa para la vista. ${eyeBreakTip(p.index)}', 'Eye break. ${eyeBreakTip(p.index)}'),
              MascotState.resting)
          : prev != null
              ? MascotReaction(
                  tr('Vista descansada. A jugar.', "Eyes rested. Let's play."), MascotState.gaming)
              : null,
      FocusEndingSoon(threshold: final t) => t.inMinutes >= 1
          ? MascotReaction(
              tr('Queda poco de esta sesión.', 'This session is almost over.'), MascotState.alert)
          : MascotReaction(tr('Última jugada.', 'Last round.'), MascotState.alert),
      WorkdayEndingSoon() => null,
      WorkdayPaused() => MascotReaction(tr('Partida en pausa.', 'Game paused.')),
      WorkdayResumed() => MascotReaction(tr('De vuelta al juego.', 'Back to the game.')),
      WorkdayFinished() => MascotReaction(
          tr('Buena sesión. Descansa la vista.', 'Good session. Rest your eyes.'), MascotState.celebrating),
    };
