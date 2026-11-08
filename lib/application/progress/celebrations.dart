import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../mascot/mascot_settings.dart';
import '../stats/consistency.dart';
import '../workday/workday_controller.dart';
import '../workday/workday_providers.dart';
import 'progress_providers.dart';
import 'progression.dart';

/// Algo que celebrar: subir de nivel, un logro, un hito de la racha…
class Celebration {
  final String title;
  final String message;

  /// Suena el sonido de subir de nivel.
  final bool levelUp;

  /// Notificación del sistema aunque la mascota esté a la vista.
  final bool alwaysNotify;

  const Celebration(this.title, this.message,
      {this.levelUp = false, this.alwaysNotify = true});

  /// Las que se guardaron durante el enfoque, juntas en una sola.
  factory Celebration.combined(List<Celebration> held) => held.length == 1
      ? Celebration(
          held.single.title, 'Mientras te enfocabas: ${held.single.message}',
          levelUp: held.single.levelUp)
      : Celebration(
          'Mientras te enfocabas',
          'Mientras te enfocabas: ${held.map((c) => c.message).join(' · ')}',
          levelUp: held.any((c) => c.levelUp),
        );
}

/// `true` mientras hay un bloque de enfoque en marcha.
bool isFocusing(WorkdayView view) {
  final s = view.status;
  return s != null &&
      s.state == WorkdayRunState.running &&
      s.phase?.kind == SessionPhase.focus;
}

/// Decide cuándo se celebra. Con el modo enfoque profundo, lo que pasa
/// durante un bloque de enfoque espera al descanso (o al final).
///
/// El estado es la última celebración a mostrar; cada una es un objeto
/// nuevo, así quien escucha reacciona aunque el texto se repita.
class CelebrationController extends StateNotifier<Celebration?> {
  final MascotSettings _settings;
  final List<Celebration> _held = [];
  WorkdayView _view = WorkdayView.none;

  CelebrationController(this._settings) : super(null);

  /// Celebraciones guardadas para el descanso.
  List<Celebration> get held => List.unmodifiable(_held);

  bool get _holding => _settings.deepFocus && isFocusing(_view);

  void add(Celebration c) {
    if (_holding) {
      _held.add(c);
    } else {
      state = c;
    }
  }

  void onWorkday(WorkdayView view) {
    _view = view;
    if (_held.isNotEmpty && !_holding) {
      state = Celebration.combined(List.of(_held));
      _held.clear();
    }
  }
}

final celebrationProvider =
    StateNotifierProvider<CelebrationController, Celebration?>((ref) {
  final c = CelebrationController(ref.watch(mascotSettingsProvider));
  ref.listen<WorkdayView>(workdayControllerProvider, (_, v) => c.onWorkday(v),
      fireImmediately: true);
  ref.listen<PlayerProgress>(progressProvider, (before, after) {
    if (before == null) return;
    for (final event in progressEvents(before, after)) {
      final m = progressMessage(event);
      c.add(Celebration(m.title, m.message, levelUp: event is LeveledUp));
    }
  });
  ref.listen<Consistency>(consistencyProvider, (before, after) {
    final message = consistencyMilestone(before, after);
    if (message != null) {
      c.add(Celebration('¡Buen ritmo!', message, alwaysNotify: false));
    }
  });
  return c;
});
