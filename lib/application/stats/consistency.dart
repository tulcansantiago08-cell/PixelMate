import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workday/workday_providers.dart';
import '../workday/workday_store.dart';
import 'stats_providers.dart';

/// Racha amable: cuántos de los últimos 7 días hubo alguna sesión.
///
/// No hay días "seguidos" que se rompan por descansar: se cuenta una
/// ventana de 7 días que avanza con el calendario.
class Consistency {
  /// Del más antiguo a hoy; `true` si ese día hubo sesión.
  final List<bool> days;

  /// Hoy (medianoche local).
  final DateTime today;

  const Consistency(this.days, this.today);

  int get active => days.where((d) => d).length;
  int get window => days.length;
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Días (medianoche local) con alguna sesión.
Set<DateTime> activeDaySet(Iterable<WorkdayRecord> records) =>
    {for (final r in records) _day(r.startedAt)};

Consistency consistencyAt(Set<DateTime> activeDays, DateTime now,
    {int window = 7}) {
  final today = _day(now);
  return Consistency([
    for (var i = window - 1; i >= 0; i--)
      activeDays.contains(DateTime(today.year, today.month, today.day - i))
  ], today);
}

/// Si en algún tramo de 7 días hubo sesiones en al menos [need] de ellos.
bool hasSteadyWindow(Set<DateTime> activeDays, {int need = 5, int window = 7}) {
  for (final start in activeDays) {
    final end = DateTime(start.year, start.month, start.day + window - 1);
    if (consistencyAt(activeDays, end, window: window).active >= need) {
      return true;
    }
  }
  return false;
}

/// Hito para celebrar al llegar a 5 o a 7 de 7 (el mismo día, subiendo).
/// `null` si no hay nada que celebrar.
String? consistencyMilestone(Consistency? before, Consistency after) {
  if (before == null || before.today != after.today) return null;
  if (after.active <= before.active) return null;
  return switch (after.active) {
    7 => '🌱 ¡7 de los últimos 7 días! Constancia total. Recuerda que '
        'descansar también cuenta 😌',
    5 => '🌱 ¡5 de los últimos 7 días! Qué buen ritmo llevas.',
    _ => null,
  };
}

/// La racha de hoy, incluida la sesión en curso.
final consistencyProvider = Provider<Consistency>((ref) {
  final history = ref.watch(recentHistoryProvider);
  final live = ref.watch(workdayControllerProvider.select((v) => v.timer));
  final now = DateTime.now();
  return consistencyAt({
    ...activeDaySet(history),
    if (live != null) _day(live.startedAt),
  }, now);
});
