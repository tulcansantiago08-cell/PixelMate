import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_timer.dart';
import '../activity/focus_guard.dart';
import 'chat_assistant.dart';

String _dur(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

/// Lo que se le pide a la IA al terminar una jornada.
String workdaySummaryPrompt({
  required WorkdayStatus status,
  required ActivityMode? mode,
  DistractionTally? distractions,
}) {
  final kind = switch (mode) {
    ActivityMode.study => 'estudio',
    ActivityMode.gaming => 'juego',
    _ => 'trabajo',
  };
  final d = distractions;
  return 'Acabo de terminar mi jornada de $kind. '
      '${status.completedNaturally ? 'La completé entera' : 'La terminé antes de tiempo'}: '
      '${_dur(status.effectiveFocus)} de enfoque, '
      '${_dur(status.effectiveBreak)} de descanso, '
      '${status.focusBlocksCompleted} bloques de enfoque terminados. '
      '${d == null ? '' : d.episodes == 0 ? 'Hoy no tuve distracciones durante el enfoque. ' : 'Hoy tuve ${d.episodes} distracciones durante el enfoque (${_dur(d.time)}). '}'
      'Dame un resumen breve y motivador de cómo me fue (2 oraciones) con un '
      'consejo concreto para la próxima. No elijas ninguna acción.';
}

/// Resumen de la jornada con la IA, solo si funciona en el propio Mac (no
/// se envían datos fuera ni se gasta crédito sin pedirlo). `null` si no se
/// puede.
Future<String?> summarizeWorkday(
  ChatAssistant? assistant, {
  required String prompt,
  required String context,
}) async {
  if (assistant == null || !assistant.onDevice) return null;
  try {
    final reply = await assistant.reply(prompt, context: context);
    final text = reply.text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
