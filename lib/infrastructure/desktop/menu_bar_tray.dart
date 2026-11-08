import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../application/desktop/tray_model.dart';

/// Icono de PixelMate en la barra de menú de macOS.
///
/// Solo habla con el plugin cuando algo cambia: el título (cuenta regresiva)
/// una vez por segundo y el menú cuando cambia su contenido.
///
/// tray_manager identifica el clic por el id del elemento en el menú
/// *actual*: si el menú se reemplaza mientras está abierto, el clic se pierde
/// sin error. Por eso el contenido del menú cambia solo en transiciones y,
/// mientras está abierto, los cambios esperan a que se cierre o se use.
class MenuBarTray with TrayListener {
  final void Function(TrayEntry entry) onSelected;

  /// Cuánto tiempo se considera abierto el menú tras hacer clic en el icono.
  static const menuOpenGrace = Duration(seconds: 20);

  String? _title;
  String? _menuSignature;
  final Map<String, TrayEntry> _entriesByKey = {};

  DateTime? _menuOpenedAt;
  List<TrayEntry>? _pending;
  Timer? _pendingTimer;

  MenuBarTray({required this.onSelected});

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('PixelMate');
  }

  Future<void> update(String title, List<TrayEntry> entries) async {
    final shownTitle = title.isEmpty ? '' : ' $title';
    if (shownTitle != _title) {
      _title = shownTitle;
      await trayManager.setTitle(shownTitle);
    }

    final signature = entries.map((e) => e.key).join('|');
    if (signature == _menuSignature) return;

    final openedAt = _menuOpenedAt;
    if (openedAt != null &&
        DateTime.now().difference(openedAt) < menuOpenGrace) {
      // El menú puede estar abierto: aplicar después.
      _pending = entries;
      _pendingTimer ??= Timer(menuOpenGrace, _applyPending);
      return;
    }
    await _setMenu(signature, entries);
  }

  Future<void> _setMenu(String signature, List<TrayEntry> entries) async {
    _menuSignature = signature;
    _entriesByKey.clear();
    await trayManager
        .setContextMenu(Menu(items: entries.map(_toItem).toList()));
  }

  void _applyPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _menuOpenedAt = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      unawaited(_setMenu(pending.map((e) => e.key).join('|'), pending));
    }
  }

  MenuItem _toItem(TrayEntry entry) {
    if (entry.isSeparator) return MenuItem.separator();
    _entriesByKey[entry.key] = entry;
    if (entry.children.isNotEmpty) {
      return MenuItem.submenu(
        key: entry.key,
        label: entry.label,
        submenu: Menu(items: entry.children.map(_toItem).toList()),
      );
    }
    if (entry.checked != null) {
      return MenuItem.checkbox(
        key: entry.key,
        label: entry.label,
        checked: entry.checked,
        disabled: !entry.enabled,
      );
    }
    return MenuItem(
      key: entry.key,
      label: entry.label,
      disabled: !entry.enabled,
    );
  }

  void _openMenu() {
    _menuOpenedAt = DateTime.now();
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseDown() => _openMenu();

  @override
  void onTrayIconRightMouseDown() => _openMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final entry = _entriesByKey[menuItem.key];
    debugPrint('[barra de menú] clic: ${menuItem.label} → ${entry?.action}');
    if (entry != null) onSelected(entry);
    // El menú ya se cerró: aplica cualquier cambio que estuviera esperando.
    _applyPending();
  }

  Future<void> dispose() async {
    _pendingTimer?.cancel();
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
