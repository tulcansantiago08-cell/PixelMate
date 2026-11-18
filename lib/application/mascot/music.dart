import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assistant/video_finder.dart';
import 'mascot_settings.dart';

/// Lo que suena en Spotify o Música.
class NowPlaying {
  final String source;
  final bool playing;
  final String title;
  final String artist;

  const NowPlaying(
      {required this.source,
      required this.playing,
      this.title = '',
      this.artist = ''});

  factory NowPlaying.fromMap(Map<Object?, Object?> m) => NowPlaying(
        source: m['source'] as String? ?? '',
        playing: (m['state'] as String? ?? '').toLowerCase() == 'playing',
        title: (m['title'] as String? ?? '').trim(),
        artist: (m['artist'] as String? ?? '').trim(),
      );

  /// Identifica la canción (para no anunciar dos veces la misma).
  String get songKey => '$title|$artist';
}

/// Estado de la música y cuándo anunciar una canción nueva.
class MusicState {
  /// Lo último que se supo (o `null` si nunca sonó nada).
  final NowPlaying? now;

  /// Sube cada vez que empieza una canción distinta.
  final int announce;

  const MusicState({this.now, this.announce = 0});

  bool get playing => now?.playing ?? false;
}

/// Sigue los avisos de las apps de música. Al pausar y reanudar la misma
/// canción no la vuelve a anunciar.
class MusicController extends StateNotifier<MusicState> {
  StreamSubscription<NowPlaying>? _sub;
  String? _lastAnnounced;
  Timer? _videoEnds;

  /// Si YouTube no dio la duración, se baila este tiempo.
  static const defaultVideoLength = Duration(minutes: 4);

  /// Tope (por si es un video muy largo, como una lista de una hora).
  static const maxVideoLength = Duration(minutes: 10);

  /// Modo discoteca pedido en el chat: baila [length] aunque no suene nada
  /// (también durante el enfoque, porque se pidió).
  void startDisco(Duration length) {
    state = MusicState(
        now: const NowPlaying(source: 'disco', playing: true),
        announce: state.announce);
    _videoEnds?.cancel();
    _videoEnds = Timer(length, () {
      if (state.now?.source == 'disco') stopDancing();
    });
  }

  /// Deja de bailar ya (el video de YouTube o la discoteca).
  void stopDancing() {
    _videoEnds?.cancel();
    final now = state.now;
    if (now == null || !now.playing) return;
    state = MusicState(
        now: NowPlaying(source: now.source, playing: false, title: now.title),
        announce: state.announce);
  }

  /// `true` si es el modo discoteca pedido (no música).
  bool get disco => state.now?.source == 'disco' && state.playing;

  /// La mascota puso un video en el navegador: el navegador no avisa cuándo
  /// suena ni cuándo termina, así que se baila lo que dura el video.
  void playedByAssistant(FoundVideo video) {
    var length = video.length ?? defaultVideoLength;
    if (length > maxVideoLength) length = maxVideoLength;
    final song = NowPlaying(
        source: 'youtube', playing: true, title: video.title, artist: '');
    onEvent(song);
    _videoEnds?.cancel();
    _videoEnds = Timer(length, () {
      final now = state.now;
      if (now != null && now.source == 'youtube' && now.playing) {
        state = MusicState(
            now:
                NowPlaying(source: 'youtube', playing: false, title: now.title),
            announce: state.announce);
      }
    });
  }

  MusicController(Stream<NowPlaying> events) : super(const MusicState()) {
    _sub = events.listen(onEvent);
  }

  void onEvent(NowPlaying e) {
    // Si empieza Spotify o Música, manda sobre el video de YouTube.
    if (e.source != 'youtube' && e.playing) _videoEnds?.cancel();
    // Si una app pausa mientras otra sigue sonando, manda la que suena.
    final current = state.now;
    if (!e.playing &&
        current != null &&
        current.playing &&
        current.source != e.source) {
      return;
    }
    final isNew =
        e.playing && e.title.isNotEmpty && e.songKey != _lastAnnounced;
    if (isNew) _lastAnnounced = e.songKey;
    state = MusicState(now: e, announce: state.announce + (isNew ? 1 : 0));
  }

  @override
  void dispose() {
    _videoEnds?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// Se sobrescribe en `main()` con los avisos de macOS.
final musicEventsProvider =
    Provider<Stream<NowPlaying>>((_) => const Stream.empty());

final musicProvider = StateNotifierProvider<MusicController, MusicState>(
    (ref) => MusicController(ref.watch(musicEventsProvider)));

/// `true` si hay música y la mascota tiene permiso para reaccionar.
final musicPlayingProvider = Provider<bool>((ref) {
  final settings = ref.watch(mascotSettingsProvider);
  final music = ref.watch(musicProvider);
  // El modo discoteca se pidió a propósito: va aunque el ajuste esté apagado.
  if (music.playing && music.now?.source == 'disco') return true;
  return settings.musicReactions && music.playing;
});

/// `true` mientras dura el modo discoteca pedido en el chat.
final discoModeProvider = Provider<bool>((ref) {
  final music = ref.watch(musicProvider);
  return music.playing && music.now?.source == 'disco';
});

const _openers = [
  '¡Temazo! 🎶',
  '¡A bailar! 💃',
  '🎵 Suena',
  '¡Me encanta esta! 🎧',
  '¡Qué ritmo! 🕺',
  '🪩 ¡Modo discoteca!',
];

/// Lo que dice la mascota al empezar una canción ([n] cambia la frase).
String songMessage(NowPlaying song, int n) {
  final opener = _openers[n % _openers.length];
  final who = song.artist.isEmpty ? '' : ' — ${song.artist}';
  return '$opener ${song.title}$who';
}
