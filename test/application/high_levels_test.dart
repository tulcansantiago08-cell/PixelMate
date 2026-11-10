import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/mascot/accessory_providers.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/progress/progress_providers.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/mascot/pet_accessory.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/aura_sparkles.dart';

WorkdayRecord big(String id, int focusMin) => WorkdayRecord(
      id: id,
      mode: ActivityMode.work,
      startedAt: DateTime(2026, 10, 1, 10).toUtc(),
      endedAt: DateTime(2026, 10, 1, 18).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: Duration(minutes: focusMin),
      effectiveBreak: Duration.zero,
      focusBlocksCompleted: 0,
      cyclesCompleted: 0,
      completed: false,
    );

void main() {
  test('accesorios nuevos en los niveles 15 y 18', () {
    expect(PetAccessory.wizardHat.unlockLevel, 15);
    expect(PetAccessory.cape.unlockLevel, 18);
    expect(PetAccessory.unlockedBetween(14, 18),
        [PetAccessory.wizardHat, PetAccessory.cape]);
  });

  test('el nivel 20 anuncia el aura; el 15 el gorro', () {
    final to20 = progressEvents(
            PlayerProgress(xp: xpForLevel(19), unlocked: const {}),
            PlayerProgress(xp: xpForLevel(20), unlocked: const {}))
        .whereType<LeveledUp>()
        .single;
    expect(to20.aura, isTrue);
    expect(progressMessage(to20).message, contains('✨ Aura brillante'));
    final to15 = progressEvents(
            PlayerProgress(xp: xpForLevel(14), unlocked: const {}),
            PlayerProgress(xp: xpForLevel(15), unlocked: const {}))
        .whereType<LeveledUp>()
        .single;
    expect(to15.aura, isFalse);
    expect(progressMessage(to15).message, contains('🧙 Gorro de mago'));
  });

  test('logro y título de Leyenda en el nivel 25', () {
    final xp25 = xpForLevel(25);
    final p = computeProgress([big('a', xp25)]);
    expect(p.level, 25);
    expect(p.title, 'Mito del enfoque');
    expect(p.unlocked, contains('legend'));
    expect(computeProgress([big('a', xp25 - 1)]).unlocked,
        isNot(contains('legend')));
  });

  test('el aura se ve desde el nivel 20 y se puede apagar', () async {
    final store = SqliteWorkdayStore.inMemory();
    final settings = MascotSettings();
    final c = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(store),
      mascotSettingsProvider.overrideWithValue(settings),
    ]);
    addTearDown(c.dispose);
    expect(c.read(auraActiveProvider), isFalse, reason: 'nivel 1');
    store.completeActive(big('a', xpForLevel(20)));
    c.invalidate(allHistoryProvider);
    expect(c.read(auraActiveProvider), isTrue);
    await settings.setAura(false);
    expect(c.read(auraActiveProvider), isFalse);
  });

  testWidgets('las chispitas se animan a 3 cuadros por segundo',
      (tester) async {
    await tester.pumpWidget(const Center(child: AuraSparkles()));
    final state = tester.state<AuraSparklesState>(find.byType(AuraSparkles));
    expect(state.frame, 0);
    await tester.pump(const Duration(milliseconds: 340));
    expect(state.frame, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(state.frame, 4);
    await tester.pumpWidget(const SizedBox());
  });
}
