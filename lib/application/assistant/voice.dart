import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mascot/mascot_settings.dart';
import 'chat_controller.dart';

/// Qué llega del reconocimiento de voz.
enum VoiceEventType {
  /// Lo que lleva entendido (cambia mientras hablas).
  partial,

  /// El texto final.
  done,

  /// Terminó sin texto final (silencio o error).
  end,

  /// Oyó «oye <nombre>»: empieza a escuchar (el texto es lo dicho después).
  wake,

  /// No pudo seguir esperando el nombre (el texto es el código de error).
  wakeError,
}

class VoiceEvent {
  final VoiceEventType type;
  final String text;
  const VoiceEvent(this.type, [this.text = '']);

  /// Desde el mapa del canal nativo; `null` si no se entiende.
  static VoiceEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = switch (raw['type']) {
      'partial' => VoiceEventType.partial,
      'done' => VoiceEventType.done,
      'end' => VoiceEventType.end,
      'wake' => VoiceEventType.wake,
      'wakeError' => VoiceEventType.wakeError,
      _ => null,
    };
    if (type == null) return null;
    return VoiceEvent(type, (raw['text'] as String?) ?? '');
  }
}

/// El micrófono y la voz del Mac (ver `Voice.swift`).
abstract class VoicePort {
  /// Empieza a escuchar. `null` si va bien; si no, un código de error
  /// (ver [voiceProblem]).
  Future<String?> start();

  /// Deja de escuchar: llega el texto final.
  Future<void> stop();

  /// Deja de escuchar sin texto.
  Future<void> cancel();

  Stream<VoiceEvent> get events;

  /// Espera a oír «oye/hola [name]» (solo reconociendo en el Mac). `null`
  /// si va bien; si no, un código de error.
  Future<String?> startWake(String name);
  Future<void> stopWake();

  Future<void> speak(String text);
  Future<void> stopSpeaking();
}

/// Sin voz (pruebas y otros sistemas).
class NoVoice implements VoicePort {
  const NoVoice();
  @override
  Future<String?> start() async => 'unavailable';
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Stream<VoiceEvent> get events => const Stream.empty();
  @override
  Future<String?> startWake(String name) async => 'unavailable';
  @override
  Future<void> stopWake() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stopSpeaking() async {}
}

/// Qué decir cuando no se puede escuchar.
String voiceProblem(String code) => switch (code) {
      'speech-denied' => '🎙️ Para entenderte necesito permiso: Ajustes del '
          'Sistema › Privacidad y seguridad › Reconocimiento de voz › '
          'activa PixelMate.',
      'mic-denied' => '🎙️ No puedo usar el micrófono: Ajustes del Sistema › '
          'Privacidad y seguridad › Micrófono › activa PixelMate.',
      'mic' => '🎙️ No encuentro ningún micrófono conectado.',
      'offline' => '🎙️ Para esperar a que me llames necesito entender español '
          'sin internet: Ajustes del Sistema › Teclado › Dictado, activa el '
          'dictado en español y deja que se descargue.',
      _ => '🎙️ El reconocimiento de voz en español no está disponible ahora. '
          'Revisa tu conexión o activa el dictado en Ajustes del Sistema › '
          'Teclado.',
    };

/// Texto para leer en voz alta: sin emojis ni símbolos que la voz
/// pronunciaría raro, y no demasiado largo.
String speechText(String text, {int maxLength = 400}) {
  var s = text
      .replaceAll(
          RegExp(
              r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
              r'\u{FE0F}\u{200D}\u{20E3}\u{2190}-\u{21FF}\u{2300}-\u{23FF}]',
              unicode: true),
          '')
      .replaceAll(RegExp(r'[*_`#•›«»]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length <= maxLength) return s;
  // Corta en el último final de frase que quepa.
  final cut = s.substring(0, maxLength);
  final end = cut.lastIndexOf(RegExp(r'[.!?]'));
  return end > maxLength ~/ 3 ? cut.substring(0, end + 1) : '$cut…';
}

enum VoiceStatus { idle, listening, thinking }

class VoiceState {
  final VoiceStatus status;

  /// Lo que lleva entendido mientras escucha.
  final String heard;

  /// Por qué no se pudo (se muestra en el chat).
  final String? problem;

  const VoiceState(
      {this.status = VoiceStatus.idle, this.heard = '', this.problem});

  bool get listening => status == VoiceStatus.listening;
}

/// Hablarle a la mascota: escucha, deja de escuchar sola cuando te callas,
/// manda lo que dijiste al chat y, si está activado, lee la respuesta.
class VoiceController extends StateNotifier<VoiceState> {
  final VoicePort _port;

  /// Manda lo que dijiste y devuelve la respuesta (o `null`).
  final Future<String?> Function(String text) onHeard;

  /// Si hay que leer la respuesta en voz alta.
  final bool Function() speakReplies;

  /// Silencio tras hablar con el que se da por terminada la frase.
  final Duration silence;

  /// Tiempo máximo esperando a que empieces a hablar.
  final Duration waitForSpeech;

  /// Lo más largo que escucha seguido.
  final Duration maxLength;

  /// Despertarla con «oye <nombre>».
  bool _wakeEnabled = false;
  String _wakeName = '';
  bool _wakeArmed = false;

  StreamSubscription<VoiceEvent>? _sub;
  Timer? _silenceTimer;
  Timer? _maxTimer;
  bool _handled = false;

  VoiceController(
    this._port, {
    required this.onHeard,
    required this.speakReplies,
    this.silence = const Duration(milliseconds: 1600),
    this.waitForSpeech = const Duration(seconds: 8),
    this.maxLength = const Duration(seconds: 30),
  }) : super(const VoiceState()) {
    _sub = _port.events.listen(_onEvent);
  }

  /// El botón del micrófono o ⌃⌥V: empieza a escuchar o, si ya escucha,
  /// termina la frase.
  Future<void> toggle() async {
    if (state.listening) return finish();
    if (state.status == VoiceStatus.idle) return listen();
  }

  /// Activa o apaga el modo «oye <nombre>».
  Future<void> configureWake(
      {required bool enabled, required String name}) async {
    final changed = enabled != _wakeEnabled || name != _wakeName;
    _wakeEnabled = enabled;
    _wakeName = name;
    if (!changed) return;
    if (!enabled) {
      _wakeArmed = false;
      await _port.stopWake();
      return;
    }
    _wakeArmed = false;
    await _armWake();
  }

  bool get wakeEnabled => _wakeEnabled;

  Future<void> _armWake() async {
    if (!_wakeEnabled || !mounted || state.status != VoiceStatus.idle) return;
    if (_wakeArmed) return;
    _wakeArmed = true;
    final problem = await _port.startWake(_wakeName);
    if (problem != null && mounted) {
      _wakeArmed = false;
      _wakeEnabled = false;
      state = VoiceState(problem: voiceProblem(problem));
    }
  }

  Future<void> listen() async {
    if (state.status != VoiceStatus.idle) return;
    _wakeArmed = false;
    _handled = false;
    state = const VoiceState(status: VoiceStatus.listening);
    final problem = await _port.start();
    if (!mounted) return;
    if (problem != null) {
      _clearTimers();
      state = VoiceState(problem: voiceProblem(problem));
      unawaited(_armWake());
      return;
    }
    _silenceTimer = Timer(waitForSpeech, finish);
    _maxTimer = Timer(maxLength, finish);
  }

  /// Deja de escuchar y usa lo entendido.
  Future<void> finish() async {
    if (!state.listening) return;
    _clearTimers();
    // Por si el Mac no manda el texto final: se usa lo entendido.
    _maxTimer = Timer(const Duration(seconds: 4), () {
      if (state.listening && !_handled) unawaited(_heard(state.heard));
    });
    await _port.stop();
  }

  /// Deja de escuchar sin mandar nada.
  Future<void> cancel() async {
    if (!mounted) return;
    _clearTimers();
    _handled = true;
    if (state.listening) await _port.cancel();
    if (mounted) state = const VoiceState();
    unawaited(_armWake());
  }

  void _onEvent(VoiceEvent e) {
    if (e.type == VoiceEventType.wakeError) {
      _wakeArmed = false;
      _wakeEnabled = false;
      if (state.status == VoiceStatus.idle) {
        state = VoiceState(problem: voiceProblem(e.text));
      }
      return;
    }
    if (e.type == VoiceEventType.wake) {
      if (state.status != VoiceStatus.idle) return;
      _wakeArmed = false;
      _handled = false;
      state = VoiceState(status: VoiceStatus.listening, heard: e.text);
      _silenceTimer =
          Timer(e.text.trim().isEmpty ? waitForSpeech : silence, finish);
      _maxTimer = Timer(maxLength, finish);
      return;
    }
    if (!state.listening || _handled) return;
    switch (e.type) {
      case VoiceEventType.partial:
        state = VoiceState(status: VoiceStatus.listening, heard: e.text);
        if (e.text.trim().isNotEmpty) {
          _silenceTimer?.cancel();
          _silenceTimer = Timer(silence, finish);
        }
      case VoiceEventType.done:
        unawaited(_heard(e.text));
      case VoiceEventType.end:
        unawaited(_heard(state.heard));
      case VoiceEventType.wake || VoiceEventType.wakeError:
        break; // ya atendidos arriba
    }
  }

  Future<void> _heard(String text) async {
    _handled = true;
    _clearTimers();
    final said = text.trim();
    if (said.isEmpty) {
      state = const VoiceState(
          problem: '🙉 No te escuché. Toca 🎙️ y habla cuando quieras.');
      unawaited(_armWake());
      return;
    }
    state = VoiceState(status: VoiceStatus.thinking, heard: said);
    String? reply;
    try {
      reply = await onHeard(said);
    } finally {
      if (mounted) state = const VoiceState();
    }
    if (reply != null && speakReplies()) {
      final spoken = speechText(reply);
      if (spoken.isNotEmpty) await _port.speak(spoken);
    }
    await _armWake();
  }

  /// Calla la voz (por ejemplo, al cerrar el chat).
  Future<void> quiet() => _port.stopSpeaking();

  void _clearTimers() {
    _silenceTimer?.cancel();
    _maxTimer?.cancel();
    _silenceTimer = null;
    _maxTimer = null;
  }

  @override
  void dispose() {
    if (_wakeEnabled) _port.stopWake();
    _clearTimers();
    _sub?.cancel();
    super.dispose();
  }
}

/// El micrófono del Mac. Se sobrescribe en `main()`.
final voicePortProvider = Provider<VoicePort>((_) => const NoVoice());

final voiceProvider = StateNotifierProvider<VoiceController, VoiceState>((ref) {
  return VoiceController(
    ref.watch(voicePortProvider),
    onHeard: (text) async {
      final before = ref.read(chatProvider).length;
      await ref.read(chatProvider.notifier).send(text);
      final messages = ref.read(chatProvider);
      if (messages.length <= before || messages.last.isUser) return null;
      return messages.last.text;
    },
    speakReplies: () => ref.read(mascotSettingsProvider).voiceReplies,
  );
});
