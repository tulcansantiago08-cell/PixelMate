import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/voice.dart';

class FakeVoice implements VoicePort {
  final events$ = StreamController<VoiceEvent>.broadcast(sync: true);
  String? startResult;
  int starts = 0, stops = 0, cancels = 0;
  final spoken = <String>[];

  @override
  Stream<VoiceEvent> get events => events$.stream;
  @override
  Future<String?> start() async {
    starts++;
    return startResult;
  }

  final wakes = <String>[];
  String? wakeResult;
  int wakeStops = 0;
  final strictWakes = <bool>[];
  @override
  Future<String?> startWake(String name, {bool strict = false}) async {
    wakes.add(name);
    strictWakes.add(strict);
    return wakeResult;
  }

  @override
  Future<void> stopWake() async => wakeStops++;

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stopSpeaking() async {}

  void say(VoiceEventType type, [String text = '']) =>
      events$.add(VoiceEvent(type, text));
}

void main() {
  late FakeVoice port;
  late List<String> heard;
  late bool speak;
  late VoiceController voice;

  setUp(() {
    port = FakeVoice();
    heard = [];
    speak = true;
    voice = VoiceController(
      port,
      onHeard: (text) async {
        heard.add(text);
        return '¡Listo! 🐾 Te lo recuerdo a las 5 ⏰';
      },
      speakReplies: () => speak,
      silence: const Duration(milliseconds: 30),
      waitForSpeech: const Duration(milliseconds: 60),
    );
  });

  tearDown(() => voice.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('escucha, muestra lo entendido y manda la frase final', () async {
    await voice.listen();
    expect(voice.state.listening, isTrue);
    port.say(VoiceEventType.partial, 'recuérdame');
    expect(voice.state.heard, 'recuérdame');
    port.say(VoiceEventType.done, 'Recuérdame llamar a mamá');
    await settle();
    await settle();
    expect(heard, ['Recuérdame llamar a mamá']);
    expect(voice.state.status, VoiceStatus.idle);
    expect(port.spoken, ['¡Listo! Te lo recuerdo a las 5']);
  });

  test('no lee la respuesta si está desactivado', () async {
    speak = false;
    await voice.listen();
    port.say(VoiceEventType.done, 'hola');
    await settle();
    await settle();
    expect(heard, ['hola']);
    expect(port.spoken, isEmpty);
  });

  test('al callarte deja de escuchar sola', () async {
    await voice.listen();
    port.say(VoiceEventType.partial, 'abre Spotify');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(port.stops, 1);
  });

  test('si nunca hablas, deja de escuchar y lo dice', () async {
    await voice.listen();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(port.stops, 1);
    port.say(VoiceEventType.end);
    await settle();
    expect(heard, isEmpty);
    expect(voice.state.problem, contains('No te escuché'));
  });

  test('si termina sin texto final usa lo que entendió', () async {
    await voice.listen();
    port.say(VoiceEventType.partial, 'qué hora es');
    port.say(VoiceEventType.end);
    await settle();
    expect(heard, ['qué hora es']);
  });

  test('pulsar otra vez termina la frase', () async {
    await voice.toggle();
    expect(port.starts, 1);
    await voice.toggle();
    expect(port.stops, 1);
  });

  test('sin permiso explica dónde activarlo', () async {
    port.startResult = 'mic-denied';
    await voice.listen();
    expect(voice.state.status, VoiceStatus.idle);
    expect(voice.state.problem, contains('Micrófono'));
    port.startResult = 'speech-denied';
    await voice.listen();
    expect(voice.state.problem, contains('Reconocimiento de voz'));
  });

  test('cancelar no manda nada', () async {
    await voice.listen();
    port.say(VoiceEventType.partial, 'algo');
    await voice.cancel();
    port.say(VoiceEventType.done, 'algo');
    await settle();
    expect(port.cancels, 1);
    expect(heard, isEmpty);
  });

  group('«oye <nombre>»', () {
    test('espera el nombre y vuelve a esperarlo tras responder', () async {
      await voice.configureWake(enabled: true, name: 'James');
      expect(port.wakes, ['James']);
      port.say(VoiceEventType.wake, 'abre Spotify');
      expect(voice.state.listening, isTrue);
      expect(voice.state.heard, 'abre Spotify');
      port.say(VoiceEventType.done, 'abre Spotify');
      await settle();
      await settle();
      expect(heard, ['abre Spotify']);
      expect(port.wakes, ['James', 'James']);
    });

    test('solo el nombre: espera a que digas algo', () async {
      await voice.configureWake(enabled: true, name: 'James');
      port.say(VoiceEventType.wake);
      expect(voice.state.listening, isTrue);
      port.say(VoiceEventType.partial, 'qué hora es');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(port.stops, 1);
    });

    test('el modo estricto se pasa al Mac y cambiarlo vuelve a empezar',
        () async {
      await voice.configureWake(enabled: true, name: 'James');
      await voice.configureWake(enabled: true, name: 'James', strict: true);
      expect(port.strictWakes, [false, true]);
      expect(port.wakeStops, 1, reason: 'para la escucha anterior');
    });

    test('apagarlo deja de esperar', () async {
      await voice.configureWake(enabled: true, name: 'James');
      await voice.configureWake(enabled: false, name: 'James');
      expect(port.wakeStops, 1);
    });

    test('sin reconocimiento en el Mac explica qué activar', () async {
      port.wakeResult = 'offline';
      await voice.configureWake(enabled: true, name: 'James');
      expect(voice.wakeEnabled, isFalse);
      expect(voice.state.problem, contains('Dictado'));
    });
  });

  test('VoiceEvent.fromMap', () {
    final e = VoiceEvent.fromMap({'type': 'done', 'text': 'hola'});
    expect(e?.type, VoiceEventType.done);
    expect(e?.text, 'hola');
    expect(VoiceEvent.fromMap({'type': 'raro'}), isNull);
    expect(VoiceEvent.fromMap('x'), isNull);
  });

  group('speechText', () {
    test('quita emojis y símbolos', () {
      expect(speechText('🪩 ¡Modo discoteca! Bailo un minuto 💃🕺'),
          '¡Modo discoteca! Bailo un minuto');
      expect(speechText('«para de bailar» • **ya**'), 'para de bailar ya');
    });

    test('corta los textos largos en un final de frase', () {
      final long = '${'Una frase bastante larga. ' * 30}fin';
      final s = speechText(long, maxLength: 100);
      expect(s.length, lessThanOrEqualTo(100));
      expect(s.endsWith('.'), isTrue);
    });
  });
}
