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
  showStats,
  toggleMascot,
  toggleDetection,
  toggleWalk,
  toggleLaunchAtLogin,
  quit,
}

/// Entrada del menú de la barra de menú, independiente del plugin.
class TrayEntry {
  final String label;
  final TrayAction? action;

  /// Para [TrayAction.startWorkday]: duración elegida.
  final Duration? workday;
  final bool enabled;

  /// Si no es `null`, la entrada se muestra como casilla de verificación.
  final bool? checked;
  final bool isSeparator;
  final List<TrayEntry> children;

  const TrayEntry(
    this.label, {
    this.action,
    this.workday,
    this.enabled = true,
    this.checked,
    this.children = const [],
  }) : isSeparator = false;

  const TrayEntry.separator()
      : label = '',
        action = null,
        workday = null,
        enabled = false,
        checked = null,
        children = const [],
        isSeparator = true;

  /// Clave estable, usada para identificar el clic y detectar cambios.
  String get key => isSeparator
      ? '---'
      : '${action?.name ?? 'info'}:${workday?.inMinutes ?? ''}:$label:$enabled:${checked ?? ''}'
          '${children.isEmpty ? '' : '[${children.map((c) => c.key).join(',')}]'}';
}

/// Texto que acompaña al icono en la barra de menú (cuenta regresiva).
String trayTitle(WorkdayView view) => compactStatus(view);

/// Menú de la barra de menú según el estado de la jornada.
List<TrayEntry> trayEntries(
  WorkdayView view, {
  required bool mascotVisible,
  bool detectionEnabled = true,
  bool walkEnabled = true,

  /// `null` si el sistema no permite abrir la app al iniciar sesión.
  bool? launchAtLogin,
}) {
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
      entries.add(const TrayEntry.separator());
    }
    entries.add(status.state == WorkdayRunState.paused
        ? const TrayEntry('Reanudar', action: TrayAction.resume)
        : const TrayEntry('Pausar', action: TrayAction.pause));
    entries.add(const TrayEntry('Saltar fase', action: TrayAction.skipPhase));
    entries
        .add(const TrayEntry('Finalizar jornada', action: TrayAction.finish));
  }

  entries
    ..add(const TrayEntry.separator())
    ..add(const TrayEntry('Estadísticas', action: TrayAction.showStats))
    ..add(TrayEntry(mascotVisible ? 'Ocultar mascota' : 'Mostrar mascota',
        action: TrayAction.toggleMascot))
    ..add(TrayEntry('Detectar apps y sugerir modo',
        action: TrayAction.toggleDetection, checked: detectionEnabled))
    ..add(TrayEntry('Pasear por el escritorio',
        action: TrayAction.toggleWalk, checked: walkEnabled));
  if (launchAtLogin != null) {
    entries.add(TrayEntry('Abrir al iniciar sesión',
        action: TrayAction.toggleLaunchAtLogin, checked: launchAtLogin));
  }
  entries
    ..add(const TrayEntry.separator())
    ..add(const TrayEntry('Salir de PixelMate', action: TrayAction.quit));
  return entries;
}
