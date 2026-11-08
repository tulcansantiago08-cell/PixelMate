import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';
import 'package:pixelmate/presentation/stats/stats_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La mascota anima en bucle, así que no se puede usar pumpAndSettle.
Future<void> settleMenu(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('clic derecho inicia una jornada y muestra el temporizador',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = SqliteWorkdayStore.inMemory();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(store),
        detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
      ],
      child: const MaterialApp(home: MascotWindow()),
    ));

    final mascot = find.byKey(mascotKey);
    await tester.tap(mascot, buttons: kSecondaryButton);
    await settleMenu(tester);
    expect(find.text('Iniciar jornada'), findsOneWidget);

    await tester.tap(find.text('💼  8 horas'));
    await settleMenu(tester);

    expect(find.textContaining('Enfoque'), findsOneWidget);
    expect(find.textContaining('50:00'), findsOneWidget);
    expect(find.textContaining('¡A trabajar!'), findsOneWidget);
    expect(store.loadActive(), isNotNull);

    // Con jornada activa el menú ofrece pausar y finalizar.
    await tester.tap(mascot, buttons: kSecondaryButton);
    await settleMenu(tester);
    await tester.tap(find.text('⏸️  Pausar'));
    await settleMenu(tester);
    expect(find.textContaining('⏸'), findsWidgets);

    await tester.tap(mascot, buttons: kSecondaryButton);
    await settleMenu(tester);
    await tester.tap(find.text('⏹️  Finalizar jornada'));
    await settleMenu(tester);
    expect(store.loadActive(), isNull);
    expect(store.history(), hasLength(1));

    // El botón 📊 junto a la mascota abre y cierra las estadísticas.
    await tester.tap(find.byTooltip('Estadísticas'));
    await settleMenu(tester);
    expect(find.byType(StatsPanel), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar estadísticas'));
    await settleMenu(tester);
    expect(find.byType(StatsPanel), findsNothing);

    // El botón ⋯ abre el mismo menú que el clic derecho.
    await tester.tap(find.byTooltip('Menú: jornada, pausa…'));
    await settleMenu(tester);
    expect(find.text('Iniciar jornada'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settleMenu(tester);

    // Deja pasar los temporizadores de saludo y del globo.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets(
      'el menú ⋯ amplía la ventana mientras está abierto y permite '
      'cambiar el nombre', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final window = NoopMascotWindow();
    final settings = MascotSettings();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
        mascotWindowProvider.overrideWithValue(window),
        mascotSettingsProvider.overrideWithValue(settings),
      ],
      child: const MaterialApp(home: MascotWindow()),
    ));

    await tester.tap(find.byTooltip('Menú: jornada, pausa…'));
    await settleMenu(tester);
    expect(window.expandedCalls, [true], reason: 'ampliada con el menú');
    expect(find.text('✏️  Cambiar nombre'), findsOneWidget);

    await tester.tap(find.text('✏️  Cambiar nombre'));
    await settleMenu(tester);
    expect(window.expandedCalls, [true],
        reason: 'sigue ampliada con el diálogo abierto');
    await tester.enterText(
        find.byKey(const ValueKey('pet-name-field')), 'Michi');
    await tester.tap(find.byKey(const ValueKey('pet-name-save')));
    await settleMenu(tester);

    expect(settings.name, 'Michi');
    expect(find.textContaining('Desde ahora soy Michi'), findsOneWidget);
    expect(window.expandedCalls, [true, false],
        reason: 'vuelve a su tamaño al terminar');

    // Cerrar el menú sin elegir también la devuelve a su tamaño.
    await tester.tap(find.byTooltip('Menú: jornada, pausa…'));
    await settleMenu(tester);
    await tester.tapAt(const Offset(5, 5));
    await settleMenu(tester);
    expect(window.expandedCalls, [true, false, true, false]);

    await tester.pump(const Duration(seconds: 10));
  });
}
