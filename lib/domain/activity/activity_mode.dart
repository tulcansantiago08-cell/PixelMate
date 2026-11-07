/// Modos de actividad disponibles en PixelMate.
enum ActivityMode {
  work,
  study,
  gaming,
  free,
}

extension ActivityModeX on ActivityMode {
  String get displayName {
    switch (this) {
      case ActivityMode.work:   return 'Trabajo';
      case ActivityMode.study:  return 'Estudio';
      case ActivityMode.gaming: return 'Videojuegos';
      case ActivityMode.free:   return 'Libre';
    }
  }

  String get emoji {
    switch (this) {
      case ActivityMode.work:   return '💼';
      case ActivityMode.study:  return '📚';
      case ActivityMode.gaming: return '🎮';
      case ActivityMode.free:   return '🌿';
    }
  }
}
