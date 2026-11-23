import '../../core/i18n/language.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/desktop/sounds.dart';
import '../../application/game/star_catch.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/workday/workday_providers.dart';
import '../stats/stats_style.dart';

enum _Stage { ready, playing, over, medals }

/// Cielo de cada nivel: nombre, degradado, color del borde y de las
/// estrellitas del fondo. Pasado el último, vuelven a empezar.
class GameTheme {
  final String name;
  final Color top;
  final Color bottom;
  final Color accent;
  final Color twinkle;
  const GameTheme(this.name, this.top, this.bottom, this.accent, this.twinkle);

  static List<GameTheme> get all => [
    GameTheme(tr('Cielo de la tarde 🌤️', 'Afternoon sky 🌤️'), const Color(0xFF1B2A4A), const Color(0xFF3E5C8A),
        const Color(0xFF64B5F6), const Color(0x66FFFFFF)),
    GameTheme(tr('Atardecer 🌇', 'Sunset 🌇'), const Color(0xFF2B1B3D), const Color(0xFF8A3B5C),
        const Color(0xFFFF8A65), const Color(0x66FFE0B2)),
    GameTheme(tr('Noche 🌙', 'Night 🌙'), const Color(0xFF0B1026), const Color(0xFF1F2A5A),
        const Color(0xFF9FA8DA), const Color(0x99FFFFFF)),
    GameTheme(tr('Aurora 🌌', 'Aurora 🌌'), const Color(0xFF07202A), const Color(0xFF1F6B5A),
        const Color(0xFF4DD0A1), const Color(0x99B2FFD9)),
    GameTheme(tr('Bosque mágico 🍄', 'Magic forest 🍄'), const Color(0xFF0F1F14), const Color(0xFF2F5A2A),
        const Color(0xFFAED581), const Color(0x99F0F4C3)),
    GameTheme(tr('Nebulosa 🔮', 'Nebula 🔮'), const Color(0xFF1A0B2E), const Color(0xFF6A2C8A),
        const Color(0xFFCE93D8), const Color(0x99F8BBD0)),
    GameTheme(tr('Volcán 🌋', 'Volcano 🌋'), const Color(0xFF1F0A0A), const Color(0xFF8A2E14),
        const Color(0xFFFF7043), const Color(0x99FFCC80)),
    GameTheme(tr('Galaxia 🪐', 'Galaxy 🪐'), const Color(0xFF05030F), const Color(0xFF2A1458),
        const Color(0xFFFFD54F), const Color(0xCCFFFFFF)),
  ];

  static GameTheme forLevel(int level) => all[(level - 1) % all.length];
}

/// Panel del minijuego «Atrapa estrellas».
class StarCatchPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const StarCatchPanel({super.key, required this.onClose});

  @override
  ConsumerState<StarCatchPanel> createState() => _StarCatchPanelState();
}

class _StarCatchPanelState extends ConsumerState<StarCatchPanel>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _focus = FocusNode();
  _Stage _stage = _Stage.ready;
  StarCatchGame? _game;
  GameResult? _result;
  String? _breakKey;
  Duration _last = Duration.zero;

  /// Flechas pulsadas: -1 izquierda, 1 derecha.
  int _direction = 0;

  /// Destellos de lo atrapado: posición x y cuándo pasó.
  final _flashes = <(CatchEvent, Duration)>[];

  /// Aviso de nivel nuevo: texto y cuándo apareció.
  (String, Duration)? _banner;

  /// Reto de hoy y si ya se avisó que se cumplió en esta partida.
  DailyChallenge? _daily;
  bool _dailyAnnounced = false;

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start([GameMode mode = GameMode.classic]) {
    _breakKey = currentBreakKey(ref.read(workdayControllerProvider));
    setState(() {
      final store = ref.read(gameStoreProvider);
      _game = StarCatchGame(skin: store.skin, mode: mode);
      _daily = store.dailyDone ? null : store.daily;
      _dailyAnnounced = false;
      _result = null;
      _flashes.clear();
      _banner = (tr('Nivel 1 · ${GameTheme.forLevel(1).name}', 'Level 1 · ${GameTheme.forLevel(1).name}'), Duration.zero);
      _stage = _Stage.playing;
    });
    _last = Duration.zero;
    _ticker
      ..stop()
      ..start();
    _focus.requestFocus();
  }

  void _onTick(Duration now) {
    final game = _game;
    if (game == null) return;
    // Un salto grande (ventana oculta, depuración) no adelanta el juego.
    var dt = now - _last;
    if (dt > const Duration(milliseconds: 100)) {
      dt = const Duration(milliseconds: 100);
    }
    _last = now;
    if (_direction != 0) game.steer(_direction);
    final levelBefore = game.level;
    final livesBefore = game.lives;
    for (final e in game.update(dt)) {
      _flashes.add((e, game.elapsed));
    }
    if (game.level > levelBefore) {
      final life = game.lives > livesBefore ? ' · +1 ❤️' : '';
      final challenge =
          StarCatchGame.challengeFor(game.level) ?? tr('Más rápido ⚡', 'Faster ⚡');
      _banner = (
        tr('¡Nivel ${game.level}! ${GameTheme.forLevel(game.level).name}$life · $challenge', 'Level ${game.level}! ${GameTheme.forLevel(game.level).name}$life · $challenge'),
        game.elapsed
      );
    }
    if (!_dailyAnnounced && _daily != null && _daily!.met(GameRun.of(game))) {
      _dailyAnnounced = true;
      _banner = (tr('🎯 ¡Reto del día cumplido! Sigue jugando', '🎯 Daily challenge done! Keep playing'), game.elapsed);
    }
    if (_banner != null &&
        game.elapsed - _banner!.$2 > const Duration(milliseconds: 3500)) {
      _banner = null;
    }
    _flashes.removeWhere(
        (f) => game.elapsed - f.$2 > const Duration(milliseconds: 500));
    if (game.over) {
      _ticker.stop();
      _finish(game.score, GameRun.of(game));
    }
    setState(() {});
  }

  Future<void> _finish(int score, GameRun run) async {
    final result = await ref
        .read(gameStoreProvider)
        .finish(score, breakKey: _breakKey, run: run, mode: _game!.mode);
    if (ref.read(soundSettingsProvider).enabled &&
        (result.newBest || result.xp > 0 || result.newMedals.isNotEmpty)) {
      ref.read(soundPlayerProvider).play(PetSound.goal);
    }
    if (!mounted) return;
    setState(() {
      _result = result;
      _stage = _Stage.over;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final dir = key == LogicalKeyboardKey.arrowLeft
        ? -1
        : key == LogicalKeyboardKey.arrowRight
            ? 1
            : 0;
    if (dir == 0) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _direction = dir;
    } else if (event is KeyUpEvent && _direction == dir) {
      _direction = 0;
      _game?.steer(0);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(gameStoreProvider);
    final theme = _game == null || _stage == _Stage.ready
        ? null
        : GameTheme.forLevel(_game!.level);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: StatsStyle.panel().copyWith(
        border: Border.all(
            color: (theme?.accent ?? StatsStyle.accent).withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: _stage == _Stage.playing
                  ? Text(tr('Nivel ${_game!.level}', 'Level ${_game!.level}'),
                      key: const ValueKey('game-level'),
                      style: TextStyle(
                          color: theme!.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700))
                  : Row(children: [
                      const Icon(Icons.star_outline_rounded,
                          size: 18, color: StatsStyle.accentLight),
                      const SizedBox(width: 6),
                      Flexible(
                          child: Text(tr('Atrapa estrellas', 'Catch the stars'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: StatsStyle.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600))),
                    ]),
            ),
            if (_stage == _Stage.playing) _hud(_game!),
            IconButton(
              key: const ValueKey('game-close'),
              tooltip: tr('Cerrar', 'Close'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: switch (_stage) {
                _Stage.ready => _intro(store),
                _Stage.playing => _field(_game!),
                _Stage.over => _summary(store),
                _Stage.medals => _medals(store),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _hud(StarCatchGame game) => Text(
        '${game.mode == GameMode.timeAttack ? '⏱ ${game.timeLeft.inSeconds} s ' : '${'❤️' * game.lives}${'🖤' * (StarCatchGame.startLives - game.lives)}'}'
        '${'🛡️' * game.shields} ${game.score} pts'
        '${game.multiplier > 1 ? ' x${game.multiplier}🔥' : ''}',
        key: const ValueKey('game-hud'),
        style: const TextStyle(
            color: StatsStyle.textSecondary,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()]),
      );

  static const _body =
      TextStyle(color: StatsStyle.textSecondary, fontSize: 12, height: 1.35);

  Widget _intro(GameStore store) {
    final view = ref.watch(workdayControllerProvider);
    final name = ref.watch(petNameProvider);
    if (focusRunning(view)) {
      return _centered([
        const Text('🎯', style: TextStyle(fontSize: 32)),
        const SizedBox(height: 8),
        Text(
            tr('Ahora toca enfocarse. $name te espera en el descanso para jugar 😉', 'Time to focus now. $name will wait for you on the break to play 😉'),
            key: const ValueKey('game-focus'),
            textAlign: TextAlign.center,
            style: _body),
      ]);
    }
    final key = currentBreakKey(view);
    final xpLine = key == null
        ? tr('En los descansos, cada partida da hasta $maxGameXp XP (una por descanso). Ahora juegas por el récord.', "On breaks, each game gives up to $maxGameXp XP (one per break). Now you're playing for the record.")
        : store.canEarnIn(key)
            ? tr('☕ Estás en un descanso: esta partida da hasta $maxGameXp XP.', "☕ You're on a break: this game gives up to $maxGameXp XP.")
            : tr('Ya ganaste la XP de este descanso; ahora juegas por el récord.', "You already earned this break's XP; now you're playing for the record.");
    return _centered([
      const Text('⭐ 🌟 💣 🌀', style: TextStyle(fontSize: 26)),
      const SizedBox(height: 8),
      Text(
          tr('Lleva la cesta con el ratón o las flechas ← → (tiene su propia velocidad: ¡anticípate!). ⭐ suma 1 y 🌟 suma 3; atrápalas seguidas para multiplicar 🔥. Tienes 3 vidas: pierdes una si se te escapa una estrella o si atrapas una trampa. Con los puntos subes de nivel: todo va más rápido y aparecen trampas nuevas.', 'Move the basket with the mouse or the ← → arrows (it has its own speed: think ahead!). ⭐ adds 1 and 🌟 adds 3; catch them in a row to multiply 🔥. You have 3 lives: you lose one if a star gets away or if you catch a trap. Points level you up: everything gets faster and new traps appear.'),
          textAlign: TextAlign.center,
          style: _body),
      const SizedBox(height: 6),
      Text(
          tr('Trampas: ⛈️ 💣 💀 quitan vida · 🧊 congela · 🌀 invierte · 🍄 encoge\nAyudas: 💖 vida · 🧲 imán · 🛡️ escudo', 'Traps: ⛈️ 💣 💀 take a life · 🧊 freezes · 🌀 reverses · 🍄 shrinks\nHelps: 💖 life · 🧲 magnet · 🛡️ shield'),
          key: const ValueKey('game-legend'),
          textAlign: TextAlign.center,
          style: _body),
      const SizedBox(height: 6),
      Text(xpLine,
          key: const ValueKey('game-xp-info'),
          textAlign: TextAlign.center,
          style: _body.copyWith(color: StatsStyle.textPrimary)),
      if (store.best > 0 || store.bestTimeAttack > 0) ...[
        const SizedBox(height: 6),
        Text(
            tr('Récord: ${store.best}', 'Record: ${store.best}') +
                (store.bestTimeAttack > 0
                    ? tr(' · contrarreloj: ${store.bestTimeAttack}',
                        ' · time attack: ${store.bestTimeAttack}')
                    : ''),
            style: _body),
      ],
      const SizedBox(height: 8),
      _dailyCard(store),
      const SizedBox(height: 6),
      Text(
          tr('Cesta: ${store.skin.emoji} ${store.skin.label} — ${store.skin.perk}', 'Basket: ${store.skin.emoji} ${store.skin.label} — ${store.skin.perk}'),
          key: const ValueKey('game-skin'),
          textAlign: TextAlign.center,
          style: _body),
      const SizedBox(height: 10),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        FilledButton(
          key: const ValueKey('game-start'),
          onPressed: _start,
          child: Text(tr('¡Jugar!', 'Play!')),
        ),
        OutlinedButton.icon(
          key: const ValueKey('game-start-time'),
          onPressed: () => _start(GameMode.timeAttack),
          icon: const Icon(Icons.timer_outlined, size: 16),
          label: Text(tr('Contrarreloj 60 s', 'Time attack 60 s')),
        ),
        OutlinedButton(
          key: const ValueKey('game-medals'),
          onPressed: () => setState(() => _stage = _Stage.medals),
          child: Text('🏅 ${store.medalsDone}/${gameMedals.length}'),
        ),
      ]),
    ]);
  }

  Widget _summary(GameStore store) {
    final r = _result!;
    return _centered([
      Text(r.newBest && r.score > 0 ? '🏆' : '🌟',
          style: const TextStyle(fontSize: 32)),
      const SizedBox(height: 8),
      Text(gameOverMessage(r),
          key: const ValueKey('game-result'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: StatsStyle.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(
          _game!.mode == GameMode.timeAttack
              ? tr('Contrarreloj · nivel ${_game!.level} · ${_game!.starsCaught} estrellas · récord ${store.bestTimeAttack}', 'Time attack · level ${_game!.level} · ${_game!.starsCaught} stars · record ${store.bestTimeAttack}')
              : tr('Nivel ${_game!.level} · ${_game!.starsCaught} estrellas · aguantaste ${_game!.elapsed.inSeconds} s · récord ${store.best}', 'Level ${_game!.level} · ${_game!.starsCaught} stars · you lasted ${_game!.elapsed.inSeconds} s · record ${store.best}'),
          textAlign: TextAlign.center,
          style: _body),
      if (r.dailyXp > 0) ...[
        const SizedBox(height: 6),
        Text(
            tr('🎯 ¡Reto del día cumplido! +${r.dailyXp} XP', '🎯 Daily challenge done! +${r.dailyXp} XP') +
                (r.dailyStreak > 1
                    ? tr(' · racha de ${r.dailyStreak} días 🔥',
                        ' · ${r.dailyStreak}-day streak 🔥')
                    : ''),
            key: const ValueKey('game-daily-done'),
            textAlign: TextAlign.center,
            style: _body.copyWith(
                color: const Color(0xFF80CBC4), fontWeight: FontWeight.w600)),
      ] else if (!store.dailyDone && _daily != null) ...[
        const SizedBox(height: 6),
        Text(
            tr('🎯 Reto de hoy: ${_daily!.text} (${_daily!.progress(GameRun.of(_game!))}/${_daily!.goal})', "🎯 Today's challenge: ${_daily!.text} (${_daily!.progress(GameRun.of(_game!))}/${_daily!.goal})"),
            textAlign: TextAlign.center,
            style: _body),
      ],
      for (final m in r.newMedals) ...[
        const SizedBox(height: 6),
        Text(
            tr('🏅 ¡Medalla «${m.title}»! Nueva cesta: ${m.reward.emoji} ${m.reward.label} (${m.reward.perk})', '🏅 “${m.title}” medal! New basket: ${m.reward.emoji} ${m.reward.label} (${m.reward.perk})'),
            key: ValueKey('game-new-medal-${m.id}'),
            textAlign: TextAlign.center,
            style: _body.copyWith(
                color: const Color(0xFFFFD54F), fontWeight: FontWeight.w600)),
      ],
      if (r.newMedals.isEmpty) _nextGoal(store),
      if (r.noXpReason != null) ...[
        const SizedBox(height: 4),
        Text(r.noXpReason!, textAlign: TextAlign.center, style: _body),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        FilledButton(
          key: const ValueKey('game-again'),
          onPressed: () => _start(_game?.mode ?? GameMode.classic),
          child: Text(tr('Otra vez', 'Again')),
        ),
        OutlinedButton(
          onPressed: () => setState(() => _stage = _Stage.medals),
          child: Text('🏅 ${store.medalsDone}/${gameMedals.length}'),
        ),
      ]),
    ]);
  }

  /// Tarjeta del reto de hoy (o cumplido, con la racha).
  Widget _dailyCard(GameStore store) {
    final done = store.dailyDone;
    final streak = store.streak;
    final text = done
        ? '${tr('🎯 Reto de hoy cumplido ✅', "🎯 Today's challenge done ✅")}${streak > 1
                ? tr(' · racha de $streak días 🔥', ' · $streak-day streak 🔥')
                : ''}\n${tr('Vuelve mañana por otro.', 'Come back tomorrow for another.')}'
        : tr('🎯 Reto de hoy: ${store.daily.text}\n+${dailyXp(streak + 1)} XP', "🎯 Today's challenge: ${store.daily.text}\n+${dailyXp(streak + 1)} XP") +
            (streak > 0
                ? tr(' · racha de $streak 🔥 (no la pierdas)',
                    " · $streak streak 🔥 (don't lose it)")
                : '');
    return Container(
      key: const ValueKey('game-daily'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: StatsStyle.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: done ? const Color(0xFF80CBC4) : const Color(0xFFFFD54F)),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: _body.copyWith(color: StatsStyle.textPrimary)),
    );
  }

  /// La medalla más cercana a conseguirse, para tener un motivo para la
  /// siguiente partida.
  Widget _nextGoal(GameStore store) {
    final pending = [
      for (final m in gameMedals)
        if (!m.done(store.stats)) m
    ];
    if (pending.isEmpty) return const SizedBox.shrink();
    pending.sort((a, b) => (b.progress(store.stats) / b.goal)
        .compareTo(a.progress(store.stats) / a.goal));
    final m = pending.first;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
          tr('Próxima medalla: ${m.emoji} ${m.title} (${m.progress(store.stats)}/${m.goal}) → ${m.reward.emoji}', 'Next medal: ${m.emoji} ${m.title} (${m.progress(store.stats)}/${m.goal}) → ${m.reward.emoji}'),
          key: const ValueKey('game-next-goal'),
          textAlign: TextAlign.center,
          style: _body.copyWith(color: StatsStyle.textPrimary)),
    );
  }

  /// Medallas con su progreso y las cestas para elegir.
  Widget _medals(GameStore store) {
    final stats = store.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(tr('Cestas (toca una para usarla)', 'Baskets (tap one to use it)'),
                  style: const TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final skin in BasketSkin.values) _skinChip(store, skin),
              ]),
              const SizedBox(height: 4),
              Text('${store.skin.emoji} ${store.skin.perk}', style: _body),
              const SizedBox(height: 10),
              Text(tr('Medallas', 'Medals'),
                  style: const TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              for (final m in gameMedals)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Text(m.done(stats) ? m.emoji : '🔒',
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m.title} → ${m.reward.emoji}',
                              style: TextStyle(
                                  color: m.done(stats)
                                      ? const Color(0xFFFFD54F)
                                      : StatsStyle.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text(m.description,
                              style: const TextStyle(
                                  color: StatsStyle.textSecondary,
                                  fontSize: 11)),
                          const SizedBox(height: 2),
                          LinearProgressIndicator(
                            value: m.progress(stats) / m.goal,
                            minHeight: 3,
                            backgroundColor: StatsStyle.grid,
                            color: m.done(stats)
                                ? const Color(0xFFFFD54F)
                                : StatsStyle.accent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${m.progress(stats)}/${m.goal}',
                        style: const TextStyle(
                            color: StatsStyle.textMuted, fontSize: 10)),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton(
            key: const ValueKey('game-start-from-medals'),
            onPressed: _start,
            child: Text(tr('¡Jugar!', 'Play!')),
          ),
          TextButton(
            onPressed: () => setState(() => _stage = _Stage.ready),
            child: Text(tr('Volver', 'Back')),
          ),
        ]),
      ],
    );
  }

  Widget _skinChip(GameStore store, BasketSkin skin) {
    final unlocked = store.isUnlocked(skin);
    final selected = store.skin == skin;
    return Tooltip(
      message: unlocked
          ? '${skin.label}: ${skin.perk}'
          : tr('${skin.label}: se desbloquea con una medalla', '${skin.label}: unlocks with a medal'),
      child: InkWell(
        key: ValueKey('skin-${skin.name}'),
        onTap: unlocked ? () => store.selectSkin(skin) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? StatsStyle.accent : StatsStyle.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? const Color(0xFFFFD54F) : StatsStyle.grid),
          ),
          child: Opacity(
            opacity: unlocked ? 1 : 0.35,
            child: Text(unlocked ? skin.emoji : '🔒',
                style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }

  Widget _centered(List<Widget> children) => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

  Widget _field(StarCatchGame game) {
    final theme = GameTheme.forLevel(game.level);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        void follow(Offset p) => game.aimAt(p.dx / w);
        return MouseRegion(
          cursor: SystemMouseCursors.none,
          onHover: (e) => follow(e.localPosition),
          child: GestureDetector(
            onPanUpdate: (d) => follow(d.localPosition),
            onTapDown: (d) => follow(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                key: const ValueKey('game-field'),
                duration: const Duration(milliseconds: 800),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.top, theme.bottom],
                  ),
                ),
                child: Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned.fill(
                    child: CustomPaint(
                        painter: _Twinkles(theme.twinkle, game.level,
                            game.elapsed.inMilliseconds / 1000)),
                  ),
                  for (final item in game.items)
                    _emoji(item.emoji, item.x * w, item.y * h,
                        size: switch (item.kind) {
                          FallingKind.bigStar || FallingKind.bomb => 22,
                          _ => 18,
                        }),
                  for (final (e, at) in _flashes)
                    _flash(e, w, h, (game.elapsed - at).inMilliseconds / 700),
                  // Franja de nivel abajo, debajo de la cesta: no tapa nada
                  // de lo que cae.
                  if (_banner != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _levelBanner(_banner!.$1, theme,
                          (game.elapsed - _banner!.$2).inMilliseconds / 3500),
                    ),
                  _basket(game, w, h),
                  Positioned(left: 6, top: 4, child: _effects(game)),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _emoji(String text, double cx, double cy, {double size = 18}) =>
      Positioned(
        left: cx - size * 0.75,
        top: cy - size * 0.75,
        width: size * 1.5,
        height: size * 1.5,
        child: Center(
            child: Text(text, style: TextStyle(fontSize: size, height: 1))),
      );

  /// "+1" o "💔" que sube y se desvanece.
  Widget _flash(CatchEvent e, double w, double h, double t) {
    final good = !e.lostLife && (e.kind.isStar || e.label.startsWith('+'));
    final left = (e.x * w - 60).clamp(0.0, max(0.0, w - 120)).toDouble();
    return Positioned(
      left: left,
      top: StarCatchGame.basketY * h - 32 - 24 * t,
      width: 120,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Text(e.label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: good
                    ? const Color(0xFFFFD54F)
                    : e.lostLife
                        ? const Color(0xFFFF8A80)
                        : const Color(0xFFE0E0E0),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(blurRadius: 3)])),
      ),
    );
  }

  /// La cesta: más pequeña con el hongo, con hielo encima si está
  /// congelada y con su escudo.
  Widget _basket(StarCatchGame game, double w, double h) {
    final size = 26 * game.halfWidth / StarCatchGame.basketHalfWidth;
    final x = game.basketX * w;
    final y = StarCatchGame.basketY * h;
    return Stack(children: [
      if (game.shields > 0)
        Positioned(
          left: x - 30,
          top: y - 26,
          width: 60,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xAA81D4FA), width: 2),
            ),
          ),
        ),
      _emoji(game.skin.emoji, x, y, size: size),
      if (game.has(GameEffect.frozen))
        _emoji('🧊', x + size * 0.6, y - 8, size: 14),
      if (game.has(GameEffect.inverted))
        _emoji('🌀', x - size * 0.6, y - 8, size: 14),
    ]);
  }

  /// Efectos activos con los segundos que les quedan.
  Widget _effects(StarCatchGame game) => Wrap(
        key: const ValueKey('game-effects'),
        spacing: 4,
        children: [
          for (final MapEntry(:key, :value) in game.effects.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${key.emoji} ${value.ceil()}s',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
        ],
      );

  /// Cartel de nivel nuevo: aparece y se desvanece.
  Widget _levelBanner(String text, GameTheme theme, double t) {
    final opacity = t < 0.15 ? t / 0.15 : (t > 0.75 ? (1 - t) / 0.25 : 1.0);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          key: const ValueKey('game-banner'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            border: Border(top: BorderSide(color: theme.accent, width: 1)),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Estrellitas de fondo que titilan; cambian de sitio con cada nivel.
class _Twinkles extends CustomPainter {
  final Color color;
  final int seed;
  final double time;
  const _Twinkles(this.color, this.seed, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final paint = Paint();
    for (var i = 0; i < 24; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.8;
      final phase = random.nextDouble() * 2 * pi;
      final glow = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 2 + phase));
      paint.color = color.withValues(alpha: color.a * glow);
      canvas.drawCircle(Offset(x, y), 0.8 + random.nextDouble(), paint);
    }
  }

  @override
  bool shouldRepaint(_Twinkles old) =>
      old.time != time || old.seed != seed || old.color != color;
}
