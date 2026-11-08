import 'dart:math';

import '../../domain/mascot/pet_species.dart';
import '../../domain/time/day_part.dart';

/// Qué hace la mascota cuando nadie la necesita.
sealed class IdleDecision {
  const IdleDecision();
}

class StayStill extends IdleDecision {
  const StayStill();
}

/// Una animación corta para que se sienta viva (estirarse, saludar).
class PlayOnce extends IdleDecision {
  final PetAnimation animation;
  const PlayOnce(this.animation);
}

class FallAsleep extends IdleDecision {
  const FallAsleep();
}

/// Dar un paseo por el escritorio.
class StartWalk extends IdleDecision {
  const StartWalk();
}

/// Comportamiento en reposo, sin depender de la interfaz ni de relojes reales.
///
/// "Actividad" es cualquier cosa que haga el usuario con la mascota o una
/// sesión en marcha; no se mira el teclado ni el ratón del sistema.
class IdleBehavior {
  final Duration sleepAfter;

  /// Probabilidad de hacer algo en cada comprobación estando despierta.
  final double fidgetChance;
  final Random _random;

  DateTime _lastActivity;
  bool _asleep = false;

  /// De noche (23:00–5:00) tiene sueño y se duerme antes.
  final Duration nightSleepAfter;

  IdleBehavior({
    required DateTime now,
    this.sleepAfter = const Duration(minutes: 10),
    this.nightSleepAfter = const Duration(minutes: 3),
    this.fidgetChance = 0.15,
    Random? random,
  })  : _lastActivity = now,
        _random = random ?? Random();

  bool get asleep => _asleep;

  static const _fidgets = [
    PetAnimation.stretch,
    PetAnimation.stretch,
    PetAnimation.wave,
  ];

  /// El usuario interactuó: se despierta y reinicia la cuenta.
  /// Devuelve `true` si estaba dormida (para animar el despertar).
  bool activity(DateTime now) {
    final wasAsleep = _asleep;
    _asleep = false;
    _lastActivity = now;
    return wasAsleep;
  }

  /// [idle] es `false` mientras hay una sesión o un panel abierto: eso cuenta
  /// como actividad y no se interrumpe con animaciones.
  /// [canWalk] permite que una de las "travesuras" sea pasear.
  IdleDecision tick(DateTime now, {required bool idle, bool canWalk = false}) {
    if (!idle) {
      activity(now);
      return const StayStill();
    }
    if (_asleep) return const StayStill();
    final sleepy = DayPart.of(now.toLocal()).sleepy;
    if (now.difference(_lastActivity) >=
        (sleepy ? nightSleepAfter : sleepAfter)) {
      _asleep = true;
      return const FallAsleep();
    }
    if (_random.nextDouble() < fidgetChance) {
      // De noche no pasea ni saluda: solo se estira bostezando.
      if (sleepy) return const PlayOnce(PetAnimation.stretch);
      if (canWalk && _random.nextBool()) return const StartWalk();
      return PlayOnce(_fidgets[_random.nextInt(_fidgets.length)]);
    }
    return const StayStill();
  }
}
