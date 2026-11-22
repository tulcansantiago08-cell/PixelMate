part of 'mascot_window.dart';

/// Lo que hace la mascota cuando pasa algo en la app: avisos, música,
/// recordatorios, logros, el resumen del día…
extension _Reactions on _MascotWindowState {
  void _listenForReactions() {
    // Si la mascota pregunta algo, deja de pasear.
    ref.listen(activityDetectionProvider, (_, s) {
      if (s != null) _walker.stop();
    });
    // Versión nueva de PixelMate (una vez por versión).
    ref.listen(updateProvider, (before, now) {
      final release = now.release;
      if (release != null && now.announce > (before?.announce ?? 0)) {
        _react(MascotReaction(updateMessage(release), MascotState.alert),
            duration: const Duration(seconds: 15));
      }
    });
    // Música: al empezar una canción, la dice (no durante el enfoque).
    ref.listen(musicProvider, (before, now) {
      final song = now.now;
      // El video que puso no llegó a sonar: el navegador no lo reprodujo.
      if ((before?.playing ?? false) &&
          before?.now?.source == 'youtube' &&
          song?.source == 'youtube' &&
          !now.playing &&
          ref.read(musicProvider.notifier).videoDidNotStart) {
        _react(
            const MascotReaction(
                'Abrí el video, pero no empezó a sonar: dale play en el '
                'navegador.',
                MascotState.alert),
            duration: const Duration(seconds: 10));
        return;
      }
      if (song == null ||
          (song.source != 'disco' &&
              !ref.read(mascotSettingsProvider).musicReactions)) {
        return;
      }
      if (song.playing && !(before?.playing ?? false)) {
        _walker.stop();
        _wake(animate: false);
      }
      if (now.announce > (before?.announce ?? 0) &&
          !isFocusing(ref.read(workdayControllerProvider)) &&
          ref.read(mascotPanelProvider) == MascotPanel.none) {
        _react(
            MascotReaction(
                songMessage(song, now.announce), MascotState.celebrating),
            duration: const Duration(seconds: 6));
      }
    });
    // Al hablarle (🎙️, ⌃⌥V u «oye <nombre>») se queda quieta y atenta.
    ref.listen(voiceProvider, (before, now) {
      if (now.listening && !(before?.listening ?? false)) {
        _walker.stop();
        _wake(animate: false);
      }
    });
    // Recordatorios a su hora: se avisan aunque haya jornada.
    void onReminder(ReminderAlert? before, ReminderAlert? alert) {
      if (alert == null || identical(before, alert)) return;
      _walker.stop();
      _wake(animate: false);
      // Las alarmas se ven en su tarjeta (con Apagar y Posponer).
      final others = [
        for (final r in alert.items)
          if (!r.alarm) r
      ];
      if (others.isEmpty) return;
      _react(
          MascotReaction(
              ReminderAlert(others, alert.at).message, MascotState.alert),
          replace: true,
          duration: const Duration(seconds: 30));
    }

    ref.listen<ReminderAlert?>(reminderProvider, onReminder);
    ref.listen<ReminderAlert?>(calendarAlertProvider, onReminder);
    // Nivel, logros y racha (con enfoque profundo, esperan al descanso).
    ref.listen(celebrationProvider, (before, c) {
      if (c == null || identical(before, c)) return;
      _walker.stop();
      _react(MascotReaction(c.message, MascotState.celebrating),
          duration: const Duration(seconds: 10));
    });
    // Por la mañana: lo que tienes hoy.
    ref.listen<String?>(briefingProvider, (before, message) {
      if (message == null || message == before) return;
      _walker.stop();
      _wake(animate: false);
      _react(MascotReaction(message, MascotState.greeting),
          replace: true, duration: const Duration(seconds: 45));
    });
    // De noche, si sigue la jornada: recordar descansar.
    ref.listen(lateNightProvider, (before, message) {
      if (message != null && before == null) {
        _walker.stop();
        _react(MascotReaction(message, MascotState.tired),
            replace: true, duration: const Duration(seconds: 15));
      }
    });
    // Guardián del enfoque: un aviso amable si hay una distracción al frente.
    ref.listen(focusGuardProvider, (before, nudge) {
      if (nudge != null && before == null) {
        _walker.stop();
        _react(
            MascotReaction(
                focusNudgeMessage(nudge, ref.read(workdayControllerProvider)),
                MascotState.alert),
            replace: true);
      }
    });
    ref.listen(dailyGoalProvider, (before, after) {
      if (goalJustReached(before, after)) {
        _walker.stop();
        _react(MascotReaction(
            goalReachedMessage(after!.goal), MascotState.celebrating));
      }
    });
  }
}
