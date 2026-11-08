import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/session/session_phase.dart';
import '../workday/workday_event.dart';

/// Sonidos 8-bit de la app (archivos en `assets/sounds/`).
enum PetSound { focus, rest, goal, level, finish }

/// Qué sonido acompaña a cada suceso de la jornada (o ninguno).
PetSound? soundForEvent(WorkdayEvent event) => switch (event) {
      WorkdayStarted() => PetSound.focus,
      PhaseStarted(:final phase, :final previous) when previous != null =>
        phase.kind == SessionPhase.focus ? PetSound.focus : PetSound.rest,
      WorkdayFinished() => PetSound.finish,
      _ => null,
    };

abstract class SoundPlayer {
  Future<void> play(PetSound sound);
}

/// Sin sonido (pruebas): guarda lo que se pidió.
class NoopSoundPlayer implements SoundPlayer {
  final List<PetSound> played = [];

  @override
  Future<void> play(PetSound sound) async => played.add(sound);
}

/// Sonidos activados o no. Vienen apagados: los activa quien los quiera.
class SoundSettings extends ChangeNotifier {
  static const _key = 'sound.enabled';
  final SharedPreferences? _prefs;
  bool _enabled;

  SoundSettings([this._prefs]) : _enabled = _prefs?.getBool(_key) ?? false;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_key, value);
    notifyListeners();
  }
}

/// Se sobrescriben en `main()`.
final soundSettingsProvider = Provider<SoundSettings>((_) => SoundSettings());
final soundPlayerProvider = Provider<SoundPlayer>((_) => NoopSoundPlayer());
