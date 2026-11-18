import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../desktop/sounds.dart';

/// Los sonidos de alarma que se pueden elegir.
const alarmSounds = {
  PetSound.alarm: 'Bip bip',
  PetSound.alarmBell: 'Campana',
  PetSound.alarmSoft: 'Suave',
};

/// Cuánto se puede posponer y con cuánta antelación avisar (minutos).
const snoozeChoices = [5, 10, 15];
const leadChoices = [0, 5, 10, 15, 30];

/// Cómo suenan las alarmas: el sonido, lo que se pospone y si avisa antes.
class AlarmSettings extends ChangeNotifier {
  static const _soundKey = 'alarm.sound';
  static const _snoozeKey = 'alarm.snooze';
  static const _leadKey = 'alarm.lead';

  final SharedPreferences? _prefs;
  PetSound _sound;
  int _snooze;
  int _lead;

  AlarmSettings([this._prefs])
      : _sound = alarmSounds.keys
                .where((s) => s.name == _prefs?.getString(_soundKey))
                .firstOrNull ??
            PetSound.alarm,
        _snooze = _pick(_prefs?.getInt(_snoozeKey), snoozeChoices, 5),
        _lead = _pick(_prefs?.getInt(_leadKey), leadChoices, 0);

  static int _pick(int? value, List<int> choices, int fallback) =>
      choices.contains(value) ? value! : fallback;

  PetSound get sound => _sound;
  int get snoozeMinutes => _snooze;

  /// Minutos antes de una tarea con hora en que avisa (0: no avisa antes).
  int get leadMinutes => _lead;

  Future<void> setSound(PetSound sound) async {
    if (!alarmSounds.containsKey(sound)) return;
    _sound = sound;
    notifyListeners();
    await _prefs?.setString(_soundKey, sound.name);
  }

  Future<void> setSnoozeMinutes(int minutes) async {
    _snooze = _pick(minutes, snoozeChoices, _snooze);
    notifyListeners();
    await _prefs?.setInt(_snoozeKey, _snooze);
  }

  Future<void> setLeadMinutes(int minutes) async {
    _lead = _pick(minutes, leadChoices, _lead);
    notifyListeners();
    await _prefs?.setInt(_leadKey, _lead);
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final alarmSettingsProvider =
    ChangeNotifierProvider<AlarmSettings>((_) => AlarmSettings());
