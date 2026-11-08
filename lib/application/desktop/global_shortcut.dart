import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Combinación del atajo global (⌥⌘P lo usa el Finder).
const shortcutLabel = '⌃⌥P';

/// Atajo de teclado del sistema.
abstract class GlobalShortcutPort {
  /// Devuelve `false` si no se pudo registrar (otra app lo usa).
  Future<bool> setEnabled(bool enabled);

  /// Cada vez que se pulsa.
  Stream<void> get presses;
}

class NoopGlobalShortcut implements GlobalShortcutPort {
  final _presses = StreamController<void>.broadcast();
  bool registered = false;
  bool available;

  NoopGlobalShortcut({this.available = true});

  /// Simula que el usuario lo pulsó.
  void press() => _presses.add(null);

  @override
  Stream<void> get presses => _presses.stream;

  @override
  Future<bool> setEnabled(bool enabled) async {
    registered = enabled && available;
    return !enabled || available;
  }
}

/// Preferencia del atajo y si está funcionando.
class ShortcutSettings extends ChangeNotifier {
  static const _key = 'shortcut.enabled';
  final SharedPreferences? _prefs;
  bool _enabled;

  /// `false` si se pidió y otra app ya usa la combinación.
  bool working = true;

  ShortcutSettings([this._prefs]) : _enabled = _prefs?.getBool(_key) ?? true;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_key, value);
    notifyListeners();
  }

  void reportWorking(bool value) {
    if (working == value) return;
    working = value;
    notifyListeners();
  }
}

final shortcutSettingsProvider =
    Provider<ShortcutSettings>((_) => ShortcutSettings());
