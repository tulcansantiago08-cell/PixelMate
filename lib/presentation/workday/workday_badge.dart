import 'package:flutter/material.dart';

import '../../application/workday/workday_controller.dart';
import '../../application/workday/workday_format.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../common/plain_text.dart';
import '../stats/stats_style.dart';

/// Globo pequeño sobre la mascota: frase de la mascota o fase y tiempo restante.
class WorkdayBadge extends StatelessWidget {
  final WorkdayView view;
  final String? speech;

  /// Si no es `null`, muestra «🌟 ¿Jugamos?» (minijuego del descanso).
  final VoidCallback? onPlay;

  const WorkdayBadge({super.key, required this.view, this.speech, this.onPlay});

  static String? statusLine(WorkdayView view) {
    final status = view.status;
    final phase = status?.phase;
    if (status == null || phase == null) return null;
    final paused = status.state == WorkdayRunState.paused ? ' · en pausa' : '';
    return '${phaseIcon(phase.kind)} ${phase.kind.displayName} '
        '${formatCountdown(status.phaseRemaining)}$paused';
  }

  @override
  Widget build(BuildContext context) {
    final line = statusLine(view);
    if (speech == null && line == null) return const SizedBox.shrink();
    final progress = view.status?.progress;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: StatsStyle.panel(radius: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (speech != null)
            PlainText(speech!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: StatsStyle.textPrimary, fontSize: 13, height: 1.35)),
          if (line != null) ...[
            if (speech != null) const SizedBox(height: 4),
            Text(line,
                style: const TextStyle(
                    color: StatsStyle.textSecondary,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (progress != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: StatsStyle.grid,
                  color: StatsStyle.accent,
                ),
              ),
            ],
          ],
          if (onPlay != null) ...[
            const SizedBox(height: 4),
            InkWell(
              key: const ValueKey('badge-play'),
              onTap: onPlay,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sports_esports_outlined,
                      size: 14, color: StatsStyle.accentLight),
                  SizedBox(width: 4),
                  Text('¿Jugamos? +XP',
                      style: TextStyle(
                          color: StatsStyle.accentLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
