import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../application/desktop/tray_model.dart';

/// Icono de PixelMate en la barra de menú de macOS.
///
/// Solo habla con el plugin cuando algo cambia: el título (cuenta regresiva)
/// una vez por segundo y el menú cuando cambia su contenido.
class MenuBarTray with TrayListener {
  final void Function(TrayEntry entry) onSelected;

  String? _title;
  String? _menuSignature;
  final Map<String, TrayEntry> _entriesByKey = {};

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
    _menuSignature = signature;
    _entriesByKey.clear();
    await trayManager
        .setContextMenu(Menu(items: entries.map(_toItem).toList()));
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

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final entry = _entriesByKey[menuItem.key];
    if (entry == null) {
      debugPrint('Elemento de menú desconocido: ${menuItem.key}');
      return;
    }
    onSelected(entry);
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
