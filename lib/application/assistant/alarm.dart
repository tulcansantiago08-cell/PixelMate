import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/sounds.dart';
import '../mascot/mascot_settings.dart';
import 'personal_store.dart';
import 'voice.dart';

/// Alarmas sonando ahora mismo.
class AlarmState {
  final List<ReminderItem> ringing;

  /// Cuándo empezó a sonar.
  final DateTime? since;

  const AlarmState([this.ringing = const [], this.since]);

  bool get active => ringing.isNotEmpty;

  /// "Reunión virtual" o "Reunión virtual · Tomar agua".
  String get text => ringing.map((r) => r.text).join(' · ');
}

/// Hace sonar las alarmas: un bip que se repite hasta que las apagas o
/// pospones (o, como mucho, [maxRing]), y dice en voz alta qué toca.
class AlarmController extends StateNotifier<AlarmState> {
  final PersonalStore _store;
  final SoundPlayer _sound;
  final void Function(String text)? speak;

  /// Registro para diagnosticar.
  final void Function(String line)? log;
  final DateTime Function() _now;

  /// Cada cuánto suena el bip.
  final Duration every;

  /// Lo más que suena si nadie la apaga.
  final Duration maxRing;

  /// Lo que se pospone si no se dice cuánto.
  static const defaultSnooze = 5;

  Timer? _loop;
  Timer? _limit;

  AlarmController(this._store, this._sound,
      {this.speak,
      this.log,
      DateTime Function()? now,
      this.every = const Duration(milliseconds: 1800),
      this.maxRing = const Duration(minutes: 3)})
      : _now = now ?? DateTime.now,
        super(const AlarmState());

  /// Empieza a sonar (o añade más alarmas a las que ya suenan).
  void ring(List<ReminderItem> items) {
    log?.call('ring ${items.length} (mounted: $mounted)');
    if (items.isEmpty || !mounted) return;
    final wasActive = state.active;
    state = AlarmState([...state.ringing, ...items], state.since ?? _now());
    if (!wasActive) {
      unawaited(_sound.play(PetSound.alarm));
      _loop = Timer.periodic(every, (_) => _sound.play(PetSound.alarm));
    }
    // Cada alarma nueva suena su tiempo completo.
    _limit?.cancel();
    _limit = Timer(maxRing, _silence);
    speak?.call(alarmSpeech(items, _now()));
  }

  /// Apaga la alarma. `false` si no sonaba ninguna.
  Future<bool> stop() async {
    if (!state.active) return false;
    _silence();
    return true;
  }

  /// La vuelve a sonar en [minutes] minutos. `false` si no sonaba ninguna.
  Future<bool> snooze([int minutes = defaultSnooze]) async {
    if (!state.active) return false;
    final items = state.ringing;
    _silence();
    final when = _now().add(Duration(minutes: minutes.clamp(1, 120)));
    for (final r in items) {
      await _store.addReminder(r.text, when, alarm: true);
    }
    return true;
  }

  void _silence() {
    _loop?.cancel();
    _limit?.cancel();
    _loop = null;
    _limit = null;
    if (mounted) state = const AlarmState();
  }

  @override
  void dispose() {
    _loop?.cancel();
    _limit?.cancel();
    super.dispose();
  }
}

String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// "Son las 8:00. Reunión virtual."
String alarmSpeech(List<ReminderItem> items, DateTime now) =>
    'Son las ${_hm(now)}. ${items.map((r) => r.text).join('. ')}.';

/// Registro de diagnóstico de la app. Se sobrescribe en `main()`.
final appLogProvider = Provider<void Function(String line)>((_) => (_) {});

final alarmProvider = StateNotifierProvider<AlarmController, AlarmState>(
  (ref) => AlarmController(
    ref.watch(personalStoreProvider),
    ref.watch(soundPlayerProvider),
    log: ref.watch(appLogProvider),
    speak: (text) {
      if (ref.read(mascotSettingsProvider).voiceReplies) {
        unawaited(ref.read(voicePortProvider).speak(speechText(text)));
      }
    },
  ),
);
