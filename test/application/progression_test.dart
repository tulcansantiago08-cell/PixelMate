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
import 'package:pixelmate/presentation/stats/level_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkdayRecord rec(
  String id, {
  ActivityMode mode = ActivityMode.work,
  DateTime? start,
  int focusMin = 60,
  int breakMin = 10,
  int blocks = 1,
  int cycles = 0,
  bool completed = false,
}) {
  final s = start ?? DateTime(2026, 11, 9, 10);
  return WorkdayRecord(
    id: id,
    mode: mode,
    startedAt: s.toUtc(),
    endedAt: s.add(Duration(minutes: focusMin + breakMin)).toUtc(),
    planned: const Duration(hours: 8),
    effectiveFocus: Duration(minutes: focusMin),
    effectiveBreak: Duration(minutes: breakMin),
    focusBlocksCompleted: blocks,
    cyclesCompleted: cycles,
    completed: completed,
  );
}

void main() {
  group('XP', () {
    test('enfoque, descanso, bloques y jornada completa', () {
      expect(xpForRecord(rec('a', focusMin: 0, breakMin: 0, blocks: 0)), 0);
      // 50 enfoque + 10/2 descanso + 1×5 bloque.
      expect(xpForRecord(rec('a', focusMin: 50, breakMin: 10)), 60);
      expect(
          xpForRecord(rec('a', focusMin: 50, breakMin: 10, completed: true)),
          85);
      // Una jornada de 8 h completa: 370 min de enfoque, 110 de descanso.
      expect(
          xpForRecord(rec('a',
              focusMin: 370, breakMin: 110, blocks: 9, completed: true)),
          370 + 55 + 45 + 25);
    });
  });

  group('niveles', () {
    test('umbrales crecientes: 100, 300, 600, 1000…', () {
      expect(xpForLevel(1), 0);
      expect(xpForLevel(2), 100);
      expect(xpForLevel(3), 300);
      expect(xpForLevel(4), 600);
      expect(xpForLevel(5), 1000);
    });

    test('levelForXp es la inversa exacta en los bordes', () {
      expect(levelForXp(-5), 1);
      expect(levelForXp(0), 1);
      for (var level = 1; level < 60; level++) {
        expect(levelForXp(xpForLevel(level)), level);
        expect(levelForXp(xpForLevel(level + 1) - 1), level);
      }
    });

    test('títulos por tramos', () {
      expect(titleForLevel(1), 'Gatito novato');
      expect(titleForLevel(2), 'Gatito novato');
      expect(titleForLevel(3), 'Aprendiz curioso');
      expect(titleForLevel(19), 'Sabio zen');
      expect(titleForLevel(99), 'Leyenda pixel');
    });

    test('progreso dentro del nivel', () {
      const p = PlayerProgress(xp: 400, unlocked: {});
      expect(p.level, 3);
      expect(p.xpIntoLevel, 100);
      expect(p.xpNeededForNext, 300);
      expect(p.levelFraction, closeTo(1 / 3, 1e-9));
    });
  });

  group('logros', () {
    Set<String> unlocked(List<WorkdayRecord> h, {WorkdayRecord? live}) =>
        computeProgress(h, live: live).unlocked;

    test('sin historial no hay nada', () {
      expect(computeProgress([]).xp, 0);
      expect(unlocked([]), isEmpty);
    });

    test('primera sesión, completa y ciclos', () {
      expect(unlocked([rec('a')]), {'first'});
      expect(unlocked([rec('a', completed: true)]), {'first', 'complete'});
      expect(unlocked([rec('a', cycles: 3)]), contains('cycles'));
    });

    test('horas de enfoque y descanso acumuladas', () {
      final h = [for (var i = 0; i < 10; i++) rec('$i', breakMin: 6)];
      expect(unlocked(h), containsAll(['focus10', 'rest']));
      expect(unlocked(h), isNot(contains('focus50')));
    });

    test('7 días distintos, aunque no sean seguidos', () {
      final h = [
        for (var i = 0; i < 7; i++)
          rec('$i', start: DateTime(2026, 11, 1 + i * 3, 10))
      ];
      expect(unlocked(h), contains('days7'));
      final sameDay = [for (var i = 0; i < 7; i++) rec('$i')];
      expect(unlocked(sameDay), isNot(contains('days7')));
    });

    test('estudio, gamer y madrugador', () {
      expect(
          unlocked([
            for (var i = 0; i < 5; i++) rec('$i', mode: ActivityMode.study)
          ]),
          contains('study'));
      expect(unlocked([rec('g', mode: ActivityMode.gaming)]),
          isNot(contains('gamer')),
          reason: 'hay que completarla');
      expect(
          unlocked([rec('g', mode: ActivityMode.gaming, completed: true)]),
          contains('gamer'));
      expect(unlocked([rec('e', start: DateTime(2026, 11, 9, 7, 59))]),
          contains('early'));
      expect(unlocked([rec('e', start: DateTime(2026, 11, 9, 8))]),
          isNot(contains('early')));
    });

    test('la sesión en curso cuenta, pero nunca dos veces', () {
      final live = rec('live', focusMin: 30, breakMin: 0, blocks: 0);
      expect(computeProgress([], live: live).xp, 30);
      expect(computeProgress([rec('a')], live: live).xp, 60 + 5 + 5 + 30);
      // Recién guardada en el historial con el mismo id.
      expect(computeProgress([live], live: live).xp, 30);
    });
  });

  group('sucesos', () {
    test('subir de nivel avisa del título nuevo solo cuando cambia', () {
      const l1 = PlayerProgress(xp: 90, unlocked: {});
      const l2 = PlayerProgress(xp: 110, unlocked: {});
      const l3 = PlayerProgress(xp: 300, unlocked: {});
      expect(progressEvents(l1, l1), isEmpty);
      final up = progressEvents(l1, l2).single as LeveledUp;
      expect(up.level, 2);
      expect(up.newTitle, isFalse);
      final up3 = progressEvents(l2, l3).single as LeveledUp;
      expect(up3.newTitle, isTrue);
      expect(progressMessage(up3).message, contains('Aprendiz curioso'));
      expect(progressEvents(l3, l1), isEmpty, reason: 'no se anuncia bajar');
    });

    test('subir de nivel anuncia los accesorios que se estrenan', () {
      const l1 = PlayerProgress(xp: 0, unlocked: {});
      const l4 = PlayerProgress(xp: 600, unlocked: {});
      final up = progressEvents(l1, l4).single as LeveledUp;
      expect(up.accessories, [PetAccessory.scarf, PetAccessory.bow]);
      expect(progressMessage(up).message, contains('🧣 Bufanda, 🎀 Moño'));
      const l5 = PlayerProgress(xp: 1000, unlocked: {});
      expect((progressEvents(l4, l5).single as LeveledUp).accessories, isEmpty);
    });

    test('el accesorio elegido solo se ve si está desbloqueado', () async {
      final store = SqliteWorkdayStore.inMemory();
      final settings = MascotSettings();
      final container = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(store),
        mascotSettingsProvider.overrideWithValue(settings),
      ]);
      addTearDown(container.dispose);
      expect(container.read(equippedAccessoryProvider), isNull);

      await settings.setAccessory(PetAccessory.scarf);
      expect(container.read(equippedAccessoryProvider), isNull,
          reason: 'nivel 1: la bufanda pide nivel 2');

      store.completeActive(rec('a', focusMin: 120, breakMin: 0, blocks: 0));
      container.invalidate(allHistoryProvider);
      expect(container.read(equippedAccessoryProvider), PetAccessory.scarf);

      await settings.setAccessory(null);
      expect(container.read(equippedAccessoryProvider), isNull);
    });

    test('el accesorio elegido se guarda', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await MascotSettings(prefs).setAccessory(PetAccessory.crown);
      expect(MascotSettings(prefs).accessory, PetAccessory.crown);
      await MascotSettings(prefs).setAccessory(null);
      expect(MascotSettings(prefs).accessory, isNull);
    });

    test('logros nuevos, uno por suceso', () {
      const before = PlayerProgress(xp: 0, unlocked: {'first'});
      const after =
          PlayerProgress(xp: 50, unlocked: {'first', 'complete', 'early'});
      final events = progressEvents(before, after);
      expect(events.map((e) => (e as AchievementUnlocked).achievement.id),
          ['complete', 'early']);
      expect(progressMessage(events.first).message, contains('Hasta el final'));
    });

    test('al guardar una sesión el proveedor anuncia lo ganado', () {
      final store = SqliteWorkdayStore.inMemory();
      final container = ProviderContainer(
          overrides: [workdayStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);
      final events = <ProgressEvent>[];
      container.listen<PlayerProgress>(progressProvider, (b, a) {
        if (b != null) events.addAll(progressEvents(b, a));
      }, fireImmediately: true);

      store.completeActive(
          rec('a', focusMin: 120, breakMin: 0, blocks: 2, completed: true));
      container.invalidate(allHistoryProvider);
      container.read(progressProvider);

      expect(container.read(progressProvider).level, 2);
      expect(events.whereType<LeveledUp>().single.level, 2);
      expect(
          events
              .whereType<AchievementUnlocked>()
              .map((e) => e.achievement.id),
          ['first', 'complete']);
    });
  });

  testWidgets('la tarjeta muestra nivel, barra y logros', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LevelCard(
            progress: PlayerProgress(xp: 400, unlocked: {'first', 'early'})),
      ),
    ));
    expect(find.text('Nv. 3'), findsOneWidget);
    expect(find.text('Aprendiz curioso'), findsOneWidget);
    expect(find.text('400 XP'), findsOneWidget);
    expect(find.text('Faltan 200 XP para el nivel 4'), findsOneWidget);
    expect(find.text('Logros 2/${achievements.length}'), findsOneWidget);
    expect(find.text('🐾'), findsOneWidget);
    expect(find.text('🔒'), findsNWidgets(achievements.length - 2));
    expect(find.text('Accesorios'), findsNothing,
        reason: 'sin onEquip no hay selector');
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(1 / 3, 1e-9));
  });

  testWidgets('elegir y quitar accesorios desde la tarjeta', (tester) async {
    final chosen = <PetAccessory?>[];
    Future<void> show(PetAccessory? equipped) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: LevelCard(
              progress: const PlayerProgress(xp: 650, unlocked: {}), // Nv. 4
              equipped: equipped,
              onEquip: chosen.add,
            ),
          ),
        ));
    await show(null);
    expect(find.text('Accesorios'), findsOneWidget);
    // Nv. 4: bufanda y moño disponibles; el resto con candado y su nivel.
    expect(find.text('🧣'), findsOneWidget);
    expect(find.text('🎀'), findsOneWidget);
    expect(find.text('Nv. 6'), findsOneWidget);
    expect(find.text('Nv. 12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('accessory-bow')));
    await tester.tap(find.byKey(const ValueKey('accessory-crown')));
    expect(chosen, [PetAccessory.bow], reason: 'la corona sigue bloqueada');

    await show(PetAccessory.bow);
    await tester.tap(find.byKey(const ValueKey('accessory-bow')));
    expect(chosen, [PetAccessory.bow, null], reason: 'tocarlo otra vez lo quita');
  });
}
