import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/game/star_catch.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('dura 60 s y fallar quita tiempo, no vidas', () {
    final game = StarCatchGame(random: Random(1), mode: GameMode.timeAttack)
      ..moveTo(0.1);
    expect(game.timeLeft, const Duration(seconds: 60));
    // Una estrella que se escapa lejos de la cesta.
    game.items.add(FallingItem(100, FallingKind.star, 0.9, 0.9));
    game.update(const Duration(milliseconds: 100));
    expect(game.lives, StarCatchGame.startLives);
    expect(game.timeLeft.inSeconds, inInclusiveRange(54, 55));
    expect(game.over, isFalse);
    // Un corazón devuelve tiempo.
    game.moveTo(0.5);
    for (var i = 0; i < 20; i++) {
      game.update(const Duration(milliseconds: 50));
    }
    game.items
      ..clear()
      ..add(FallingItem(101, FallingKind.heart, game.basketX, 0.85));
    final before = game.timeLeft;
    game.update(const Duration(milliseconds: 16));
    expect(game.timeLeft > before, isTrue);
    // Se acaba el tiempo.
    game.items.clear();
    while (!game.over) {
      game.update(const Duration(milliseconds: 500));
      game.items.removeWhere((i) => i.kind.isStar);
    }
    expect(game.timeLeft, Duration.zero);
    expect(game.lives, StarCatchGame.startLives);
  });

  test('el récord de contrarreloj va aparte', () async {
    SharedPreferences.setMockInitialValues({});
    final store = GameStore(await SharedPreferences.getInstance());
    await store.finish(40, mode: GameMode.timeAttack);
    await store.finish(10);
    expect((store.best, store.bestTimeAttack), (10, 40));
    final r = await store.finish(30, mode: GameMode.timeAttack);
    expect(r.newBest, isFalse);
  });
}
