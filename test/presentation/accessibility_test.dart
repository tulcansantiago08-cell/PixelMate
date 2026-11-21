import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/assistant/calendar_tab.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Esc y ⌘W cierran el panel; la mascota se lee bien',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
    ]);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: MascotWindow())));
    await frames(tester);
    expect(find.bySemanticsLabel(RegExp(r'toca para charlar')), findsOneWidget);

    container.read(mascotPanelProvider.notifier).state = MascotPanel.stats;
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    expect(container.read(mascotPanelProvider), MascotPanel.none);

    container.read(mascotPanelProvider.notifier).state = MascotPanel.pending;
    await frames(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await frames(tester);
    expect(container.read(mascotPanelProvider), MascotPanel.none);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('los días del calendario se leen con su fecha', (tester) async {
    final semantics = tester.ensureSemantics();
    final notes = CalendarStore();
    await notes.add('Cumple', DateTime(2026, 11, 20));
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [calendarStoreProvider.overrideWith((_) => notes)],
      child: MaterialApp(
          home: Scaffold(body: CalendarTab(today: DateTime(2026, 11, 17)))),
    ));
    await tester.pump();
    expect(find.bySemanticsLabel('17 de noviembre, hoy'), findsOneWidget);
    expect(find.bySemanticsLabel('20 de noviembre, con cosas anotadas'),
        findsOneWidget);
    semantics.dispose();
  });
}
