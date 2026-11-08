import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/workday/workday_controller.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';

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
          child: Text('💼  ${hours.inHours} horas'),
        ),
    ];
  } else {
    final paused = view.status?.state == WorkdayRunState.paused;
    items = [
      PopupMenuItem(
        value: paused ? controller.resume : controller.pause,
        child: Text(paused ? '▶️  Reanudar' : '⏸️  Pausar'),
      ),
      PopupMenuItem(
        value: controller.skipPhase,
        child: const Text('⏭️  Saltar fase'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: controller.finish,
        child: const Text('⏹️  Finalizar jornada'),
      ),
    ];
  }

  items
    ..add(const PopupMenuDivider())
    ..add(PopupMenuItem(
        value: onShowStats, child: const Text('📊  Estadísticas')));
  if (onWalk != null) {
    items.add(
        PopupMenuItem(value: onWalk, child: const Text('🚶  Dar un paseo')));
  }

  if (onRename != null) {
    items.add(PopupMenuItem(
        value: onRename, child: const Text('✏️  Cambiar nombre')));
  }

  if (onSettings != null) {
    items.add(
        PopupMenuItem(value: onSettings, child: const Text('⚙️  Ajustes')));
  }

  return showMenu<MenuAction>(
    context: context,
    position: position,
    items: items,
  );
}
