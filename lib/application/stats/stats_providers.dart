import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workday/workday_providers.dart';
import '../workday/workday_store.dart';
import 'activity_stats.dart';

/// Historial reciente. Se vuelve a leer de SQLite solo cuando empieza o
/// termina una sesión, no en cada tic del temporizador.
final recentHistoryProvider = Provider<List<WorkdayRecord>>((ref) {
  ref.watch(workdayControllerProvider.select((v) => v.timer?.id));
  final since = DateTime.now().subtract(const Duration(days: 40));
  return ref.watch(workdayStoreProvider).history(since: since);
});

final statsPeriodProvider =
    StateProvider<StatsPeriod>((_) => StatsPeriod.today);

/// Estadísticas del periodo elegido, incluida la sesión en curso.
final activityStatsProvider = Provider<ActivityStats>((ref) {
  final period = ref.watch(statsPeriodProvider);
  final history = ref.watch(recentHistoryProvider);
  final view = ref.watch(workdayControllerProvider);
  final now = DateTime.now();
  final timer = view.timer;
  final mode = view.mode;
  return computeStats(
    period: period,
    now: now,
    history: history,
    live: timer != null && mode != null
        ? WorkdayRecord.fromTimer(mode, timer, now)
        : null,
  );
});
