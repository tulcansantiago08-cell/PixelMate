import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/activity/activity_mode.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_config.dart';
import '../../domain/session/workday_timer.dart';
import 'workday_event.dart';
import 'workday_store.dart';

/// Lo que la interfaz necesita para dibujar la jornada.
class WorkdayView {
  final ActivityMode? mode;
  final WorkdayTimer? timer;
  final WorkdayStatus? status;

  const WorkdayView({this.mode, this.timer, this.status});

  static const none = WorkdayView();

  bool get isActive => timer != null;
}

/// Mantiene una única jornada activa, la guarda en cada cambio y emite
/// [WorkdayEvent]s sin repetirlos.
///
/// El reloj es inyectable para las pruebas. El tic solo refresca la vista:
/// el estado real se calcula desde marcas de tiempo (ver [WorkdayTimer]).
class WorkdayController extends StateNotifier<WorkdayView> {
  final WorkdayStore _store;
  final DateTime Function() _now;
  final String Function() _newId;
  final Duration _tickInterval;

  final _events = StreamController<WorkdayEvent>.broadcast();
  Timer? _ticker;

  // Avisos ya emitidos, para no repetirlos.
  int? _lastPhaseIndex;
  final Set<String> _sentWarnings = {};

  static const focusWarnings = [Duration(minutes: 5), Duration(seconds: 30)];
  static const workdayWarnings = [Duration(minutes: 30), Duration(minutes: 5)];

  WorkdayController({
    required WorkdayStore store,
    DateTime Function()? now,
    String Function()? newId,
    Duration tickInterval = const Duration(seconds: 1),
  })  : _store = store,
        _now = now ?? DateTime.now,
        _newId = newId ?? _timestampId,
        _tickInterval = tickInterval,
        super(WorkdayView.none) {
    _recover();
  }

  static String _timestampId() =>
      'jornada-${DateTime.now().toUtc().microsecondsSinceEpoch}';

  Stream<WorkdayEvent> get events => _events.stream;

  ActivityMode? _lastMode;

  /// Modo de la sesión actual o de la última que terminó (para que el aviso
  /// de fin use las frases correctas).
  ActivityMode get currentMode => state.mode ?? _lastMode ?? ActivityMode.work;

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  /// Inicia una jornada. Lanza [StateError] si ya hay una en curso.
  void start(WorkdayConfig config, {ActivityMode mode = ActivityMode.work}) {
    if (state.isActive) {
      throw StateError('Ya hay una jornada en curso');
    }
    config.validate();
    final timer = WorkdayTimer.start(id: _newId(), config: config, now: _now());
    _lastPhaseIndex = 0;
    _sentWarnings.clear();
    _lastMode = mode;
    _apply(ActiveWorkday(mode, timer));
    _emit(const WorkdayStarted());
    _startTicker();
  }

  void pause() {
    if (_update((t) => t.pause(_now()))) _emit(const WorkdayPaused());
  }

  void resume() {
    if (_update((t) => t.resume(_now()))) _emit(const WorkdayResumed());
  }

  void skipPhase() => _update((t) => t.skipPhase(_now()));

  void finish() => _update((t) => t.finish(_now()));

  /// Recalcula el estado. Lo llama el tic; las pruebas lo llaman a mano.
  void refresh() {
    final timer = state.timer;
    final mode = state.mode;
    if (timer == null || mode == null) return;
    final now = _now();
    final status = timer.statusAt(now);

    if (status.state == WorkdayRunState.finished) {
      _store.completeActive(WorkdayRecord.fromTimer(mode, timer, now));
      _stopTicker();
      state = WorkdayView.none;
      _emit(WorkdayFinished(status));
      return;
    }

    _detectEvents(timer, status);
    state = WorkdayView(mode: mode, timer: timer, status: status);
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------

  void _recover() {
    final active = _store.loadActive();
    if (active == null) return;
    _lastMode = active.mode;
    final status = active.timer.statusAt(_now());
    // Al recuperar no se repiten avisos de fases que ya pasaron.
    _lastPhaseIndex = status.phase?.index;
    _markPassedWarnings(status);
    state = WorkdayView(mode: active.mode, timer: active.timer, status: status);
    refresh(); // si terminó mientras la app estaba cerrada, se registra ya
    if (state.isActive) _startTicker();
  }

  /// Aplica una acción; devuelve `true` si cambió algo.
  bool _update(WorkdayTimer Function(WorkdayTimer) action) {
    final timer = state.timer;
    final mode = state.mode;
    if (timer == null || mode == null) return false;
    final next = action(timer);
    if (identical(next, timer)) return false;
    _apply(ActiveWorkday(mode, next));
    return true;
  }

  void _apply(ActiveWorkday active) {
    _store.saveActive(active);
    state = WorkdayView(
      mode: active.mode,
      timer: active.timer,
      status: active.timer.statusAt(_now()),
    );
    refresh();
  }

  void _detectEvents(WorkdayTimer timer, WorkdayStatus status) {
    final phase = status.phase;
    if (phase == null) return;

    if (_lastPhaseIndex != phase.index) {
      final previous =
          _lastPhaseIndex == null ? null : timer.plan[_lastPhaseIndex!];
      _lastPhaseIndex = phase.index;
      _emit(PhaseStarted(phase, previous));
    }

    if (status.state != WorkdayRunState.running) return;

    if (phase.kind == SessionPhase.focus) {
      final crossed = _newlyCrossed(focusWarnings, phase.duration,
          status.phaseRemaining, 'fase${phase.index}');
      if (crossed != null) _emit(FocusEndingSoon(phase, crossed));
    }

    final crossed = _newlyCrossed(workdayWarnings, timer.config.workday,
        status.workdayRemaining, 'jornada');
    if (crossed != null) _emit(WorkdayEndingSoon(crossed));
  }

  /// Marca como enviados los umbrales ya alcanzados y devuelve el más
  /// cercano de los nuevos. Si se cruzan dos a la vez (p. ej. tras el reposo
  /// del Mac) solo se avisa una vez, con el más próximo.
  Duration? _newlyCrossed(List<Duration> thresholds, Duration total,
      Duration remaining, String scope) {
    Duration? nearest;
    for (final w in thresholds) {
      if (total > w &&
          remaining <= w &&
          _sentWarnings.add('$scope:${w.inSeconds}')) {
        if (nearest == null || w < nearest) nearest = w;
      }
    }
    return nearest;
  }

  void _markPassedWarnings(WorkdayStatus status) {
    final phase = status.phase;
    if (phase != null && phase.kind == SessionPhase.focus) {
      _newlyCrossed(focusWarnings, phase.duration, status.phaseRemaining,
          'fase${phase.index}');
    }
    _newlyCrossed(workdayWarnings, status.position + status.workdayRemaining,
        status.workdayRemaining, 'jornada');
  }

  void _emit(WorkdayEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => refresh());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    _events.close();
    super.dispose();
  }
}
