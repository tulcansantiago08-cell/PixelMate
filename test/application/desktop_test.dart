import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/desktop/mascot_placement.dart';
import 'package:pixelmate/application/desktop/tray_model.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_dialogue.dart';
import 'package:pixelmate/application/workday/workday_event.dart';
import 'package:pixelmate/application/workday/workday_format.dart';
import 'package:pixelmate/application/workday/workday_notifications.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/domain/session/session_phase.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/domain/session/workday_timer.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 9, 8);
  DateTime at(int m, [int s = 0]) => t0.add(Duration(minutes: m, seconds: s));

  WorkdayView viewAt(WorkdayTimer timer, DateTime now) => WorkdayView(
      mode: ActivityMode.work, timer: timer, status: timer.statusAt(now));

  final timer =
      WorkdayTimer.start(id: 'j', config: const WorkdayConfig(), now: t0);

  group('formatos', () {
    test('cuenta regresiva redondea hacia arriba', () {
      expect(
          formatCountdown(
              const Duration(minutes: 49, seconds: 59, milliseconds: 1)),
          '50:00');
      expect(formatCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('horas y minutos', () {
      expect(formatHoursMinutes(const Duration(minutes: 8)), '8 min');
      expect(
          formatHoursMinutes(const Duration(minutes: 7, seconds: 1)), '8 min');
      expect(formatHoursMinutes(const Duration(hours: 2)), '2 h');
      expect(formatHoursMinutes(const Duration(hours: 6, minutes: 12)),
          '6 h 12 min');
    });
  });

  group('barra de menú', () {
    test('sin jornada: título vacío y submenú para iniciar', () {
      final entries = trayEntries(WorkdayView.none, mascotVisible: true);
      expect(trayTitle(WorkdayView.none), '');
      final start = entries.first;
      expect(start.label, 'Iniciar jornada');
      expect(
          start.children.map((c) => c.workday), WorkdayConfig.presetWorkdays);
      expect(entries.map((e) => e.action),
          containsAll([TrayAction.toggleMascot, TrayAction.quit]));
      expect(entries.map((e) => e.action), isNot(contains(TrayAction.pause)));
    });

    test('con jornada: cuenta regresiva y acciones de control', () {
      final view = viewAt(timer, at(7, 50));
      expect(trayTitle(view), '🎯 42:10');
      final actions =
          trayEntries(view, mascotVisible: true).map((e) => e.action);
      expect(
          actions,
          containsAll([
            TrayAction.pause,
            TrayAction.skipPhase,
            TrayAction.finish,
          ]));
    });

    test('en pausa muestra ⏸ y ofrece reanudar', () {
      final view = viewAt(timer.pause(at(10)), at(20));
      expect(trayTitle(view), startsWith('⏸'));
      final actions =
          trayEntries(view, mascotVisible: true).map((e) => e.action);
      expect(actions, contains(TrayAction.resume));
      expect(actions, isNot(contains(TrayAction.pause)));
    });

    test('el texto de mostrar/ocultar depende de la visibilidad', () {
      String label(bool visible) =>
          trayEntries(WorkdayView.none, mascotVisible: visible)
              .firstWhere((e) => e.action == TrayAction.toggleMascot)
              .label;
      expect(label(true), 'Ocultar mascota');
      expect(label(false), 'Mostrar mascota');
    });

    test('el menú no cambia cada segundo (solo el título)', () {
      String signature(DateTime now) =>
          trayEntries(viewAt(timer, now), mascotVisible: true)
              .map((e) => e.key)
              .join('|');
      expect(signature(at(10, 1)), signature(at(10, 40)));
    });

    test('las claves son únicas para identificar el clic', () {
      final all = [
        for (final e in trayEntries(WorkdayView.none, mascotVisible: true))
          if (!e.isSeparator) ...[e, ...e.children]
      ];
      expect(all.map((e) => e.key).toSet(), hasLength(all.length));
    });
  });

  group('posición de la mascota', () {
    const screen = Rect.fromLTWH(0, 25, 1440, 800); // sin barra de menú
    const window = Size(280, 300);

    test('por defecto va abajo a la derecha con margen', () {
      final o = MascotPlacement.defaultOrigin(screen, window);
      expect(o, const Offset(1440 - 280 - 12, 825 - 300 - 12));
    });

    test('restaura la posición guardada', () {
      final o = MascotPlacement.restoreOrigin(
        savedBottomRight: const Offset(600, 500),
        window: window,
        visibleAreas: [screen],
      );
      expect(o, const Offset(320, 200));
    });

    test('si la pantalla guardada ya no existe vuelve a la esquina', () {
      final o = MascotPlacement.restoreOrigin(
        savedBottomRight: const Offset(3000, 500), // monitor desconectado
        window: window,
        visibleAreas: [screen],
      );
      expect(o, MascotPlacement.defaultOrigin(screen, window));
    });

    test('funciona con un segundo monitor', () {
      const second = Rect.fromLTWH(1440, 0, 1920, 1080);
      final o = MascotPlacement.restoreOrigin(
        savedBottomRight: const Offset(3000, 900),
        window: window,
        visibleAreas: [screen, second],
      );
      expect(o, const Offset(2720, 600));
    });

    test('si queda medio fuera se ajusta dentro de la pantalla', () {
      final o = MascotPlacement.restoreOrigin(
        savedBottomRight: const Offset(1500, 830),
        window: window,
        visibleAreas: [screen],
      );
      expect(o, const Offset(1160, 525));
    });

    test('al agrandar para el chat la esquina inferior derecha no se mueve',
        () {
      const origin = Offset(1000, 500);
      const big = Size(320, 480);
      final o = MascotPlacement.resizeKeepingBottomRight(origin, window, big);
      expect((o & big).bottomRight, (origin & window).bottomRight);
    });
  });

  group('notificaciones del sistema', () {
    final plan = timer.plan;

    test('avisan al empezar descansos y al volver al enfoque', () {
      final rest = noticeFor(PhaseStarted(plan[1], plan[0]))!;
      expect(rest.title, '☕ Descanso de 10 min');
      expect(rest.body, contains(eyeBreakTip(1)));
      expect(noticeFor(PhaseStarted(plan[5], plan[4]))!.title,
          '🌿 Descanso largo de 30 min');
      expect(noticeFor(PhaseStarted(plan[2], plan[1]))!.title,
          '🎯 Enfoque de 50 min');
    });

    test('al terminar la jornada', () {
      final done = noticeFor(WorkdayFinished(timer.statusAt(at(480))))!;
      expect(done.title, contains('terminada'));
    });

    test('los avisos menores no generan notificación', () {
      expect(noticeFor(const WorkdayStarted()), isNull);
      expect(noticeFor(const WorkdayPaused()), isNull);
      expect(noticeFor(FocusEndingSoon(plan[0], const Duration(minutes: 5))),
          isNull);
      expect(plan[0].kind, SessionPhase.focus);
    });
  });
}
