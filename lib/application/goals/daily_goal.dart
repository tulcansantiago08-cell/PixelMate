import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stats/activity_stats.dart';
import '../stats/stats_providers.dart';
import '../workday/workday_providers.dart';
import '../workday/workday_store.dart';

/// Meta diaria de enfoque, guardada localmente.
class DailyGoalSettings extends ChangeNotifier {
  static const _key = 'goal.dailyMinutes';
  static const defaultGoal = Duration(hours: 4);

  /// Opciones del selector. `Duration.zero` = sin meta.
  static const options = [
    Duration.zero,
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
    Duration(hours: 5),
    Duration(hours: 6),
    Duration(hours: 8),
  ];

  /// Sin [prefs] el valor solo vive en memoria (pruebas).
  final SharedPreferences? _prefs;
  Duration _goal;

  DailyGoalSettings([this._prefs])
      : _goal = switch (_prefs?.getInt(_key)) {
          final m? when m >= 0 => Duration(minutes: m),
          _ => defaultGoal,
        };

  Duration get goal => _goal;
  bool get enabled => _goal > Duration.zero;

  Future<void> setGoal(Duration value) async {
    _goal = value;
    await _prefs?.setInt(_key, value.inMinutes);
    notifyListeners();
  }
}

/// Cuánto lleva hoy respecto a la meta.
class DailyGoalStatus {
  final Duration done;
  final Duration goal;

  const DailyGoalStatus({required this.done, required this.goal});

  bool get reached => done >= goal;
  double get fraction =>
      (done.inSeconds / goal.inSeconds).clamp(0, 1).toDouble();
  Duration get remaining => reached ? Duration.zero : goal - done;
}

/// `true` si [after] acaba de cumplir la meta por avanzar (no por bajarla
/// ni al abrir la app con la meta ya cumplida).
bool goalJustReached(DailyGoalStatus? before, DailyGoalStatus? after) =>
    before != null &&
    after != null &&
    before.goal == after.goal &&
    !before.reached &&
    after.reached;

String goalReachedMessage(Duration goal) {
  final h = goal.inMinutes ~/ 60, m = goal.inMinutes % 60;
  final text = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
  return '¡Meta diaria cumplida! $text de enfoque hoy 🎯 Lo que sigue es extra.';
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final dailyGoalSettingsProvider =
    Provider<DailyGoalSettings>((_) => DailyGoalSettings());

/// Progreso de hoy, incluida la sesión en curso. `null` si no hay meta.
final dailyGoalProvider = Provider<DailyGoalStatus?>((ref) {
  final settings = ref.watch(dailyGoalSettingsProvider);
  void changed() => ref.invalidateSelf();
  settings.addListener(changed);
  ref.onDispose(() => settings.removeListener(changed));
  if (!settings.enabled) return null;

  final view = ref.watch(workdayControllerProvider);
  final now = DateTime.now();
  final timer = view.timer;
  final mode = view.mode;
  final today = computeStats(
    period: StatsPeriod.today,
    now: now,
    history: ref.watch(recentHistoryProvider),
    live: timer != null && mode != null
        ? WorkdayRecord.fromTimer(mode, timer, now)
        : null,
  );
  return DailyGoalStatus(done: today.totalFocus, goal: settings.goal);
});
