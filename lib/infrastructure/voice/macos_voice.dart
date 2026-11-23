import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/assistant/voice.dart';
import '../../core/i18n/language.dart';

/// Micrófono y voz del Mac (ver `Voice.swift`).
class MacosVoice implements VoicePort {
  static const _channel = MethodChannel('com.pixelmate/voice');
  static const _events = EventChannel('com.pixelmate/voice/events');

  late final Stream<VoiceEvent> _stream = _events
      .receiveBroadcastStream()
      .map(VoiceEvent.fromMap)
      .where((e) => e != null)
      .cast<VoiceEvent>();

  @override
  Stream<VoiceEvent> get events => _stream;

  @override
  Future<String?> start() async {
    try {
      return await _channel.invokeMethod<String>('start', _lang);
    } catch (e) {
      debugPrint('Voz: $e');
      return 'unavailable';
    }
  }

  @override
  Future<String?> startWake(String name, {bool strict = false}) async {
    try {
      return await _channel
          .invokeMethod<String>('startWake', {'name': name, 'strict': strict, ..._lang});
    } catch (e) {
      debugPrint('Voz: $e');
      return 'unavailable';
    }
  }

  @override
  Future<void> stopWake() => _call('stopWake');

  @override
  Future<void> stop() => _call('stop');

  @override
  Future<void> cancel() => _call('cancel');

  @override
  Future<void> speak(String text) => _call('speak', {'text': text, ..._lang});

  /// Idioma de la app para el reconocimiento y la voz.
  Map<String, String> get _lang => {'lang': LanguageSettings.current.code};

  @override
  Future<void> stopSpeaking() => _call('stopSpeaking');

  Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      debugPrint('Voz ($method): $e');
    }
  }
}
