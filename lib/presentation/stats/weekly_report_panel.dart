import '../../core/i18n/language.dart';
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

/// "3–9 nov" o "29 sep – 5 oct" (en inglés: "Nov 3–9", "Sep 29 – Oct 5").
String weekRange(DateTime start, DateTime end) {
  if (tr('es', 'en') == 'en') {
    final m = shortMonths;
    return start.month == end.month
        ? '${m[end.month - 1]} ${start.day}–${end.day}'
        : '${m[start.month - 1]} ${start.day} – ${m[end.month - 1]} ${end.day}';
  }
  return start.month == end.month
      ? '${start.day}–${end.day} ${_months[end.month - 1]}'
      : '${start.day} ${_months[start.month - 1]} – ${end.day} ${_months[end.month - 1]}';
}

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
      decoration: StatsStyle.panel(),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _Arrow(
              key: const ValueKey('weekly-prev'),
              icon: Icons.chevron_left,
              tooltip: tr('Semana anterior', 'Previous week'),
              onTap: () => ref.read(weeklyReportWeekProvider.notifier).state =
                  DateTime(week.year, week.month, week.day - 7),
            ),
            Expanded(
              child: Text(
                  '${current ? tr('Esta semana', 'This week') : tr('Tu semana', 'Your week')} · '
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
              tooltip: tr('Semana siguiente', 'Next week'),
              onTap: current
                  ? null
                  : () => ref.read(weeklyReportWeekProvider.notifier).state =
                      DateTime(week.year, week.month, week.day + 7),
            ),
            IconButton(
              tooltip: tr('Cerrar', 'Close'),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(tr('Esta semana no hubo sesiones.', 'There were no sessions this week.'),
                            style: const TextStyle(
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
                      _Line(Icons.calendar_today_outlined,
                          tr('${report.activeDays} de 7 días activos', '${report.activeDays} of 7 days active')),
                      _Line(
                          Icons.check_circle_outline_rounded,
                          '${report.sessions} '
                          '${report.sessions == 1 ? tr('sesión', 'session') : tr('sesiones', 'sessions')}'
                          '${report.completed > 0 ? ' · ${report.completed} ${report.completed == 1 ? tr('completa', 'completed') : tr('completas', 'completed')}' : ''}'),
                      if (report.goal != null)
                        _Line(Icons.flag_outlined,
                            tr('Meta cumplida ${report.goalDays} de 7 días', 'Goal reached ${report.goalDays} of 7 days')),
                      if (report.bestDay case final best?)
                        _Line(Icons.emoji_events_outlined,
                            tr('Mejor día: ${longDate(best.day)} (${formatSpent(best.total)})', 'Best day: ${longDate(best.day)} (${formatSpent(best.total)})')),
                      _Line(Icons.star_outline_rounded, '+${report.xp} XP'),
                      if (report.bestTimeOfDay case final moment?)
                        _Line(
                            Icons.schedule_rounded, tr('Te enfocas más $moment.', 'You focus most $moment.')),
                      if (report.suggestedGoal case final next?)
                        _GoalSuggestion(next: next, current: goal),
                      const SizedBox(height: 10),
                      FutureBuilder<String?>(
                        future: _comment,
                        builder: (context, snap) {
                          final text = snap.data;
                          if (snap.connectionState != ConnectionState.done) {
                            return Text(tr('$name está pensando…', '$name is thinking…'),
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
                            child: Text('$name: $text',
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
      return tr('de enfoque · la semana pasada no hubo sesiones', 'of focus · no sessions last week');
    }
    if (r.change == Duration.zero) return tr('de enfoque · igual que la anterior', 'of focus · same as the previous one');
    return r.change > Duration.zero
        ? tr('de enfoque · ▲ ${formatSpent(r.change)} más que la anterior', 'of focus · ▲ ${formatSpent(r.change)} more than the previous one')
        : tr('de enfoque · ▼ ${formatSpent(-r.change)} menos que la anterior', 'of focus · ▼ ${formatSpent(-r.change)} less than the previous one');
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 15, color: StatsStyle.accentLight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: StatsStyle.textPrimary, fontSize: 12)),
          ),
        ]),
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

/// «Meta para la próxima semana: 3 h al día» y un botón para usarla.
class _GoalSuggestion extends ConsumerWidget {
  final Duration next;
  final Duration? current;
  const _GoalSuggestion({required this.next, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final same = current == next;
    return Container(
      key: const ValueKey('weekly-goal'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: StatsStyle.card(highlighted: true),
      child: Row(children: [
        const Icon(Icons.flag_outlined, size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              same
                  ? tr('Tu meta de ${next.inHours} h al día va bien: mantenla.', 'Your ${next.inHours} h a day goal is going well: keep it.')
                  : tr('Para la próxima semana: ${next.inHours} h al día.', 'For next week: ${next.inHours} h a day.'),
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        if (!same)
          TextButton(
            key: const ValueKey('weekly-goal-use'),
            style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact),
            onPressed: () => ref.read(dailyGoalSettingsProvider).setGoal(next),
            child: Text(tr('Usarla', 'Use it'), style: const TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}
