import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/workday/workday_controller.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';
import '../stats/stats_style.dart';

/// Acción elegida en el menú (se ejecuta después de cerrarlo).
typedef MenuAction = FutureOr<void> Function();

/// Menú contextual (clic derecho o ⋯ sobre la mascota). Devuelve la acción
/// elegida sin ejecutarla, para que quien lo abre decida el orden (por
/// ejemplo, devolver la ventana a su tamaño antes de pasear).
Future<MenuAction?> showWorkdayMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WorkdayController controller,
  required WorkdayView view,
  required MenuAction onShowStats,
  MenuAction? onWalk,
  MenuAction? onRename,
  MenuAction? onSettings,
  MenuAction? onPending,
  MenuAction? onHide,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    globalPosition & const Size(1, 1),
    Offset.zero & overlay.size,
  );

  final List<PopupMenuEntry<MenuAction>> items;
  if (!view.isActive) {
    items = [
      const PopupMenuItem(enabled: false, child: Text('Iniciar jornada')),
      for (final hours in WorkdayConfig.presetWorkdays)
        PopupMenuItem(
          value: () => controller.start(WorkdayConfig(workday: hours)),
          child: _label(Icons.work_outline_rounded, '${hours.inHours} horas'),
        ),
    ];
  } else {
    final paused = view.status?.state == WorkdayRunState.paused;
    items = [
      PopupMenuItem(
        value: paused ? controller.resume : controller.pause,
        child: paused
            ? _label(Icons.play_arrow_rounded, 'Reanudar')
            : _label(Icons.pause_rounded, 'Pausar'),
      ),
      PopupMenuItem(
        value: controller.skipPhase,
        child: _label(Icons.skip_next_rounded, 'Saltar fase'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: controller.finish,
        child: _label(Icons.stop_rounded, 'Finalizar jornada'),
      ),
    ];
  }

  items
    ..add(const PopupMenuDivider())
    ..add(PopupMenuItem(
        value: onShowStats,
        child: _label(Icons.bar_chart_rounded, 'Estadísticas')));
  if (onPending != null) {
    items.add(PopupMenuItem(
        value: onPending,
        child: _label(Icons.checklist_rounded, 'Pendientes')));
  }
  if (onWalk != null) {
    items.add(PopupMenuItem(
        value: onWalk,
        child: _label(Icons.directions_walk_rounded, 'Dar un paseo')));
  }

  if (onRename != null) {
    items.add(PopupMenuItem(
        value: onRename, child: _label(Icons.edit_outlined, 'Cambiar nombre')));
  }

  if (onSettings != null) {
    items.add(PopupMenuItem(
        value: onSettings, child: _label(Icons.settings_outlined, 'Ajustes')));
  }

  if (onHide != null) {
    items
      ..add(const PopupMenuDivider())
      ..add(PopupMenuItem(
          value: onHide,
          child: _label(Icons.visibility_off_outlined, 'Esconder')));
  }

  return showMenu<MenuAction>(
    context: context,
    position: position,
    items: items,
  );
}

/// Una opción del menú: ícono de línea y texto.
Widget _label(IconData icon, String text) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: StatsStyle.textSecondary),
      const SizedBox(width: 10),
      Flexible(
        child: Text(text,
            style:
                const TextStyle(color: StatsStyle.textPrimary, fontSize: 13)),
      ),
    ]);
