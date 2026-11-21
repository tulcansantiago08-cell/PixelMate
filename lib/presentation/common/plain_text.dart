import 'package:flutter/material.dart';

import '../stats/stats_style.dart';

/// Emojis y símbolos que se quitan del texto que se muestra (los mensajes
/// se escriben con emojis; la interfaz los dibuja con íconos de línea).
final _emoji = RegExp(
    // Sin tocar ⌃ ⌥ ⌘ ↩ ↗: son teclas y flechas, no emojis.
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{231A}\u{231B}'
    r'\u{23E9}-\u{23FA}\u{25B6}\u{25C0}\u{FE0F}\u{200D}\u{20E3}\u{FF0B}]',
    unicode: true);

/// El ícono de línea que corresponde al emoji con que empieza un mensaje.
const _icons = <String, IconData>{
  '📅': Icons.event_outlined,
  '🗓': Icons.event_outlined,
  '⏰': Icons.alarm_rounded,
  '🔔': Icons.notifications_active_outlined,
  '🔕': Icons.notifications_off_outlined,
  '📝': Icons.edit_note_rounded,
  '✅': Icons.check_circle_outline_rounded,
  '⚠': Icons.warning_amber_rounded,
  '🤔': Icons.help_outline_rounded,
  '👋': Icons.waving_hand_outlined,
  '🗑': Icons.delete_outline_rounded,
  '😴': Icons.snooze_rounded,
  '🎙': Icons.mic_none_rounded,
  '🙉': Icons.hearing_disabled_outlined,
  '🎵': Icons.music_note_outlined,
  '🎶': Icons.music_note_outlined,
  '🎧': Icons.headphones_outlined,
  '🔊': Icons.volume_up_outlined,
  '🔉': Icons.volume_down_outlined,
  '🔇': Icons.volume_off_outlined,
  '💻': Icons.code_rounded,
  '🌙': Icons.nightlight_outlined,
  '☀': Icons.wb_sunny_outlined,
  '📊': Icons.bar_chart_rounded,
  '🎯': Icons.flag_outlined,
  '🏆': Icons.emoji_events_outlined,
  '⭐': Icons.star_outline_rounded,
  '🌟': Icons.star_outline_rounded,
  '💡': Icons.lightbulb_outline_rounded,
  '🔍': Icons.search_rounded,
  '🔎': Icons.search_rounded,
  '🌐': Icons.language_rounded,
  '🚀': Icons.rocket_launch_outlined,
  '💼': Icons.work_outline_rounded,
  '📚': Icons.menu_book_outlined,
  '🎮': Icons.sports_esports_outlined,
  '👌': Icons.thumb_up_alt_outlined,
  '🛑': Icons.stop_circle_outlined,
  '▶': Icons.play_arrow_rounded,
  '⏸': Icons.pause_rounded,
  '⏹': Icons.stop_rounded,
  '⏭': Icons.skip_next_rounded,
  '📂': Icons.folder_open_outlined,
  '❌': Icons.close_rounded,
  '🐾': Icons.pets_outlined,
  '🙈': Icons.visibility_off_outlined,
  '🔁': Icons.repeat_rounded,
  '🍎': Icons.event_available_outlined,
  '💧': Icons.water_drop_outlined,
  '☕': Icons.coffee_outlined,
  '🎉': Icons.celebration_outlined,
  '🥳': Icons.celebration_outlined,
  '💪': Icons.fitness_center_rounded,
  '🧘': Icons.self_improvement_rounded,
  '👀': Icons.visibility_outlined,
  '📈': Icons.trending_up_rounded,
  '🔥': Icons.local_fire_department_outlined,
  '✨': Icons.auto_awesome_outlined,
  '🕺': Icons.music_note_outlined,
  '💃': Icons.music_note_outlined,
  '🪩': Icons.music_note_outlined,
  '📦': Icons.inventory_2_outlined,
  '🎨': Icons.palette_outlined,
  '⚙': Icons.settings_outlined,
  '🔒': Icons.lock_outline_rounded,
  '🙌': Icons.thumb_up_alt_outlined,
  '👍': Icons.thumb_up_alt_outlined,
  '❤': Icons.favorite_border_rounded,
  '💖': Icons.favorite_border_rounded,
  '😊': Icons.sentiment_satisfied_alt_outlined,
  '🙂': Icons.sentiment_satisfied_alt_outlined,
  '😅': Icons.sentiment_satisfied_alt_outlined,
};

/// [text] sin emojis (y sin los espacios que dejaban).
String stripEmoji(String text) => text
    .replaceAll(_emoji, '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'^[ \t]+', multiLine: true), '')
    .replaceAll(RegExp(r'•\s+'), '• ')
    .trim();

/// El ícono del emoji con que empieza [text], o `null`.
IconData? leadingIcon(String text) {
  final t = text.trimLeft();
  for (final MapEntry(:key, :value) in _icons.entries) {
    if (t.startsWith(key.trim())) return value;
  }
  return null;
}

/// Texto de un mensaje: sin emojis y, si empezaba con uno, con su ícono de
/// línea delante.
class PlainText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? iconColor;
  final int? maxLines;
  final TextAlign? textAlign;

  const PlainText(this.text,
      {super.key, this.style, this.iconColor, this.maxLines, this.textAlign});

  @override
  Widget build(BuildContext context) {
    final icon = leadingIcon(text);
    final body = Text(stripEmoji(text),
        style: style,
        maxLines: maxLines,
        textAlign: textAlign,
        overflow: maxLines == null ? null : TextOverflow.ellipsis);
    if (icon == null) return body;
    final size = (style?.fontSize ?? 13) + 3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 6),
          child: Icon(icon,
              size: size, color: iconColor ?? StatsStyle.accentLight),
        ),
        Flexible(child: body),
      ],
    );
  }
}
