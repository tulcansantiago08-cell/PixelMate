import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/game/star_catch.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/game/star_catch_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const tick = Duration(milliseconds: 100);

void main() {
  group('juego', () {
    test('la cesta atrapa estrellas y las nubes quitan una vida', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      game.items.add(FallingItem(100, FallingKind.bigStar, 0.5, 0.85));
      expect(game.update(tick).single.kind, FallingKind.bigStar);
      expect(game.score, 3);
      expect(game.lives, StarCatchGame.startLives);

      game.items.add(FallingItem(101, FallingKind.cloud, 0.55, 0.85));
      final events = game.update(tick);
      expect(events.single.lostLife, isTrue);
      expect(game.score, 3);
      expect(game.lives, StarCatchGame.startLives - 1);
    });

    test('una estrella que se escapa quita una vida; una nube no', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.1);
      game.items
        ..add(FallingItem(100, FallingKind.star, 0.9, 0.9))
        ..add(FallingItem(101, FallingKind.cloud, 0.7, 0.9));
      final events = game.update(tick);
      expect(events.single.kind, FallingKind.star);
      expect(events.single.lostLife, isTrue);
      expect(game.lives, StarCatchGame.startLives - 1);
      expect(game.starsMissed, 1);
      // Sigue cayendo, pero no se cuenta dos veces.
      game.update(tick);
      expect(game.lives, StarCatchGame.startLives - 1);
    });

    test('llegar tarde con la cesta también atrapa (sin restar)', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.1);
      game.items.add(FallingItem(100, FallingKind.star, 0.6, 0.86));
      // Ya pasó el centro de la cesta, pero sigue dentro de ella.
      game.moveTo(0.6);
      expect(game.update(tick).single.lostLife, isFalse);
      expect(game.score, 1);
      expect(game.lives, StarCatchGame.startLives);
    });

    test('niveles: más rápido, más nubes y una vida cada 3 niveles', () {
      expect(StarCatchGame.levelForScore(0), 1);
      expect(StarCatchGame.levelForScore(10), 2);
      expect(StarCatchGame.levelForScore(29), 2);
      expect(StarCatchGame.levelForScore(60), 4);

      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      final speed1 = game.fallSpeed;
      final clouds1 = game.cloudChance;
      game
        ..score = 59
        ..lives = 1
        ..items.add(FallingItem(100, FallingKind.bigStar, 0.5, 0.85));
      game.update(tick);
      expect(game.level, 4);
      expect(game.lives, 2, reason: 'el nivel 4 devuelve una vida');
      expect(game.fallSpeed, greaterThan(speed1));
      expect(game.cloudChance, greaterThan(clouds1));
      expect(game.pointsToNext, 100 - 62);
    });

    test('la dificultad se nota en cada nivel', () {
      final game = StarCatchGame(random: Random(3));
      final speeds = <double>[];
      for (final level in [1, 2, 3, 5, 7, 10]) {
        game.level = level;
        speeds.add(game.fallSpeed);
      }
      expect(speeds[1] / speeds[0], greaterThan(1.25),
          reason: 'el nivel 2 ya cae bastante más rápido');
      expect(speeds.last / speeds.first, greaterThan(2.5));
      game.level = 2;
      expect(game.wobble, 0);
      expect(game.speedSpread, 0);
      game.level = 3;
      expect(game.wobble, greaterThan(0));
      game.level = 5;
      expect(game.speedSpread, greaterThan(0));
      expect(game.pairChance, 0);
      game.level = 8;
      expect(game.pairChance, greaterThan(0));
      expect(StarCatchGame.challengeFor(3), contains('igzag'));

      // En zigzag la x cambia mientras cae, y la cesta la sigue atrapando
      // donde está ahora.
      final item =
          FallingItem(1, FallingKind.star, 0.5, 0.2, wobble: 0.1, phase: 0);
      final x1 = item.x;
      item.y = 0.35;
      expect(item.x, isNot(closeTo(x1, 0.01)));
    });

    test('la cesta no se teletransporta: va hacia el ratón', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.2);
      game.aimAt(0.7);
      game.update(tick);
      expect(game.basketX, closeTo(0.2 + game.basketSpeed * 0.1, 1e-9));
      for (var i = 0; i < 20; i++) {
        game.update(tick);
      }
      expect(game.basketX, closeTo(0.7, 1e-9));
    });

    /// Atrapa [kind] con la cesta en el centro.
    CatchEvent catchOne(StarCatchGame game, FallingKind kind) {
      game.items.add(FallingItem(500, kind, game.basketX, 0.85));
      return game.update(tick).singleWhere((e) => e.kind == kind);
    }

    test('trampas: bomba, hielo, remolino y hongo', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      expect(catchOne(game, FallingKind.bomb).lostLife, isTrue);
      expect(game.lives, 2);

      final speed = game.basketSpeed;
      expect(catchOne(game, FallingKind.ice).label, contains('Congelada'));
      expect(game.basketSpeed, lessThan(speed));

      final width = game.halfWidth;
      catchOne(game, FallingKind.mushroom);
      expect(game.halfWidth, lessThan(width));

      catchOne(game, FallingKind.swirl);
      expect(game.has(GameEffect.inverted), isTrue);
      game.moveTo(0.5);
      game.aimAt(0.9); // con el remolino, va hacia el otro lado
      game.update(tick);
      expect(game.basketX, lessThan(0.5));

      // Los efectos se acaban.
      for (var i = 0; i < 70; i++) {
        game.update(tick);
        game.items.clear();
      }
      expect(game.effects, isEmpty);
      expect(game.halfWidth, width);
    });

    test('ayudas: escudo, vida e imán', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      catchOne(game, FallingKind.shield);
      expect(game.shields, 1);
      final saved = catchOne(game, FallingKind.cloud);
      expect(saved.lostLife, isFalse);
      expect(game.lives, 3);
      expect(game.shields, 0);

      catchOne(game, FallingKind.cloud);
      expect(game.lives, 2);
      expect(catchOne(game, FallingKind.heart).label, '+❤️');
      expect(game.lives, 3);
      expect(catchOne(game, FallingKind.heart).label, '+5',
          reason: 'con las vidas llenas, da puntos');

      catchOne(game, FallingKind.magnet);
      final caught = game.starsCaught;
      // Lejos de la cesta (que no se mueve): sin imán se escaparía.
      game.items.add(FallingItem(600, FallingKind.star, 0.78, 0.4));
      for (var i = 0; i < 15; i++) {
        game.update(tick);
      }
      expect(game.starsCaught, caught + 1,
          reason: 'el imán la llevó a la cesta');
      expect(game.lives, 3);
    });

    test('la estrella falsa se delata y quita una vida', () {
      final fake = FallingItem(1, FallingKind.fake, 0.5, 0.2);
      expect(fake.emoji, '⭐');
      fake.y = 0.6;
      expect(fake.emoji, '💀');
      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      expect(catchOne(game, FallingKind.fake).lostLife, isTrue);
      // Si se escapa, no pasa nada.
      game.items.add(FallingItem(2, FallingKind.fake, 0.95, 0.9));
      game.moveTo(0.1);
      game.update(tick);
      expect(game.lives, 2);
    });

    test('cada nivel trae trampas nuevas', () {
      final game = StarCatchGame();
      expect(game.weights.keys, isNot(contains(FallingKind.bomb)));
      game.level = 2;
      expect(game.weights.keys, contains(FallingKind.bomb));
      game.level = 6;
      expect(game.weights.keys,
          containsAll([FallingKind.ice, FallingKind.swirl, FallingKind.fake]));
      expect(game.halfWidth, lessThan(StarCatchGame.basketHalfWidth));
    });

    test('combo: multiplica los puntos y se rompe al fallar', () {
      final game = StarCatchGame(random: Random(1))..moveTo(0.5);
      for (var i = 0; i < 7; i++) {
        catchOne(game, FallingKind.star);
      }
      expect(game.multiplier, 1);
      expect(catchOne(game, FallingKind.star).label, contains('x2'));
      expect(game.multiplier, 2);
      final before = game.score;
      catchOne(game, FallingKind.bigStar);
      expect(game.score, before + 6);
      // Hielo no rompe el combo; una nube sí.
      catchOne(game, FallingKind.ice);
      expect(game.combo, 9);
      catchOne(game, FallingKind.cloud);
      expect(game.combo, 0);
      expect(game.multiplier, 1);
      expect(game.maxCombo, 9);
    });

    test('cestas con truco', () {
      expect(StarCatchGame(skin: BasketSkin.crown).shields, 1);
      expect(
          StarCatchGame(skin: BasketSkin.hat).has(GameEffect.magnet), isTrue);
      expect(StarCatchGame(skin: BasketSkin.bucket).halfWidth,
          greaterThan(StarCatchGame().halfWidth));
      expect(StarCatchGame(skin: BasketSkin.ufo).basketSpeed,
          greaterThan(StarCatchGame().basketSpeed));
      final honey = StarCatchGame(skin: BasketSkin.honey)..moveTo(0.5);
      catchOne(honey, FallingKind.bigStar);
      expect(honey.score, 4);
      final rainbow = StarCatchGame(skin: BasketSkin.rainbow)..moveTo(0.5);
      catchOne(rainbow, FallingKind.ice);
      expect(rainbow.effects[GameEffect.frozen], lessThan(2));
    });

    test('se juega hasta perder las vidas y se acelera', () {
      final game = StarCatchGame(random: Random(2))..moveTo(-3);
      expect(game.basketX, StarCatchGame.basketHalfWidth);
      game.nudge(10);
      expect(game.basketX, 1 - StarCatchGame.basketHalfWidth);
      for (var i = 0; i < 6000 && !game.over; i++) {
        game.update(tick);
      }
      expect(game.over, isTrue);
      expect(game.lives, 0);
      expect(game.update(tick), isEmpty);
    });
  });

  test('XP: una partida premiada por descanso, con tope', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = GameStore(prefs);
    expect(xpForScore(9), 3);
    expect(xpForScore(200), maxGameXp);

    var r = await store.finish(12);
    expect(r.xp, 0);
    expect(r.noXpReason, contains('récord'));
    expect(r.newBest, isTrue);

    r = await store.finish(20, breakKey: 'j1#1');
    expect(r.xp, 6);
    expect(store.canEarnIn('j1#1'), isFalse);
    r = await store.finish(30, breakKey: 'j1#1');
    expect(r.xp, 0);
    expect(store.canEarnIn('j1#3'), isTrue);

    final again = GameStore(prefs);
    expect(again.best, 30);
    expect(again.bonusXp, 6);
    expect(computeProgress([], bonusXp: again.bonusXp).xp, 6);
    expect(gameOverMessage(const GameResult(30, xp: 10, newBest: true)),
        '¡30 puntos! ¡Nuevo récord! 🏆 +10 XP ✨');
  });

  test('medallas: desbloquean cestas y se guardan', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = GameStore(prefs);
    expect(store.isUnlocked(BasketSkin.ufo), isFalse);
    await store.selectSkin(BasketSkin.ufo);
    expect(store.skin, BasketSkin.basket, reason: 'bloqueada');

    var r = await store.finish(40,
        run: const GameRun(level: 3, maxCombo: 5, stars: 30, seconds: 70));
    expect(r.newMedals.map((m) => m.id), ['level3']);
    expect(store.isUnlocked(BasketSkin.bucket), isTrue);

    r = await store.finish(200,
        run: const GameRun(level: 6, maxCombo: 20, stars: 280, seconds: 190));
    expect(r.newMedals.map((m) => m.id),
        containsAll(['combo16', 'stars300', 'level6', 'survive180']));
    await store.selectSkin(BasketSkin.ufo);

    final again = GameStore(prefs);
    expect(again.skin, BasketSkin.ufo);
    expect(again.stats.totalStars, 310);
    expect(again.stats.games, 2);
    expect(again.medalsDone, 5);
  });

  testWidgets('se juega una partida completa', (tester) async {
    tester.view.physicalSize = const Size(304, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = GameStore(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        gameStoreProvider.overrideWith((_) => store),
      ],
      child: MaterialApp(home: Scaffold(body: StarCatchPanel(onClose: () {}))),
    ));
    expect(find.textContaining('juegas por el récord'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('game-start')));
    await tester.tap(find.byKey(const ValueKey('game-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('game-field')), findsOneWidget);
    expect(find.text('🧺'), findsOneWidget);
    expect(find.byKey(const ValueKey('game-banner')), findsOneWidget);
    expect(find.text('Nivel 1'), findsOneWidget);
    for (var i = 0; i < 3000; i++) {
      await tester.pump(tick);
      if (find.byKey(const ValueKey('game-result')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('game-result')), findsOneWidget);
    expect(find.byKey(const ValueKey('game-again')), findsOneWidget);
    expect(store.bonusXp, 0, reason: 'sin descanso no hay XP');
    expect(store.stats.games, 1);

    // Pantalla de medallas y cestas.
    await tester.tap(find.text('🏅 ${store.medalsDone}/${gameMedals.length}'));
    await tester.pump();
    expect(find.text('Medallas'), findsOneWidget);
    expect(find.byKey(const ValueKey('skin-basket')), findsOneWidget);
  });
}
