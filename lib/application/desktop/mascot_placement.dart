import 'dart:ui';

/// Cálculos de posición de la ventana de la mascota.
///
/// Las coordenadas son las de window_manager/screen_retriever en macOS:
/// origen arriba a la izquierda de la pantalla principal, `y` hacia abajo.
class MascotPlacement {
  static const margin = 12.0;

  /// Esquina inferior derecha del área visible (sin Dock ni barra de menú).
  static Offset defaultOrigin(Rect visibleArea, Size window) => Offset(
        visibleArea.right - window.width - margin,
        visibleArea.bottom - window.height - margin,
      );

  /// Recupera una posición guardada (esquina inferior derecha de la ventana)
  /// y la ajusta a la pantalla. Si esa pantalla ya no existe, vuelve a la
  /// esquina por defecto de la primera.
  static Offset restoreOrigin({
    required Offset? savedBottomRight,
    required Size window,
    required List<Rect> visibleAreas,
  }) {
    assert(visibleAreas.isNotEmpty);
    if (savedBottomRight == null) {
      return defaultOrigin(visibleAreas.first, window);
    }
    final origin = savedBottomRight - Offset(window.width, window.height);
    final center = (origin & window).center;
    final area = visibleAreas.where((a) => a.contains(center)).firstOrNull;
    if (area == null) return defaultOrigin(visibleAreas.first, window);
    return clamp(origin, window, area);
  }

  /// Mantiene la ventana completa dentro del área.
  static Offset clamp(Offset origin, Size window, Rect area) => Offset(
        origin.dx.clamp(area.left, area.right - window.width).toDouble(),
        origin.dy.clamp(area.top, area.bottom - window.height).toDouble(),
      );

  /// Nuevo origen al cambiar de tamaño, sin mover la esquina inferior
  /// derecha (donde está la mascota).
  static Offset resizeKeepingBottomRight(
          Offset origin, Size oldSize, Size newSize) =>
      Offset(
        origin.dx + oldSize.width - newSize.width,
        origin.dy + oldSize.height - newSize.height,
      );
}
