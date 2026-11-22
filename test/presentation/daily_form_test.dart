import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/daily_tasks.dart';
import 'package:pixelmate/presentation/assistant/daily_tasks_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('al añadir, el cursor va al texto; vacío avisa; lleno guarda',
      (tester) async {
    for (final c in ['com.pixelmate/app', 'com.pixelmate/sound']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DailyTaskStore(prefs);
    await tester.binding.setSurfaceSize(const Size(340, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [dailyTaskStoreProvider.overrideWith((_) => store)],
      child: MaterialApp(home: Scaffold(body: DailyTasksPanel(onClose: () {}))),
    ));
    await tester.tap(find.byKey(const ValueKey('daily-add')));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('daily-text')));
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('daily-save')));
    await tester.tap(find.byKey(const ValueKey('daily-save')));
    await tester.pumpAndSettle();
    expect(find.text('Escribe qué tienes que hacer.'), findsOneWidget);
    expect(store.tasks, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('daily-text')), 'Reunión virtual');
    await tester.ensureVisible(find.byKey(const ValueKey('daily-save')));
    await tester.tap(find.byKey(const ValueKey('daily-save')));
    await tester.pumpAndSettle();
    expect(DailyTaskStore(prefs).tasks.single.text, 'Reunión virtual');
  });
}
