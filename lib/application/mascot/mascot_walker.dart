import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../desktop/mascot_window_port.dart';
import 'walk_plan.dart';

/// Hace caminar a la mascota moviendo su ventana en horizontal.
///
/// - Se queda a la altura donde el usuario la dejó.
/// - Nunca sale del área visible de su pantalla.
/// - Solo hay temporizador mientras camina (unos 15 pasos por segundo).
/// - Al terminar o detenerse guarda la posición.
class MascotWalker extends ChangeNotifier {
  final MascotWindowPort window;
  final DateTime Function() _now;
  final Random _random;
  final Duration step;
  final double speed;

  WalkPlan? _plan;
  double _y = 0;
  Timer? _timer;

  MascotWalker({
    required this.window,
    DateTime Function()? now,
    Random? random,
    this.step = const Duration(milliseconds: 66),
    this.speed = 30,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  bool get walking => _plan != null;

  /// Hacia dónde mira mientras camina (para voltear el sprite).
  bool get facingLeft => _plan?.towardsLeft ?? false;

  /// Empieza un paseo. Devuelve `false` si no hay sitio o ya camina.
  Future<bool> start() async {
    if (walking) return false;
    final bounds = await window.bounds();
    final area = await window.visibleAreaOf(bounds);
    final plan = planWalk(
      currentX: bounds.left,
      minX: area.left,
      maxX: area.right - bounds.width,
      now: _now(),
      random: _random,
      speed: speed,
    );
    if (plan == null) return false;
    _plan = plan;
    _y = bounds.top;
    _timer = Timer.periodic(step, (_) => _tick());
    notifyListeners();
    return true;
  }

  void _tick() {
    final plan = _plan;
    if (plan == null) return;
    final now = _now();
    unawaited(window.moveTo(Offset(plan.xAt(now).roundToDouble(), _y)));
    if (plan.isDoneAt(now)) unawaited(stop());
  }

  /// Detiene el paseo donde esté (por ejemplo, si el usuario la toca).
  Future<void> stop() async {
    if (!walking) return;
    _timer?.cancel();
    _timer = null;
    _plan = null;
    notifyListeners();
    await window.rememberPosition();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
