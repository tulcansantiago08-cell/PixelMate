import 'package:flutter/material.dart';

import '../../application/stats/consistency.dart';
import 'stats_style.dart';

/// "🌱 5 de los últimos 7 días" con un punto por día (hoy a la derecha).
class ConsistencyRow extends StatelessWidget {
  final Consistency consistency;
  const ConsistencyRow({super.key, required this.consistency});

  @override
  Widget build(BuildContext context) {
    final c = consistency;
    return Row(children: [
      Expanded(
        child: Text(
          c.active == 0
              ? '🌱 Sin sesiones en los últimos 7 días'
              : '🌱 ${c.active} de los últimos ${c.window} días',
          key: const ValueKey('consistency-text'),
          style: const TextStyle(color: StatsStyle.textSecondary, fontSize: 11),
        ),
      ),
      for (var i = 0; i < c.days.length; i++)
        Tooltip(
          message:
              '${longDate(DateTime(c.today.year, c.today.month, c.today.day - (c.days.length - 1 - i)))}: '
              '${c.days[i] ? 'con sesión' : 'sin sesión'}',
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.days[i] ? StatsStyle.accent : Colors.transparent,
              border: Border.all(
                  color: c.days[i] ? StatsStyle.accent : StatsStyle.grid,
                  width: 1.5),
            ),
          ),
        ),
    ]);
  }
}
