import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import 'workday_controller.dart';

/// Formato `h:mm:ss` o `mm:ss`.
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Cuenta regresiva redondeada hacia arriba (al empezar muestra 50:00).
String formatCountdown(Duration remaining) =>
    formatClock(Duration(seconds: (remaining.inMilliseconds / 1000).ceil()));

String phaseIcon(SessionPhase kind) => switch (kind) {
      SessionPhase.focus => '🎯',
      SessionPhase.shortBreak => '☕',
      SessionPhase.longBreak => '🌿',
      SessionPhase.idle => '',
    };

/// Texto corto de la jornada para la barra de menú; vacío si no hay jornada.
String compactStatus(WorkdayView view) {
  final status = view.status;
  final phase = status?.phase;
  if (status == null || phase == null) return '';
  final icon =
      status.state == WorkdayRunState.paused ? '⏸' : phaseIcon(phase.kind);
  return '$icon ${formatCountdown(status.phaseRemaining)}';
}

/// Tiempo aproximado en horas y minutos, redondeado hacia arriba
/// ("6 h 12 min", "8 min"). Cambia como mucho una vez por minuto.
String formatHoursMinutes(Duration d) {
  final totalMinutes = (d.inSeconds / 60).ceil();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}
