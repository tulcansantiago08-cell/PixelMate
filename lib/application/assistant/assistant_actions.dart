import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';
import '../goals/daily_goal.dart';
import '../workday/workday_controller.dart';
import 'chat_assistant.dart';

/// Ejecuta la acción que pidió la IA, solo si tiene sentido ahora, y
/// devuelve una confirmación visible para el chat (o `null` si no hizo nada).
///
/// La IA nunca actúa por su cuenta: solo traduce lo que el usuario pidió, y
/// aquí se comprueba de nuevo contra el estado real.
String? runAssistantAction(
  AssistantReply reply, {
  required WorkdayController workday,
  required WorkdayView view,
  required DailyGoalSettings goal,
  required void Function() openStats,
}) {
  final hours = reply.hours.clamp(0, 12);
  final status = view.status;
  final running = status != null && status.state == WorkdayRunState.running;
  final paused = status != null && status.state == WorkdayRunState.paused;

  String? start(ActivityMode mode, WorkdayConfig base, String label) {
    if (view.isActive) return 'ℹ️ Ya hay una jornada en curso.';
    final config =
        hours > 0 ? base.copyWith(workday: Duration(hours: hours)) : base;
    workday.start(config, mode: mode);
    return '▶️ Empecé una jornada de $label de '
        '${config.workday.inHours} h.';
  }

  switch (reply.action) {
    case AssistantAction.none:
      return null;
    case AssistantAction.startWork:
      return start(ActivityMode.work, const WorkdayConfig(), 'trabajo');
    case AssistantAction.startStudy:
      return start(ActivityMode.study, WorkdayConfig.study, 'estudio');
    case AssistantAction.startGaming:
      return start(ActivityMode.gaming, WorkdayConfig.gaming, 'juego');
    case AssistantAction.pause:
      if (!running) return null;
      workday.pause();
      return '⏸️ Pausé la jornada.';
    case AssistantAction.resume:
      if (!paused) return null;
      workday.resume();
      return '▶️ Reanudé la jornada.';
    case AssistantAction.finish:
      if (!view.isActive) return null;
      workday.finish();
      return '⏹️ Terminé la jornada.';
    case AssistantAction.setGoal:
      if (hours == 0) return null;
      goal.setGoal(Duration(hours: hours));
      return '🎯 Tu meta diaria ahora es de $hours h.';
    case AssistantAction.openStats:
      openStats();
      return '📊 Abrí tus estadísticas.';
  }
}
