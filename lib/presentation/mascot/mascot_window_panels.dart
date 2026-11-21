part of 'mascot_window.dart';

/// El panel abierto encima de la mascota.
extension _Panels on _MascotWindowState {
  Widget _panelFor(MascotPanel panel) {
    return switch (panel) {
      MascotPanel.chat => const ChatBubble(),
      MascotPanel.settings => SettingsPanel(
          onClose: () => _openPanel(MascotPanel.none),
          onShowWelcome: () => _openPanel(MascotPanel.welcome),
        ),
      MascotPanel.welcome => WelcomePanel(onDone: _finishWelcome),
      MascotPanel.pending =>
        PendingPanel(onClose: () => _openPanel(MascotPanel.none)),
      MascotPanel.game =>
        StarCatchPanel(onClose: () => _openPanel(MascotPanel.none)),
      MascotPanel.weekly =>
        WeeklyReportPanel(onClose: () => _openPanel(MascotPanel.none)),
      MascotPanel.album =>
        CollectionPanel(onClose: () => _openPanel(MascotPanel.none)),
      MascotPanel.daily =>
        DailyTasksPanel(onClose: () => _openPanel(MascotPanel.none)),
      _ => StatsPanel(
          onClose: () => _openPanel(MascotPanel.none),
          onShowWeekly: () => _showWeekly(weekStartOf(DateTime.now())),
          onShowAlbum: () => _openPanel(MascotPanel.album),
        ),
    };
  }
}
