import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/activity/detectable_app.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../workday/workday_controller.dart';
import '../workday/workday_providers.dart';
import 'activity_providers.dart';
import 'focus_guard.dart';

/// Une el guardián con la app al frente y el tic de la jornada. El estado es
/// el aviso visible (o `null`).
class FocusGuardController extends StateNotifier<FocusNudge?> {
  final FocusGuard _guard;
  final FocusGuardSettings _settings;
  final DateTime Function() _now;
  final Duration autoHide;
  StreamSubscription<ForegroundApp>? _sub;
  Timer? _hide;

  FocusGuardController({
    required FocusGuard guard,
    required FocusGuardSettings settings,
    required Stream<ForegroundApp> foregroundApps,
    DateTime Function()? now,
    this.autoHide = const Duration(seconds: 30),
  })  : _guard = guard,
        _settings = settings,
        _now = now ?? DateTime.now,
        super(null) {
    _sub = foregroundApps.listen(_onForeground);
    _settings.addListener(_onSettings);
  }

  void _onForeground(ForegroundApp app) {
    _guard.onForeground(app, _now());
    // Volvió a otra app: el aviso ya cumplió su función.
    if (state != null && state!.app != app) _clear();
  }

  void _onSettings() {
    if (!_settings.enabled) _clear();
  }

  /// Con cada tic de la jornada.
  void onTick(WorkdayView view) {
    final status = view.status;
    final focusing = status != null &&
        status.state == WorkdayRunState.running &&
        status.phase?.kind == SessionPhase.focus;
    final r = _guard.check(
      now: _now(),
      focusing: focusing,
      mode: view.mode,
      enabled: _settings.enabled,
    );
    if (r.spent > Duration.zero || r.newEpisode) {
      unawaited(_settings.record(spent: r.spent, episode: r.newEpisode));
    }
    final nudge = r.nudge;
    if (nudge != null) {
      _hide?.cancel();
      state = nudge;
      _hide = Timer(autoHide, _clear);
    }
    if (!focusing && state != null) _clear();
  }

  void _clear() {
    _hide?.cancel();
    if (mounted) state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    _settings.removeListener(_onSettings);
    super.dispose();
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final focusGuardSettingsProvider =
    Provider<FocusGuardSettings>((_) => FocusGuardSettings());

final focusGuardProvider =
    StateNotifierProvider<FocusGuardController, FocusNudge?>((ref) {
  final controller = FocusGuardController(
    guard: FocusGuard(catalog: ref.watch(appCatalogProvider)),
    settings: ref.watch(focusGuardSettingsProvider),
    foregroundApps: ref.watch(foregroundAppsProvider),
  );
  ref.listen<WorkdayView>(
    workdayControllerProvider,
    (_, view) => controller.onTick(view),
  );
  return controller;
});

/// Distracciones de hoy, para el panel.
final distractionsTodayProvider = Provider<DistractionTally?>((ref) {
  final settings = ref.watch(focusGuardSettingsProvider);
  void changed() => ref.invalidateSelf();
  settings.addListener(changed);
  ref.onDispose(() => settings.removeListener(changed));
  return settings.enabled ? settings.today : null;
});

/// Texto del aviso, con cuánto falta para el descanso.
String focusNudgeMessage(FocusNudge nudge, WorkdayView view) {
  final left = view.status?.phaseRemaining.inMinutes;
  final when = left == null || left < 1
      ? 'Ya casi es el descanso.'
      : 'Quedan $left min para el descanso.';
  return '👀 Veo ${nudge.appName} en pleno enfoque. '
      '¿Lo dejamos para el descanso? $when';
}
