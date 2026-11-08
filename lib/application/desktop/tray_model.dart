import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';
import '../workday/workday_controller.dart';
import '../workday/workday_format.dart';

enum TrayAction {
  startWorkday,
  pause,
  resume,
  skipPhase,
  finish,
  toggleMascot,
  quit,
}

/// Entrada del menú de la barra de menú, independiente del plugin.
class TrayEntry {
  final String label;
  final TrayAction? action;

  /// Para [TrayAction.startWorkday]: duración elegida.
  final Duration? workday;
  final bool enabled;
  final bool isSeparator;
  final List<TrayEntry> children;

  const TrayEntry(
    this.label, {
    this.action,
    this.workday,
    this.enabled = true,
    this.children = const [],
  }) : isSeparator = false;

  const TrayEntry.separator()
      : label = '',
        action = null,
        workday = null,
        enabled = false,
        children = const [],
        isSeparator = true;

  /// Clave estable, usada para identificar el clic y detectar cambios.
  String get key => isSeparator
      ? '---'
      : '${action?.name ?? 'info'}:${workday?.inMinutes ?? ''}:$label:$enabled'
          '${children.isEmpty ? '' : '[${children.map((c) => c.key).join(',')}]'}';
}

/// Texto que acompaña al icono en la barra de menú (cuenta regresiva).
String trayTitle(WorkdayView view) => compactStatus(view);

/// Menú de la barra de menú según el estado de la jornada.
List<TrayEntry> trayEntries(WorkdayView view, {required bool mascotVisible}) {
  final status = view.status;
  final entries = <TrayEntry>[];

  if (status == null) {
    entries.add(TrayEntry('Iniciar jornada', children: [
      for (final hours in WorkdayConfig.presetWorkdays)
        TrayEntry('${hours.inHours} horas',
            action: TrayAction.startWorkday, workday: hours),
    ]));
  } else {
    final phase = status.phase;
    if (phase != null) {
      entries.add(TrayEntry(
        '${phase.kind.displayName} · ciclo ${phase.cycle}',
        enabled: false,
      ));
      entries.add(TrayEntry(
        'Jornada: ${(status.progress * 100).floor()} % · '
        'quedan ${formatHoursMinutes(status.workdayRemaining)}',
        enabled: false,
      ));
      entries.add(const TrayEntry.separator());
    }
    entries.add(status.state == WorkdayRunState.paused
        ? const TrayEntry('Reanudar', action: TrayAction.resume)
        : const TrayEntry('Pausar', action: TrayAction.pause));
    entries.add(const TrayEntry('Saltar fase', action: TrayAction.skipPhase));
    entries.add(const TrayEntry('Finalizar jornada', action: TrayAction.finish));
  }

  entries
    ..add(const TrayEntry.separator())
    ..add(TrayEntry(mascotVisible ? 'Ocultar mascota' : 'Mostrar mascota',
        action: TrayAction.toggleMascot))
    ..add(const TrayEntry.separator())
    ..add(const TrayEntry('Salir de PixelMate', action: TrayAction.quit));
  return entries;
}
