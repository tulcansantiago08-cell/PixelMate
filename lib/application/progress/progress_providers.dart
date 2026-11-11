import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/star_catch.dart';
import '../workday/workday_providers.dart';
import '../workday/workday_store.dart';
import 'progression.dart';

/// Todo el historial. Se vuelve a leer solo cuando empieza o termina una
/// sesión.
final allHistoryProvider = Provider<List<WorkdayRecord>>((ref) {
  ref.watch(workdayControllerProvider.select((v) => v.timer?.id));
  return ref.watch(workdayStoreProvider).history();
});

/// Nivel, XP y logros, incluida la sesión en curso (la barra avanza en vivo).
final progressProvider = Provider<PlayerProgress>((ref) {
  final history = ref.watch(allHistoryProvider);
  final view = ref.watch(workdayControllerProvider);
  final timer = view.timer;
  final mode = view.mode;
  return computeProgress(
    history,
    bonusXp: ref.watch(gameXpProvider),
    live: timer != null && mode != null
        ? WorkdayRecord.fromTimer(mode, timer, DateTime.now())
        : null,
  );
});
