import 'package:flutter/material.dart';

import '../../application/progress/progression.dart';
import '../../domain/mascot/pet_accessory.dart';
import 'stats_style.dart';

/// Nivel y barra de XP, arriba del panel de estadísticas. Al tocarla se
/// despliegan los logros y los accesorios (plegada por defecto para que lo
/// de hoy quede a la vista).
class LevelCard extends StatefulWidget {
  final PlayerProgress progress;

  /// Accesorio puesto ahora (o ninguno).
  final PetAccessory? equipped;

  /// Elegir un accesorio; `null` para quitárselo.
  final ValueChanged<PetAccessory?>? onEquip;

  final bool initiallyExpanded;

  const LevelCard({
    super.key,
    required this.progress,
    this.equipped,
    this.onEquip,
    this.initiallyExpanded = false,
  });

  @override
  State<LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<LevelCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final equipped = widget.equipped;
    final onEquip = widget.onEquip;
    final unlocked = achievements.where(progress.isUnlocked).length;
    // Solo la cabecera pliega y despliega: tocar un logro o un accesorio
    // (aunque esté bloqueado) no debe cerrar la tarjeta.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: StatsStyle.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            key: const ValueKey('level-card'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
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
                  message:
                      '${progress.xpIntoLevel} de ${progress.xpNeededForNext} XP'
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
                Row(children: [
                  Expanded(
                    child: Text(
                      'Faltan ${progress.xpNeededForNext - progress.xpIntoLevel} XP '
                      'para el nivel ${progress.level + 1}',
                      style: const TextStyle(
                          color: StatsStyle.textMuted, fontSize: 10),
                    ),
                  ),
                  Text(
                    _expanded
                        ? 'Ocultar ▴'
                        : '🏅 $unlocked/${achievements.length}'
                            '${onEquip != null ? ' · accesorios' : ''} ▾',
                    style: const TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 10),
                  ),
                ]),
              ],
            ),
          ),
          if (_expanded) ..._details(progress, equipped, onEquip, unlocked),
        ],
      ),
    );
  }

  List<Widget> _details(PlayerProgress progress, PetAccessory? equipped,
          ValueChanged<PetAccessory?>? onEquip, int unlocked) =>
      [
        const SizedBox(height: 8),
        Text('Logros $unlocked/${achievements.length}',
            style:
                const TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final a in achievements) _Badge(a, progress.isUnlocked(a)),
          ],
        ),
        if (onEquip != null) ...[
          const SizedBox(height: 8),
          const Text('Accesorios',
              style: TextStyle(color: StatsStyle.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          AccessoryPicker(
            level: progress.level,
            equipped: equipped,
            onEquip: onEquip,
          ),
        ],
      ];
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
          border:
              Border.all(color: unlocked ? StatsStyle.accent : StatsStyle.grid),
        ),
        // Bloqueados: candado en lugar del emoji, no solo un color apagado.
        child: Text(unlocked ? achievement.emoji : '🔒',
            style: TextStyle(fontSize: unlocked ? 14 : 11)),
      ),
    );
  }
}

/// Accesorios: los desbloqueados se ponen y se quitan con un toque; los
/// bloqueados muestran el nivel que piden.
class AccessoryPicker extends StatelessWidget {
  final int level;
  final PetAccessory? equipped;
  final ValueChanged<PetAccessory?> onEquip;

  const AccessoryPicker({
    super.key,
    required this.level,
    required this.equipped,
    required this.onEquip,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final a in PetAccessory.values)
            _AccessoryChip(
              accessory: a,
              unlocked: a.unlockedAt(level),
              equipped: a == equipped,
              // Tocar el que lleva puesto se lo quita.
              onTap: () => onEquip(a == equipped ? null : a),
            ),
        ],
      );
}

class _AccessoryChip extends StatelessWidget {
  final PetAccessory accessory;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;

  const _AccessoryChip({
    required this.accessory,
    required this.unlocked,
    required this.equipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tooltip = !unlocked
        ? '${accessory.label}: se desbloquea en el nivel ${accessory.unlockLevel}'
        : equipped
            ? '${accessory.label} (puesto). Toca para quitártelo'
            : '${accessory.label}. Toca para ponértelo';
    return Tooltip(
      message: tooltip,
      child: Material(
        color: equipped ? StatsStyle.accent : StatsStyle.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('accessory-${accessory.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: unlocked ? onTap : null,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: unlocked ? StatsStyle.accent : StatsStyle.grid),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(unlocked ? accessory.emoji : '🔒',
                  style: TextStyle(fontSize: unlocked ? 13 : 10)),
              if (!unlocked) ...[
                const SizedBox(width: 3),
                Text('Nv. ${accessory.unlockLevel}',
                    style: const TextStyle(
                        color: StatsStyle.textMuted, fontSize: 10)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
