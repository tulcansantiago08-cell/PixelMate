import 'dart:math';

import '../../domain/activity/activity_mode.dart';
import '../workday/workday_store.dart';

/// Experiencia, niveles y logros.
///
/// Todo se calcula a partir del historial de sesiones: no hay nada extra que
/// guardar ni que pueda desincronizarse, y nunca se pierde XP (descansar o
/// dejar pasar días no resta nada).

// ---------------------------------------------------------------------------
// XP

/// XP de una sesión (también de la que está en curso, con lo hecho hasta ahora):
/// - 1 por minuto de enfoque.
/// - 1 por cada 2 minutos de descanso: descansar también es parte del plan.
/// - 5 por cada bloque de enfoque terminado.
/// - 25 por completar la jornada sin terminarla antes.
int xpForRecord(WorkdayRecord r) =>
    r.effectiveFocus.inMinutes +
    r.effectiveBreak.inMinutes ~/ 2 +
    r.focusBlocksCompleted * 5 +
    (r.completed ? 25 : 0);

// ---------------------------------------------------------------------------
// Niveles

/// XP total necesaria para llegar a [level] (el nivel 1 empieza en 0).
/// Cada nivel pide 100 XP más que el anterior: 100, 300, 600, 1000…
int xpForLevel(int level) => 50 * level * (level - 1);

/// Nivel que corresponde a [xp] (inversa de [xpForLevel]).
int levelForXp(int xp) {
  if (xp <= 0) return 1;
  var level = ((1 + sqrt(1 + xp / 12.5)) / 2).floor();
  // Corrige posibles errores de redondeo.
  while (xpForLevel(level + 1) <= xp) {
    level++;
  }
  while (level > 1 && xpForLevel(level) > xp) {
    level--;
  }
  return level;
}

/// Títulos según el nivel: se muestran en el panel y al subir de nivel.
const _titles = <(int, String)>[
  (1, 'Gatito novato'),
  (3, 'Aprendiz curioso'),
  (5, 'Constante'),
  (8, 'Mente enfocada'),
  (12, 'Maestro del ritmo'),
  (16, 'Sabio zen'),
  (20, 'Leyenda pixel'),
];

String titleForLevel(int level) =>
    _titles.lastWhere((t) => level >= t.$1).$2;

// ---------------------------------------------------------------------------
// Logros

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool Function(_History h) _unlocked;

  const Achievement._(
      this.id, this.emoji, this.title, this.description, this._unlocked);
}

/// Resumen del historial que usan los logros.
class _History {
  final List<WorkdayRecord> records;
  final Duration focus;
  final Duration breaks;
  final int activeDays;

  _History(this.records)
      : focus = records.fold(Duration.zero, (s, r) => s + r.effectiveFocus),
        breaks = records.fold(Duration.zero, (s, r) => s + r.effectiveBreak),
        activeDays = records.map((r) {
          final l = r.startedAt.toLocal();
          return DateTime(l.year, l.month, l.day);
        }).toSet().length;

  int sessionsOf(ActivityMode mode) =>
      records.where((r) => r.mode == mode).length;
}

/// Logros en el orden en que se muestran.
final achievements = <Achievement>[
  Achievement._('first', '🐾', 'Primeros pasos',
      'Haz tu primera sesión.', (h) => h.records.isNotEmpty),
  Achievement._('complete', '✅', 'Hasta el final',
      'Completa una jornada sin terminarla antes.',
      (h) => h.records.any((r) => r.completed)),
  Achievement._('cycles', '🌀', 'Ciclo perfecto',
      'Completa 3 ciclos en una misma jornada.',
      (h) => h.records.any((r) => r.cyclesCompleted >= 3)),
  Achievement._('rest', '☕', 'Buen descanso',
      'Suma 1 hora de descansos.',
      (h) => h.breaks >= const Duration(hours: 1)),
  Achievement._('focus10', '⏱️', '10 horas',
      'Suma 10 horas de enfoque.',
      (h) => h.focus >= const Duration(hours: 10)),
  Achievement._('focus50', '🔥', '50 horas',
      'Suma 50 horas de enfoque.',
      (h) => h.focus >= const Duration(hours: 50)),
  Achievement._('days7', '📅', 'Siete días',
      'Ten sesiones en 7 días distintos (no hace falta que sean seguidos).',
      (h) => h.activeDays >= 7),
  Achievement._('study', '📚', 'Estudioso',
      'Haz 5 sesiones de estudio.',
      (h) => h.sessionsOf(ActivityMode.study) >= 5),
  Achievement._('gamer', '🎮', 'Gamer responsable',
      'Completa una sesión de juego con sus pausas.',
      (h) => h.records
          .any((r) => r.mode == ActivityMode.gaming && r.completed)),
  Achievement._('early', '🌅', 'Madrugador',
      'Empieza una sesión antes de las 8:00.',
      (h) => h.records.any((r) => r.startedAt.toLocal().hour < 8)),
];

// ---------------------------------------------------------------------------
// Progreso

class PlayerProgress {
  final int xp;
  final Set<String> unlocked;

  const PlayerProgress({required this.xp, required this.unlocked});

  static const empty = PlayerProgress(xp: 0, unlocked: {});

  int get level => levelForXp(xp);
  String get title => titleForLevel(level);

  /// XP conseguida dentro del nivel actual.
  int get xpIntoLevel => xp - xpForLevel(level);

  /// XP que pide el nivel actual para subir al siguiente.
  int get xpNeededForNext => xpForLevel(level + 1) - xpForLevel(level);

  double get levelFraction => xpIntoLevel / xpNeededForNext;

  bool isUnlocked(Achievement a) => unlocked.contains(a.id);
}

/// Progreso con todo el historial. [live] es la sesión en curso; si ya está
/// guardada en el historial (mismo id) no se cuenta dos veces.
PlayerProgress computeProgress(List<WorkdayRecord> history,
    {WorkdayRecord? live}) {
  final records = [
    ...history,
    if (live != null && !history.any((r) => r.id == live.id)) live,
  ];
  final h = _History(records);
  return PlayerProgress(
    xp: records.fold(0, (sum, r) => sum + xpForRecord(r)),
    unlocked: {
      for (final a in achievements)
        if (a._unlocked(h)) a.id
    },
  );
}

// ---------------------------------------------------------------------------
// Sucesos (para celebrar)

sealed class ProgressEvent {
  const ProgressEvent();
}

class LeveledUp extends ProgressEvent {
  final int level;
  final String title;

  /// `true` si con este nivel se estrena título.
  final bool newTitle;
  const LeveledUp(this.level, this.title, {required this.newTitle});
}

class AchievementUnlocked extends ProgressEvent {
  final Achievement achievement;
  const AchievementUnlocked(this.achievement);
}

/// Qué cambió entre dos cálculos de progreso. Solo cuenta lo que se gana:
/// si el historial cambia hacia atrás, no se anuncia nada.
List<ProgressEvent> progressEvents(PlayerProgress before, PlayerProgress after) {
  final events = <ProgressEvent>[];
  if (after.level > before.level) {
    events.add(LeveledUp(after.level, after.title,
        newTitle: after.title != before.title));
  }
  for (final a in achievements) {
    if (after.isUnlocked(a) && !before.isUnlocked(a)) {
      events.add(AchievementUnlocked(a));
    }
  }
  return events;
}

/// Mensaje de la mascota y de la notificación para un suceso.
({String title, String message}) progressMessage(ProgressEvent event) =>
    switch (event) {
      LeveledUp(:final level, :final title, :final newTitle) => (
          title: '¡Nivel $level!',
          message: newTitle
              ? '¡Subiste a nivel $level! Ahora eres «$title» 🎉'
              : '¡Subiste a nivel $level! Sigue así 🎉',
        ),
      AchievementUnlocked(:final achievement) => (
          title: 'Logro desbloqueado',
          message:
              '¡Logro: ${achievement.emoji} ${achievement.title}! ${achievement.description}',
        ),
    };
