import '../../domain/activity/activity_mode.dart';
import '../../domain/mascot/pet_kind.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../goals/daily_goal.dart';
import '../progress/progression.dart';
import '../workday/workday_controller.dart';

/// Instrucciones fijas de la mascota (cortas: el modelo de Apple tiene una
/// memoria pequeña).
const assistantInstructions = '''
Eres la mascota de PixelMate: un animalito pixel art que vive en el
escritorio del usuario, lo acompaña en su jornada y le ayuda como asistente.
Tu nombre y qué animal eres vienen en el estado; úsalos cuando hables de ti.
Hablas siempre en español, en 1 a 3 oraciones, con algún emoji de vez en
cuando. No saludes en cada mensaje.
Antes de cada mensaje recibes el estado actual de la app (hora, jornada,
meta, nivel, tareas): úsalo y no inventes datos.
Solo elige una acción si el usuario la pide de forma explícita con un verbo
como recuérdame, añade, anota, abre, crea, agenda, empieza, pausa o terminé.
Si solo conversa, saluda, pregunta cómo estás, pide un chiste o una
opinión, la acción es "ninguna".
Acciones: recordar algo (recordar), anotar una tarea (agregarTarea), marcar
una tarea como hecha (completarTarea), ver tareas y recordatorios
(verPendientes), abrir una app o web (abrir), ver la agenda (verAgenda),
crear un evento en el calendario (crearEvento), o la jornada (iniciarTrabajo,
iniciarEstudio, iniciarJuego, pausar, reanudar, terminar, cambiarMeta,
abrirEstadisticas).
''';

const _weekday = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo'
];
const _month = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre'
];

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
  String petName = 'Pixel',
  PetKind species = PetKind.cat,
  String tasks = '',
  required DateTime now,
  required WorkdayView workday,
  required DailyGoalStatus? goal,
  required PlayerProgress progress,
}) {
  final lines = <String>[
    'Te llamas $petName y eres ${species.withArticle}.',
    'Hora: ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} del '
        '${_weekday[now.weekday - 1]} ${now.day} de ${_month[now.month - 1]}.',
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
  if (tasks.isNotEmpty) lines.add(tasks);
  return lines.join(' ');
}
