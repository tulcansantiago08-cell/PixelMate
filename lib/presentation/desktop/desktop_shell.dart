import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final Future<void> Function() quitApp;

  late final MenuBarTray _tray = MenuBarTray(onSelected: _onTrayAction);
  final List<void Function()> _cleanup = [];

  DesktopShell({
    required this.container,
    required this.window,
    required this.notifier,
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

    void onVisibility() => _refreshTray(container.read(workdayControllerProvider));
    window.visible.addListener(onVisibility);
    _cleanup.add(() => window.visible.removeListener(onVisibility));

    final events = _workday.events.listen((event) {
      final notice = noticeFor(event);
      if (notice != null) unawaited(notifier.show(notice));
    });
    _cleanup.add(events.cancel);
  }

  void _refreshTray(WorkdayView view) {
    unawaited(_tray.update(
      trayTitle(view),
      trayEntries(view, mascotVisible: window.visible.value),
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
      case TrayAction.toggleMascot:
        await window.toggle();
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
