import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/progress/celebrations.dart';
import 'package:pixelmate/application/progress/progress_providers.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';

WorkdayRecord past(int focusMin) => WorkdayRecord(
      id: 'past-$focusMin',
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
  test('varias guardadas se juntan en un solo mensaje', () {
    final one = Celebration.combined(
        [const Celebration('¡Nivel 4!', '¡Subiste a nivel 4!', levelUp: true)]);
    expect(one.message, 'Mientras te enfocabas: ¡Subiste a nivel 4!');
    expect(one.levelUp, isTrue);
    final many = Celebration.combined([
      const Celebration('a', 'Nivel 4', levelUp: true),
      const Celebration('b', 'Logro: Hasta el final'),
    ]);
    expect(many.title, 'Mientras te enfocabas');
    expect(
        many.message, 'Mientras te enfocabas: Nivel 4 · Logro: Hasta el final');
    expect(many.levelUp, isTrue);
  });

  group('con la jornada real', () {
    late SqliteWorkdayStore store;
    late MascotSettings settings;
    late ProviderContainer c;
    final seen = <Celebration>[];

    setUp(() {
      store = SqliteWorkdayStore.inMemory();
      settings = MascotSettings();
      c = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(store),
        mascotSettingsProvider.overrideWithValue(settings),
      ]);
      addTearDown(c.dispose);
      seen.clear();
      c.listen<Celebration?>(celebrationProvider, (before, now) {
        if (now != null && !identical(before, now)) seen.add(now);
      }, fireImmediately: true);
    });

    /// Sube de nivel guardando una jornada antigua (1000 XP: nivel 5).
    void levelUp() {
      store.completeActive(past(1000));
      c.invalidate(allHistoryProvider);
      c.read(progressProvider);
    }

    test('sin enfoque profundo, se celebra al momento', () {
      c.read(workdayControllerProvider.notifier).start(const WorkdayConfig());
      levelUp();
      expect(seen.map((s) => s.title), contains('¡Nivel 5!'));
      expect(seen.first.message, isNot(startsWith('Mientras')));
      c.read(workdayControllerProvider.notifier).finish();
    });

    test('con enfoque profundo, espera al descanso y llega junta', () async {
      await settings.setDeepFocus(true);
      final workday = c.read(workdayControllerProvider.notifier);
      workday.start(const WorkdayConfig());
      levelUp();
      expect(seen, isEmpty, reason: 'en pleno enfoque no se interrumpe');
      expect(c.read(celebrationProvider.notifier).held, isNotEmpty);

      workday.skipPhase(); // -> descanso
      expect(seen, hasLength(1));
      expect(seen.single.message, startsWith('Mientras te enfocabas:'));
      expect(seen.single.message, contains('nivel 5'));
      expect(seen.single.levelUp, isTrue);
      expect(c.read(celebrationProvider.notifier).held, isEmpty);
      workday.finish();
    });

    test('si termina la jornada en pleno enfoque, también se dice', () async {
      await settings.setDeepFocus(true);
      final workday = c.read(workdayControllerProvider.notifier);
      workday.start(const WorkdayConfig());
      levelUp();
      expect(seen, isEmpty);
      workday.finish();
      expect(seen, hasLength(1));
      expect(seen.single.message, startsWith('Mientras te enfocabas:'));
    });

    test('sin jornada no hay nada que esperar', () async {
      await settings.setDeepFocus(true);
      levelUp();
      expect(seen.map((s) => s.title), contains('¡Nivel 5!'));
    });
  });
}
