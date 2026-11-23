import '../../core/i18n/language.dart';

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
      case ActivityMode.work:   return tr('Trabajo', 'Work');
      case ActivityMode.study:  return tr('Estudio', 'Study');
      case ActivityMode.gaming: return tr('Videojuegos', 'Video games');
      case ActivityMode.free:   return tr('Libre', 'Free');
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
