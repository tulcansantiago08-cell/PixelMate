import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/session.dart';

void main() {
  group('Session — cálculo de ciclos', () {
    Session makeSession(Duration planned) => Session(
          id: 'test-1',
          mode: ActivityMode.work,
          startedAt: DateTime.now(),
          plannedDuration: planned,
          focusDuration: const Duration(minutes: 50),
          shortBreakDuration: const Duration(minutes: 10),
          longBreakDuration: const Duration(minutes: 30),
          cyclesBeforeLongBreak: 3,
        );

    test('jornada de 4 horas produce ciclos suficientes', () {
      final s = makeSession(const Duration(hours: 4));
      // 4h = 240min. Bloque largo = 3*(50+10)+30 = 210min → 1 bloque + resto
      expect(s.totalCycles, greaterThan(0));
    });

    test('jornada de 8 horas produce más ciclos que una de 4', () {
      final s4 = makeSession(const Duration(hours: 4));
      final s8 = makeSession(const Duration(hours: 8));
      expect(s8.totalCycles, greaterThan(s4.totalCycles));
    });

    test('copyWith preserva campos no modificados', () {
      final s = makeSession(const Duration(hours: 8));
      final s2 = s.copyWith(completed: true, cyclesCompleted: 3);
      expect(s2.completed, isTrue);
      expect(s2.cyclesCompleted, 3);
      expect(s2.mode, s.mode);
      expect(s2.plannedDuration, s.plannedDuration);
    });
  });

  group('ActivityMode extensions', () {
    test('displayName no está vacío para ningún modo', () {
      for (final mode in ActivityMode.values) {
        expect(mode.displayName, isNotEmpty);
        expect(mode.emoji, isNotEmpty);
      }
    });
  });
}
