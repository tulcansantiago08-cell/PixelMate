import 'dart:math';

/// Un paseo horizontal de la mascota, calculado sin tocar la ventana.
///
/// La posición en cada instante sale de la hora de inicio y la velocidad,
/// así un tic perdido no acumula error.
class WalkPlan {
  final double fromX;
  final double toX;

  /// Píxeles por segundo.
  final double speed;
  final DateTime startedAt;

  const WalkPlan({
    required this.fromX,
    required this.toX,
    required this.speed,
    required this.startedAt,
  });

  bool get towardsLeft => toX < fromX;

  Duration get duration =>
      Duration(microseconds: ((toX - fromX).abs() / speed * 1000000).round());

  bool isDoneAt(DateTime now) => !now.isBefore(startedAt.add(duration));

  double xAt(DateTime now) {
    final elapsed = now.difference(startedAt).inMicroseconds / 1000000;
    if (elapsed <= 0) return fromX;
    final travelled = min(elapsed * speed, (toX - fromX).abs());
    return towardsLeft ? fromX - travelled : fromX + travelled;
  }
}

/// Elige un destino al azar dentro de [minX]..[maxX], a una distancia
/// razonable. Devuelve `null` si no hay sitio para pasear.
WalkPlan? planWalk({
  required double currentX,
  required double minX,
  required double maxX,
  required DateTime now,
  required Random random,
  double speed = 30,
  double minDistance = 80,
  double maxDistance = 360,
}) {
  if (maxX <= minX) return null;
  final x = currentX.clamp(minX, maxX).toDouble();
  final roomLeft = x - minX;
  final roomRight = maxX - x;

  // Prefiere el lado con más espacio, pero no siempre (para que no parezca
  // que va y viene igual).
  final goLeft = roomLeft >= minDistance &&
      (roomRight < minDistance ||
          random.nextDouble() < roomLeft / (roomLeft + roomRight));
  final room = goLeft ? roomLeft : roomRight;
  if (room < minDistance) return null;

  final distance = minDistance +
      random.nextDouble() * (min(maxDistance, room) - minDistance);
  return WalkPlan(
    fromX: x,
    toX: goLeft ? x - distance : x + distance,
    speed: speed,
    startedAt: now,
  );
}
