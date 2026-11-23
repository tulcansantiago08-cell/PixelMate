import '../../core/i18n/language.dart';
import 'package:flutter/material.dart';

import '../../application/goals/daily_goal.dart';
import 'stats_style.dart';

/// Meta de hoy: barra de progreso y selector de la meta.
class DailyGoalRow extends StatelessWidget {
  /// `null` si no hay meta.
  final DailyGoalStatus? status;
  final Duration goal;
  final ValueChanged<Duration> onGoalChanged;

  const DailyGoalRow({
    super.key,
    required this.status,
    required this.goal,
    required this.onGoalChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              s == null
                  ? tr('Sin meta diaria', 'No daily goal')
                  : s.reached
                      ? tr('Meta cumplida', 'Goal reached')
                      : tr('Faltan ${formatSpent(s.remaining)} para tu meta', '${formatSpent(s.remaining)} to go for your goal'),
              style: const TextStyle(
                  color: StatsStyle.textSecondary, fontSize: 11),
            ),
          ),
          PopupMenuButton<Duration>(
            key: const ValueKey('goal-picker'),
            tooltip: tr('Cambiar la meta diaria', 'Change the daily goal'),
            initialValue: goal,
            onSelected: onGoalChanged,
            color: StatsStyle.surfaceRaised,
            itemBuilder: (_) => [
              for (final option in DailyGoalSettings.options)
                PopupMenuItem(
                  value: option,
                  height: 32,
                  child: Text(
                    option == Duration.zero
                        ? tr('Sin meta', 'No goal')
                        : tr('${formatSpent(option)} al día', '${formatSpent(option)} a day'),
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                goal == Duration.zero
                    ? tr('Poner meta ▾', 'Set goal ▾')
                    : tr('Meta: ${formatSpent(goal)} ▾', 'Goal: ${formatSpent(goal)} ▾'),
                style: const TextStyle(
                    color: StatsStyle.textPrimary, fontSize: 11),
              ),
            ),
          ),
        ]),
        if (s != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: s.fraction,
              minHeight: 6,
              backgroundColor: StatsStyle.grid,
              color: StatsStyle.accent,
            ),
          ),
        ],
      ],
    );
  }
}
