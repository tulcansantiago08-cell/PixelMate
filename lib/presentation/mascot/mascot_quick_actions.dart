import 'package:flutter/material.dart';

/// Botones pequeños junto a la mascota, siempre visibles, para que las
/// funciones principales no dependan de saber usar el clic derecho o la
/// barra de menú.
class MascotQuickActions extends StatelessWidget {
  final bool statsOpen;
  final VoidCallback onStats;
  final void Function(Offset globalPosition) onMenu;

  /// Minijuego «Atrapa estrellas» (o `null` para no mostrar el botón).
  final VoidCallback? onGame;
  final bool gameOpen;

  /// Tareas diarias (o `null` para no mostrar el botón).
  final VoidCallback? onDaily;
  final bool dailyOpen;

  /// Esconder la mascota (o `null` para no mostrar el botón).
  final VoidCallback? onHide;

  const MascotQuickActions({
    super.key,
    required this.statsOpen,
    required this.onStats,
    required this.onMenu,
    this.onGame,
    this.gameOpen = false,
    this.onDaily,
    this.dailyOpen = false,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundButton(
            tooltip: statsOpen ? 'Cerrar estadísticas' : 'Estadísticas',
            icon: Icons.bar_chart_rounded,
            active: statsOpen,
            onPressed: (_) => onStats(),
          ),
          if (onGame != null) ...[
            const SizedBox(height: 6),
            _RoundButton(
              tooltip: gameOpen ? 'Cerrar el juego' : 'Atrapa estrellas',
              icon: Icons.star_rounded,
              active: gameOpen,
              onPressed: (_) => onGame!(),
            ),
          ],
          if (onDaily != null) ...[
            const SizedBox(height: 6),
            _RoundButton(
              tooltip: dailyOpen ? 'Cerrar tareas diarias' : 'Tareas diarias',
              icon: Icons.alarm_rounded,
              active: dailyOpen,
              onPressed: (_) => onDaily!(),
            ),
          ],
          const SizedBox(height: 6),
          _RoundButton(
            tooltip: 'Menú: jornada, pausa…',
            icon: Icons.more_horiz_rounded,
            onPressed: onMenu,
          ),
          if (onHide != null) ...[
            const SizedBox(height: 6),
            _RoundButton(
              key: const ValueKey('mascot-hide'),
              tooltip: 'Esconder (vuelve con «Oye…», ⌃⌥P o el menú 🐾)',
              icon: Icons.visibility_off_rounded,
              onPressed: (_) => onHide!(),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool active;
  final void Function(Offset globalPosition) onPressed;

  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? const Color(0xFF7C3AED) : const Color(0xEE1E1B2E),
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTapUp: (details) => onPressed(details.globalPosition),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 17, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
