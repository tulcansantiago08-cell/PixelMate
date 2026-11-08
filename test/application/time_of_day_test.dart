import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/suggestion.dart';
import 'package:pixelmate/application/mascot/idle_behavior.dart';
import 'package:pixelmate/application/mascot/late_night.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/domain/mascot/pet_species.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/time/day_part.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

void main() {
  test('partes del día', () {
    expect(DayPart.of(at(8, 4, 59)), DayPart.night);
    expect(DayPart.of(at(8, 5)), DayPart.morning);
    expect(DayPart.of(at(8, 11, 59)), DayPart.morning);
    expect(DayPart.of(at(8, 12)), DayPart.afternoon);
    expect(DayPart.of(at(8, 19)), DayPart.evening);
    expect(DayPart.of(at(8, 23)), DayPart.night);
    expect(DayPart.night.sleepy, isTrue);
    expect(DayPart.evening.sleepy, isFalse);
  });

  test('el saludo depende de la hora (y a las 2:00 no es "buenos días")', () {
    expect(Suggestion.welcome(at(8, 9)).message, startsWith('¡Buenos días!'));
    expect(
        Suggestion.welcome(at(8, 15)).message, startsWith('¡Buenas tardes!'));
    expect(
        Suggestion.welcome(at(8, 21)).message, startsWith('¡Buenas noches!'));
    final late = Suggestion.welcome(at(8, 2)).message;
    expect(late, contains('Es muy tarde'));
    expect(late, isNot(contains('Buenos días')));
  });

  group('de noche tiene sueño', () {
    test('se duerme a los 3 min (de día, a los 10)', () {
      final night = IdleBehavior(now: at(8, 23, 30), fidgetChance: 0);
      expect(night.tick(at(8, 23, 32), idle: true), isA<StayStill>());
      expect(night.tick(at(8, 23, 33), idle: true), isA<FallAsleep>());

      final day = IdleBehavior(now: at(8, 15), fidgetChance: 0);
      expect(day.tick(at(8, 15, 3), idle: true), isA<StayStill>());
      expect(day.tick(at(8, 15, 10), idle: true), isA<FallAsleep>());
    });

    test('de noche no pasea ni saluda: solo bosteza estirándose', () {
      final b = IdleBehavior(now: at(9, 0), fidgetChance: 1, random: Random(1));
      for (var s = 1; s <= 60; s++) {
        final d = b.tick(at(9, 0).add(Duration(seconds: s)),
            idle: true, canWalk: true);
        expect(d, isA<PlayOnce>());
        expect((d as PlayOnce).animation, PetAnimation.stretch);
      }
    });
  });

  group('recordatorio nocturno', () {
    test('22:00, 23:30 y 1:00, una vez cada uno y solo con jornada', () {
      final r = LateNightReminder();
      expect(r.check(at(8, 21, 59), sessionActive: true), isNull);
      expect(r.check(at(8, 22, 5), sessionActive: false), isNull,
          reason: 'sin jornada no se dice nada');
      expect(r.check(at(8, 22, 6), sessionActive: true),
          contains('Ya son las 22:06'));
      expect(r.check(at(8, 22, 30), sessionActive: true), isNull);
      expect(r.check(at(8, 23, 31), sessionActive: true),
          contains('Son las 23:31'));
      expect(r.check(at(9, 0, 30), sessionActive: true), isNull);
      expect(r.check(at(9, 1, 2), sessionActive: true), contains('a dormir'));
      expect(r.check(at(9, 3), sessionActive: true), isNull);
    });

    test('si empieza tarde, solo el último umbral (no tres seguidos)', () {
      final r = LateNightReminder();
      expect(r.check(at(9, 1, 15), sessionActive: true), contains('a dormir'));
      expect(r.check(at(9, 1, 16), sessionActive: true), isNull);
    });

    test('cada noche empieza de nuevo', () {
      final r = LateNightReminder();
      expect(r.check(at(8, 22), sessionActive: true), isNotNull);
      expect(r.check(at(9, 10), sessionActive: true), isNull,
          reason: 'de día nada');
      expect(r.check(at(9, 22), sessionActive: true), isNotNull);
    });

    test('con la jornada real y la preferencia', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = MascotSettings(prefs);
      expect(settings.nightReminders, isTrue);

      final c = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      ]);
      addTearDown(c.dispose);
      var now = at(8, 22, 10);
      final controller = LateNightController(settings, now: () => now);
      addTearDown(controller.dispose);
      final workday = c.read(workdayControllerProvider.notifier);

      controller.onTick(c.read(workdayControllerProvider));
      expect(controller.state, isNull, reason: 'sin jornada');
      workday.start(const WorkdayConfig());
      controller.onTick(c.read(workdayControllerProvider));
      expect(controller.state, contains('22:10'));

      await settings.setNightReminders(false);
      expect(MascotSettings(prefs).nightReminders, isFalse);
      now = at(8, 23, 40);
      final quiet = LateNightController(settings, now: () => now);
      addTearDown(quiet.dispose);
      quiet.onTick(c.read(workdayControllerProvider));
      expect(quiet.state, isNull, reason: 'desactivado');
      workday.finish();
    });
  });
}
