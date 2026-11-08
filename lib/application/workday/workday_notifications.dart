import '../../domain/activity/activity_mode.dart';
import '../../domain/session/session_phase.dart';
import 'workday_dialogue.dart';
import 'workday_event.dart';

/// Notificación del sistema para un suceso de la jornada.
class WorkdayNotice {
  final String title;
  final String body;
  const WorkdayNotice(this.title, this.body);
}

/// Solo los momentos importantes generan notificación del sistema, para no
/// molestar: empieza un descanso, se vuelve al enfoque y termina la sesión.
/// Los avisos de "quedan 5 min" se quedan en el globo de la mascota.
WorkdayNotice? noticeFor(WorkdayEvent event,
    {ActivityMode mode = ActivityMode.work}) {
  final body = reactionFor(event, mode: mode)?.message;
  if (body == null) return null;
  final gaming = mode == ActivityMode.gaming;
  return switch (event) {
    PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
        _ when gaming && p.kind.isBreak => WorkdayNotice(
            '👀 Descanso visual de ${p.duration.inMinutes} min', body),
        SessionPhase.shortBreak => WorkdayNotice(
            '☕ Descanso de ${p.duration.inMinutes} min',
            '$body ${eyeBreakTip(p.index)}'),
        SessionPhase.longBreak => WorkdayNotice(
            '🌿 Descanso largo de ${p.duration.inMinutes} min', body),
        SessionPhase.focus when prev != null => WorkdayNotice(
            gaming
                ? '🎮 A jugar: ${p.duration.inMinutes} min'
                : '🎯 Enfoque de ${p.duration.inMinutes} min',
            body),
        _ => null,
      },
    WorkdayFinished() => WorkdayNotice(
        gaming ? '🎮 Sesión terminada' : '🌙 Jornada terminada', body),
    _ => null,
  };
}
