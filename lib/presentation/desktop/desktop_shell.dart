import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/activity/detection_settings.dart';
import '../../application/activity/focus_guard.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/assistant/alarm.dart';
import '../../application/assistant/chat_controller.dart';
import '../../application/assistant/daily_tasks.dart';
import '../../application/assistant/reminders.dart';
import '../../application/assistant/apple_reminders.dart';
import '../../application/assistant/calendar_notes.dart';
import '../../application/assistant/daily_briefing.dart';
import '../../application/assistant/voice.dart';
import '../../application/workday/focus_mode.dart';
import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/updates.dart';
import '../../application/desktop/login_item.dart';
import '../../application/desktop/sounds.dart';
import '../../application/desktop/mascot_panel.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/late_night.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/celebrations.dart';
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

  /// Si estaba escondida y la llamaste por voz: cuánto se queda a la vista
  /// tras responderte, y tras una falsa alarma.
  final Duration rehideAfter;
  final Duration rehideSilent;

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
    this.rehideAfter = const Duration(seconds: 25),
    this.rehideSilent = const Duration(seconds: 3),
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
    // Al esconderla, una vez: cómo hacer que vuelva.
    void onHidden() {
      if (window.visible.value) return;
      if (_quietHide) {
        _quietHide = false;
        return;
      }
      if (_toldHowToReturn) return;
      _toldHowToReturn = true;
      unawaited(notifier.show(WorkdayNotice(
          '${mascot.name} se escondió',
          hiddenMascotHelp(
              name: mascot.name,
              wake: mascot.wakeWord,
              shortcut: shortcutSettings.enabled))));
    }

    window.visible.addListener(onHidden);
    _cleanup.add(() => window.visible.removeListener(onHidden));
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
      // Modo Concentración de macOS durante el enfoque (si está activado).
      unawaited(container.read(focusModeProvider).onEvent(event,
          current:
              container.read(workdayControllerProvider).status?.phase?.kind));
    });
    _cleanup.add(events.cancel);

    // Nivel, logros y racha (con enfoque profundo, esperan al descanso).
    final celebrations =
        container.listen<Celebration?>(celebrationProvider, (before, c) {
      if (c == null || identical(before, c)) return;
      if (c.levelUp) _play(PetSound.level);
      if (c.alwaysNotify || !window.visible.value) {
        unawaited(notifier.show(WorkdayNotice(c.title, c.message)));
      }
    });
    _cleanup.add(celebrations.close);

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

    // Versión nueva: se avisa una sola vez por versión.
    final updates =
        container.listen<UpdateState>(updateProvider, (before, now) {
      final release = now.release;
      if (release != null && now.announce > (before?.announce ?? 0)) {
        unawaited(notifier.show(WorkdayNotice(
            'PixelMate ${release.version}', updateMessage(release))));
      }
    });
    _cleanup.add(updates.close);

    // Recordatorios del usuario: siempre con notificación (y sonido).
    void onReminder(ReminderAlert? before, ReminderAlert? alert) {
      if (alert == null || identical(before, alert)) return;
      // Alarmas: suenan hasta apagarlas, con la mascota a la vista.
      final alarms = [
        for (final r in alert.items)
          if (r.alarm) r
      ];
      if (alarms.isNotEmpty) {
        container.read(alarmProvider.notifier).ring(alarms);
      }
      final others = [
        for (final r in alert.items)
          if (!r.alarm) r
      ];
      if (others.isEmpty) return;
      _play(PetSound.focus);
      unawaited(notifier.show(WorkdayNotice(
          'Recordatorio', ReminderAlert(others, alert.at).message)));
    }

    final reminders =
        container.listen<ReminderAlert?>(reminderProvider, onReminder);
    _cleanup.add(reminders.close);
    // Lo anotado en el calendario: mismo aviso (y sus alarmas suenan).
    final notes =
        container.listen<ReminderAlert?>(calendarAlertProvider, onReminder);
    _cleanup.add(notes.close);

    // Alarmas (también las de las tareas diarias): la mascota a la vista y
    // una notificación.
    container.read(dailyTaskSchedulerProvider);
    // Pendientes en Recordatorios (iPhone), si está activado.
    final apple = container.read(appleRemindersProvider);
    if (apple.enabled) unawaited(apple.push());
    final ringing = container.listen<AlarmState>(alarmProvider, (before, now) {
      if (!now.active || (before?.active ?? false)) return;
      if (!window.visible.value) unawaited(window.show());
      unawaited(notifier.show(WorkdayNotice('Alarma', now.text)));
    });
    _cleanup.add(ringing.close);

    // Resumen del día: si la mascota está oculta, por notificación.
    final briefing =
        container.listen<String?>(briefingProvider, (before, message) {
      if (message != null && message != before && !window.visible.value) {
        unawaited(notifier.show(WorkdayNotice('Tu día', message)));
      }
    });
    _cleanup.add(briefing.close);

    // Recordatorio nocturno: si la mascota está oculta, por notificación.
    final night = container.listen<String?>(lateNightProvider, (before, msg) {
      if (msg != null && before == null && !window.visible.value) {
        unawaited(notifier.show(WorkdayNotice('Es tarde', msg)));
      }
    });
    _cleanup.add(night.close);

    // Atajo global: abre o cierra el chat desde cualquier app.
    await _applyShortcut();
    shortcutSettings.addListener(_applyShortcut);
    _cleanup.add(() => shortcutSettings.removeListener(_applyShortcut));
    final presses = shortcut.presses.listen((_) => _toggleChat());
    _cleanup.add(presses.cancel);
    final talks = shortcut.voicePresses.listen((_) => _talk());
    _cleanup.add(talks.cancel);

    // «Oye <nombre>»: al oír su nombre sale y abre el chat escuchando.
    void applyWake() =>
        unawaited(container.read(voiceProvider.notifier).configureWake(
            enabled: mascot.wakeWord,
            name: mascot.name,
            strict: mascot.wakeStrict));
    applyWake();
    mascot.addListener(applyWake);
    _cleanup.add(() => mascot.removeListener(applyWake));
    // Si se abrió el chat al oír su nombre y luego no dijiste nada (una
    // falsa alarma), se vuelve a cerrar para no tapar la pantalla. Y si
    // estaba escondida, al terminar de hablar se vuelve a esconder.
    MascotPanel? beforeVoice;
    var hiddenBeforeVoice = false;
    final heard = container.listen<VoiceState>(voiceProvider, (before, now) {
      final started = now.listening && !(before?.listening ?? false);
      if (started) {
        _rehide?.cancel();
        hiddenBeforeVoice = !window.visible.value;
        final panel = container.read(mascotPanelProvider);
        if (panel != MascotPanel.chat) {
          beforeVoice = panel;
          unawaited(_showPanel(MascotPanel.chat));
        } else {
          beforeVoice = null;
        }
        return;
      }
      final wasBusy = before != null && before.status != VoiceStatus.idle;
      if (!wasBusy || now.status != VoiceStatus.idle) return;
      final silent = now.problem == nothingHeard;
      final back = beforeVoice;
      beforeVoice = null;
      if (hiddenBeforeVoice) {
        hiddenBeforeVoice = false;
        // Falsa alarma: enseguida; si respondió, deja leer la respuesta.
        _rehideLater(silent ? rehideSilent : rehideAfter);
        return;
      }
      if (back != null &&
          silent &&
          container.read(mascotPanelProvider) == MascotPanel.chat) {
        unawaited(_showPanel(back));
      }
    });
    _cleanup.add(heard.close);
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
        petName: mascot.name,
        wakeEnabled: mascot.wakeWord,
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
      case TrayAction.showPending:
        await _showPanel(MascotPanel.pending);
      case TrayAction.toggleMascot:
        await window.toggle();
      case TrayAction.toggleDetection:
        await detection.setEnabled(!detection.enabled);
      case TrayAction.toggleWalk:
        await mascot.setWalkEnabled(!mascot.walkEnabled);
      case TrayAction.toggleWake:
        await mascot.setWakeWord(!mascot.wakeWord);
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

  /// ⌃⌥V: abre el chat escuchando (o termina la frase si ya escucha).
  Future<void> _talk() async {
    await container.read(voiceProvider.notifier).toggle();
  }

  Timer? _rehide;

  /// Vuelve a esconder la mascota pasado [after], si mientras tanto no
  /// seguiste hablándole ni escribiéndole y no suena una alarma.
  void _rehideLater(Duration after) {
    _rehide?.cancel();
    final messages = container.read(chatProvider).length;
    final since = DateTime.now();
    _rehide = Timer(after, () async {
      if (!window.visible.value) return;
      if (container.read(voiceProvider).status != VoiceStatus.idle) return;
      if (container.read(alarmProvider).active) return;
      if (container.read(chatProvider).length != messages) return;
      // Si la estás usando (otro panel, el juego, una alarma…), se queda.
      final panel = container.read(mascotPanelProvider);
      if (panel != MascotPanel.chat && panel != MascotPanel.none) return;
      final touched = container.read(lastInteractionProvider);
      if (touched != null && touched.isAfter(since)) return;
      await setMascotPanel(
        window: window,
        panel: container.read(mascotPanelProvider.notifier),
        next: MascotPanel.none,
      );
      _quietHide = true;
      await window.hide();
    });
  }

  /// La próxima vez que se esconda, sin avisar cómo traerla.
  bool _quietHide = false;

  /// Ya se explicó en esta sesión cómo traerla de vuelta.
  bool _toldHowToReturn = false;

  Future<void> _showPanel(MascotPanel next) async {
    if (!window.visible.value) await window.show();
    await setMascotPanel(
      window: window,
      panel: container.read(mascotPanelProvider.notifier),
      next: next,
    );
  }

  Future<void> dispose() async {
    _rehide?.cancel();
    for (final c in _cleanup) {
      c();
    }
    _cleanup.clear();
    await _tray.dispose();
  }
}

/// Cómo traer de vuelta a la mascota escondida.
String hiddenMascotHelp(
    {required String name, required bool wake, required bool shortcut}) {
  const menu =
      'elige «Mostrar mascota» en el menú de PixelMate (barra superior)';
  final ways = [
    if (wake) 'di «Oye $name»',
    if (shortcut) 'pulsa ⌃⌥P',
  ];
  final how = ways.isEmpty ? menu : '${ways.join(', ')} o $menu';
  return 'Sigue aquí. Para que vuelva, $how.';
}
