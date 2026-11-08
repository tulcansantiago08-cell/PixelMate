import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/mascot/idle_behavior.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/mascot/mascot_walker.dart';
import 'package:pixelmate/application/mascot/walk_plan.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 11, 9, 10);

  group('plan del paseo', () {
    test('siempre dentro de los límites y a distancia razonable', () {
      final random = Random(42);
      for (var i = 0; i < 500; i++) {
        final x = random.nextDouble() * 1200;
        final plan =
            planWalk(currentX: x, minX: 0, maxX: 1160, now: t0, random: random);
        expect(plan, isNotNull);
        expect(plan!.toX, inInclusiveRange(0, 1160));
        final distance = (plan.toX - plan.fromX).abs();
        expect(distance, inInclusiveRange(80, 360));
      }
    });

    test('pegada a un borde, camina hacia el otro lado', () {
      final random = Random(1);
      for (var i = 0; i < 50; i++) {
        expect(
            planWalk(
                    currentX: 1160,
                    minX: 0,
                    maxX: 1160,
                    now: t0,
                    random: random)!
                .towardsLeft,
            isTrue);
        expect(
            planWalk(currentX: 0, minX: 0, maxX: 1160, now: t0, random: random)!
                .towardsLeft,
            isFalse);
      }
    });

    test('sin espacio no pasea', () {
      expect(
          planWalk(currentX: 10, minX: 0, maxX: 50, now: t0, random: Random()),
          isNull);
      expect(planWalk(currentX: 0, minX: 0, maxX: 0, now: t0, random: Random()),
          isNull);
    });

    test('la posición avanza a velocidad constante y se detiene al llegar', () {
      final plan = WalkPlan(fromX: 500, toX: 380, speed: 30, startedAt: t0);
      expect(plan.towardsLeft, isTrue);
      expect(plan.duration, const Duration(seconds: 4));
      expect(plan.xAt(t0), 500);
      expect(plan.xAt(t0.add(const Duration(seconds: 2))), 440);
      expect(plan.xAt(t0.add(const Duration(seconds: 10))), 380);
      expect(plan.isDoneAt(t0.add(const Duration(seconds: 3))), isFalse);
      expect(plan.isDoneAt(t0.add(const Duration(seconds: 4))), isTrue);
    });
  });

  group('caminante', () {
    test('mueve la ventana en horizontal, a su altura, y guarda al final',
        () async {
      var now = t0;
      final window = NoopMascotWindow(
        currentBounds: const Rect.fromLTWH(1148, 400, 280, 340),
        screenArea: const Rect.fromLTWH(0, 30, 1440, 807),
      );
      final walker = MascotWalker(
        window: window,
        now: () => now,
        random: Random(3),
        step: const Duration(milliseconds: 10),
      );
      addTearDown(walker.dispose);

      expect(await walker.start(), isTrue);
      expect(walker.walking, isTrue);
      expect(walker.facingLeft, isTrue, reason: 'está pegada a la derecha');
      expect(await walker.start(), isFalse, reason: 'ya camina');

      // Avanza el reloj hasta pasado el final del paseo.
      for (var i = 0; i < 20; i++) {
        now = now.add(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 15));
        if (!walker.walking) break;
      }
      expect(walker.walking, isFalse);
      expect(window.moves, isNotEmpty);
      expect(window.moves.every((o) => o.dy == 400), isTrue);
      expect(
          window.moves.every((o) => o.dx >= 0 && o.dx <= 1440 - 280), isTrue);
      expect(window.moves.last.dx, lessThan(1148));
      expect(window.remembered, 1);
    });

    test('detenerlo a mitad guarda donde quedó', () async {
      final window = NoopMascotWindow();
      final walker = MascotWalker(window: window, random: Random(5));
      addTearDown(walker.dispose);
      await walker.start();
      await walker.stop();
      expect(walker.walking, isFalse);
      expect(window.remembered, 1);
      await walker.stop();
      expect(window.remembered, 1, reason: 'detener dos veces no guarda dos');
    });
  });

  group('cuándo pasea', () {
    test('solo si el paseo está activado', () {
      final never = IdleBehavior(now: t0, fidgetChance: 1, random: Random(7));
      for (var i = 1; i <= 50; i++) {
        expect(
            never.tick(t0.add(Duration(seconds: i)),
                idle: true, canWalk: false),
            isNot(isA<StartWalk>()));
      }
      final sometimes =
          IdleBehavior(now: t0, fidgetChance: 1, random: Random(7));
      final decisions = [
        for (var i = 1; i <= 50; i++)
          sometimes.tick(t0.add(Duration(seconds: i)),
              idle: true, canWalk: true)
      ];
      expect(decisions.whereType<StartWalk>(), isNotEmpty);
      expect(decisions.whereType<PlayOnce>(), isNotEmpty);
    });

    test('nunca durante una sesión', () {
      final b = IdleBehavior(now: t0, fidgetChance: 1, random: Random(7));
      for (var i = 1; i <= 20; i++) {
        expect(b.tick(t0.add(Duration(seconds: i)), idle: false, canWalk: true),
            isA<StayStill>());
      }
    });

    test('la preferencia se guarda y se muestra en la barra de menú', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = MascotSettings(prefs);
      expect(settings.walkEnabled, isTrue);
      await settings.setWalkEnabled(false);
      expect(MascotSettings(prefs).walkEnabled, isFalse);

      TrayEntry entry(bool on) =>
          trayEntries(WorkdayView.none, mascotVisible: true, walkEnabled: on)
              .firstWhere((e) => e.action == TrayAction.toggleWalk);
      expect(entry(true).checked, isTrue);
      expect(entry(false).checked, isFalse);
    });
  });
}
