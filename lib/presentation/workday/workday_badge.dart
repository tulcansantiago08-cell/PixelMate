import 'package:flutter/material.dart';

import '../../application/workday/workday_controller.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';

/// Globo pequeño sobre la mascota: frase de la mascota o fase y tiempo restante.
class WorkdayBadge extends StatelessWidget {
  final WorkdayView view;
  final String? speech;

  const WorkdayBadge({super.key, required this.view, this.speech});

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String? statusLine(WorkdayView view) {
    final status = view.status;
    final phase = status?.phase;
    if (status == null || phase == null) return null;
    final icon = switch (phase.kind) {
      SessionPhase.focus => '🎯',
      SessionPhase.shortBreak => '☕',
      SessionPhase.longBreak => '🌿',
      SessionPhase.idle => '',
    };
    final paused = status.state == WorkdayRunState.paused ? ' ⏸' : '';
    // Cuenta regresiva: se redondea hacia arriba (al empezar muestra 50:00).
    final remaining = Duration(
        seconds: (status.phaseRemaining.inMilliseconds / 1000).ceil());
    return '$icon ${phase.kind.displayName} ${formatDuration(remaining)}$paused';
  }

  @override
  Widget build(BuildContext context) {
    final line = statusLine(view);
    if (speech == null && line == null) return const SizedBox.shrink();
    final progress = view.status?.progress;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xEE1E1B2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7C3AED), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (speech != null)
            Text(speech!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (line != null) ...[
            if (speech != null) const SizedBox(height: 4),
            Text(line,
                style: const TextStyle(
                    color: Color(0xFFD8CCFF),
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (progress != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: const Color(0xFF3A3550),
                  color: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
