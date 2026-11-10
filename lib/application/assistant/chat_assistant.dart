/// IA con la que conversa la mascota (la de Apple en el Mac o Claude).
abstract class ChatAssistant {
  /// Nombre que se muestra en el chat.
  String get label;

  /// Si puede mirar una captura de pantalla.
  bool get supportsImages;

  /// Si puede pedir acciones de la app (iniciar jornada, cambiar meta…).
  bool get supportsActions;

  /// Si funciona en el propio Mac (nada sale del equipo ni cuesta dinero).
  bool get onDevice => false;

  /// [context] describe el estado actual de la app (jornada, meta, nivel).
  Future<AssistantReply> reply(
    String message, {
    required String context,
    String? imageBase64,
  });

  /// Olvida la conversación.
  Future<void> reset();

  /// Prepara el modelo para que la primera respuesta llegue antes.
  Future<void> prewarm() async {}
}

/// Acciones que la IA puede pedir. La app decide si se pueden hacer.
enum AssistantAction {
  none('ninguna'),
  startWork('iniciarTrabajo'),
  startStudy('iniciarEstudio'),
  startGaming('iniciarJuego'),
  pause('pausar'),
  resume('reanudar'),
  finish('terminar'),
  setGoal('cambiarMeta'),
  openStats('abrirEstadisticas'),
  // Asistente (las ejecuta AssistantExecutor).
  remind('recordar'),
  addTask('agregarTarea'),
  completeTask('completarTarea'),
  showPending('verPendientes'),
  open('abrir'),
  showAgenda('verAgenda'),
  createEvent('crearEvento');

  /// Nombre que usa el modelo.
  final String wire;
  const AssistantAction(this.wire);

  static AssistantAction parse(Object? wire) =>
      values.where((a) => a.wire == wire).firstOrNull ?? none;
}

class AssistantReply {
  final String text;
  final AssistantAction action;

  /// Horas que pidió el usuario (jornada o meta); 0 si no dijo.
  final int hours;

  /// Para el asistente: qué recordar, la tarea, la app o el evento.
  final String detail;

  /// "En X minutos" (recordatorios).
  final int minutes;

  /// Hora "HH:mm" y día ("hoy", "mañana" o "").
  final String time;
  final String day;

  /// Número de tarea (1 = la primera).
  final int number;

  const AssistantReply(this.text,
      {this.action = AssistantAction.none,
      this.hours = 0,
      this.detail = '',
      this.minutes = 0,
      this.time = '',
      this.day = '',
      this.number = 0});
}

/// Error con un mensaje listo para mostrar al usuario.
class AssistantException implements Exception {
  final String message;
  const AssistantException(this.message);

  @override
  String toString() => message;
}

/// Qué IA usar y, si no hay ninguna, por qué.
class AssistantChoice {
  final ChatAssistant? assistant;

  /// Explicación para el usuario cuando no hay IA disponible.
  final String? problem;

  const AssistantChoice(this.assistant, [this.problem]);
}
