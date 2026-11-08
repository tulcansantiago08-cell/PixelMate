import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/mascot/pet_accessory.dart';

/// Preferencias de comportamiento de la mascota.
class MascotSettings extends ChangeNotifier {
  static const _walkKey = 'mascot.walk';
  static const _accessoryKey = 'mascot.accessory';

  /// Sin [prefs] los valores solo viven en memoria (pruebas).
  final SharedPreferences? _prefs;
  bool _walk;
  PetAccessory? _accessory;

  MascotSettings([this._prefs])
      : _walk = _prefs?.getBool(_walkKey) ?? true,
        _accessory = PetAccessory.byName(_prefs?.getString(_accessoryKey));

  /// Pasear por el escritorio cuando está en reposo.
  bool get walkEnabled => _walk;

  Future<void> setWalkEnabled(bool value) async {
    _walk = value;
    await _prefs?.setBool(_walkKey, value);
    notifyListeners();
  }

  /// Accesorio elegido (o ninguno). Solo se ve si ya está desbloqueado.
  PetAccessory? get accessory => _accessory;

  Future<void> setAccessory(PetAccessory? value) async {
    _accessory = value;
    if (value == null) {
      await _prefs?.remove(_accessoryKey);
    } else {
      await _prefs?.setString(_accessoryKey, value.name);
    }
    notifyListeners();
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final mascotSettingsProvider =
    Provider<MascotSettings>((_) => MascotSettings());
