import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/mascot/pet_species.dart';
import '../../domain/session/session_phase.dart';

/// Un consejo para aprovechar el descanso.
enum WellnessTip {
  water('💧', 'Toma un vaso de agua. ¡Yo me tomo mi café! ☕', PetAnimation.rest),
  stretch('🙆', 'Estírate conmigo: brazos arriba, hombros atrás.',
      PetAnimation.stretch),
  eyes('👀', 'Regla 20-20-20: mira algo lejano durante 20 segundos.', null),
  breathe('🌬️', 'Respira hondo 4 veces: inhala en 4, exhala en 6.', null),
  posture('🪑', 'Revisa tu postura: espalda apoyada y pies en el suelo.',
      PetAnimation.stretch),
  walk('🚶', 'Levántate y camina un poco: ¡las piernas también trabajan!',
      PetAnimation.walk),
  snack('🍎', 'Si tienes hambre, algo ligero: fruta o unos frutos secos.',
      PetAnimation.rest);

  final String emoji;
  final String text;

  /// Lo que hace la mascota a la vez (o nada).
  final PetAnimation? animation;

  const WellnessTip(this.emoji, this.text, this.animation);

  String get message => '$emoji $text';

  /// Consejos que caben en un descanso corto o largo.
  static const short = [water, stretch, eyes, breathe, posture];
  static const long = [walk, water, stretch, eyes, snack];
}

/// Elige el consejo de cada descanso rotando, para no repetir.
class WellnessCoach {
  int _short = 0;
  int _long = 0;

  /// `null` si la fase no es un descanso.
  WellnessTip? next(SessionPhase phase) => switch (phase) {
        SessionPhase.shortBreak =>
          WellnessTip.short[_short++ % WellnessTip.short.length],
        SessionPhase.longBreak =>
          WellnessTip.long[_long++ % WellnessTip.long.length],
        _ => null,
      };
}

/// Uno por sesión de la app, así la rotación sigue entre jornadas.
final wellnessCoachProvider = Provider<WellnessCoach>((_) => WellnessCoach());
