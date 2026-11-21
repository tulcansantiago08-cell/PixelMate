part of 'settings_panel.dart';

// Piezas de la lista de ajustes: secciones, filas e interruptores.

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: StatsStyle.textMuted,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600)),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final Widget trailing;
  const _Row({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(label,
              style:
                  const TextStyle(color: StatsStyle.textPrimary, fontSize: 12)),
        ),
        trailing,
      ]);
}

class _Switch extends StatelessWidget {
  final String keyName;
  final String label;
  final String? help;
  final bool value;

  /// `null` = bloqueado (se ve apagado y no se puede tocar).
  final ValueChanged<bool>? onChanged;

  const _Switch({
    required this.keyName,
    required this.label,
    this.help,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12)),
                if (help != null)
                  PlainText(help!,
                      iconColor: StatsStyle.textMuted,
                      style: const TextStyle(
                          color: StatsStyle.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              key: ValueKey('settings-$keyName'),
              value: value,
              activeTrackColor: StatsStyle.accent,
              onChanged: onChanged,
            ),
          ),
        ]),
      );
}

/// Un valor que se puede cambiar: el texto y un lápiz.
class _Editable extends StatelessWidget {
  final String text;
  const _Editable(this.text);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          const SizedBox(width: 4),
          const Icon(Icons.edit_outlined, size: 14),
        ],
      );
}
