import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_actions.dart';
import 'package:pixelmate/application/assistant/chat_assistant.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';

void main() {
  final now = DateTime(2026, 11, 17, 10);

  group('normalizeRequest (lo que llega del dictado)', () {
    test('quita saludo, nombre, punto final y "por favor"', () {
      expect(normalizeRequest('Pixel, abre Spotify.'), 'abre Spotify');
      expect(normalizeRequest('Oye Luna abre Spotify', petName: 'Luna'),
          'abre Spotify');
      expect(normalizeRequest('Abre Spotify, por favor.'), 'Abre Spotify');
      expect(normalizeRequest('Hola Pixel, ¿cómo estás?'), '¿cómo estás?');
    });

    test('las preguntas amables pasan a órdenes', () {
      expect(normalizeRequest('¿Puedes abrir Spotify?'), 'abre Spotify');
      expect(normalizeRequest('¿Me puedes recordar en 5 minutos estirarme?'),
          'recuérdame en 5 minutos estirarme');
      expect(normalizeRequest('Quiero escuchar Despacito.'),
          'reproduce Despacito');
    });
  });

  group('parseCommand con frases dictadas', () {
    for (final (text, intent) in [
      ('Pixel, abre Spotify.', AssistantIntent.open),
      ('Oye, abre Spotify', AssistantIntent.open),
      ('¿Puedes abrir Spotify?', AssistantIntent.open),
      ('Abre Spotify, por favor.', AssistantIntent.open),
      ('Pon Despacito en YouTube.', AssistantIntent.open),
      ('Quiero escuchar Despacito.', AssistantIntent.open),
      ('Pixel, recuérdame en 10 minutos tomar agua.', AssistantIntent.remind),
      ('¿Me puedes recordar en 10 minutos tomar agua?', AssistantIntent.remind),
      ('Apunta comprar leche.', AssistantIntent.addTask),
      ('Modo discoteca.', AssistantIntent.danceStart),
    ]) {
      test(text, () => expect(parseCommand(text, now)?.intent, intent));
    }

    test('el texto de la orden no arrastra la puntuación', () {
      expect(parseCommand('Abre Spotify, por favor.', now)?.text, 'Spotify');
      expect(parseCommand('Pon Despacito en YouTube.', now)?.text, 'Despacito');
    });

    test('una charla sigue yendo a la IA', () {
      expect(parseCommand('Hola Pixel, ¿cómo estás?', now), isNull);
    });
  });

  group('abrir y buscar', () {
    for (final (text, query, site, browser, play) in [
      ('Abre Safari y busca gatos.', 'gatos', 'google', 'Safari', false),
      (
        'Abre Brave, busca recetas de pasta',
        'recetas de pasta',
        'google',
        'Brave',
        false
      ),
      ('Abre Safari para buscar el clima', 'clima', 'google', 'Safari', false),
      ('Abre YouTube y busca Bad Bunny', 'Bad Bunny', 'youtube', null, false),
      ('Abre YouTube y pon Despacito', 'Despacito', 'youtube', null, true),
      ('Abre Spotify y pon Bad Bunny', 'Bad Bunny', 'spotify', null, true),
      ('Busca cómo hacer pan', 'cómo hacer pan', 'google', null, false),
      ('Busca gatos en Safari', 'gatos', 'google', 'Safari', false),
      ('Busca en Google gatos', 'gatos', 'google', null, false),
    ]) {
      test(text, () {
        final c = parseCommand(text, now)!;
        expect(c.intent, AssistantIntent.open);
        expect(c.text, query);
        expect(c.searchIn, site);
        expect(c.browser, browser);
        expect(c.play, play);
      });
    }

    test('sin nada que buscar, solo abre', () {
      final c = parseCommand('Abre Safari y busca', now)!;
      expect(c.text, 'Safari');
      expect(c.searchIn, isNull);
    });
  });

  group('workdayCommand', () {
    for (final (text, action) in [
      ('Empieza mi jornada.', AssistantAction.startWork),
      ('Pixel, empieza una jornada de estudio.', AssistantAction.startStudy),
      ('Vamos a estudiar', AssistantAction.startStudy),
      ('Inicia la sesión de juego', AssistantAction.startGaming),
      ('Pausa.', AssistantAction.pause),
      ('Pausa la jornada', AssistantAction.pause),
      ('Reanuda la jornada.', AssistantAction.resume),
      ('Termina la jornada', AssistantAction.finish),
      ('Cambia mi meta a 6 horas', AssistantAction.setGoal),
      ('Muéstrame mis estadísticas', AssistantAction.openStats),
    ]) {
      test(text, () => expect(workdayCommand(text)?.action, action));
    }

    test('lee las horas', () {
      expect(workdayCommand('Empieza mi jornada de 3 horas')?.hours, 3);
    });

    test('no confunde otras frases', () {
      expect(workdayCommand('¿Cuánto me falta?'), isNull);
      expect(workdayCommand('Para de bailar'), isNull);
      expect(workdayCommand('Mi meta es ser feliz'), isNull);
    });
  });
}
