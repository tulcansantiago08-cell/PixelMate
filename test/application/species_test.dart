import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_context.dart';
import 'package:pixelmate/application/mascot/accessory_providers.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/progress/progress_providers.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/mascot/pet_accessory.dart';
import 'package:pixelmate/domain/mascot/pet_kind.dart';
import 'package:pixelmate/domain/mascot/pet_species.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/pet_sprites.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkdayRecord rec(String id, int focusMin) => WorkdayRecord(
      id: id,
      mode: ActivityMode.work,
      startedAt: DateTime(2026, 11, 1, 10).toUtc(),
      endedAt: DateTime(2026, 11, 1, 18).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: Duration(minutes: focusMin),
      effectiveBreak: Duration.zero,
      focusBlocksCompleted: 0,
      cyclesCompleted: 0,
      completed: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('especies: gato desde el inicio, perro en el 5, zorro en el 10', () {
    expect(PetKind.cat.unlockedAt(1), isTrue);
    expect(PetKind.dog.unlockedAt(4), isFalse);
    expect(PetKind.dog.unlockedAt(5), isTrue);
    expect(PetKind.fox.unlockedAt(10), isTrue);
    expect(PetKind.byId('fox'), PetKind.fox);
    expect(PetKind.byId('dragón'), isNull);
    expect(PetKind.unlockedBetween(3, 10), [PetKind.dog, PetKind.fox]);
    expect(PetKind.dog.withArticle, 'un perro');
  });

  test('cada especie tiene su hoja, todas las animaciones y accesorios', () {
    for (final kind in PetKind.values) {
      final json =
          jsonDecode(File('assets/pets/${kind.id}/pet.json').readAsStringSync())
              as Map<String, dynamic>;
      final species = PetSpecies.fromJson(json);
      expect(species.id, kind.id);
      expect(species.name, kind.label);
      expect(species.accessoryAssets.keys, containsAll(PetAccessory.values));
      expect(File(species.sheetAsset).existsSync(), isTrue);
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final kind in PetKind.values) {
      expect(pubspec, contains('- assets/pets/${kind.id}/\n'));
      expect(pubspec, contains('- assets/pets/${kind.id}/accessories/\n'));
    }
  });

  testWidgets('el perro y el zorro se cargan como el gato', (tester) async {
    for (final kind in PetKind.values) {
      final pet =
          (await tester.runAsync(() => loadPet(kind.id, bundle: rootBundle)))!;
      expect(pet.species.id, kind.id);
      expect(pet.accessories.keys, containsAll(PetAccessory.values));
    }
  });

  test('la especie elegida se guarda y solo se ve si está desbloqueada',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = MascotSettings(prefs);
    expect(settings.species, PetKind.cat);
    await settings.setSpecies(PetKind.dog);
    expect(MascotSettings(prefs).species, PetKind.dog);

    final store = SqliteWorkdayStore.inMemory();
    final c = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(store),
      mascotSettingsProvider.overrideWithValue(settings),
    ]);
    addTearDown(c.dispose);
    expect(c.read(activeSpeciesProvider), PetKind.cat,
        reason: 'nivel 1: el perro aún no');
    expect(c.read(petSpeciesIdProvider), 'cat');

    store.completeActive(rec('a', 1000)); // 1000 XP: nivel 5
    c.invalidate(allHistoryProvider);
    expect(c.read(progressProvider).level, 5);
    expect(c.read(activeSpeciesProvider), PetKind.dog);
    expect(c.read(petSpeciesIdProvider), 'dog');

    await settings.setSpecies(PetKind.fox);
    expect(c.read(activeSpeciesProvider), PetKind.cat,
        reason: 'el zorro pide nivel 10');
  });

  test('subir de nivel anuncia la especie nueva y la IA sabe qué es', () {
    const l4 = PlayerProgress(xp: 600, unlocked: {});
    const l5 = PlayerProgress(xp: 1000, unlocked: {});
    final up = progressEvents(l4, l5).single as LeveledUp;
    expect(up.species, [PetKind.dog]);
    expect(progressMessage(up).message,
        contains('Desbloqueaste: 🐶 Perro (elígelo en ⚙️ Ajustes).'));

    expect(
        describeContext(
          petName: 'James',
          species: PetKind.fox,
          now: DateTime(2026, 11, 8, 9),
          workday: WorkdayView.none,
          goal: null,
          progress: PlayerProgress.empty,
        ),
        startsWith('Te llamas James y eres un zorro.'));
  });
}
