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
                  ? 'Sin meta diaria'
                  : s.reached
                      ? '🎯 ¡Meta cumplida!'
                      : '🎯 Faltan ${formatSpent(s.remaining)} para tu meta',
              style: const TextStyle(
                  color: StatsStyle.textSecondary, fontSize: 11),
            ),
          ),
          PopupMenuButton<Duration>(
            key: const ValueKey('goal-picker'),
            tooltip: 'Cambiar la meta diaria',
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
                        ? 'Sin meta'
                        : '${formatSpent(option)} al día',
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                goal == Duration.zero
                    ? 'Poner meta ▾'
                    : 'Meta: ${formatSpent(goal)} ▾',
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
