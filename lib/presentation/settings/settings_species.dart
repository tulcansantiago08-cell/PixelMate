part of 'settings_panel.dart';

// Elegir la especie de la mascota.

/// Elegir especie: las desbloqueadas se eligen con un toque; las demás
/// muestran el nivel que piden.
class _SpeciesPicker extends StatelessWidget {
  final int level;
  final PetKind active;
  final ValueChanged<PetKind> onChoose;

  const _SpeciesPicker(
      {required this.level, required this.active, required this.onChoose});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final k in PetKind.values)
            Tooltip(
              message: k.unlockedAt(level)
                  ? k.label
                  : tr('${k.label}: se desbloquea en el nivel ${k.unlockLevel}', '${k.label}: unlocks at level ${k.unlockLevel}'),
              child: Material(
                color: k == active ? StatsStyle.accent : StatsStyle.surface,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: ValueKey('species-${k.id}'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: k.unlockedAt(level) ? () => onChoose(k) : null,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: k.unlockedAt(level)
                              ? StatsStyle.accent
                              : StatsStyle.grid),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(k.unlockedAt(level) ? k.emoji : '🔒',
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                          k.unlockedAt(level)
                              ? k.label
                              : tr('${k.label} · Nv. ${k.unlockLevel}', '${k.label} · Lv. ${k.unlockLevel}'),
                          style: TextStyle(
                              fontSize: 11,
                              color: k == active
                                  ? Colors.white
                                  : k.unlockedAt(level)
                                      ? StatsStyle.textPrimary
                                      : StatsStyle.textMuted)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      );
}
