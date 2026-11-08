import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_kind.dart';

/// Preferencias de comportamiento de la mascota.
class MascotSettings extends ChangeNotifier {
  static const _walkKey = 'mascot.walk';
  static const _accessoryKey = 'mascot.accessory';
  static const _nameKey = 'mascot.name';
  static const _onboardingKey = 'onboarding.done';
  static const _speciesKey = 'mascot.species';

  /// Nombre por defecto, hasta que el usuario elija uno.
  static const defaultName = 'Pixel';
  static const maxNameLength = 16;

  /// Sin [prefs] los valores solo viven en memoria (pruebas).
  final SharedPreferences? _prefs;
  bool _walk;
  PetAccessory? _accessory;
  String _name;
  PetKind _species;

  MascotSettings([this._prefs])
      : _walk = _prefs?.getBool(_walkKey) ?? true,
        _accessory = PetAccessory.byName(_prefs?.getString(_accessoryKey)),
        _name = cleanName(_prefs?.getString(_nameKey)) ?? defaultName,
        _species = PetKind.byId(_prefs?.getString(_speciesKey)) ?? PetKind.cat;

  /// Pasear por el escritorio cuando está en reposo.
  bool get walkEnabled => _walk;

  Future<void> setWalkEnabled(bool value) async {
    _walk = value;
    await _prefs?.setBool(_walkKey, value);
    notifyListeners();
  }

  /// Cómo se llama la mascota.
  String get name => _name;

  /// `true` si el usuario ya le puso nombre.
  bool get hasCustomName => _prefs?.getString(_nameKey) != null;

  /// Quita espacios sobrantes y limita el largo. `null` si queda vacío.
  static String? cleanName(String? raw) {
    final name = raw?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    if (name.isEmpty) return null;
    return name.length > maxNameLength
        ? name.substring(0, maxNameLength).trim()
        : name;
  }

  /// Devuelve el nombre guardado, o `null` si no era válido.
  Future<String?> setName(String raw) async {
    final name = cleanName(raw);
    if (name == null) return null;
    _name = name;
    await _prefs?.setString(_nameKey, name);
    notifyListeners();
    return name;
  }

  /// Si ya vio la bienvenida de la primera vez. Sin preferencias guardadas
  /// (pruebas) se da por vista.
  bool get onboardingDone => _prefs?.getBool(_onboardingKey) ?? _prefs == null;

  Future<void> completeOnboarding() async {
    await _prefs?.setBool(_onboardingKey, true);
    notifyListeners();
  }

  /// Especie elegida. Solo se usa si ya está desbloqueada.
  PetKind get species => _species;

  Future<void> setSpecies(PetKind value) async {
    _species = value;
    await _prefs?.setString(_speciesKey, value.id);
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

/// Nombre de la mascota (se actualiza al cambiarlo).
final petNameProvider = Provider<String>((ref) {
  final settings = ref.watch(mascotSettingsProvider);
  void changed() => ref.invalidateSelf();
  settings.addListener(changed);
  ref.onDispose(() => settings.removeListener(changed));
  return settings.name;
});
