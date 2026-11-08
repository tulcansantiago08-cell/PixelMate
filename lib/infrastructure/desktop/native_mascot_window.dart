import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/desktop/mascot_placement.dart';
import '../../application/desktop/mascot_window_port.dart';

/// Ventana real de la mascota (window_manager + screen_retriever).
///
/// - Empieza en la esquina inferior derecha o donde el usuario la dejó.
/// - Aparece en todos los escritorios, pero no sobre apps a pantalla
///   completa (juegos, vídeos).
/// - Guarda la posición cada vez que el usuario la arrastra.
class NativeMascotWindow extends MascotWindowPort with WindowListener {
  static const compactSize = Size(280, 300);
  static const expandedSize = Size(320, 480);

  static const _keyX = 'mascot.bottomRight.x';
  static const _keyY = 'mascot.bottomRight.y';

  final SharedPreferences _prefs;

  @override
  final ValueNotifier<bool> visible = ValueNotifier(true);

  bool _expanded = false;

  NativeMascotWindow(this._prefs);

  /// Coloca la ventana. Llamar antes de mostrarla.
  Future<void> init() async {
    windowManager.addListener(this);
    final areas = await _visibleAreas();
    final x = _prefs.getDouble(_keyX);
    final y = _prefs.getDouble(_keyY);
    final origin = MascotPlacement.restoreOrigin(
      savedBottomRight: x != null && y != null ? Offset(x, y) : null,
      window: compactSize,
      visibleAreas: areas,
    );
    await windowManager.setBounds(origin & compactSize);
    await windowManager.setVisibleOnAllWorkspaces(true,
        visibleOnFullScreen: false);
  }

  Future<List<Rect>> _visibleAreas() async {
    final primary = await screenRetriever.getPrimaryDisplay();
    final all = await screenRetriever.getAllDisplays();
    Rect area(Display d) =>
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    return [
      area(primary),
      for (final d in all)
        if (d.id != primary.id) area(d),
    ];
  }

  @override
  void onWindowMoved() async {
    final bounds = await windowManager.getBounds();
    await _prefs.setDouble(_keyX, bounds.right);
    await _prefs.setDouble(_keyY, bounds.bottom);
  }

  @override
  Future<void> setExpanded(bool expanded) async {
    if (expanded == _expanded) return;
    _expanded = expanded;
    final bounds = await windowManager.getBounds();
    final newSize = expanded ? expandedSize : compactSize;
    var origin = MascotPlacement.resizeKeepingBottomRight(
        bounds.topLeft, bounds.size, newSize);
    final areas = await _visibleAreas();
    final area = areas
            .where((a) => a.contains(bounds.bottomRight - const Offset(1, 1)))
            .firstOrNull ??
        areas.first;
    origin = MascotPlacement.clamp(origin, newSize, area);
    await windowManager.setBounds(origin & newSize);
  }

  @override
  Future<void> show() async {
    await windowManager.show();
    visible.value = true;
  }

  @override
  Future<void> hide() async {
    await windowManager.hide();
    visible.value = false;
  }
}
