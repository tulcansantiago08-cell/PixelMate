import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/activity/detection_settings.dart';
import '../../application/activity/focus_guard.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/login_item.dart';
import '../../application/desktop/sounds.dart';
import '../../application/desktop/mascot_panel.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/progress/progression.dart';
import '../../application/desktop/mascot_window_port.dart';
import '../../application/desktop/tray_model.dart';
import '../../application/workday/workday_controller.dart';
import '../../application/workday/workday_notifications.dart';
import '../../application/workday/workday_providers.dart';
import '../../domain/session/workday_config.dart';
import '../../infrastructure/desktop/menu_bar_tray.dart';
import '../../infrastructure/desktop/system_notifier.dart';

/// Une la jornada con la barra de menú, la ventana y las notificaciones.
class DesktopShell {
  final ProviderContainer container;
  final MascotWindowPort window;
  final SystemNotifier notifier;
  final DetectionSettings detection;
  final MascotSettings mascot;
  final LaunchAtLogin launchAtLogin;
  final FocusGuardSettings focusGuard;
  final GlobalShortcutPort shortcut;
  final ShortcutSettings shortcutSettings;
  final SoundPlayer sounds;
  final SoundSettings soundSettings;
  final Future<void> Function() quitApp;

  late final MenuBarTray _tray = MenuBarTray(onSelected: _onTrayAction);
  final List<void Function()> _cleanup = [];

  DesktopShell({
    required this.container,
    required this.window,
    required this.notifier,
    required this.detection,
    required this.mascot,
    LaunchAtLogin? launchAtLogin,
    FocusGuardSettings? focusGuard,
    GlobalShortcutPort? shortcut,
    ShortcutSettings? shortcutSettings,
    SoundPlayer? sounds,
    SoundSettings? soundSettings,
    required this.quitApp,
  })  : focusGuard = focusGuard ?? FocusGuardSettings(),
        launchAtLogin = launchAtLogin ?? LaunchAtLogin(NoopLoginItem()),
        shortcut = shortcut ?? NoopGlobalShortcut(),
        shortcutSettings = shortcutSettings ?? ShortcutSettings(),
        sounds = sounds ?? NoopSoundPlayer(),
        soundSettings = soundSettings ?? SoundSettings();

  WorkdayController get _workday =>
      container.read(workdayControllerProvider.notifier);

  Future<void> start() async {
    await _tray.init();
    await notifier.init();
    await launchAtLogin.load();

    final sub = container.listen<WorkdayView>(
      workdayControllerProvider,
      (_, view) => _refreshTray(view),
      fireImmediately: true,
    );
    _cleanup.add(sub.close);

    void onVisibility() =>
        _refreshTray(container.read(workdayControllerProvider));
    window.visible.addListener(onVisibility);
    _cleanup.add(() => window.visible.removeListener(onVisibility));
    detection.addListener(onVisibility);
    _cleanup.add(() => detection.removeListener(onVisibility));
    mascot.addListener(onVisibility);
    _cleanup.add(() => mascot.removeListener(onVisibility));
    focusGuard.addListener(onVisibility);
    _cleanup.add(() => focusGuard.removeListener(onVisibility));
    launchAtLogin.addListener(onVisibility);
    _cleanup.add(() => launchAtLogin.removeListener(onVisibility));

    final events = _workday.events.listen((event) {
      final notice = noticeFor(event, mode: _workday.currentMode);
      if (notice != null) unawaited(notifier.show(notice));
      _play(soundForEvent(event));
    });
    _cleanup.add(events.cancel);

    // Subidas de nivel y logros: también se avisan si la mascota está oculta.
    final progress = container.listen<PlayerProgress>(
      progressProvider,
      (before, after) {
        if (before == null) return;
        for (final event in progressEvents(before, after)) {
          if (event is LeveledUp) _play(PetSound.level);
          final m = progressMessage(event);
          unawaited(notifier.show(WorkdayNotice(m.title, m.message)));
        }
      },
    );
    _cleanup.add(progress.close);

    final goal = container.listen<DailyGoalStatus?>(
      dailyGoalProvider,
      (before, after) {
        if (goalJustReached(before, after)) {
          _play(PetSound.goal);
          unawaited(notifier.show(WorkdayNotice(
              'Meta diaria cumplida', goalReachedMessage(after!.goal))));
        }
      },
    );
    _cleanup.add(goal.close);

    // Aviso del guardián: si la mascota está oculta, por notificación.
    final guard = container.listen<FocusNudge?>(
      focusGuardProvider,
      (before, nudge) {
        if (nudge != null && before == null && !window.visible.value) {
          unawaited(notifier.show(WorkdayNotice(
              'Guardián del enfoque',
              focusNudgeMessage(
                  nudge, container.read(workdayControllerProvider)))));
        }
      },
    );
    _cleanup.add(guard.close);

    // Atajo global: abre o cierra el chat desde cualquier app.
    await _applyShortcut();
    shortcutSettings.addListener(_applyShortcut);
    _cleanup.add(() => shortcutSettings.removeListener(_applyShortcut));
    final presses = shortcut.presses.listen((_) => _toggleChat());
    _cleanup.add(presses.cancel);
  }

  void _refreshTray(WorkdayView view) {
    unawaited(_tray.update(
      trayTitle(view),
      trayEntries(
        view,
        mascotVisible: window.visible.value,
        detectionEnabled: detection.enabled,
        walkEnabled: mascot.walkEnabled,
        focusGuardEnabled: focusGuard.enabled,
        launchAtLogin: launchAtLogin.supported ? launchAtLogin.enabled : null,
      ),
    ));
  }

  Future<void> _onTrayAction(TrayEntry entry) async {
    switch (entry.action) {
      case TrayAction.startWorkday:
        if (!container.read(workdayControllerProvider).isActive) {
          _workday.start(WorkdayConfig(workday: entry.workday!));
        }
      case TrayAction.pause:
        _workday.pause();
      case TrayAction.resume:
        _workday.resume();
      case TrayAction.skipPhase:
        _workday.skipPhase();
      case TrayAction.finish:
        _workday.finish();
      case TrayAction.showStats:
        await _showPanel(MascotPanel.stats);
      case TrayAction.showSettings:
        await _showPanel(MascotPanel.settings);
      case TrayAction.toggleMascot:
        await window.toggle();
      case TrayAction.toggleDetection:
        await detection.setEnabled(!detection.enabled);
      case TrayAction.toggleWalk:
        await mascot.setWalkEnabled(!mascot.walkEnabled);
      case TrayAction.toggleFocusGuard:
        await focusGuard.setEnabled(!focusGuard.enabled);
      case TrayAction.toggleLaunchAtLogin:
        if (!await launchAtLogin.setEnabled(!launchAtLogin.enabled)) {
          unawaited(notifier.show(const WorkdayNotice(
              'Falta un permiso', launchAtLoginApprovalHint)));
        }
      case TrayAction.quit:
        await dispose();
        await quitApp();
      case null:
        break;
    }
  }

  Future<void> _applyShortcut() async {
    final ok = await shortcut.setEnabled(shortcutSettings.enabled);
    shortcutSettings.reportWorking(ok);
  }

  void _play(PetSound? sound) {
    if (sound != null && soundSettings.enabled) unawaited(sounds.play(sound));
  }

  /// El atajo: muestra la mascota y abre el chat (o lo cierra si ya está).
  Future<void> _toggleChat() async {
    final panel = container.read(mascotPanelProvider);
    if (!window.visible.value) await window.show();
    await setMascotPanel(
      window: window,
      panel: container.read(mascotPanelProvider.notifier),
      next: panel == MascotPanel.chat ? MascotPanel.none : MascotPanel.chat,
    );
  }

  Future<void> _showPanel(MascotPanel next) async {
    if (!window.visible.value) await window.show();
    await setMascotPanel(
      window: window,
      panel: container.read(mascotPanelProvider.notifier),
      next: next,
    );
  }

  Future<void> dispose() async {
    for (final c in _cleanup) {
      c();
    }
    _cleanup.clear();
    await _tray.dispose();
  }
}
