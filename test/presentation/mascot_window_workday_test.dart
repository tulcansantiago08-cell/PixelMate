import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/mascot_window.dart';

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
    await tester.pumpWidget(ProviderScope(
      overrides: [workdayStoreProvider.overrideWithValue(store)],
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

    // Deja pasar los temporizadores de saludo y del globo.
    await tester.pump(const Duration(seconds: 10));
  });
}
