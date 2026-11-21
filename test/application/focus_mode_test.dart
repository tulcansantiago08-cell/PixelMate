import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/workday/focus_mode.dart';
import 'package:pixelmate/application/workday/workday_event.dart';
import 'package:pixelmate/domain/session/phase_planner.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';

void main() {
  final plan = planWorkday(const WorkdayConfig());
  final focus = plan.firstWhere((p) => p.kind == SessionPhase.focus);
  final rest = plan.firstWhere((p) => p.kind != SessionPhase.focus);

  late FocusModeSettings settings;
  late FakeMacActions mac;
  late FocusModeController mode;

  setUp(() {
    settings = FocusModeSettings();
    mac = FakeMacActions();
    mode = FocusModeController(settings, mac);
  });

  test('apagado no ejecuta atajos', () async {
    await mode.onEvent(PhaseStarted(focus, null));
    expect(mac.shortcutsRun, isEmpty);
  });

  test('enfoque, descanso, pausa y fin', () async {
    await settings.setEnabled(true);
    await mode.onEvent(PhaseStarted(focus, null));
    await mode.onEvent(PhaseStarted(focus, null)); // ya estaba
    await mode.onEvent(PhaseStarted(rest, focus));
    await mode.onEvent(PhaseStarted(focus, rest));
    await mode.onEvent(const WorkdayPaused());
    await mode.onEvent(const WorkdayResumed(), current: SessionPhase.focus);
    await mode.onEvent(PhaseStarted(rest, focus));
    expect(mac.shortcutsRun, [
      FocusModeSettings.onShortcut,
      FocusModeSettings.offShortcut,
      FocusModeSettings.onShortcut,
      FocusModeSettings.offShortcut,
      FocusModeSettings.onShortcut,
      FocusModeSettings.offShortcut,
    ]);
  });

  test('si falta el atajo, lo explica', () async {
    await settings.setEnabled(true);
    mac.shortcuts = {};
    await mode.onEvent(PhaseStarted(focus, null));
    expect(settings.problem, contains('PixelMate Enfoque'));
    mac.shortcuts = null;
    await mode.onEvent(PhaseStarted(focus, null));
    expect(settings.problem, isNull);
  });
}
