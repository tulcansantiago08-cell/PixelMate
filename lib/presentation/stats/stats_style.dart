import 'package:flutter/material.dart';

import '../../domain/activity/activity_mode.dart';

/// Colores y textos del panel de estadísticas.
///
/// Colores de modo: espacios 1–3 de la paleta categórica oscura de
/// referencia, validados juntos sobre la superficie #1E1B2E (todas las
/// comprobaciones de contraste y daltonismo superadas). Orden fijo: el color
/// sigue al modo, nunca a su posición.
class StatsStyle {
  static const surface = Color(0xFF1E1B2E);
  static const surfaceRaised = Color(0xFF2A2640);
  static const textPrimary = Color(0xFFF0EFEC);
  static const textSecondary = Color(0xFFC3C2B7);
  static const textMuted = Color(0xFF8E8AA3);
  static const accent = Color(0xFF7C3AED);
  static const grid = Color(0xFF3A3550);

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
