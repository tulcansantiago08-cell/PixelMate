import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de comportamiento de la mascota.
class MascotSettings extends ChangeNotifier {
  static const _walkKey = 'mascot.walk';

  /// Sin [prefs] los valores solo viven en memoria (pruebas).
  final SharedPreferences? _prefs;
  bool _walk;

  MascotSettings([this._prefs]) : _walk = _prefs?.getBool(_walkKey) ?? true;

  /// Pasear por el escritorio cuando está en reposo.
  bool get walkEnabled => _walk;

  Future<void> setWalkEnabled(bool value) async {
    _walk = value;
    await _prefs?.setBool(_walkKey, value);
    notifyListeners();
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final mascotSettingsProvider =
    Provider<MascotSettings>((_) => MascotSettings());
