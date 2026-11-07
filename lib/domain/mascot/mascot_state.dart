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
      case MascotState.idle:        return 'Libre';
      case MascotState.greeting:    return 'Saludando';
      case MascotState.working:     return 'Trabajando';
      case MascotState.studying:    return 'Estudiando';
      case MascotState.gaming:      return 'Jugando';
      case MascotState.resting:     return 'Descansando';
      case MascotState.sleeping:    return 'Durmiendo';
      case MascotState.celebrating: return '¡Celebrando!';
      case MascotState.alert:       return 'Alerta';
      case MascotState.tired:       return 'Cansada';
      case MascotState.chatting:    return 'Chateando';
    }
  }

  bool get isActive => this == MascotState.working ||
      this == MascotState.studying ||
      this == MascotState.gaming;
}
