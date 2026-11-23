import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';
import '../goals/daily_goal.dart';
import '../workday/workday_controller.dart';
import 'chat_assistant.dart';
import 'command_parser.dart';

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
    return '▶️ Empecé una jornada de $label de ${config.workday.inHours} h.';
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
    case AssistantAction.remind ||
          AssistantAction.addTask ||
          AssistantAction.completeTask ||
          AssistantAction.showPending ||
          AssistantAction.open ||
          AssistantAction.showAgenda ||
          AssistantAction.createEvent:
      return null; // las hace AssistantExecutor
  }
}

/// Órdenes claras sobre la jornada, sin pasar por la IA (así funcionan
/// siempre, también por voz): «empieza mi jornada de estudio de 3 horas»,
/// «pausa», «reanuda la jornada», «termina la jornada», «cambia mi meta a
/// 6 horas», «muestra mis estadísticas». `null` si no es una de ellas.
AssistantReply? workdayCommand(String message, {String? petName}) {
  final m = fold(normalizeRequest(message, petName: petName))
      .replaceAll(RegExp(r'[¿?¡!.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final hoursMatch = RegExp(r'\b(\d{1,2})\s*(?:h|horas?)\b').firstMatch(m);
  final hours = hoursMatch == null ? 0 : int.parse(hoursMatch.group(1)!);
  AssistantReply reply(AssistantAction a) =>
      AssistantReply('', action: a, hours: hours);

  const session = r'(?:jornada|sesion|bloque|enfoque|temporizador|pomodoro)';
  if (RegExp(r'^(?:empieza|empezar|empecemos|comienza|comenzar|inicia|iniciar|arranca|arrancar|activa|pon|ponme)\s+(?:(?:mi|la|una|el|un)\s+)?' +
              session +
              r'\b')
          .hasMatch(m) ||
      RegExp(r'^(?:vamos|voy)\s+a\s+(?:trabajar|estudiar|jugar)\b')
          .hasMatch(m) ||
      RegExp(r'^(?:a\s+)?(?:trabajar|estudiar)$').hasMatch(m)) {
    if (RegExp(r'\b(?:estudi\w*)\b').hasMatch(m)) {
      return reply(AssistantAction.startStudy);
    }
    if (RegExp(r'\b(?:jueg\w*|jugar|gaming)\b').hasMatch(m)) {
      return reply(AssistantAction.startGaming);
    }
    return reply(AssistantAction.startWork);
  }
  if (RegExp(r'^(?:pausa|pausar|pausala|pon en pausa|deten|detener)(?:\s+(?:(?:mi|la|el)\s+)?' +
              session +
              r')?$')
          .hasMatch(m) ||
      RegExp(r'^(?:para|pon pausa a)\s+(?:(?:mi|la|el)\s+)?' + session + r'$')
          .hasMatch(m)) {
    return reply(AssistantAction.pause);
  }
  if (RegExp(
          r'^(?:reanuda|reanudar|reanudala|continua|continuar|retoma|retomar|sigue con)(?:\s+(?:(?:mi|la|el)\s+)?' +
              session +
              r')?$')
      .hasMatch(m)) {
    return reply(AssistantAction.resume);
  }
  if (RegExp(
          r'^(?:termina|terminar|acaba|acabar|finaliza|finalizar|cierra|detén|deten)\s+(?:(?:mi|la|el)\s+)?(?:jornada|sesion)$')
      .hasMatch(m)) {
    return reply(AssistantAction.finish);
  }
  if (hours > 0 &&
      RegExp(r'\bmeta\b').hasMatch(m) &&
      RegExp(r'^(?:cambia|pon|ponme|sube|baja|ajusta|mi meta|fija|establece)\b')
          .hasMatch(m)) {
    return reply(AssistantAction.setGoal);
  }
  if (RegExp(
          r'^(?:muestra|muestrame|abre|abreme|ensename|ver|dame)\s+(?:mis\s+|las\s+)?estadisticas\b')
      .hasMatch(m)) {
    return reply(AssistantAction.openStats);
  }
  return null;
}

/// Qué decir si la orden de jornada no se pudo hacer ahora.
String workdayCommandSkipped(AssistantAction a) => switch (a) {
      AssistantAction.pause => 'ℹ️ No hay una jornada en marcha para pausar.',
      AssistantAction.resume => 'ℹ️ No hay una jornada en pausa.',
      AssistantAction.finish => 'ℹ️ No hay ninguna jornada en curso.',
      AssistantAction.setGoal => 'ℹ️ Dime la meta en horas, por ejemplo «cambia mi meta a 6 horas».',
      _ => 'ℹ️ No pude hacerlo ahora.',
    };
