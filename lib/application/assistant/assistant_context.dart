import '../../domain/activity/activity_mode.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../goals/daily_goal.dart';
import '../progress/progression.dart';
import '../workday/workday_controller.dart';

/// Instrucciones fijas de la mascota (cortas: el modelo de Apple tiene una
/// memoria pequeña).
const assistantInstructions = '''
Eres PixelMate, un gato pixel art que vive en el escritorio del usuario y lo
acompaña en su jornada. Eres alegre, cercano y motivador. Hablas siempre en
español, en 1 a 3 oraciones, con algún emoji de vez en cuando.
Antes de cada mensaje recibes el estado actual de la app: úsalo para
responder con datos reales (tiempo restante, meta, nivel) y no inventes
cifras. Si el usuario te pide hacer algo en la app (empezar, pausar,
reanudar o terminar la jornada, cambiar su meta diaria o ver sus
estadísticas), elige esa acción; si no lo pide de forma explícita, no
elijas ninguna.
''';

String _dur(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

String _mode(ActivityMode? m) => switch (m) {
      ActivityMode.work => 'trabajo',
      ActivityMode.study => 'estudio',
      ActivityMode.gaming => 'juego',
      ActivityMode.free || null => 'libre',
    };

String _phase(SessionPhase p) => switch (p) {
      SessionPhase.focus => 'enfoque',
      SessionPhase.shortBreak => 'descanso corto',
      SessionPhase.longBreak => 'descanso largo',
      _ => p.name,
    };

/// Estado de la app en texto, para que la IA responda sobre el día real.
String describeContext({
  required DateTime now,
  required WorkdayView workday,
  required DailyGoalStatus? goal,
  required PlayerProgress progress,
}) {
  final lines = <String>[
    'Hora: ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}.',
  ];
  final status = workday.status;
  if (status == null) {
    lines.add('No hay jornada en curso.');
  } else {
    final phase = status.phase;
    final paused = status.state == WorkdayRunState.paused;
    lines.add('Jornada de ${_mode(workday.mode)} en curso'
        '${paused ? ' (en pausa)' : ''}.');
    if (phase != null) {
      lines.add('Fase: ${_phase(phase.kind)} (ciclo ${phase.cycle}); '
          'quedan ${_dur(status.phaseRemaining)} de esta fase.');
    }
    lines.add('Enfoque de esta jornada: ${_dur(status.effectiveFocus)}; '
        'quedan ${_dur(status.workdayRemaining)} de jornada.');
  }
  if (goal == null) {
    lines.add('Sin meta diaria.');
  } else {
    lines.add('Enfoque de hoy: ${_dur(goal.done)} de una meta de '
        '${_dur(goal.goal)}${goal.reached ? ' (meta cumplida)' : ''}.');
  }
  lines.add('Nivel ${progress.level} («${progress.title}»), '
      '${progress.xp} XP; faltan '
      '${progress.xpNeededForNext - progress.xpIntoLevel} XP para el '
      'nivel ${progress.level + 1}.');
  return lines.join(' ');
}
