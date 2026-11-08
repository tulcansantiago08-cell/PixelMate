import 'phase_planner.dart';
import 'session_phase.dart';
import 'workday_config.dart';

/// Tramo del plan que el usuario saltó (no cuenta como tiempo efectivo).
class SkippedSpan {
  /// Desplazamiento dentro del plan donde empezó el salto.
  final Duration start;
  final Duration duration;

  const SkippedSpan(this.start, this.duration);

  Duration get end => start + duration;
}

enum WorkdayRunState { running, paused, finished }

/// Temporizador de jornada basado en marcas de tiempo reales.
///
/// No cuenta segundos con un contador: guarda cuándo empezó la jornada,
/// cuánto tiempo estuvo en pausa y qué tramos se saltaron. El estado en
/// cualquier momento se calcula con [statusAt]. Así sobrevive a reposo del
/// Mac, bloqueos y reinicios de la app (ver `docs/motor_de_jornada.md`).
///
/// Es inmutable: cada acción devuelve un temporizador nuevo.
class WorkdayTimer {
  final String id;
  final WorkdayConfig config;
  final DateTime startedAt;

  /// Tiempo total en pausa ya cerrado (pausas que se reanudaron).
  final Duration pausedTotal;

  /// Si está en pausa, desde cuándo.
  final DateTime? pausedAt;

  final List<SkippedSpan> skips;

  /// Si el usuario finalizó la jornada manualmente, cuándo.
  final DateTime? finishedAt;

  final List<PlannedPhase> plan;

  WorkdayTimer._({
    required this.id,
    required this.config,
    required this.startedAt,
    required this.pausedTotal,
    required this.pausedAt,
    required this.skips,
    required this.finishedAt,
  }) : plan = planWorkday(config);

  factory WorkdayTimer.start({
    required String id,
    required WorkdayConfig config,
    required DateTime now,
  }) =>
      WorkdayTimer._(
        id: id,
        config: config,
        startedAt: now.toUtc(),
        pausedTotal: Duration.zero,
        pausedAt: null,
        skips: const [],
        finishedAt: null,
      );

  WorkdayTimer _copy({
    Duration? pausedTotal,
    DateTime? Function()? pausedAt,
    List<SkippedSpan>? skips,
    DateTime? finishedAt,
  }) =>
      WorkdayTimer._(
        id: id,
        config: config,
        startedAt: startedAt,
        pausedTotal: pausedTotal ?? this.pausedTotal,
        pausedAt: pausedAt != null ? pausedAt() : this.pausedAt,
        skips: skips ?? this.skips,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  // ---------------------------------------------------------------------------
  // Cálculo de posición
  // ---------------------------------------------------------------------------

  Duration get _skippedTotal =>
      skips.fold(Duration.zero, (sum, s) => sum + s.duration);

  /// Tiempo de reloj transcurrido sin pausas (no incluye saltos).
  Duration activeElapsedAt(DateTime now) {
    var reference = now.toUtc();
    if (finishedAt != null && finishedAt!.isBefore(reference)) {
      reference = finishedAt!;
    }
    if (pausedAt != null && pausedAt!.isBefore(reference)) {
      reference = pausedAt!;
    }
    final elapsed = reference.difference(startedAt) - pausedTotal;
    // Si el reloj del sistema retrocede, no devolvemos tiempo negativo.
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Posición dentro del plan (tiempo activo + tramos saltados),
  /// limitada a la duración de la jornada.
  Duration positionAt(DateTime now) {
    final pos = activeElapsedAt(now) + _skippedTotal;
    return pos > config.workday ? config.workday : pos;
  }

  PlannedPhase? phaseAtPosition(Duration position) {
    for (final phase in plan) {
      if (position < phase.end) return phase;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  WorkdayTimer pause(DateTime now) {
    if (statusAt(now).state != WorkdayRunState.running) return this;
    return _copy(pausedAt: () => now.toUtc());
  }

  WorkdayTimer resume(DateTime now) {
    final paused = pausedAt;
    if (paused == null || finishedAt != null) return this;
    var pauseLength = now.toUtc().difference(paused);
    if (pauseLength.isNegative) pauseLength = Duration.zero;
    return _copy(
      pausedTotal: pausedTotal + pauseLength,
      pausedAt: () => null,
    );
  }

  /// Salta el resto de la fase actual. La jornada termina antes en la
  /// misma medida: el tiempo saltado no se recupera ni cuenta como efectivo.
  WorkdayTimer skipPhase(DateTime now) {
    if (statusAt(now).state == WorkdayRunState.finished) return this;
    final pos = positionAt(now);
    final phase = phaseAtPosition(pos);
    if (phase == null) return this;
    return _copy(skips: [...skips, SkippedSpan(pos, phase.end - pos)]);
  }

  /// Finaliza la jornada manualmente.
  WorkdayTimer finish(DateTime now) {
    if (statusAt(now).state == WorkdayRunState.finished) return this;
    return _copy(finishedAt: now.toUtc());
  }

  // ---------------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------------

  WorkdayStatus statusAt(DateTime now) {
    final position = positionAt(now);
    final reachedEnd = position >= config.workday;
    final state = (finishedAt != null || reachedEnd)
        ? WorkdayRunState.finished
        : pausedAt != null
            ? WorkdayRunState.paused
            : WorkdayRunState.running;

    final phase =
        state == WorkdayRunState.finished ? null : phaseAtPosition(position);

    var focusDone = 0;
    var cyclesDone = 0;
    var effectiveFocus = Duration.zero;
    var effectiveBreak = Duration.zero;

    for (final p in plan) {
      final reached = _overlap(p.start, p.end, Duration.zero, position);
      if (reached == Duration.zero) continue;
      final skipped = skips.fold<Duration>(Duration.zero,
          (sum, s) => sum + _overlap(p.start, p.end, s.start, s.end));
      final effective = reached - skipped;

      if (p.kind == SessionPhase.focus) {
        effectiveFocus += effective;
        if (position >= p.end && skipped == Duration.zero) focusDone++;
      } else {
        effectiveBreak += effective;
        if (p.kind == SessionPhase.longBreak && position >= p.end) {
          cyclesDone++;
        }
      }
    }

    return WorkdayStatus(
      state: state,
      phase: phase,
      phaseElapsed: phase == null ? Duration.zero : position - phase.start,
      phaseRemaining: phase == null ? Duration.zero : phase.end - position,
      position: position,
      workdayRemaining: config.workday - position,
      progress: position.inMilliseconds / config.workday.inMilliseconds,
      focusBlocksCompleted: focusDone,
      cyclesCompleted: cyclesDone,
      effectiveFocus: effectiveFocus,
      effectiveBreak: effectiveBreak,
      completedNaturally: reachedEnd && finishedAt == null,
    );
  }

  /// Momento en que terminará la fase actual si nada cambia, o `null` si
  /// está en pausa o finalizada. Sirve para programar un único aviso en
  /// lugar de comprobar el estado cada segundo.
  DateTime? nextTransitionAt(DateTime now) {
    final status = statusAt(now);
    if (status.state != WorkdayRunState.running) return null;
    return now.toUtc().add(status.phaseRemaining);
  }

  static Duration _overlap(
      Duration aStart, Duration aEnd, Duration bStart, Duration bEnd) {
    final start = aStart > bStart ? aStart : bStart;
    final end = aEnd < bEnd ? aEnd : bEnd;
    return end > start ? end - start : Duration.zero;
  }

  // ---------------------------------------------------------------------------
  // Persistencia (para recuperar la sesión tras cerrar la app)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'config': config.toJson(),
        'startedAt': startedAt.toIso8601String(),
        'pausedTotalMs': pausedTotal.inMilliseconds,
        'pausedAt': pausedAt?.toIso8601String(),
        'skips': [
          for (final s in skips)
            {
              'startMs': s.start.inMilliseconds,
              'durationMs': s.duration.inMilliseconds
            }
        ],
        'finishedAt': finishedAt?.toIso8601String(),
      };

  factory WorkdayTimer.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != 1) {
      throw FormatException('Versión de sesión no soportada: $version');
    }
    DateTime? parse(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toUtc();
    return WorkdayTimer._(
      id: json['id'] as String,
      config: WorkdayConfig.fromJson(json['config'] as Map<String, dynamic>),
      startedAt: parse(json['startedAt'])!,
      pausedTotal: Duration(milliseconds: json['pausedTotalMs'] as int),
      pausedAt: parse(json['pausedAt']),
      skips: [
        for (final s in json['skips'] as List)
          SkippedSpan(
            Duration(milliseconds: (s as Map)['startMs'] as int),
            Duration(milliseconds: s['durationMs'] as int),
          )
      ],
      finishedAt: parse(json['finishedAt']),
    );
  }
}

/// Foto del estado de la jornada en un instante.
class WorkdayStatus {
  final WorkdayRunState state;

  /// Fase actual, o `null` si la jornada terminó.
  final PlannedPhase? phase;
  final Duration phaseElapsed;
  final Duration phaseRemaining;

  /// Avance dentro del plan (incluye descansos y tramos saltados).
  final Duration position;
  final Duration workdayRemaining;

  /// De 0.0 a 1.0.
  final double progress;

  /// Bloques de enfoque terminados sin saltarse.
  final int focusBlocksCompleted;

  /// Ciclos cuyo descanso largo ya terminó.
  final int cyclesCompleted;

  /// Tiempo realmente pasado en enfoque (sin saltos ni pausas).
  final Duration effectiveFocus;
  final Duration effectiveBreak;

  /// `true` si llegó al final del plan sin que el usuario la finalizara.
  final bool completedNaturally;

  const WorkdayStatus({
    required this.state,
    required this.phase,
    required this.phaseElapsed,
    required this.phaseRemaining,
    required this.position,
    required this.workdayRemaining,
    required this.progress,
    required this.focusBlocksCompleted,
    required this.cyclesCompleted,
    required this.effectiveFocus,
    required this.effectiveBreak,
    required this.completedNaturally,
  });

  /// Tiempo hasta el próximo descanso, o `null` si ya está descansando.
  Duration? get nextBreakIn =>
      phase?.kind == SessionPhase.focus ? phaseRemaining : null;
}
