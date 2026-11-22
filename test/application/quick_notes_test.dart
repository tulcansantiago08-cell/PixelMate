import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:pixelmate/application/assistant/voice.dart';
import 'package:pixelmate/presentation/assistant/pending_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 21, 10);
  ParsedCommand? p(String s) => parseCommand(s, now, petName: 'James');

  test('frases de nota', () {
    for (final (phrase, text) in [
      (
        'toma nota: mañana preguntar al profe por el examen',
        'Mañana preguntar al profe por el examen'
      ),
      (
        'Oye James, guarda esta idea: una app para regar plantas',
        'Una app para regar plantas'
      ),
      ('nota rápida reunión con Ana fue bien', 'Reunión con Ana fue bien'),
      ('toma nota de que el wifi es pixel123', 'El wifi es pixel123'),
    ]) {
      final c = p(phrase);
      expect((c?.intent, c?.text), (AssistantIntent.note, text),
          reason: phrase);
    }
  });

  test('«anota que tengo que…» apunta la tarea limpia', () {
    expect(p('anota que tengo que comprar pan')!.text, 'comprar pan');
    expect(p('apunta que hay que pagar la luz')!.text, 'pagar la luz');
    expect(p('apunta comprar leche')!.text, 'comprar leche');
  });

  test('se guarda y se borra', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PersonalStore(prefs);
    final ex = AssistantExecutor(store, FakeMacActions(), now: () => now);
    expect(await ex.run(p('toma nota: llevar la calculadora')!),
        contains('Nota guardada'));
    final again = PersonalStore(prefs);
    expect(again.notes.single.text, 'Llevar la calculadora');
    await again.removeNote(again.notes.single.id);
    expect(again.notes, isEmpty);
  });

  test('al dictar una nota espera más', () {
    expect(isDictatedNote('toma nota de que mañana'), isTrue);
    expect(isDictatedNote('abre Safari'), isFalse);
  });

  testWidgets('las notas se ven en Pendientes', (tester) async {
    final store = PersonalStore();
    await store.addNote('Una app para regar plantas');
    await tester.pumpWidget(ProviderScope(
      overrides: [personalStoreProvider.overrideWithValue(store)],
      child: MaterialApp(home: Scaffold(body: PendingPanel(onClose: () {}))),
    ));
    await tester.pump();
    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Una app para regar plantas'), findsOneWidget);
  });
}
