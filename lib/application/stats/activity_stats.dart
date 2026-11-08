import '../../domain/activity/activity_mode.dart';
import '../workday/workday_store.dart';

enum StatsPeriod { today, week, month }

extension StatsPeriodX on StatsPeriod {
  String get label => switch (this) {
        StatsPeriod.today => 'Hoy',
        StatsPeriod.week => 'Semana',
        StatsPeriod.month => 'Mes',
      };
}

/// Modos con sesiones medibles (el modo libre no tiene temporizador).
const trackedModes = [
  ActivityMode.work,
  ActivityMode.study,
  ActivityMode.gaming
];

/// Totales de un modo dentro del periodo.
class ModeTotals {
  final Duration focus;
  final Duration breaks;
  final int sessions;
  final int completed;
  final int cycles;

  const ModeTotals({
    this.focus = Duration.zero,
    this.breaks = Duration.zero,
    this.sessions = 0,
    this.completed = 0,
    this.cycles = 0,
  });

  ModeTotals operator +(WorkdayRecord r) => ModeTotals(
        focus: focus + r.effectiveFocus,
        breaks: breaks + r.effectiveBreak,
        sessions: sessions + 1,
        completed: completed + (r.completed ? 1 : 0),
        cycles: cycles + r.cyclesCompleted,
      );
}

/// Tiempo de enfoque de un día, por modo (para el gráfico).
class DayBucket {
  final DateTime day; // medianoche local
  final Map<ActivityMode, Duration> focusByMode;

  const DayBucket(this.day, this.focusByMode);

  Duration get total =>
      focusByMode.values.fold(Duration.zero, (sum, d) => sum + d);
}

class ActivityStats {
  final StatsPeriod period;
  final DateTime start; // inclusive, medianoche local
  final DateTime end; // exclusivo
  final Map<ActivityMode, ModeTotals> byMode;

  /// Un elemento por día del periodo (vacío para "Hoy").
  final List<DayBucket> days;

  /// Sesiones del periodo, la más reciente primero.
  final List<WorkdayRecord> sessions;

  const ActivityStats({
    required this.period,
    required this.start,
    required this.end,
    required this.byMode,
    required this.days,
    required this.sessions,
  });

  ModeTotals totals(ActivityMode mode) => byMode[mode] ?? const ModeTotals();

  Duration get totalFocus =>
      byMode.values.fold(Duration.zero, (sum, t) => sum + t.focus);

  /// Días con alguna sesión. Se muestra en positivo: no hay "rachas" que
  /// se rompan por descansar.
  int get activeDays => days.where((d) => d.total > Duration.zero).length;

  bool get isEmpty => sessions.isEmpty;
}

/// Inicio del periodo que contiene [now] (hora local). La semana empieza
/// el lunes.
DateTime periodStart(StatsPeriod period, DateTime now) {
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  return switch (period) {
    StatsPeriod.today => today,
    StatsPeriod.week => DateTime(
        today.year, today.month, today.day - (today.weekday - DateTime.monday)),
    StatsPeriod.month => DateTime(today.year, today.month),
  };
}

DateTime periodEnd(StatsPeriod period, DateTime start) => switch (period) {
      StatsPeriod.today => DateTime(start.year, start.month, start.day + 1),
      StatsPeriod.week => DateTime(start.year, start.month, start.day + 7),
      StatsPeriod.month => DateTime(start.year, start.month + 1),
    };

/// Calcula las estadísticas del periodo.
///
/// Cada sesión cuenta en el día (local) en que empezó. [live] es la sesión
/// en curso, con su tiempo hasta ahora.
ActivityStats computeStats({
  required StatsPeriod period,
  required DateTime now,
  required List<WorkdayRecord> history,
  WorkdayRecord? live,
}) {
  final start = periodStart(period, now);
  final end = periodEnd(period, start);

  DateTime dayOf(WorkdayRecord r) {
    final l = r.startedAt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  final records = [
    for (final r in [...history, if (live != null) live])
      if (!dayOf(r).isBefore(start) && dayOf(r).isBefore(end)) r
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final byMode = <ActivityMode, ModeTotals>{};
  for (final r in records) {
    byMode[r.mode] = (byMode[r.mode] ?? const ModeTotals()) + r;
  }

  final days = <DayBucket>[];
  if (period != StatsPeriod.today) {
    for (var d = start;
        d.isBefore(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final focus = <ActivityMode, Duration>{};
      for (final r in records.where((r) => dayOf(r) == d)) {
        focus[r.mode] = (focus[r.mode] ?? Duration.zero) + r.effectiveFocus;
      }
      days.add(DayBucket(d, focus));
    }
  }

  return ActivityStats(
    period: period,
    start: start,
    end: end,
    byMode: byMode,
    days: days,
    sessions: records,
  );
}
