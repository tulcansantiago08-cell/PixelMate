import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/activity/activity_mode.dart';
import '../progress/progression.dart';
import '../workday/workday_store.dart';
import 'activity_stats.dart';

/// Resumen de una semana (lunes a domingo).
class WeeklyReport {
  final DateTime start; // lunes, medianoche local
  final ActivityStats stats;
  final Duration previousFocus;
  final int xp;

  /// Meta diaria usada para contar los días cumplidos (`null` si no hay).
  final Duration? goal;
  final int goalDays;

  const WeeklyReport({
    required this.start,
    required this.stats,
    required this.previousFocus,
    required this.xp,
    required this.goal,
    required this.goalDays,
  });

  DateTime get end => DateTime(start.year, start.month, start.day + 6);
  Duration get focus => stats.totalFocus;
  Duration get change => focus - previousFocus;
  int get activeDays => stats.activeDays;
  int get sessions => stats.sessions.length;
  int get completed => stats.sessions.where((s) => s.completed).length;
  bool get isEmpty => stats.isEmpty;

  /// Día con más enfoque (o `null` si no hubo).
  DayBucket? get bestDay {
    DayBucket? best;
    for (final d in stats.days) {
      if (d.total > Duration.zero && (best == null || d.total > best.total)) {
        best = d;
      }
    }
    return best;
  }
}

/// Lunes de la semana de [date] (hora local).
DateTime weekStartOf(DateTime date) => periodStart(StatsPeriod.week, date);

String weekKey(DateTime weekStart) =>
    '${weekStart.year}-${weekStart.month}-${weekStart.day}';

WeeklyReport buildWeeklyReport({
  required List<WorkdayRecord> history,
  required DateTime weekStart,
  Duration? goal,
}) {
  final stats =
      computeStats(period: StatsPeriod.week, now: weekStart, history: history);
  final previous = computeStats(
    period: StatsPeriod.week,
    now: DateTime(weekStart.year, weekStart.month, weekStart.day - 7),
    history: history,
  );
  final hasGoal = goal != null && goal > Duration.zero;
  return WeeklyReport(
    start: weekStart,
    stats: stats,
    previousFocus: previous.totalFocus,
    xp: stats.sessions.fold(0, (sum, r) => sum + xpForRecord(r)),
    goal: hasGoal ? goal : null,
    goalDays: hasGoal ? stats.days.where((d) => d.total >= goal).length : 0,
  );
}

/// La semana que se resume al pedirlo a mano: la en curso el domingo desde
/// las 18:00; si no, la anterior.
DateTime latestReportableWeek(DateTime now) => weekToReport(now)!;

/// Qué semana toca resumir ahora (o `null`): el domingo desde las 18:00, la
/// semana en curso; cualquier otro día, la anterior. Nunca dos veces la
/// misma.
DateTime? weekToReport(DateTime now, {String? lastShown}) {
  final local = now.toLocal();
  final thisWeek = weekStartOf(local);
  final week = local.weekday == DateTime.sunday && local.hour >= 18
      ? thisWeek
      : DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);
  return weekKey(week) == lastShown ? null : week;
}

String _dur(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

String _mode(ActivityMode m) => switch (m) {
      ActivityMode.work => 'trabajo',
      ActivityMode.study => 'estudio',
      ActivityMode.gaming => 'juego',
      ActivityMode.free => 'libre',
    };

/// Lo que se le pide a la IA para comentar la semana.
String weeklyPrompt(WeeklyReport r) {
  final modes = [
    for (final m in trackedModes)
      if (r.stats.totals(m).focus > Duration.zero)
        '${_mode(m)} ${_dur(r.stats.totals(m).focus)}'
  ].join(', ');
  final change = r.previousFocus == Duration.zero
      ? 'La semana anterior no tuve sesiones.'
      : r.change >= Duration.zero
          ? 'Son ${_dur(r.change)} más que la semana anterior.'
          : 'Son ${_dur(-r.change)} menos que la semana anterior.';
  final goal = r.goal == null
      ? ''
      : 'Cumplí mi meta diaria de ${_dur(r.goal!)} ${r.goalDays} '
          '${r.goalDays == 1 ? 'día' : 'días'}. ';
  return 'Este es el resumen de mi semana: ${_dur(r.focus)} de enfoque '
      '($modes) en ${r.activeDays} '
      '${r.activeDays == 1 ? 'día' : 'días'} y ${r.sessions} '
      '${r.sessions == 1 ? 'sesión' : 'sesiones'}. $change $goal'
      'Gané ${r.xp} XP. Coméntame la semana en 2 o 3 oraciones, con ánimo '
      'y un consejo concreto para la semana que empieza. No elijas ninguna '
      'acción.';
}

/// Qué semanas ya se mostraron y el comentario de la IA de cada una (para
/// no volver a generarlo al reabrir).
class WeeklyReportStore {
  static const _lastKey = 'weekly.lastShown';
  static String _commentKey(String week) => 'weekly.comment.$week';

  final SharedPreferences? _prefs;
  String? _last;
  final Map<String, String> _comments = {};

  WeeklyReportStore([this._prefs]) : _last = _prefs?.getString(_lastKey);

  String? get lastShown => _last;

  Future<void> markShown(DateTime weekStart) async {
    _last = weekKey(weekStart);
    await _prefs?.setString(_lastKey, _last!);
  }

  /// La clave incluye los números de la semana: si se vuelve a abrir con
  /// más sesiones (por ejemplo, a mitad de semana y luego el domingo), se
  /// genera un comentario nuevo.
  static String _fingerprint(WeeklyReport r) =>
      '${weekKey(r.start)}-${r.focus.inMinutes}-${r.sessions}';

  String? comment(WeeklyReport report) {
    final k = _fingerprint(report);
    return _comments[k] ?? _prefs?.getString(_commentKey(k));
  }

  Future<void> saveComment(WeeklyReport report, String text) async {
    final k = _fingerprint(report);
    _comments[k] = text;
    await _prefs?.setString(_commentKey(k), text);
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final weeklyReportStoreProvider =
    Provider<WeeklyReportStore>((_) => WeeklyReportStore());

/// Semana que muestra el panel del resumen.
final weeklyReportWeekProvider = StateProvider<DateTime?>((_) => null);
