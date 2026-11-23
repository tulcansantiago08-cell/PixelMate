import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/session/session_phase.dart';
import '../assistant/mac_actions.dart';
import 'workday_event.dart';

/// Activar el modo Concentración de macOS durante el enfoque y quitarlo en
/// los descansos. macOS no deja hacerlo directamente: se usan dos atajos de
/// la app Atajos («Activar Concentración» / «Desactivar Concentración»).
class FocusModeSettings extends ChangeNotifier {
  static const _onKey = 'focusMode.enabled';
  static const onShortcut = 'PixelMate Enfoque';
  static const offShortcut = 'PixelMate Descanso';

  final SharedPreferences? _prefs;
  bool _enabled;

  /// Por qué no funcionó la última vez, o `null`.
  String? problem;

  FocusModeSettings([this._prefs])
      : _enabled = _prefs?.getBool(_onKey) ?? false;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    problem = null;
    notifyListeners();
    await _prefs?.setBool(_onKey, on);
  }

  void _report(String? text) {
    if (text == problem) return;
    problem = text;
    notifyListeners();
  }
}

/// Qué decir si un atajo no funcionó.
String? focusModeProblem(String status, String shortcut) => switch (status) {
      'ok' => null,
      'missing' => 'No encuentro el atajo «$shortcut». Créalo en la app Atajos (mira cómo, arriba).',
      'denied' => 'Sin permiso para usar Atajos: Ajustes del Sistema › Privacidad y seguridad › Automatización › PixelMate.',
      _ => 'No pude ejecutar el atajo «$shortcut».',
    };

/// Escucha la jornada y ejecuta los atajos: enfoque → Concentración;
/// descanso, pausa o fin → sin Concentración.
class FocusModeController {
  final FocusModeSettings settings;
  final MacActions mac;

  /// `true` si dejamos la Concentración puesta.
  bool _on = false;

  FocusModeController(this.settings, this.mac);

  Future<void> onEvent(WorkdayEvent event, {SessionPhase? current}) async {
    if (!settings.enabled) return;
    final want = switch (event) {
      PhaseStarted(:final phase) => phase.kind == SessionPhase.focus,
      WorkdayResumed() => current == SessionPhase.focus,
      WorkdayPaused() || WorkdayFinished() => false,
      _ => null,
    };
    if (want == null || want == _on) return;
    await set(want);
  }

  /// Pone o quita la Concentración (también para «Probar»).
  Future<bool> set(bool on) async {
    final name =
        on ? FocusModeSettings.onShortcut : FocusModeSettings.offShortcut;
    final status = await mac.runShortcut(name);
    settings._report(focusModeProblem(status, name));
    if (status == 'ok') _on = on;
    return status == 'ok';
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final focusModeSettingsProvider =
    ChangeNotifierProvider<FocusModeSettings>((_) => FocusModeSettings());

final focusModeProvider = Provider<FocusModeController>((ref) =>
    FocusModeController(
        ref.read(focusModeSettingsProvider), ref.read(macActionsProvider)));
