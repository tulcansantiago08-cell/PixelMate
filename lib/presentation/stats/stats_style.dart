import 'package:flutter/material.dart';

import '../../domain/activity/activity_mode.dart';

/// Colores, letra y tarjetas de los paneles: azul noche con vidrio y un
/// azul eléctrico de acento.
///
/// Colores de modo: espacios 1–3 de la paleta categórica oscura de
/// referencia. Orden fijo: el color sigue al modo, nunca a su posición.
class StatsStyle {
  /// Letra de toda la app (geométrica, incluida en macOS).
  static const fontFamily = 'Avenir Next';

  static const surface = Color(0xFF111833);
  static const surfaceRaised = Color(0xFF1C2550);
  static const textPrimary = Color(0xFFF5F7FF);
  static const textSecondary = Color(0xFFB3BBDC);
  static const textMuted = Color(0xFF7480AD);
  static const accent = Color(0xFF3D5AFE);
  static const accentLight = Color(0xFF6E8BFF);
  static const grid = Color(0xFF283260);

  /// Borde fino, como de vidrio.
  static const glassBorder = Color(0x1FFFFFFF);

  /// Fondo de los paneles: azul noche con un brillo azul arriba.
  static BoxDecoration panel({double radius = 20}) => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF51A2556), Color(0xF5111833), Color(0xF50C1128)],
          stops: [0, 0.45, 1],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glassBorder),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: -2,
          ),
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      );

  /// Una tarjeta dentro de un panel (un poco más clara).
  static BoxDecoration card({double radius = 14, bool highlighted = false}) =>
      BoxDecoration(
        gradient: highlighted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A44D8), Color(0xFF1A2A8C)],
              )
            : null,
        color: highlighted ? null : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glassBorder),
      );

  /// El degradado de los botones y la barra de título.
  static const accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accent, accentLight],
  );

  static Color modeColor(ActivityMode mode) => switch (mode) {
        ActivityMode.work => const Color(0xFF3987E5),
        ActivityMode.study => const Color(0xFFD95926),
        ActivityMode.gaming => const Color(0xFF199E70),
        ActivityMode.free => textMuted,
      };

  static String modeLabel(ActivityMode mode) => switch (mode) {
        ActivityMode.work => 'Trabajo',
        ActivityMode.study => 'Estudio',
        ActivityMode.gaming => 'Juego',
        ActivityMode.free => 'Libre',
      };
}

/// "2 h 10 min", "45 min", "<1 min" o "0 min" (redondeo hacia abajo:
/// no inflamos lo que el usuario hizo).
String formatSpent(Duration d) {
  if (d == Duration.zero) return '0 min';
  final minutes = d.inMinutes;
  if (minutes == 0) return '<1 min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

const _weekdayShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _weekdayLong = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic'
];

String weekdayInitial(DateTime d) => _weekdayShort[d.weekday - 1];

/// "Martes 10 nov".
String longDate(DateTime d) =>
    '${_weekdayLong[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "Hoy 09:12", "Ayer 18:40" o "10 nov 09:12".
String sessionWhen(DateTime startedAt, DateTime now) {
  final l = startedAt.toLocal();
  final n = now.toLocal();
  final day = DateTime(l.year, l.month, l.day);
  final today = DateTime(n.year, n.month, n.day);
  final hm = '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Hoy $hm';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Ayer $hm';
  }
  return '${l.day} ${_months[l.month - 1]} $hm';
}
