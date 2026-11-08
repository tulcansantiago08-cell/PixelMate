import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de la detección automática, guardadas localmente.
class DetectionSettings extends ChangeNotifier {
  static const _enabledKey = 'detection.enabled';
  static const _excludedKey = 'detection.excluded';

  final SharedPreferences _prefs;

  DetectionSettings(this._prefs);

  bool get enabled => _prefs.getBool(_enabledKey) ?? true;

  /// Apps (bundle id o nombre) para las que nunca se sugiere nada.
  Set<String> get excludedApps =>
      (_prefs.getStringList(_excludedKey) ?? const []).toSet();

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(_enabledKey, value);
    notifyListeners();
  }

  Future<void> exclude(String appKey) async {
    await _prefs.setStringList(
        _excludedKey, {...excludedApps, appKey}.toList());
    notifyListeners();
  }

  Future<void> include(String appKey) async {
    await _prefs.setStringList(
        _excludedKey, (excludedApps..remove(appKey)).toList());
    notifyListeners();
  }
}
