import 'package:flutter/material.dart';

import '../../application/progress/progression.dart';
import 'stats_style.dart';

/// Nivel, barra de XP y logros, arriba del panel de estadísticas.
class LevelCard extends StatelessWidget {
  final PlayerProgress progress;

  const LevelCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final unlocked = achievements.where(progress.isUnlocked).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: StatsStyle.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Nv. ${progress.level}',
                key: const ValueKey('level'),
                style: const TextStyle(
                    color: StatsStyle.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(progress.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: StatsStyle.textSecondary, fontSize: 12)),
            ),
            Text('${progress.xp} XP',
                style: const TextStyle(
                    color: StatsStyle.textMuted,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          Tooltip(
            message: '${progress.xpIntoLevel} de ${progress.xpNeededForNext} XP'
                ' para el nivel ${progress.level + 1}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.levelFraction.clamp(0, 1),
                minHeight: 8,
                backgroundColor: StatsStyle.grid,
                color: StatsStyle.accent,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Faltan ${progress.xpNeededForNext - progress.xpIntoLevel} XP '
            'para el nivel ${progress.level + 1}',
            style: const TextStyle(color: StatsStyle.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Text('Logros $unlocked/${achievements.length}',
              style: const TextStyle(
                  color: StatsStyle.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final a in achievements) _Badge(a, progress.isUnlocked(a)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  const _Badge(this.achievement, this.unlocked);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${achievement.title}${unlocked ? ' ✓' : ' (bloqueado)'}\n'
          '${achievement.description}',
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: unlocked ? StatsStyle.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: unlocked ? StatsStyle.accent : StatsStyle.grid),
        ),
        // Bloqueados: candado en lugar del emoji, no solo un color apagado.
        child: Text(unlocked ? achievement.emoji : '🔒',
            style: TextStyle(fontSize: unlocked ? 14 : 11)),
      ),
    );
  }
}
