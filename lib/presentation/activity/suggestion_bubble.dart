import 'package:flutter/material.dart';

import '../../application/activity/suggestion.dart';
import '../common/plain_text.dart';
import '../stats/stats_style.dart';

/// Globo de la mascota con una pregunta y botones de respuesta.
class SuggestionBubble extends StatelessWidget {
  final Suggestion suggestion;
  final void Function(SuggestionAction action) onChoose;

  const SuggestionBubble({
    super.key,
    required this.suggestion,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 264),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: StatsStyle.panel(radius: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlainText(
            suggestion.message,
            style: const TextStyle(
                color: StatsStyle.textPrimary, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (i, option) in suggestion.options.indexed)
                _OptionButton(
                  label: option.label,
                  primary: i == 0,
                  onPressed: () => onChoose(option.action),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onPressed;

  const _OptionButton({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? StatsStyle.accent : StatsStyle.surfaceRaised,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            stripEmoji(label),
            style: TextStyle(
              color: primary ? Colors.white : const Color(0xFFD8CCFF),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
