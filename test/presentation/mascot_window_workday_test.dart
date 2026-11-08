import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
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

    final mascot = find.byType(CustomPaint).last;
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
}
