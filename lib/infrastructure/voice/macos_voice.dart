import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/assistant/voice.dart';

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
      return await _channel.invokeMethod<String>('start');
    } catch (e) {
      debugPrint('Voz: $e');
      return 'unavailable';
    }
  }

  @override
  Future<String?> startWake(String name) async {
    try {
      return await _channel.invokeMethod<String>('startWake', name);
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
  Future<void> speak(String text) => _call('speak', text);

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
