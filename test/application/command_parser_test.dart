import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';

/// Martes 10 de noviembre de 2026, 7:55.
final now = DateTime(2026, 11, 10, 7, 55);

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

void main() {
  group('cuándo', () {
    test('relativo', () {
      expect(parseWhen('en 20 minutos', now),
          now.add(const Duration(minutes: 20)));
      expect(parseWhen('en una hora', now), now.add(const Duration(hours: 1)));
      expect(parseWhen('dentro de 2 horas', now),
          now.add(const Duration(hours: 2)));
      expect(parseWhen('en media hora', now),
          now.add(const Duration(minutes: 30)));
      expect(
          parseWhen('en cinco min', now), now.add(const Duration(minutes: 5)));
    });

    test('a una hora concreta', () {
      expect(parseWhen('a las 5 de la tarde', now), at(10, 17));
      expect(parseWhen('a las 5', now), at(10, 17), reason: '5 sin más: tarde');
      expect(parseWhen('a las 10', now), at(10, 10));
      expect(parseWhen('a las 9:30', now), at(10, 9, 30));
      expect(parseWhen('a las 9 y media', now), at(10, 9, 30));
      expect(parseWhen('a las 17:45', now), at(10, 17, 45));
      expect(parseWhen('a las 7 de la mañana', now), at(11, 7),
          reason: 'ya pasó hoy: mañana');
      expect(parseWhen('al mediodía', now), at(10, 12));
      expect(parseWhen('esta noche', now), at(10, 21));
    });

    test('con día', () {
      expect(parseWhen('mañana a las 9', now), at(11, 9),
          reason: '9 de la mañana, no 21');
      expect(parseWhen('mañana a las 10', now), at(11, 10));
      expect(parseWhen('pasado mañana a las 4', now), at(12, 16));
      expect(parseWhen('mañana', now), at(11, 9), reason: 'solo el día: 9:00');
      expect(parseWhen('el viernes a las 11', now), at(13, 11));
      expect(parseWhen('el martes a las 11', now), at(17, 11),
          reason: 'hoy es martes: el próximo');
      expect(parseWhen('hoy a las 8 de la noche', now), at(10, 20));
    });

    test('"de la mañana" no es "mañana"', () {
      expect(parseWhen('a las 9 de la mañana', now), at(10, 9));
    });

    test('sin hora', () {
      expect(parseWhen('llamar a mamá', now), isNull);
      expect(parseWhen('a las 25', now), isNull);
    });
  });

  group('órdenes', () {
    ParsedCommand? p(String s) => parseCommand(s, now);

    test('recordatorios', () {
      var c = p('Recuérdame en 20 minutos llamar a mamá')!;
      expect(c.intent, AssistantIntent.remind);
      expect(c.text, 'llamar a mamá');
      expect(c.when, now.add(const Duration(minutes: 20)));

      c = p('recuérdame a las 5 de la tarde ir al gimnasio')!;
      expect(c.text, 'ir al gimnasio');
      expect(c.when, at(10, 17));

      c = p('recuérdame mañana a las 9 tomar la pastilla')!;
      expect(c.text, 'tomar la pastilla');
      expect(c.when, at(11, 9));

      c = p('avísame que saque la ropa en media hora')!;
      expect(c.text, 'saque la ropa');
      expect(c.when, now.add(const Duration(minutes: 30)));

      c = p('recuérdame comprar pan')!;
      expect(c.text, 'comprar pan');
      expect(c.when, isNull, reason: 'sin hora: se pregunta');
    });

    test('tareas', () {
      var c = p('añade a mis tareas pagar la luz')!;
      expect(c.intent, AssistantIntent.addTask);
      expect(c.text, 'pagar la luz');
      expect(p('apunta llamar al banco')!.text, 'llamar al banco');
      expect(p('anota: revisar el correo')!.text, 'revisar el correo');
      expect(p('agrega comprar leche a mi lista')!.text, 'comprar leche');
      expect(p('¿Qué tengo pendiente?')!.intent, AssistantIntent.showPending);
      expect(p('muéstrame mis tareas')!.intent, AssistantIntent.showPending);
      c = p('marca la 2 como hecha')!;
      expect(c.intent, AssistantIntent.completeTask);
      expect(c.number, 2);
      expect(p('ya terminé la segunda')!.number, 2);
    });

    test('abrir', () {
      expect(p('abre spotify')!.text, 'spotify');
      expect(p('Abre YouTube')!.text, 'YouTube');
      expect(p('ábreme la calculadora')!.text, 'calculadora');
      expect(p('abre la página de github')!.text, 'github');
      expect(p('abre la app Notas')!.text, 'Notas');
    });

    test('buscar en YouTube, Spotify o Google y elegir navegador', () {
      var c = p('ábreme una canción en youtube en brave')!;
      expect((
        c.intent,
        c.text,
        c.browser,
        c.searchIn
      ), (
        AssistantIntent.open,
        'youtube',
        'Brave',
        null
      ), reason: 'sin canción: abre YouTube en Brave');
      c = p('abre una canción de Bad Bunny en YouTube en Brave')!;
      expect(
          (c.text, c.browser, c.searchIn), ('Bad Bunny', 'Brave', 'youtube'));
      c = p('abre en brave la canción Flowers de Miley Cyrus en youtube')!;
      expect((c.text, c.browser, c.searchIn),
          ('Flowers de Miley Cyrus', 'Brave', 'youtube'));
      c = p('pon Despacito en YouTube')!;
      expect((c.text, c.browser, c.searchIn), ('Despacito', null, 'youtube'));
      expect(
          p('ponme Bohemian Rhapsody en YouTube')!.text, 'Bohemian Rhapsody');
      c = p('busca recetas de pasta en google')!;
      expect((c.text, c.searchIn), ('recetas de pasta', 'google'));
      expect(p('reproduce Shakira en spotify')!.searchIn, 'spotify');
      c = p('abre github en safari')!;
      expect((c.text, c.browser, c.searchIn), ('github', 'Safari', null));
      expect(p('abre brave')!.text, 'brave', reason: 'abrir el navegador');
      expect(p('pon mi meta en 3 horas'), isNull);
    });

    test('reproducir: "reproduce/pon/toca" dan play; "abre/busca" no', () {
      var c = p('reproduce Tití me preguntó de Bad Bunny en Brave')!;
      expect((c.text, c.browser, c.searchIn, c.play),
          ('Tití me preguntó de Bad Bunny', 'Brave', 'youtube', true));
      c = p('reproduce despacito')!;
      expect((c.text, c.searchIn, c.play), ('despacito', 'youtube', true),
          reason: 'sin sitio: YouTube');
      expect(p('toca algo de Shakira')!.text, 'Shakira');
      expect(p('pon la canción Flowers en youtube')!.play, isTrue);
      expect(p('busca recetas en youtube')!.play, isFalse);
      expect(p('abre una canción de Bad Bunny en YouTube en Brave')!.play,
          isFalse);
      expect(p('reproduce Shakira en spotify')!.searchIn, 'spotify');
      expect(p('pon una alarma'), isNull);
    });

    test('agenda y eventos', () {
      expect(p('¿qué tengo hoy en el calendario?')!.intent,
          AssistantIntent.showAgenda);
      final tomorrow = p('¿qué tengo mañana?')!;
      expect(tomorrow.intent, AssistantIntent.showAgenda);
      expect(tomorrow.dayOffset, 1);
      final e = p('crea una reunión con Ana mañana a las 10')!;
      expect(e.intent, AssistantIntent.createEvent);
      expect(e.text, 'Reunión con Ana');
      expect(e.when, at(11, 10));
      expect(p('agenda una cita con el dentista el viernes a las 4')!.when,
          at(13, 16));
      expect(p('añade una reunión de equipo hoy a las 3')!.intent,
          AssistantIntent.createEvent,
          reason: '"añade una reunión" es un evento, no una tarea');
    });

    test('entiende la orden aunque el verbo esté mal escrito', () {
      final c = p('reprode paradixe de feid en youtube en brave')!;
      expect((c.text, c.browser, c.searchIn, c.play),
          ('paradixe de feid', 'Brave', 'youtube', true));
      expect(p('reprodusca despacito')!.play, isTrue);
      expect(p('reproduse shakira')!.text, 'shakira');
      expect(
          p('recuerdamee en 10 minutos sacar la ropa')!.text, 'sacar la ropa');
      expect(p('abrre spotify')!.text, 'spotify');
      expect(p('apuntaa comprar pan')!.intent, AssistantIntent.addTask);
      // Palabras cortas o parecidas que no son órdenes.
      expect(p('abro la ventana'), isNull);
      expect(p('quiero descansar'), isNull);
      expect(fixVerbTypo('hola, ¿cómo estás?'), 'hola, ¿cómo estás?');
      expect(fixVerbTypo('reprode algo'), 'reproduce algo');
    });

    test('crear código: también dentro de "abre VS Code y…"', () {
      var c =
          p('abre visual studio code y haz un script de python para sumar')!;
      expect((
        c.intent,
        c.text,
        c.language,
        c.editor
      ), (
        AssistantIntent.createCode,
        'sumar',
        'python',
        'Visual Studio Code'
      ));
      c = p('abre vs y haz un script de python para sumar')!;
      expect((c.text, c.editor), ('sumar', 'Visual Studio Code'));
      c = p('hazme un programa en javascript que cuente del 1 al 10')!;
      expect((c.text, c.language, c.editor),
          ('cuente del 1 al 10', 'javascript', null));
      expect(
          p('crea un script para sumar en python en vs code')!.text, 'sumar');
      expect(p('escribe un codigo que ordene una lista')!.language, 'python',
          reason: 'sin lenguaje: Python');
      expect(p('abre visual studio code')!.intent, AssistantIntent.open);
      expect(p('programa una reunión mañana a las 10')!.intent,
          AssistantIntent.createEvent);
      expect(p('haz un script'), isNull, reason: 'falta qué debe hacer');
    });

    test('la conversación no es una orden', () {
      for (final s in [
        '¿cómo estás?',
        'cuéntame un chiste',
        'estoy cansado hoy',
        'gracias!',
        'hola',
        '¿cuánto me falta para el descanso?',
        'pon mi meta en 3 horas',
        'empieza una jornada de estudio',
      ]) {
        expect(p(s), isNull, reason: s);
      }
      expect(mentionsAssistantAction('¿cómo estás?'), isFalse);
      expect(mentionsAssistantAction('cuéntame un chiste'), isFalse);
      expect(mentionsAssistantAction('ya terminé el informe'), isTrue);
    });
  });
}
