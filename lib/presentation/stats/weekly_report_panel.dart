import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/chat_controller.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/stats/weekly_report.dart';
import 'stats_chart.dart';
import 'stats_style.dart';

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
  'dic',
];

/// "3–9 nov" o "29 sep – 5 oct".
String weekRange(DateTime start, DateTime end) => start.month == end.month
    ? '${start.day}–${end.day} ${_months[end.month - 1]}'
    : '${start.day} ${_months[start.month - 1]} – '
        '${end.day} ${_months[end.month - 1]}';

/// Resumen de la semana con el comentario de la mascota.
class WeeklyReportPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const WeeklyReportPanel({super.key, required this.onClose});

  @override
  ConsumerState<WeeklyReportPanel> createState() => _WeeklyReportPanelState();
}

class _WeeklyReportPanelState extends ConsumerState<WeeklyReportPanel> {
  Future<String?>? _comment;
  DateTime? _commentWeek;

  @override
  Widget build(BuildContext context) {
    final week = ref.watch(weeklyReportWeekProvider) ??
        latestReportableWeek(DateTime.now());
    final goal = ref.watch(dailyGoalSettingsProvider).goal;
    final report = buildWeeklyReport(
      history: ref.watch(allHistoryProvider),
      weekStart: week,
      goal: goal,
    );
    if (_commentWeek != week) {
      _commentWeek = week;
      _comment = report.isEmpty
          ? Future.value(null)
          : ref.read(chatProvider.notifier).commentWeek(report);
    }
    final name = ref.watch(petNameProvider);
    final current = week == weekStartOf(DateTime.now());

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
            _Arrow(
              key: const ValueKey('weekly-prev'),
              icon: Icons.chevron_left,
              tooltip: 'Semana anterior',
              onTap: () => ref.read(weeklyReportWeekProvider.notifier).state =
                  DateTime(week.year, week.month, week.day - 7),
            ),
            Expanded(
              child: Text(
                  '📅 ${current ? 'Esta semana' : 'Tu semana'} · '
                  '${weekRange(report.start, report.end)}',
                  key: const ValueKey('weekly-title'),
                  style: const TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            _Arrow(
              key: const ValueKey('weekly-next'),
              icon: Icons.chevron_right,
              tooltip: 'Semana siguiente',
              onTap: current
                  ? null
                  : () => ref.read(weeklyReportWeekProvider.notifier).state =
                      DateTime(week.year, week.month, week.day + 7),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 4),
              children: report.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                            'Esta semana no hubo sesiones. ¡La próxima la '
                            'empezamos juntos! 🐾',
                            style: TextStyle(
                                color: StatsStyle.textSecondary, fontSize: 12)),
                      ),
                    ]
                  : [
                      Text(formatSpent(report.focus),
                          key: const ValueKey('weekly-focus'),
                          style: const TextStyle(
                              color: StatsStyle.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w700)),
                      Text(_changeText(report),
                          key: const ValueKey('weekly-change'),
                          style: const TextStyle(
                              color: StatsStyle.textSecondary, fontSize: 11)),
                      const SizedBox(height: 10),
                      StatsDayChart(days: report.stats.days, height: 80),
                      const SizedBox(height: 10),
                      _Line('📆', '${report.activeDays} de 7 días activos'),
                      _Line(
                          '✅',
                          '${report.sessions} '
                              '${report.sessions == 1 ? 'sesión' : 'sesiones'}'
                              '${report.completed > 0 ? ' · ${report.completed} ${report.completed == 1 ? 'completa' : 'completas'}' : ''}'),
                      if (report.goal != null)
                        _Line(
                            '🎯', 'Meta cumplida ${report.goalDays} de 7 días'),
                      if (report.bestDay case final best?)
                        _Line('🏆',
                            'Mejor día: ${longDate(best.day)} (${formatSpent(best.total)})'),
                      _Line('⭐', '+${report.xp} XP'),
                      const SizedBox(height: 10),
                      FutureBuilder<String?>(
                        future: _comment,
                        builder: (context, snap) {
                          final text = snap.data;
                          if (snap.connectionState != ConnectionState.done) {
                            return Text('💬 $name está pensando…',
                                style: const TextStyle(
                                    color: StatsStyle.textMuted, fontSize: 12));
                          }
                          if (text == null) return const SizedBox.shrink();
                          return Container(
                            key: const ValueKey('weekly-comment'),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: StatsStyle.surfaceRaised,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('💬 $name: $text',
                                style: const TextStyle(
                                    color: StatsStyle.textPrimary,
                                    fontSize: 12)),
                          );
                        },
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  /// La diferencia también va en texto (no solo con flechas o colores).
  static String _changeText(WeeklyReport r) {
    if (r.previousFocus == Duration.zero) {
      return 'de enfoque · la semana pasada no hubo sesiones';
    }
    if (r.change == Duration.zero) return 'de enfoque · igual que la anterior';
    return r.change > Duration.zero
        ? 'de enfoque · ▲ ${formatSpent(r.change)} más que la anterior'
        : 'de enfoque · ▼ ${formatSpent(-r.change)} menos que la anterior';
  }
}

class _Line extends StatelessWidget {
  final String icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$icon  $text',
            style:
                const TextStyle(color: StatsStyle.textPrimary, fontSize: 12)),
      );
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _Arrow(
      {super.key, required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(icon,
            size: 20,
            color: onTap == null ? StatsStyle.grid : StatsStyle.textSecondary),
      );
}
