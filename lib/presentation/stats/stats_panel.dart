import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/stats/activity_stats.dart';
import '../../application/stats/stats_providers.dart';
import '../../application/workday/workday_providers.dart';
import '../../domain/activity/activity_mode.dart';
import '../../application/workday/workday_store.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/stats/consistency.dart';
import 'consistency_row.dart';
import 'daily_goal_row.dart';
import 'level_card.dart';
import 'stats_chart.dart';
import 'stats_style.dart';

/// Panel de estadísticas: hoy, semana y mes, separado por modo.
class StatsPanel extends ConsumerWidget {
  final VoidCallback onClose;

  /// Abre el resumen semanal (si no se da, no se muestra el botón).
  final VoidCallback? onShowWeekly;

  const StatsPanel({super.key, required this.onClose, this.onShowWeekly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(activityStatsProvider);
    final period = ref.watch(statsPeriodProvider);
    final liveId =
        ref.watch(workdayControllerProvider.select((v) => v.timer?.id));

    return Container(
      decoration: BoxDecoration(
        color: StatsStyle.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatsStyle.accent, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('📊 Estadísticas',
                  style: TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          _PeriodSelector(
            selected: period,
            onSelected: (p) => ref.read(statsPeriodProvider.notifier).state = p,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 4),
              children: [
                LevelCard(
                  progress: ref.watch(progressProvider),
                  equipped: ref.watch(equippedAccessoryProvider),
                  onEquip: (a) =>
                      ref.read(mascotSettingsProvider).setAccessory(a),
                ),
                const SizedBox(height: 12),
                _Hero(stats: stats),
                const SizedBox(height: 6),
                ConsistencyRow(consistency: ref.watch(consistencyProvider)),
                if (period == StatsPeriod.today) ...[
                  const SizedBox(height: 8),
                  DailyGoalRow(
                    status: ref.watch(dailyGoalProvider),
                    goal: ref.watch(dailyGoalSettingsProvider).goal,
                    onGoalChanged: (g) =>
                        ref.read(dailyGoalSettingsProvider).setGoal(g),
                  ),
                  if (ref.watch(distractionsTodayProvider) case final d?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        d.episodes == 0
                            ? '🛡️ Sin distracciones en el enfoque de hoy'
                            : '👀 ${d.episodes} '
                                '${d.episodes == 1 ? 'distracción' : 'distracciones'}'
                                ' en el enfoque · ${formatSpent(d.time)}',
                        key: const ValueKey('distractions-today'),
                        style: const TextStyle(
                            color: StatsStyle.textSecondary, fontSize: 11),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                for (final mode in trackedModes)
                  _ModeRow(mode: mode, totals: stats.totals(mode)),
                if (stats.days.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StatsDayChart(days: stats.days),
                ],
                if (onShowWeekly != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('open-weekly'),
                    onPressed: onShowWeekly,
                    child: const Text('📅 Resumen de la semana'),
                  ),
                ],
                const SizedBox(height: 12),
                _RecentSessions(sessions: stats.sessions, liveId: liveId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onSelected;

  const _PeriodSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final p in StatsPeriod.values)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: p == selected ? StatsStyle.accent : StatsStyle.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelected(p),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(p.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: p == selected
                          ? Colors.white
                          : StatsStyle.textSecondary,
                    )),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  final ActivityStats stats;
  const _Hero({required this.stats});

  @override
  Widget build(BuildContext context) {
    final subtitle = stats.isEmpty
        ? 'Aún no hay sesiones. ¡Cuando quieras empezamos! 🐾'
        : stats.period == StatsPeriod.today
            ? '${stats.sessions.length} ${stats.sessions.length == 1 ? 'sesión' : 'sesiones'}'
            : '${stats.activeDays} ${stats.activeDays == 1 ? 'día activo' : 'días activos'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatSpent(stats.totalFocus),
            style: const TextStyle(
                color: StatsStyle.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700)),
        Text('de actividad · $subtitle',
            style:
                const TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  final ActivityMode mode;
  final ModeTotals totals;
  const _ModeRow({required this.mode, required this.totals});

  @override
  Widget build(BuildContext context) {
    final detail = totals.sessions == 0
        ? 'sin sesiones'
        : '${totals.sessions} ${totals.sessions == 1 ? 'sesión' : 'sesiones'}'
            '${totals.completed > 0 ? ' · ${totals.completed} ${totals.completed == 1 ? 'completa' : 'completas'}' : ''}'
            '${totals.breaks > Duration.zero ? ' · ${formatSpent(totals.breaks)} de descanso' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: StatsStyle.modeColor(mode),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(StatsStyle.modeLabel(mode),
                  style: const TextStyle(
                      color: StatsStyle.textPrimary, fontSize: 13)),
              Text(detail,
                  style: const TextStyle(
                      color: StatsStyle.textMuted, fontSize: 10)),
            ],
          ),
        ),
        Text(formatSpent(totals.focus),
            style: const TextStyle(
                color: StatsStyle.textPrimary,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _RecentSessions extends StatelessWidget {
  final List<WorkdayRecord> sessions;
  final String? liveId;
  const _RecentSessions({required this.sessions, required this.liveId});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Últimas sesiones',
            style: TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        for (final s in sessions.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Container(
                width: 3,
                height: 26,
                color: StatsStyle.modeColor(s.mode),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${sessionWhen(s.startedAt, now)} · ${StatsStyle.modeLabel(s.mode)}\n'
                  '${formatSpent(s.effectiveFocus)} · '
                  '${s.id == liveId ? 'en curso' : s.completed ? '✓ completa' : 'terminada'}',
                  style: const TextStyle(
                      color: StatsStyle.textPrimary, fontSize: 11),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}
