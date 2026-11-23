import '../../core/i18n/language.dart';

/// Estados posibles de la mascota.
/// Cada estado tiene una animación y un comportamiento asociado.
enum MascotState {
  idle,
  greeting,
  working,
  studying,
  gaming,
  resting,
  sleeping,
  celebrating,
  alert,
  tired,
  chatting,
}

extension MascotStateX on MascotState {
  String get displayName {
    switch (this) {
      case MascotState.idle:
        return tr('Libre', 'Free');
      case MascotState.greeting:
        return tr('Saludando', 'Greeting');
      case MascotState.working:
        return tr('Trabajando', 'Working');
      case MascotState.studying:
        return tr('Estudiando', 'Studying');
      case MascotState.gaming:
        return tr('Jugando', 'Playing');
      case MascotState.resting:
        return tr('Descansando', 'Resting');
      case MascotState.sleeping:
        return tr('Durmiendo', 'Sleeping');
      case MascotState.celebrating:
        return tr('Celebrando', 'Celebrating');
      case MascotState.alert:
        return tr('Alerta', 'Alert');
      case MascotState.tired:
        return tr('Cansada', 'Tired');
      case MascotState.chatting:
        return tr('Chateando', 'Chatting');
    }
  }

  bool get isActive =>
      this == MascotState.working ||
      this == MascotState.studying ||
      this == MascotState.gaming;
}
