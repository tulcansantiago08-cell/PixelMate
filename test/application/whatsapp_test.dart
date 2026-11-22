import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';

void main() {
  ParsedCommand? p(String s) =>
      parseCommand(s, DateTime(2026, 11, 22), petName: 'James');

  test('frases', () {
    for (final (phrase, who, text) in [
      (
        'Oye James, mándale a Mamá por WhatsApp que llego tarde',
        'Mamá',
        'Llego tarde'
      ),
      (
        've a whatsapp y envía un mensaje a Juan Pérez diciendo que ya salí',
        'Juan Pérez',
        'Ya salí'
      ),
      (
        'escríbele a Ana por WhatsApp: nos vemos a las 8',
        'Ana',
        'Nos vemos a las 8'
      ),
      (
        'manda un mensaje por whatsapp a Carlos que mañana no voy',
        'Carlos',
        'Mañana no voy'
      ),
      ('envía un whatsapp a mi hermano', 'hermano', ''),
      (
        'envía un mensaje a negra que diga llego más tarde',
        'negra',
        'Llego más tarde'
      ),
      ('escríbele a Ana que ya voy', 'Ana', 'Ya voy'),
      (
        'mándale un mensaje a Juan que le digas que mañana no voy',
        'Juan',
        'Mañana no voy'
      ),
    ]) {
      final c = p(phrase)!;
      expect((c.intent, c.app, c.text), (AssistantIntent.whatsapp, who, text),
          reason: phrase);
    }
    expect(p('abre whatsapp')!.intent, AssistantIntent.open);
    final yt = p('Blessd en YouTube')!;
    expect((yt.intent, yt.text, yt.searchIn, yt.play),
        (AssistantIntent.open, 'Blessd', 'youtube', true));
    // Otras cosas con «escribe» o «manda» no son mensajes.
    for (final other in [
      'escribe un script de Python para sumar',
      'escribe un texto para mi clase sobre la fotosíntesis',
      'mándame un mensaje a las 5 para tomar agua',
      'escríbeme un mensaje de cumpleaños para mi mamá',
    ]) {
      expect(p(other)?.intent, isNot(AssistantIntent.whatsapp), reason: other);
    }
    // Varios destinatarios: la coma no corta el mensaje.
    final many = p('envía un whatsapp a Ana, Pedro y Luis que ya llegué')!;
    expect((many.app, many.text), ('Ana, Pedro y Luis', 'Ya llegué'));
  });

  test('el número con el prefijo del país', () {
    expect(whatsappNumber('+593 99 123 4567', 'EC'), '593991234567');
    expect(whatsappNumber('099 123 4567', 'EC'), '593991234567');
    expect(whatsappNumber('0034 600 11 22 33', 'EC'), '34600112233');
    expect(whatsappNumber('300 123 4567', 'CO'), '573001234567');
    expect(whatsappNumber('99 123 4567', 'XX'), '991234567');
  });

  group('ejecutor', () {
    late FakeMacActions mac;
    late AssistantExecutor ex;
    setUp(() {
      mac = FakeMacActions(apps: {'WhatsApp'})
        ..contacts.addAll(const [
          Contact('Mamá', phones: ['099 123 4567']),
          Contact('Ana López', phones: ['+593 98 000 0001']),
          Contact('Ana Ruiz', phones: ['+593 98 000 0002']),
          Contact('Pedro Sin Número'),
        ]);
      ex = AssistantExecutor(PersonalStore(), mac);
    });

    test('abre WhatsApp con el mensaje listo, sin enviarlo', () async {
      final reply =
          await ex.run(p('mándale a Mamá por WhatsApp que llego tarde')!);
      expect(reply, contains('pulsa Enter'));
      expect(mac.opened.single,
          'whatsapp://send?phone=593991234567&text=Llego%20tarde');
    });

    test('si hay varias, pregunta cuál', () async {
      expect(await ex.run(p('escríbele a Ana por WhatsApp: hola')!),
          contains('¿A cuál? Ana López, Ana Ruiz'));
      await ex.run(p('escríbele a Ana Ruiz por WhatsApp: hola')!);
      expect(mac.opened.single, contains('phone=593980000002'));
    });

    test('si no tengo su número: abre WhatsApp y copia el mensaje', () async {
      expect(await ex.run(p('mándale a Lucía por WhatsApp que hola')!),
          contains('No tengo a «Lucía»'));
      expect(mac.copied, 'Hola');
      expect(mac.opened.last, 'WhatsApp');
      expect(await ex.run(p('mándale a Pedro por WhatsApp que hola')!),
          contains('no tiene número'));
    });

    test('sin la app de WhatsApp, abre WhatsApp Web', () async {
      final noApp = FakeMacActions()
        ..contacts.add(const Contact('Mamá', phones: ['099 123 4567']));
      final r = await AssistantExecutor(PersonalStore(), noApp)
          .run(p('mándale a Lucía por WhatsApp que hola')!);
      expect(r, contains('Abrí WhatsApp'));
      expect(noApp.opened.single, 'https://web.whatsapp.com');
    });

    test('un contacto con emoji cuenta como el mismo nombre', () async {
      mac.contacts.addAll(const [
        Contact('Negra ❤️', phones: ['+593 98 000 0003']),
        Contact('Negra Sofía', phones: ['+593 98 000 0004']),
      ]);
      await ex.run(p('mándale a negra por WhatsApp que hola')!);
      expect(mac.opened.single, contains('phone=593980000003'));
    });

    test('sin permiso, lo dice', () async {
      mac.contactsAllowed = false;
      expect(await ex.run(p('mándale a Mamá por WhatsApp que hola')!),
          contains('Sin permiso para Contactos'));
      expect(mac.opened, isEmpty);
    });
  });
}
