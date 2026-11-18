import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/assistant_executor.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';

void main() {
  final now = DateTime(2026, 11, 17, 10);
  ParsedCommand? p(String text) => parseCommand(text, now);

  group('volumen', () {
    for (final (text, action, n) in [
      ('Sube el volumen.', 'up', 15),
      ('Súbele un poco', 'up', 8),
      ('Súbelo', 'up', 15),
      ('Sube la música', 'up', 15),
      ('Más volumen', 'up', 15),
      ('Sube el volumen 20', 'up', 20),
      ('Baja el volumen', 'down', 15),
      ('Bájale mucho', 'down', 30),
      ('Bájalo', 'down', 15),
      ('Más bajo', 'down', 15),
      ('Pixel, ¿puedes bajar el volumen?', 'down', 15),
      ('Volumen al 50', 'set', 50),
      ('Pon el volumen en 30%', 'set', 30),
      ('Sube el volumen al 80', 'set', 80),
      ('Ponlo a tope', 'set', 100),
      ('Baja el volumen al mínimo', 'set', 0),
    ]) {
      test(text, () {
        final c = p(text);
        expect(c?.intent, AssistantIntent.volume);
        expect(c?.text, action);
        expect(c?.number, n);
      });
    }

    for (final (text, action) in [
      ('Silencia', 'mute'),
      ('Quita el sonido', 'mute'),
      ('Ponlo en silencio', 'mute'),
      ('Activa el sonido', 'unmute'),
      ('Quita el silencio', 'unmute'),
      ('¿A cuánto está el volumen?', 'get'),
    ]) {
      test(text, () {
        expect(p(text)?.intent, AssistantIntent.volume);
        expect(p(text)?.text, action);
      });
    }

    test('no confunde otras órdenes', () {
      expect(p('Baja el brillo'), isNull);
      expect(p('Para de bailar')?.intent, AssistantIntent.danceStop);
      expect(p('Pon Despacito en YouTube')?.intent, AssistantIntent.open);
    });
  });

  group('apps', () {
    test('abrir con nombres en español', () {
      for (final text in [
        'Abre Notas',
        'abre notas.',
        'Ábreme la app de Notas',
        '¿Puedes abrir Notas?',
        'Pixel, abre las notas'
      ]) {
        final c = p(text);
        expect(c?.intent, AssistantIntent.open, reason: text);
        expect(fold(c!.text).replaceFirst('las ', ''), 'notas', reason: text);
      }
    });

    test('cerrar', () {
      expect(p('Cierra Spotify.')?.intent, AssistantIntent.closeApp);
      expect(p('Cierra Spotify.')?.text, 'Spotify');
      expect(p('¿Puedes cerrar Notas?')?.text, 'Notas');
      expect(p('Cierra la jornada')?.intent, isNot(AssistantIntent.closeApp));
    });
  });

  group('música, apps y nombre', () {
    for (final (text, action, app) in [
      ('Pausa la música', 'pause', null),
      ('Pausa Spotify', 'pause', 'Spotify'),
      ('Para la canción.', 'pause', null),
      ('Dale play', 'play', null),
      ('Reanuda la música', 'play', null),
      ('Siguiente canción', 'next', null),
      ('Pasa la canción', 'next', null),
      ('Pon la siguiente en Spotify', 'next', 'Spotify'),
      ('La anterior', 'previous', null),
      ('Canción anterior', 'previous', null),
      ('¿Qué canción es esta?', 'now', null),
      ('Pausa Apple Music', 'pause', 'Música'),
    ]) {
      test(text, () {
        final c = p(text);
        expect(c?.intent, AssistantIntent.media);
        expect(c?.text, action);
        expect(c?.app, app);
      });
    }

    test('pausa a secas sigue siendo la jornada', () {
      expect(p('Pausa'), isNull);
    });

    test('abrir Apple Music y ocultar o listar apps', () {
      expect(p('Abre Apple Music')?.text, 'Apple Music');
      expect(p('Oculta Safari')?.intent, AssistantIntent.hideApp);
      expect(p('¿Qué apps tengo abiertas?')?.intent, AssistantIntent.listApps);
    });

    test('activar y apagar «oye <nombre>»', () {
      for (final text in [
        'Activa el oye James',
        'Activa «Oye James»',
        'Escúchame siempre',
        'Activa la palabra de activación',
        'Pon el modo hola James',
      ]) {
        expect(p(text)?.intent, AssistantIntent.wakeWord, reason: text);
        expect(p(text)?.text, 'on', reason: text);
      }
      for (final text in ['Desactiva el oye James', 'Deja de escucharme']) {
        expect(p(text)?.text, 'off', reason: text);
      }
      expect(p('Hola James, ¿cómo estás?'), isNull);
    });

    test('cómo llamar al usuario', () {
      expect(p('Llámame Santi')?.intent, AssistantIntent.setUserName);
      expect(p('Me llamo Santiago Tulcán')?.text, 'Santiago Tulcán');
      expect(p('¿Puedes llamarme Santi?')?.text, 'Santi');
      expect(p('Llámame en 10 minutos'), isNull);
      expect(cleanUserName('santi'), 'Santi');
    });
  });

  group('ejecutor', () {
    late FakeMacActions mac;
    late AssistantExecutor run;
    setUp(() {
      mac = FakeMacActions(apps: {'Notas'})..running = {'Spotify'};
      run = AssistantExecutor(PersonalStore(), mac, now: () => now);
    });

    test('sube, baja, fija y silencia', () async {
      expect(await run.run(p('Sube el volumen')!), '🔉 Volumen al 65 %.');
      expect(await run.run(p('Bájale un poco')!), '🔉 Volumen al 57 %.');
      expect(await run.run(p('Ponlo a tope')!), '🔊 Volumen al 100 %.');
      expect(await run.run(p('Súbele')!), '🔊 Ya está al máximo (100 %).');
      expect(await run.run(p('Silencia')!), '🔇 Silencié el sonido.');
      expect(mac.muted, isTrue);
      expect(
          await run.run(p('Activa el sonido')!), '🔊 Sonido activado (100 %).');
    });

    test('salida que no deja cambiar el volumen', () async {
      mac.fixedVolume = true;
      expect(await run.run(p('Sube el volumen')!), contains('no deja'));
    });

    test('controla la música', () async {
      expect(await run.run(p('Pausa la música')!), contains('No veo Spotify'));
      mac.players = {'Spotify'};
      expect(await run.run(p('Pausa la música')!), '⏸️ Pausé Spotify.');
      expect(await run.run(p('Siguiente canción')!),
          '⏭️ Siguiente canción en Spotify.');
      expect(await run.run(p('¿Qué canción suena?')!),
          '🎵 Suena «Despacito — Luis Fonsi» en Spotify.');
      mac.mediaDenied = true;
      expect(await run.run(p('Dale play')!), contains('Automatización'));
    });

    test('lista y oculta apps', () async {
      expect(
          await run.run(p('¿Qué apps tengo abiertas?')!), contains('Spotify'));
      expect(await run.run(p('Oculta Spotify')!), '🙈 Oculté Spotify.');
    });

    test('activa «oye <nombre>»', () async {
      bool? wake;
      run = AssistantExecutor(PersonalStore(), mac,
          now: () => now,
          onWakeWord: (on) async {
            wake = on;
            return 'James';
          });
      expect(await run.run(p('Activa el oye James')!), contains('Oye James'));
      expect(wake, isTrue);
      expect(await run.run(p('Deja de escucharme')!), contains('Ya no'));
      expect(wake, isFalse);
    });

    test('guarda el nombre del usuario', () async {
      String? saved;
      run = AssistantExecutor(PersonalStore(), mac,
          now: () => now, onUserName: (n) async => saved = n);
      expect(await run.run(p('Llámame santi')!), contains('Santi'));
      expect(saved, 'Santi');
    });

    test('cierra una app abierta, después de preguntar', () async {
      expect(await run.run(p('Cierra Spotify')!),
          startsWith('⚠️ ¿Cierro Spotify?'));
      expect(run.awaitingConfirmation, isTrue);
      expect(await run.confirm(true), '👋 Cerré Spotify.');
      expect(run.awaitingConfirmation, isFalse);
      await run.run(p('Cierra Spotify')!);
      expect(await run.confirm(true), contains('No veo'));
    });

    test('«no» la deja abierta', () async {
      await run.run(p('Cierra Spotify')!);
      expect(await run.confirm(false), '👌 Vale, no lo hago.');
      expect(await run.confirm(true), contains('No tenía nada pendiente'));
    });

    test('otra orden cancela la pregunta', () async {
      await run.run(p('Cierra Spotify')!);
      await run.run(p('sube el volumen')!);
      expect(run.awaitingConfirmation, isFalse);
    });

    test('sí y no', () {
      for (final yes in ['sí', 'Sí, ciérrala', 'dale', 'claro!', 'ok']) {
        expect(yesNo(yes), isTrue, reason: yes);
      }
      for (final no in ['no', 'mejor no', 'No, gracias', 'cancela']) {
        expect(yesNo(no), isFalse, reason: no);
      }
      expect(yesNo('sí quiero un chiste'), isNull);
    });
  });
}
