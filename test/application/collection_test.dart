import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/collection/collection.dart';
import 'package:pixelmate/application/game/star_catch.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/progress/progress_providers.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/domain/mascot/pet_accessory.dart';
import 'package:pixelmate/domain/mascot/pet_kind.dart';
import 'package:pixelmate/presentation/collection/collection_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayerProgress atLevel(int level, {Set<String> unlocked = const {'first'}}) =>
    PlayerProgress(xp: xpForLevel(level), unlocked: unlocked);

void main() {
  test('el álbum cuenta lo conseguido y lo que falta', () async {
    SharedPreferences.setMockInitialValues({});
    final game = GameStore(await SharedPreferences.getInstance());
    final c = buildCollection(
      progress: atLevel(6),
      species: PetKind.dog,
      accessory: PetAccessory.bow,
      auraOn: false,
      game: game,
    );
    final total = PetKind.values.length +
        PetAccessory.values.length +
        1 +
        achievements.length +
        gameMedals.length +
        BasketSkin.values.length;
    expect(c.total, total);
    // Nivel 6: gato y perro, 3 accesorios, 1 logro, la cesta básica.
    expect(c.unlocked, 2 + 3 + 1 + 1);
    final dog = c.sections.first.items[1];
    expect(dog.unlocked && dog.inUse && dog.usable, isTrue);
    final fox = c.sections.first.items[2];
    expect(fox.unlocked, isFalse);
    expect(fox.hint, contains('nivel 10'));
    expect(fox.hint, contains('faltan 4 niveles'));
    expect(c.nextByLevel(6)!.name, 'Audífonos');

    await game.finish(0, run: const GameRun(level: 3));
    final after = buildCollection(
        progress: atLevel(6),
        species: PetKind.dog,
        accessory: null,
        auraOn: false,
        game: game);
    expect(after.unlocked, c.unlocked + 2, reason: 'medalla y cesta 🪣');
  });

  testWidgets('se ve, se explica y se usa desde el álbum', (tester) async {
    tester.view.physicalSize = const Size(300, 270);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mascot = MascotSettings(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        progressProvider.overrideWithValue(atLevel(6)),
        mascotSettingsProvider.overrideWithValue(mascot),
        gameStoreProvider.overrideWith((_) => GameStore(prefs)),
      ],
      child: MaterialApp(home: Scaffold(body: CollectionPanel(onClose: () {}))),
    ));
    expect(find.textContaining('7/'), findsOneWidget);
    expect(find.byKey(const ValueKey('album-next')), findsOneWidget);

    // Bloqueado: dice cómo conseguirlo, sin botón.
    await tester.tap(find.byKey(const ValueKey('album-species.fox')));
    await tester.pump();
    expect(find.textContaining('nivel 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('album-use')), findsNothing);

    // Desbloqueado: se pone y se quita.
    final glasses = find.byKey(const ValueKey('album-accessory.sunglasses'));
    await tester.scrollUntilVisible(glasses, 40,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(glasses);
    await tester.pump();
    expect(find.text('Poner'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('album-use')));
    await tester.pump();
    expect(mascot.accessory, PetAccessory.sunglasses);
    expect(find.text('Quitar'), findsOneWidget);

    // Vuelve arriba de la lista (la pieza quedaba medio tapada).
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 600));
    await tester.pumpAndSettle();
    final dog = find.byKey(const ValueKey('album-species.dog'));
    await tester.tap(dog);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('album-use')));
    await tester.pump();
    expect(mascot.species, PetKind.dog);
    expect(find.text('En uso'), findsOneWidget);
  });
}
