import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/daily_tasks.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/settings/backup.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un recorrido de punta a punta por la ventana de la mascota, como lo haría
/// alguien: abrir paneles con los botones, anotar en el calendario, pedir
/// algo en el chat, esconderla, y guardar y restaurar una copia.
void main() {
  /// La mascota anima en bucle: no se puede esperar a que se quede quieta.
  Future<void> frames(WidgetTester tester, [int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await frames(tester);
  }

  testWidgets('recorrido completo', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.pixelmate/app'), (_) async => null);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();
    final window = NoopMascotWindow();
    final store = PersonalStore(prefs);
    final notes = CalendarStore(prefs);
    final daily = DailyTaskStore(prefs);
    final files = MemoryBackupFiles();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
      mascotSettingsProvider.overrideWithValue(MascotSettings(prefs)),
      mascotWindowProvider.overrideWithValue(window),
      personalStoreProvider.overrideWithValue(store),
      calendarStoreProvider.overrideWith((_) => notes),
      dailyTaskStoreProvider.overrideWith((_) => daily),
      backupPrefsProvider.overrideWithValue(prefs),
      backupFilesProvider.overrideWithValue(files),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MascotWindow()),
    ));
    await frames(tester);

    // 1. Tareas diarias: añadir una con hora y días.
    await tapTooltip(tester, 'Tareas diarias');
    expect(container.read(mascotPanelProvider), MascotPanel.daily);
    await tester.tap(find.byKey(const ValueKey('daily-add')));
    await frames(tester);
    await tester.enterText(
        find.byKey(const ValueKey('daily-text')), 'Tomar agua');
    await tester.enterText(find.byKey(const ValueKey('daily-minute')), '30');
    await tester.ensureVisible(find.byKey(const ValueKey('daily-save')));
    await tester.tap(find.byKey(const ValueKey('daily-save')));
    await frames(tester);
    expect((daily.tasks.single.text, daily.tasks.single.minute),
        ('Tomar agua', 30));

    // 2. Calendario: elegir un día futuro y escribir directo.
    await tester.tap(find.text('Calendario'));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('cal-next')));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('cal-day-10')));
    await frames(tester);
    await tester.enterText(
        find.byKey(const ValueKey('cal-quick')), 'Cumple de Ana');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await frames(tester);
    expect(notes.notes.single.text, 'Cumple de Ana');
    await tester.scrollUntilVisible(find.text('Cumple de Ana'), 80,
        scrollable: find
            .ancestor(
                of: find.byKey(const ValueKey('cal-quick')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Cumple de Ana'), findsOneWidget);

    // 3. Cerrar el panel y abrir el chat tocando a la mascota.
    await tapTooltip(tester, 'Cerrar tareas diarias');
    expect(container.read(mascotPanelProvider), MascotPanel.none);
    await tester.tap(find.byKey(mascotKey));
    await frames(tester);
    expect(container.read(mascotPanelProvider), MascotPanel.chat);

    // 4. Pedir algo en el chat: se hace sin IA y responde sin emojis.
    await tester.enterText(find.byType(TextField).last, 'apunta comprar pan');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await frames(tester);
    expect(store.pending.single.text, 'comprar pan');
    expect(find.textContaining('comprar pan'), findsWidgets);
    expect(find.textContaining('📝'), findsNothing,
        reason: 'los mensajes se ven sin emojis');

    // 5. Ajustes: guardar una copia de seguridad.
    container.read(mascotPanelProvider.notifier).state = MascotPanel.settings;
    await frames(tester);
    final export = find.byKey(const ValueKey('backup-export'));
    await tester.scrollUntilVisible(export, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(export);
    await frames(tester);
    await tester.tap(export);
    await frames(tester);
    expect(files.saved.values.single, contains('Cumple de Ana'));
    expect(files.saved.values.single, contains('Tomar agua'));

    // 6. Esconderla con el botón del ojo.
    container.read(mascotPanelProvider.notifier).state = MascotPanel.none;
    await frames(tester);
    await tapTooltip(
        tester, 'Esconder (vuelve con «Oye…», ⌃⌥P o la barra superior)');
    expect(window.visible.value, isFalse);
    expect(container.read(mascotPanelProvider), MascotPanel.none);

    // 7. Restaurar la copia en un Mac «nuevo».
    SharedPreferences.setMockInitialValues({});
    final fresh = await SharedPreferences.getInstance();
    expect(
        await restoreBackup(fresh, files.saved.values.single), greaterThan(2));
    expect(CalendarStore(fresh).notes.single.text, 'Cumple de Ana');
    expect(DailyTaskStore(fresh).tasks.single.text, 'Tomar agua');
    expect(PersonalStore(fresh).pending.single.text, 'comprar pan');

    // Cerrar todo (los revisores de alarmas usan temporizadores).
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
