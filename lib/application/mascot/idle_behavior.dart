import 'dart:math';

import '../../domain/mascot/pet_species.dart';

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

  IdleBehavior({
    required DateTime now,
    this.sleepAfter = const Duration(minutes: 10),
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
  IdleDecision tick(DateTime now, {required bool idle}) {
    if (!idle) {
      activity(now);
      return const StayStill();
    }
    if (_asleep) return const StayStill();
    if (now.difference(_lastActivity) >= sleepAfter) {
      _asleep = true;
      return const FallAsleep();
    }
    if (_random.nextDouble() < fidgetChance) {
      return PlayOnce(_fidgets[_random.nextInt(_fidgets.length)]);
    }
    return const StayStill();
  }
}
