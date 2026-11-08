import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workday/workday_controller.dart';
import '../workday/workday_providers.dart';
import 'mascot_settings.dart';

/// Recordatorios para no quedarse trabajando hasta muy tarde.
///
/// Solo con una jornada en curso, como mucho uno por umbral y por noche:
/// a las 22:00, a las 23:30 y a la 1:00. Si se empieza tarde, se dice solo
/// el último umbral ya pasado (no tres seguidos).
class LateNightReminder {
  /// Tiempo desde la medianoche del día en que empezó la noche (la 1:00 de
  /// la madrugada son 25 h).
  static const thresholds = [
    Duration(hours: 22),
    Duration(hours: 23, minutes: 30),
    Duration(hours: 25),
  ];

  String? _night;
  int _shown = 0; // cuántos umbrales ya se dijeron esta noche

  /// Devuelve el mensaje a mostrar ahora, o `null`.
  String? check(DateTime now, {required bool sessionActive}) {
    final local = now.toLocal();
    // Antes de las 5:00 seguimos en la noche del día anterior.
    final early = local.hour < 5;
    final day = early
        ? DateTime(local.year, local.month, local.day - 1)
        : DateTime(local.year, local.month, local.day);
    final key = '${day.year}-${day.month}-${day.day}';
    if (key != _night) {
      _night = key;
      _shown = 0;
    }
    if (!sessionActive) return null;

    final sinceMidnight =
        Duration(hours: local.hour + (early ? 24 : 0), minutes: local.minute);
    var reached = 0;
    for (final t in thresholds) {
      if (sinceMidnight >= t) reached++;
    }
    if (reached <= _shown) return null;
    _shown = reached;
    return message(reached - 1, local);
  }

  static String message(int index, DateTime local) {
    final time = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
    return switch (index) {
      0 => '🌙 Ya son las $time. ¿Cerramos por hoy? Descansar también es '
          'avanzar.',
      1 => '🌙 Son las $time y seguimos aquí. Tu yo de mañana te lo '
          'agradecerá: ¿lo dejamos?',
      _ => '😴 Ya es la $time… De verdad, a dormir. Mañana seguimos.',
    };
  }
}

/// El aviso visible (o `null`); desaparece solo.
class LateNightController extends StateNotifier<String?> {
  final LateNightReminder _reminder = LateNightReminder();
  final MascotSettings _settings;
  final DateTime Function() _now;
  final Duration autoHide;
  Timer? _hide;

  LateNightController(this._settings,
      {DateTime Function()? now, this.autoHide = const Duration(seconds: 40)})
      : _now = now ?? DateTime.now,
        super(null);

  void onTick(WorkdayView view) {
    final active = view.isActive && _settings.nightReminders;
    final message = _reminder.check(_now(), sessionActive: active);
    if (message == null) return;
    _hide?.cancel();
    state = message;
    _hide = Timer(autoHide, () {
      if (mounted) state = null;
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }
}

final lateNightProvider =
    StateNotifierProvider<LateNightController, String?>((ref) {
  final controller = LateNightController(ref.watch(mascotSettingsProvider));
  ref.listen<WorkdayView>(
    workdayControllerProvider,
    (_, view) => controller.onTick(view),
  );
  return controller;
});
