import '../../core/i18n/language.dart';
import 'dart:math';

import '../../domain/activity/activity_mode.dart';
import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_kind.dart';
import '../stats/consistency.dart';
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
List<(int, String)> get _titles => [
      (1, tr('Gatito novato', 'Rookie kitten')),
      (3, tr('Aprendiz curioso', 'Curious apprentice')),
      (5, tr('Constante', 'Consistent')),
      (8, tr('Mente enfocada', 'Focused mind')),
      (12, tr('Maestro del ritmo', 'Rhythm master')),
      (16, tr('Sabio zen', 'Zen sage')),
      (20, tr('Leyenda pixel', 'Pixel legend')),
      (25, tr('Mito del enfoque', 'Focus myth')),
    ];

String titleForLevel(int level) => _titles.lastWhere((t) => level >= t.$1).$2;

// ---------------------------------------------------------------------------
// Logros

class Achievement {
  final String id;
  final String emoji;

  /// (español, inglés).
  final (String, String) _title;
  final (String, String) _description;
  final bool Function(_History h) _unlocked;

  const Achievement._(
      this.id, this.emoji, this._title, this._description, this._unlocked);

  String get title => tr(_title.$1, _title.$2);
  String get description => tr(_description.$1, _description.$2);
}

/// Resumen del historial que usan los logros.
class _History {
  final List<WorkdayRecord> records;
  final Duration focus;
  final Duration breaks;
  final int activeDays;

  /// Sesiones en 5 de 7 días en algún tramo de una semana.
  final bool steady;

  final int xp;

  _History(this.records, {int bonusXp = 0})
      : xp = records.fold(bonusXp, (sum, r) => sum + xpForRecord(r)),
        steady = hasSteadyWindow(activeDaySet(records)),
        focus = records.fold(Duration.zero, (s, r) => s + r.effectiveFocus),
        breaks = records.fold(Duration.zero, (s, r) => s + r.effectiveBreak),
        activeDays = records
            .map((r) {
              final l = r.startedAt.toLocal();
              return DateTime(l.year, l.month, l.day);
            })
            .toSet()
            .length;

  int sessionsOf(ActivityMode mode) =>
      records.where((r) => r.mode == mode).length;
}

/// Logros en el orden en que se muestran.
final achievements = <Achievement>[
  Achievement._('first', '🐾', ('Primeros pasos', 'First steps'), ('Haz tu primera sesión.', 'Do your first session.'),
      (h) => h.records.isNotEmpty),
  Achievement._(
      'complete',
      '✅',
      ('Hasta el final', 'All the way'),
      ('Completa una jornada sin terminarla antes.', 'Complete a workday without ending it early.'),
      (h) => h.records.any((r) => r.completed)),
  Achievement._(
      'cycles',
      '🌀',
      ('Ciclo perfecto', 'Perfect cycle'),
      ('Completa 3 ciclos en una misma jornada.', 'Complete 3 cycles in a single workday.'),
      (h) => h.records.any((r) => r.cyclesCompleted >= 3)),
  Achievement._('rest', '☕', ('Buen descanso', 'Good rest'), ('Suma 1 hora de descansos.', 'Add up 1 hour of breaks.'),
      (h) => h.breaks >= const Duration(hours: 1)),
  Achievement._('focus10', '⏱️', ('10 horas', '10 hours'), ('Suma 10 horas de enfoque.', 'Add up 10 hours of focus.'),
      (h) => h.focus >= const Duration(hours: 10)),
  Achievement._('focus50', '🔥', ('50 horas', '50 hours'), ('Suma 50 horas de enfoque.', 'Add up 50 hours of focus.'),
      (h) => h.focus >= const Duration(hours: 50)),
  Achievement._(
      'days7',
      '📅',
      ('Siete días', 'Seven days'),
      ('Ten sesiones en 7 días distintos (no hace falta que sean seguidos).', 'Have sessions on 7 different days (they don\'t need to be in a row).'),
      (h) => h.activeDays >= 7),
  Achievement._(
      'steady',
      '🌱',
      ('Buen ritmo', 'Good rhythm'),
      ('Ten sesiones en 5 de 7 días (no hace falta que sean seguidos).', 'Have sessions on 5 of 7 days (they don\'t need to be in a row).'),
      (h) => h.steady),
  Achievement._('study', '📚', ('Estudioso', 'Studious'), ('Haz 5 sesiones de estudio.', 'Do 5 study sessions.'),
      (h) => h.sessionsOf(ActivityMode.study) >= 5),
  Achievement._(
      'gamer',
      '🎮',
      ('Gamer responsable', 'Responsible gamer'),
      ('Completa una sesión de juego con sus pausas.', 'Complete a gaming session with its breaks.'),
      (h) =>
          h.records.any((r) => r.mode == ActivityMode.gaming && r.completed)),
  Achievement._(
      'early',
      '🌅',
      ('Madrugador', 'Early bird'),
      ('Empieza una sesión antes de las 8:00.', 'Start a session before 8:00.'),
      (h) => h.records.any((r) => r.startedAt.toLocal().hour < 8)),
  Achievement._('legend', '🌈', ('Leyenda', 'Legend'), ('Llega al nivel 25.', 'Reach level 25.'),
      (h) => levelForXp(h.xp) >= 25),
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
/// guardada en el historial (mismo id) no se cuenta dos veces. [bonusXp] es
/// la XP ganada fuera de las sesiones (el minijuego de los descansos).
PlayerProgress computeProgress(List<WorkdayRecord> history,
    {WorkdayRecord? live, int bonusXp = 0}) {
  final records = [
    ...history,
    if (live != null && !history.any((r) => r.id == live.id)) live,
  ];
  final h = _History(records, bonusXp: bonusXp);
  return PlayerProgress(
    xp: h.xp,
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

  /// Accesorios que se desbloquean con esta subida.
  final List<PetAccessory> accessories;

  /// Especies que se desbloquean con esta subida.
  final List<PetKind> species;

  /// Si con esta subida se desbloquea el aura brillante.
  final bool aura;

  const LeveledUp(this.level, this.title,
      {required this.newTitle,
      this.accessories = const [],
      this.species = const [],
      this.aura = false});
}

class AchievementUnlocked extends ProgressEvent {
  final Achievement achievement;
  const AchievementUnlocked(this.achievement);
}

/// Qué cambió entre dos cálculos de progreso. Solo cuenta lo que se gana:
/// si el historial cambia hacia atrás, no se anuncia nada.
List<ProgressEvent> progressEvents(
    PlayerProgress before, PlayerProgress after) {
  final events = <ProgressEvent>[];
  if (after.level > before.level) {
    events.add(LeveledUp(after.level, after.title,
        newTitle: after.title != before.title,
        accessories: PetAccessory.unlockedBetween(before.level, after.level),
        species: PetKind.unlockedBetween(before.level, after.level),
        aura:
            before.level < auraUnlockLevel && after.level >= auraUnlockLevel));
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
      LeveledUp(
        :final level,
        :final title,
        :final newTitle,
        :final accessories,
        :final species,
        :final aura
      ) =>
        (
          title: tr('Nivel $level', 'Level $level'),
          message: (newTitle
                  ? tr('Subiste a nivel $level: ahora eres «$title».',
                      'You reached level $level: now you\'re “$title”.')
                  : tr('Subiste a nivel $level.', 'You reached level $level.')) +
              _unlocks([
                for (final k in species) '${k.emoji} ${k.label}',
                for (final a in accessories) '${a.emoji} ${a.label}',
                if (aura) tr('✨ Aura brillante', '✨ Shiny aura'),
              ]),
        ),
      AchievementUnlocked(:final achievement) => (
          title: tr('Logro desbloqueado', 'Achievement unlocked'),
          message: tr('Logro: ${achievement.title}. ${achievement.description}',
              'Achievement: ${achievement.title}. ${achievement.description}'),
        ),
    };

String _unlocks(List<String> items) => items.isEmpty
    ? ''
    : tr(' Desbloqueaste: ${items.join(', ')} (elígelo en ⚙️ Ajustes).',
        ' You unlocked: ${items.join(', ')} (choose it in ⚙️ Settings).');
