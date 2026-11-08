import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mascot_window_port.dart';

/// Panel abierto sobre la mascota.
enum MascotPanel { none, chat, stats, settings, welcome, weekly }

final mascotPanelProvider = StateProvider<MascotPanel>((_) => MascotPanel.none);

/// Cambia el panel ajustando el tamaño de la ventana en el orden correcto:
/// al abrir, primero se agranda; al cerrar, primero se quita el panel. Así
/// nunca se dibuja un panel en la ventana pequeña.
Future<void> setMascotPanel({
  required MascotWindowPort window,
  required StateController<MascotPanel> panel,
  required MascotPanel next,
}) async {
  if (next == panel.state) return;
  if (next != MascotPanel.none) {
    await window.setExpanded(true);
    panel.state = next;
  } else {
    panel.state = next;
    await window.setExpanded(false);
  }
}
