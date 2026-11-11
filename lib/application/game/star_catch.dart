import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../workday/workday_controller.dart';

/// Minijuego «Atrapa estrellas»: caen estrellas, trampas y ayudas, y una
/// cesta las recoge. Todo en coordenadas normalizadas (0–1) para que la
/// pantalla solo tenga que escalar.

enum FallingKind {
  star('⭐', points: 1),
  bigStar('🌟', points: 3),

  // Trampas que quitan una vida.
  cloud('⛈️', hurts: true),
  bomb('💣', hurts: true, speed: 1.5),

  /// Parece una estrella, pero a mitad de camino se vuelve calavera.
  fake('⭐', hurts: true),

  // Trampas que estorban.
  ice('🧊'),
  swirl('🌀'),
  mushroom('🍄'),

  // Ayudas.
  heart('💖'),
  magnet('🧲'),
  shield('🛡️');

  final String emoji;
  final int points;

  /// Atraparlo quita una vida.
  final bool hurts;

  /// Velocidad respecto a la del nivel.
  final double speed;

  const FallingKind(this.emoji,
      {this.points = 0, this.hurts = false, this.speed = 1});

  /// Estrella de verdad: si se escapa, se pierde una vida.
  bool get isStar => this == star || this == bigStar;
}

/// Efectos temporales sobre la cesta.
enum GameEffect {
  frozen('🧊', Duration(milliseconds: 3500)),
  inverted('🌀', Duration(seconds: 5)),
  shrunk('🍄', Duration(seconds: 6)),
  magnet('🧲', Duration(seconds: 6));

  final String emoji;
  final Duration duration;
  const GameEffect(this.emoji, this.duration);
}

/// Cestas que se desbloquean con medallas. Cada una tiene un truco.
enum BasketSkin {
  basket('🧺', 'Cesta', 'Sin trucos: pura habilidad'),
  bucket('🪣', 'Cubo', 'Un 15 % más ancho', widthFactor: 1.15),
  hat('🎩', 'Sombrero mágico', 'Empieza con 🧲 imán', startMagnet: true),
  honey('🍯', 'Tarro de miel', 'Cada 🌟 da un punto más', bigStarBonus: 1),
  ufo('🛸', 'OVNI', 'Se mueve un 20 % más rápido', speedFactor: 1.2),
  rainbow('🌈', 'Arcoíris', '🧊 🌀 🍄 duran la mitad', trapFactor: 0.5),
  crown('👑', 'Corona', 'Empieza con un 🛡️ escudo', startShield: true);

  final String emoji;
  final String label;
  final String perk;
  final double widthFactor;
  final double speedFactor;
  final double trapFactor;
  final int bigStarBonus;
  final bool startMagnet;
  final bool startShield;

  const BasketSkin(this.emoji, this.label, this.perk,
      {this.widthFactor = 1,
      this.speedFactor = 1,
      this.trapFactor = 1,
      this.bigStarBonus = 0,
      this.startMagnet = false,
      this.startShield = false});

  static BasketSkin byName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => BasketSkin.basket);
}

class FallingItem {
  final int id;
  final FallingKind kind;

  /// Columna por la que cae (sin contar el zigzag; el imán la mueve).
  double baseX;
  double y;

  /// Velocidad respecto a la del nivel (1 = igual).
  final double speed;

  /// Amplitud del zigzag (0 = cae recto).
  final double wobble;
  final double phase;

  /// Ya pasó la cesta sin que lo atrapara (sigue cayendo hasta salir).
  bool passed = false;

  FallingItem(this.id, this.kind, this.baseX, this.y,
      {this.speed = 1, this.wobble = 0, this.phase = 0});

  /// Altura a la que una estrella falsa muestra lo que es.
  static const fakeRevealY = 0.5;

  /// Lo que se ve: la estrella falsa se delata a mitad de camino.
  String get emoji =>
      kind == FallingKind.fake && y >= fakeRevealY ? '💀' : kind.emoji;

  /// Posición horizontal: con zigzag, oscila mientras cae.
  double get x => wobble == 0
      ? baseX
      : (baseX + wobble * sin(phase + y * 3 * pi))
          .clamp(StarCatchGame.itemRadius, 1 - StarCatchGame.itemRadius);

  FallingItem _at(double atY) => FallingItem(id, kind, baseX, atY,
      speed: speed, wobble: wobble, phase: phase);
}

/// Algo que pasó en un paso del juego (para efectos y sonidos).
class CatchEvent {
  final FallingKind kind;
  final double x;

  /// `true` si costó una vida.
  final bool lostLife;

  /// Texto que sube sobre la cesta («+1», «💔», «🌀 ¡Al revés!»…).
  final String label;

  const CatchEvent(this.kind, this.x, {this.lostLife = false, this.label = ''});
}

/// Se juega hasta perder las vidas: una se va con cada estrella que se
/// escapa y con cada trampa dañina que cae en la cesta. Con los puntos se
/// sube de nivel: todo cae más rápido, la cesta se achica y aparecen
/// trampas nuevas. La cesta tiene su propia velocidad: no salta adonde
/// apunta el ratón, va hacia allí.
class StarCatchGame {
  static const startLives = 3;

  /// Media anchura de la cesta en el nivel 1.
  static const basketHalfWidth = 0.12;

  /// Altura del centro de la cesta.
  static const basketY = 0.86;

  /// Zona en la que la cesta atrapa: un poco por encima de su centro (el
  /// borde de la cesta) hasta un poco por debajo. Así lo que se ve dentro
  /// de la cesta cuenta como atrapado aunque llegues justo a tiempo.
  static const catchTop = basketY - 0.08;
  static const catchBottom = basketY + 0.05;

  /// Radio de los objetos que caen.
  static const itemRadius = 0.04;

  /// Cada cuántos niveles se recupera una vida (si falta alguna).
  static const lifeEvery = 3;

  final Random _random;
  final List<FallingItem> items = [];
  double basketX = 0.5;
  double _target = 0.5;
  int score = 0;
  int lives = startLives;
  int level = 1;
  int shields = 0;
  int starsCaught = 0;
  int starsMissed = 0;
  int trapsHit = 0;

  /// Estrellas seguidas sin perder ninguna ni caer en trampas dañinas.
  int combo = 0;
  int maxCombo = 0;

  final BasketSkin skin;
  Duration elapsed = Duration.zero;
  double _spawnIn = 0.4;
  int _nextId = 0;

  /// Efectos activos y los segundos que les quedan.
  final Map<GameEffect, double> effects = {};

  StarCatchGame({Random? random, this.skin = BasketSkin.basket})
      : _random = random ?? Random() {
    if (skin.startShield) shields = 1;
    if (skin.startMagnet) _addEffect(GameEffect.magnet);
  }

  /// Multiplicador de puntos por combo: x2 con 8 seguidas, x3 con 16… (máx. x5).
  int get multiplier => min(1 + combo ~/ comboStep, 5);

  static const comboStep = 8;

  bool get over => lives <= 0;

  bool has(GameEffect e) => (effects[e] ?? 0) > 0;

  /// Puntos con los que se llega a [level]: 0, 10, 30, 60, 100, 150…
  static int pointsForLevel(int level) => 5 * level * (level - 1);

  /// Nivel que corresponde a [score].
  static int levelForScore(int score) {
    var level = 1;
    while (pointsForLevel(level + 1) <= score) {
      level++;
    }
    return level;
  }

  /// Puntos que faltan para el siguiente nivel.
  int get pointsToNext => pointsForLevel(level + 1) - score;

  /// Pantallas por segundo que cae un objeto: cada nivel, bastante más.
  double get fallSpeed => min(0.45 + 0.13 * (level - 1), 1.6);

  /// Segundos entre un objeto y el siguiente.
  double get spawnEvery => max(0.7 - 0.07 * (level - 1), 0.22);

  /// Media anchura de la cesta: se achica con los niveles y con el hongo.
  double get halfWidth =>
      max(basketHalfWidth - 0.004 * (level - 1), 0.085) *
      skin.widthFactor *
      (has(GameEffect.shrunk) ? 0.6 : 1);

  /// Pantallas por segundo que se mueve la cesta (el hielo la frena).
  double get basketSpeed =>
      (1.3 + 0.06 * (level - 1)) *
      skin.speedFactor *
      (has(GameEffect.frozen) ? 0.3 : 1);

  /// Desde el nivel 3 caen en zigzag, cada vez más abierto.
  double get wobble => level < 3 ? 0 : min(0.04 * (level - 2), 0.16);

  /// Desde el nivel 5 cada una cae a su velocidad.
  double get speedSpread => level < 5 ? 0 : min(0.15 * (level - 4), 0.6);

  /// Desde el nivel 7 a veces caen de a dos.
  double get pairChance => level < 7 ? 0 : min(0.1 * (level - 6), 0.4);

  /// Peso de cada cosa que puede caer en el nivel actual.
  Map<FallingKind, double> get weights => {
        FallingKind.star: 60,
        FallingKind.bigStar: 8,
        FallingKind.cloud: min(10 + 3.0 * (level - 1), 26),
        if (level >= 2) FallingKind.bomb: min(5 + 2.0 * (level - 2), 14),
        if (level >= 2) FallingKind.magnet: 2.5,
        if (level >= 3) FallingKind.ice: 5,
        if (level >= 3) FallingKind.heart: 2,
        if (level >= 4) FallingKind.swirl: 5,
        if (level >= 4) FallingKind.shield: 2,
        if (level >= 5) FallingKind.mushroom: 5,
        if (level >= 6) FallingKind.fake: min(5 + 2.0 * (level - 6), 13),
      };

  /// Probabilidad de que caiga algo que quita una vida.
  double get cloudChance {
    final w = weights;
    final total = w.values.fold<double>(0, (a, b) => a + b);
    final bad = w.entries
        .where((e) => e.key.hurts)
        .fold<double>(0, (a, e) => a + e.value);
    return bad / total;
  }

  /// Lo nuevo de cada nivel (para el cartel), o `null`.
  static String? challengeFor(int level) => switch (level) {
        2 => '¡Cuidado con las 💣! Atrapa los 🧲',
        3 => 'Zigzag y 🧊 hielo que congela la cesta',
        4 => '🌀 Remolinos: invierten los controles',
        5 => '🍄 Hongos que encogen la cesta',
        6 => '💀 ¡Estrellas falsas! Mira bien',
        7 => '¡Lluvia: a veces caen de a dos!',
        _ => null,
      };

  /// Pone la cesta en [x] al instante.
  void moveTo(double x) {
    basketX = x.clamp(halfWidth, 1 - halfWidth).toDouble();
    _target = basketX;
  }

  void nudge(double dx) => moveTo(basketX + dx);

  /// La cesta irá hacia [x] (el ratón). Con el remolino, al revés.
  void aimAt(double x) => _target = has(GameEffect.inverted) ? 1 - x : x;

  /// Flechas: -1 izquierda, 1 derecha, 0 parar.
  void steer(int direction) {
    if (direction == 0) {
      _target = basketX;
      return;
    }
    final d = has(GameEffect.inverted) ? -direction : direction;
    _target = d > 0 ? 1 : 0;
  }

  FallingKind _randomKind() {
    final w = weights;
    var r = _random.nextDouble() * w.values.fold<double>(0, (a, b) => a + b);
    for (final e in w.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return FallingKind.star;
  }

  void _spawn() {
    final spread = speedSpread;
    final kind = _randomKind();
    items.add(FallingItem(
      _nextId++,
      kind,
      itemRadius + _random.nextDouble() * (1 - 2 * itemRadius),
      -itemRadius,
      speed: kind.speed *
          (spread == 0
              ? 1
              : 1 - spread / 2 + _random.nextDouble() * spread * 1.5),
      wobble: wobble == 0 ? 0 : wobble * (0.5 + _random.nextDouble() * 0.5),
      phase: _random.nextDouble() * 2 * pi,
    ));
  }

  bool _inBasket(FallingItem item) =>
      item.y >= catchTop &&
      item.y <= catchBottom &&
      (item.x - basketX).abs() <= halfWidth + itemRadius;

  /// Quita una vida, salvo que haya escudo. Devuelve el evento.
  CatchEvent _hurt(FallingItem item) {
    if (shields > 0) {
      shields--;
      return CatchEvent(item.kind, item.x, label: '🛡️ ¡Salvado!');
    }
    lives--;
    combo = 0;
    return CatchEvent(item.kind, item.x, lostLife: true, label: '💔');
  }

  void _addEffect(GameEffect e) {
    final trap = e != GameEffect.magnet;
    effects[e] =
        e.duration.inMilliseconds / 1000 * (trap ? skin.trapFactor : 1);
  }

  CatchEvent _caught(FallingItem item) {
    final kind = item.kind;
    if (kind.isStar) {
      combo++;
      maxCombo = max(maxCombo, combo);
      final base =
          kind.points + (kind == FallingKind.bigStar ? skin.bigStarBonus : 0);
      final points = base * multiplier;
      score += points;
      starsCaught++;
      // Al subir el multiplicador, se celebra.
      final label = combo % comboStep == 0 && multiplier > 1
          ? '🔥 ¡Combo x$multiplier!'
          : '+$points';
      return CatchEvent(kind, item.x, label: label);
    }
    if (kind.hurts) {
      trapsHit++;
      return _hurt(item);
    }
    switch (kind) {
      case FallingKind.ice:
        trapsHit++;
        _addEffect(GameEffect.frozen);
        return CatchEvent(kind, item.x, label: '🧊 ¡Congelada!');
      case FallingKind.swirl:
        trapsHit++;
        _addEffect(GameEffect.inverted);
        _target = 1 - _target;
        return CatchEvent(kind, item.x, label: '🌀 ¡Al revés!');
      case FallingKind.mushroom:
        trapsHit++;
        _addEffect(GameEffect.shrunk);
        return CatchEvent(kind, item.x, label: '🍄 ¡Mini cesta!');
      case FallingKind.magnet:
        _addEffect(GameEffect.magnet);
        return CatchEvent(kind, item.x, label: '🧲 ¡Imán!');
      case FallingKind.shield:
        shields = min(shields + 1, 2);
        return CatchEvent(kind, item.x, label: '🛡️ ¡Escudo!');
      case FallingKind.heart:
        if (lives < startLives) {
          lives++;
          return CatchEvent(kind, item.x, label: '+❤️');
        }
        score += 5;
        return CatchEvent(kind, item.x, label: '+5');
      default:
        return CatchEvent(kind, item.x);
    }
  }

  /// Avanza el juego [dt]. Devuelve lo atrapado y lo perdido.
  List<CatchEvent> update(Duration dt) {
    if (over) return const [];
    final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
    elapsed += dt;

    // Efectos que se acaban.
    for (final e in effects.keys.toList()) {
      final left = effects[e]! - seconds;
      if (left <= 0) {
        effects.remove(e);
        if (e == GameEffect.inverted) _target = basketX;
      } else {
        effects[e] = left;
      }
    }

    // La cesta va hacia donde apuntas, con su velocidad.
    final goal = _target.clamp(halfWidth, 1 - halfWidth);
    final maxStep = basketSpeed * seconds;
    basketX += (goal - basketX).clamp(-maxStep, maxStep);
    basketX = basketX.clamp(halfWidth, 1 - halfWidth).toDouble();

    _spawnIn -= seconds;
    while (_spawnIn <= 0) {
      _spawn();
      if (_random.nextDouble() < pairChance) _spawn();
      _spawnIn += spawnEvery;
    }

    final magnet = has(GameEffect.magnet);
    final events = <CatchEvent>[];
    items.removeWhere((item) {
      final before = item.y;
      item.y += fallSpeed * item.speed * seconds;
      if (item.passed) return item.y > 1 + itemRadius;
      // El imán atrae las estrellas cercanas hacia la cesta.
      if (magnet && item.kind.isStar && item.y > 0.3) {
        final dx = basketX - item.baseX;
        if (dx.abs() < 0.35) {
          item.baseX += dx.clamp(-0.8 * seconds, 0.8 * seconds);
        }
      }
      // Comprueba también la mitad del paso: a mucha velocidad un objeto
      // podría saltarse la zona de la cesta en un solo paso.
      if (_inBasket(item) || _inBasket(item._at((before + item.y) / 2))) {
        events.add(_caught(item));
        return true;
      }
      if (item.y > catchBottom) {
        item.passed = true;
        if (item.kind.isStar) {
          starsMissed++;
          events.add(_hurt(item));
        }
      }
      return false;
    });
    if (over) {
      lives = 0;
      return events;
    }

    final newLevel = levelForScore(score);
    while (level < newLevel) {
      level++;
      if (level % lifeEvery == 1 && lives < startLives) lives++;
    }
    return events;
  }
}

// ---------------------------------------------------------------------------
// Premio y récord

/// XP máxima de una partida.
const maxGameXp = 15;

/// XP de una partida: 1 por cada 3 puntos, hasta [maxGameXp].
int xpForScore(int score) => min(score ~/ 3, maxGameXp);

/// Identifica el descanso en curso (`null` si no hay descanso).
String? currentBreakKey(WorkdayView view) {
  final timer = view.timer;
  final phase = view.status?.phase;
  if (timer == null || phase == null || !phase.kind.isBreak) return null;
  if (view.status?.state != WorkdayRunState.running) return null;
  return '${timer.id}#${phase.index}';
}

/// `true` si hay un bloque de enfoque en marcha (ahí no se juega).
bool focusRunning(WorkdayView view) {
  final s = view.status;
  return s != null &&
      s.state == WorkdayRunState.running &&
      s.phase?.kind == SessionPhase.focus;
}

/// Lo que importa de una partida para las medallas.
class GameRun {
  final int level;
  final int maxCombo;
  final int stars;
  final int seconds;
  const GameRun(
      {this.level = 1, this.maxCombo = 0, this.stars = 0, this.seconds = 0});

  factory GameRun.of(StarCatchGame g) => GameRun(
      level: g.level,
      maxCombo: g.maxCombo,
      stars: g.starsCaught,
      seconds: g.elapsed.inSeconds);
}

/// Récords de todas las partidas.
class GameStats {
  final int bestLevel;
  final int bestCombo;
  final int totalStars;
  final int longestSeconds;
  final int games;
  const GameStats(
      {this.bestLevel = 0,
      this.bestCombo = 0,
      this.totalStars = 0,
      this.longestSeconds = 0,
      this.games = 0});
}

/// Meta del juego: al cumplirla, desbloquea una cesta.
class GameMedal {
  final String id;
  final String emoji;
  final String title;
  final String description;
  final int goal;
  final int Function(GameStats s) _value;
  final BasketSkin reward;

  const GameMedal._(this.id, this.emoji, this.title, this.description,
      this.goal, this._value, this.reward);

  int progress(GameStats s) => min(_value(s), goal);
  bool done(GameStats s) => _value(s) >= goal;
}

final gameMedals = <GameMedal>[
  GameMedal._('level3', '🚀', 'Despegue', 'Llega al nivel 3.', 3,
      (s) => s.bestLevel, BasketSkin.bucket),
  GameMedal._(
      'combo16',
      '🔥',
      'Racha de fuego',
      'Atrapa 16 estrellas seguidas (combo x3).',
      16,
      (s) => s.bestCombo,
      BasketSkin.hat),
  GameMedal._(
      'stars300',
      '✨',
      'Coleccionista',
      'Atrapa 300 estrellas entre todas tus partidas.',
      300,
      (s) => s.totalStars,
      BasketSkin.honey),
  GameMedal._('level6', '🪐', 'Explorador', 'Llega al nivel 6.', 6,
      (s) => s.bestLevel, BasketSkin.ufo),
  GameMedal._(
      'survive180',
      '⏱️',
      'Superviviente',
      'Aguanta 3 minutos en una partida.',
      180,
      (s) => s.longestSeconds,
      BasketSkin.rainbow),
  GameMedal._('level8', '👑', 'Leyenda estelar', 'Llega al nivel 8.', 8,
      (s) => s.bestLevel, BasketSkin.crown),
];

/// Resultado de una partida ya guardada.
class GameResult {
  final int score;
  final int xp;
  final bool newBest;

  /// Por qué no dio XP (o `null` si sí dio).
  final String? noXpReason;

  /// Medallas conseguidas en esta partida.
  final List<GameMedal> newMedals;

  const GameResult(this.score,
      {required this.xp,
      required this.newBest,
      this.noXpReason,
      this.newMedals = const []});
}

/// Récord y XP ganada jugando. Una partida premiada por descanso: así el
/// juego acompaña al descanso sin convertirse en la forma de subir de nivel.
class GameStore extends ChangeNotifier {
  static const _bestKey = 'game.stars.best';
  static const _xpKey = 'game.stars.xp';
  static const _lastBreakKey = 'game.stars.lastBreak';
  static const _skinKey = 'game.stars.skin';
  static const _levelKey = 'game.stars.bestLevel';
  static const _comboKey = 'game.stars.bestCombo';
  static const _totalKey = 'game.stars.totalStars';
  static const _longestKey = 'game.stars.longest';
  static const _gamesKey = 'game.stars.games';

  final SharedPreferences? _prefs;
  int _best;
  int _bonusXp;
  String? _lastBreak;
  BasketSkin _skin;
  GameStats _stats;

  GameStore([this._prefs])
      : _best = _prefs?.getInt(_bestKey) ?? 0,
        _bonusXp = _prefs?.getInt(_xpKey) ?? 0,
        _lastBreak = _prefs?.getString(_lastBreakKey),
        _skin = BasketSkin.byName(_prefs?.getString(_skinKey)),
        _stats = GameStats(
          bestLevel: _prefs?.getInt(_levelKey) ?? 0,
          bestCombo: _prefs?.getInt(_comboKey) ?? 0,
          totalStars: _prefs?.getInt(_totalKey) ?? 0,
          longestSeconds: _prefs?.getInt(_longestKey) ?? 0,
          games: _prefs?.getInt(_gamesKey) ?? 0,
        );

  int get best => _best;
  int get bonusXp => _bonusXp;
  GameStats get stats => _stats;

  /// Cesta elegida (si sigue desbloqueada).
  BasketSkin get skin => isUnlocked(_skin) ? _skin : BasketSkin.basket;

  bool isUnlocked(BasketSkin skin) =>
      skin == BasketSkin.basket ||
      gameMedals.any((m) => m.reward == skin && m.done(_stats));

  int get medalsDone => gameMedals.where((m) => m.done(_stats)).length;

  Future<void> selectSkin(BasketSkin skin) async {
    if (!isUnlocked(skin)) return;
    _skin = skin;
    await _prefs?.setString(_skinKey, skin.name);
    notifyListeners();
  }

  Future<List<GameMedal>> _record(GameRun run) async {
    final before = _stats;
    _stats = GameStats(
      bestLevel: max(before.bestLevel, run.level),
      bestCombo: max(before.bestCombo, run.maxCombo),
      totalStars: before.totalStars + run.stars,
      longestSeconds: max(before.longestSeconds, run.seconds),
      games: before.games + 1,
    );
    await _prefs?.setInt(_levelKey, _stats.bestLevel);
    await _prefs?.setInt(_comboKey, _stats.bestCombo);
    await _prefs?.setInt(_totalKey, _stats.totalStars);
    await _prefs?.setInt(_longestKey, _stats.longestSeconds);
    await _prefs?.setInt(_gamesKey, _stats.games);
    return [
      for (final m in gameMedals)
        if (m.done(_stats) && !m.done(before)) m
    ];
  }

  /// `true` si en el descanso [breakKey] aún no se ganó XP jugando.
  bool canEarnIn(String? breakKey) =>
      breakKey != null && breakKey != _lastBreak;

  /// Guarda una partida que acabó con [score] durante [breakKey].
  Future<GameResult> finish(int score,
      {String? breakKey, GameRun run = const GameRun()}) async {
    final medals = await _record(run);
    final newBest = score > _best;
    if (newBest) {
      _best = score;
      await _prefs?.setInt(_bestKey, score);
    }
    var xp = 0;
    String? reason;
    if (breakKey == null) {
      reason = 'Fuera de los descansos se juega solo por el récord.';
    } else if (!canEarnIn(breakKey)) {
      reason = 'La XP de este descanso ya la ganaste.';
    } else {
      xp = xpForScore(score);
      _lastBreak = breakKey;
      _bonusXp += xp;
      await _prefs?.setString(_lastBreakKey, breakKey);
      await _prefs?.setInt(_xpKey, _bonusXp);
    }
    notifyListeners();
    return GameResult(score,
        xp: xp, newBest: newBest, noXpReason: reason, newMedals: medals);
  }
}

final gameStoreProvider = ChangeNotifierProvider<GameStore>((_) => GameStore());

/// XP ganada jugando (se suma a la del historial).
final gameXpProvider =
    Provider<int>((ref) => ref.watch(gameStoreProvider).bonusXp);

/// Lo que dice la mascota al terminar.
String gameOverMessage(GameResult r) {
  final buffer = StringBuffer(r.score == 0
      ? '¡Uy, ninguna estrella! La próxima seguro 💪'
      : '¡${r.score} puntos!');
  if (r.newBest && r.score > 0) buffer.write(' ¡Nuevo récord! 🏆');
  if (r.xp > 0) buffer.write(' +${r.xp} XP ✨');
  return buffer.toString();
}
