import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_context.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/chat_controller.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/application/workday/workday_controller.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/mascot/rename_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('nombre de la mascota', () {
    test('limpia espacios, limita el largo y rechaza vacíos', () {
      expect(MascotSettings.cleanName('  Michi  '), 'Michi');
      expect(MascotSettings.cleanName('Don   Gato'), 'Don Gato');
      expect(MascotSettings.cleanName('   '), isNull);
      expect(MascotSettings.cleanName(null), isNull);
      expect(MascotSettings.cleanName('a' * 30)!.length,
          MascotSettings.maxNameLength);
    });

    test('se guarda; por defecto "Pixel"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = MascotSettings(prefs);
      expect(s.name, 'Pixel');
      expect(s.hasCustomName, isFalse);
      expect(await s.setName('  '), isNull);
      expect(s.name, 'Pixel', reason: 'un nombre vacío no se guarda');
      expect(await s.setName(' Luna '), 'Luna');
      final again = MascotSettings(prefs);
      expect(again.name, 'Luna');
      expect(again.hasCustomName, isTrue);
    });

    test('la IA y el chat usan el nombre', () async {
      final settings = MascotSettings();
      await settings.setName('Michi');
      final c = ProviderContainer(overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        mascotSettingsProvider.overrideWithValue(settings),
        assistantChoiceProvider
            .overrideWith((_) async => const AssistantChoice(null, 'x')),
      ]);
      addTearDown(c.dispose);
      expect(c.read(petNameProvider), 'Michi');
      expect(
          c.read(chatProvider).first.text, startsWith('¡Hola! Soy Michi 🐾'));

      await settings.setName('Nube');
      expect(c.read(petNameProvider), 'Nube');

      final context = describeContext(
        petName: 'Nube',
        now: DateTime(2026, 11, 8, 10),
        workday: WorkdayView.none,
        goal: null,
        progress: PlayerProgress.empty,
      );
      expect(context, startsWith('Te llamas Nube.'));
      expect(assistantInstructions, contains('Tu nombre viene en el estado'));
    });
  });

  testWidgets('el diálogo devuelve el nombre escrito o nada al cancelar',
      (tester) async {
    String? result = 'sin respuesta';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showRenameDialog(context, 'Pixel'),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Pixel'), findsOneWidget, reason: 'muestra el actual');
    await tester.enterText(
        find.byKey(const ValueKey('pet-name-field')), 'Michi');
    await tester.tap(find.byKey(const ValueKey('pet-name-save')));
    await tester.pumpAndSettle();
    expect(result, 'Michi');

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  test('el ícono de la app ya no es el de Flutter y tiene todos los tamaños',
      () {
    const dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final s in [16, 32, 64, 128, 256, 512, 1024]) {
      final bytes = File('$dir/app_icon_$s.png').readAsBytesSync();
      // Ancho en la cabecera IHDR del PNG.
      final width =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      expect(width, s, reason: 'app_icon_$s.png');
    }
  });
}
