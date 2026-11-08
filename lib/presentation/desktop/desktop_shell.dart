import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/activity/detection_settings.dart';
import '../../application/desktop/mascot_panel.dart';
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
  final Future<void> Function() quitApp;

  late final MenuBarTray _tray = MenuBarTray(onSelected: _onTrayAction);
  final List<void Function()> _cleanup = [];

  DesktopShell({
    required this.container,
    required this.window,
    required this.notifier,
    required this.detection,
    required this.mascot,
    required this.quitApp,
  });

  WorkdayController get _workday =>
      container.read(workdayControllerProvider.notifier);

  Future<void> start() async {
    await _tray.init();
    await notifier.init();

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

    final events = _workday.events.listen((event) {
      final notice = noticeFor(event, mode: _workday.currentMode);
      if (notice != null) unawaited(notifier.show(notice));
    });
    _cleanup.add(events.cancel);

    // Subidas de nivel y logros: también se avisan si la mascota está oculta.
    final progress = container.listen<PlayerProgress>(
      progressProvider,
      (before, after) {
        if (before == null) return;
        for (final event in progressEvents(before, after)) {
          final m = progressMessage(event);
          unawaited(notifier.show(WorkdayNotice(m.title, m.message)));
        }
      },
    );
    _cleanup.add(progress.close);
  }

  void _refreshTray(WorkdayView view) {
    unawaited(_tray.update(
      trayTitle(view),
      trayEntries(
        view,
        mascotVisible: window.visible.value,
        detectionEnabled: detection.enabled,
        walkEnabled: mascot.walkEnabled,
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
        if (!window.visible.value) await window.show();
        await setMascotPanel(
          window: window,
          panel: container.read(mascotPanelProvider.notifier),
          next: MascotPanel.stats,
        );
      case TrayAction.toggleMascot:
        await window.toggle();
      case TrayAction.toggleDetection:
        await detection.setEnabled(!detection.enabled);
      case TrayAction.toggleWalk:
        await mascot.setWalkEnabled(!mascot.walkEnabled);
      case TrayAction.quit:
        await dispose();
        await quitApp();
      case null:
        break;
    }
  }

  Future<void> dispose() async {
    for (final c in _cleanup) {
      c();
    }
    _cleanup.clear();
    await _tray.dispose();
  }
}
