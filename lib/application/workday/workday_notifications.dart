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
/// molestar: empieza un descanso, se vuelve al enfoque y termina la jornada.
/// Los avisos de "quedan 5 min" se quedan en el globo de la mascota.
WorkdayNotice? noticeFor(WorkdayEvent event) {
  final body = reactionFor(event)?.message;
  if (body == null) return null;
  return switch (event) {
    PhaseStarted(phase: final p, previous: final prev) => switch (p.kind) {
        SessionPhase.shortBreak => WorkdayNotice(
            '☕ Descanso de ${p.duration.inMinutes} min',
            '$body Levántate, estira y mira algo lejano.'),
        SessionPhase.longBreak => WorkdayNotice(
            '🌿 Descanso largo de ${p.duration.inMinutes} min', body),
        SessionPhase.focus when prev != null => WorkdayNotice(
            '🎯 Enfoque de ${p.duration.inMinutes} min', body),
        _ => null,
      },
    WorkdayFinished() => WorkdayNotice('🌙 Jornada terminada', body),
    _ => null,
  };
}
