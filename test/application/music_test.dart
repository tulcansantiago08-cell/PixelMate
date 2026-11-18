import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/video_finder.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/mascot/music.dart';
import 'package:pixelmate/presentation/mascot/music_dance.dart';

NowPlaying song(String title,
        {bool playing = true,
        String source = 'spotify',
        String artist = 'Feid'}) =>
    NowPlaying(source: source, playing: playing, title: title, artist: artist);

void main() {
  test('lee el aviso de Spotify y Música', () {
    final s = NowPlaying.fromMap({
      'source': 'music',
      'state': 'Playing',
      'title': ' Paradise ',
      'artist': 'Feid',
    });
    expect(s.playing, isTrue);
    expect(s.title, 'Paradise');
    expect(NowPlaying.fromMap({'state': 'Paused'}).playing, isFalse);
    expect(NowPlaying.fromMap({}).playing, isFalse);
  });

  test('anuncia cada canción nueva una vez, no al pausar y reanudar', () {
    final c = MusicController(const Stream.empty());
    addTearDown(c.dispose);
    c.onEvent(song('Paradise'));
    expect(c.state.playing, isTrue);
    expect(c.state.announce, 1);

    c.onEvent(song('Paradise', playing: false));
    expect(c.state.playing, isFalse);
    c.onEvent(song('Paradise'));
    expect(c.state.announce, 1, reason: 'misma canción');

    c.onEvent(song('Normal'));
    expect(c.state.announce, 2);
    expect(c.state.now!.title, 'Normal');
  });

  test('si otra app pausa, sigue mandando la que suena', () {
    final c = MusicController(const Stream.empty());
    addTearDown(c.dispose);
    c.onEvent(song('Paradise', source: 'spotify'));
    c.onEvent(song('Otra', source: 'music', playing: false));
    expect(c.state.playing, isTrue);
    expect(c.state.now!.source, 'spotify');
  });

  test('sin título no anuncia nada (pero cuenta como música)', () {
    final c = MusicController(const Stream.empty());
    addTearDown(c.dispose);
    c.onEvent(const NowPlaying(source: 'music', playing: true));
    expect(c.state.playing, isTrue);
    expect(c.state.announce, 0);
  });

  test('el ajuste apaga la reacción', () async {
    final events = StreamController<NowPlaying>();
    addTearDown(events.close);
    final settings = MascotSettings();
    final container = ProviderContainer(overrides: [
      musicEventsProvider.overrideWithValue(events.stream),
      mascotSettingsProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);
    expect(container.read(musicPlayingProvider), isFalse);
    events.add(song('Paradise'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(musicPlayingProvider), isTrue);
    await settings.setMusicReactions(false);
    container.invalidate(musicPlayingProvider);
    expect(container.read(musicPlayingProvider), isFalse);
  });

  test('mensaje de la canción', () {
    expect(songMessage(song('Paradise'), 0), contains('Paradise — Feid'));
    expect(songMessage(song('Solo', artist: ''), 3), endsWith('Solo'));
    expect(songMessage(song('A'), 1), isNot(songMessage(song('A'), 2)));
  });

  testWidgets('con YouTube baila lo que dura el video', (tester) async {
    final c = MusicController(const Stream.empty());
    addTearDown(c.dispose);
    c.playedByAssistant(const FoundVideo('abc', 'Feid - Paradise',
        length: Duration(minutes: 3)));
    expect(c.state.playing, isTrue);
    expect(c.state.announce, 1);
    expect(c.state.now!.title, 'Feid - Paradise');
    await tester.pump(const Duration(minutes: 2, seconds: 59));
    expect(c.state.playing, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(c.state.playing, isFalse, reason: 'terminó el video');

    // Sin duración: 4 minutos; muy largo: tope de 10.
    c.playedByAssistant(const FoundVideo('def', 'Otra'));
    await tester.pump(const Duration(minutes: 4, seconds: 1));
    expect(c.state.playing, isFalse);
    c.playedByAssistant(
        const FoundVideo('ghi', 'Mix 1 hora', length: Duration(hours: 1)));
    await tester.pump(const Duration(minutes: 10, seconds: 1));
    expect(c.state.playing, isFalse);
  });

  testWidgets('si luego suena Spotify, el video no la detiene', (tester) async {
    final c = MusicController(const Stream.empty());
    addTearDown(c.dispose);
    c.playedByAssistant(
        const FoundVideo('abc', 'Video', length: Duration(minutes: 1)));
    c.onEvent(song('Paradise'));
    await tester.pump(const Duration(minutes: 2));
    expect(c.state.playing, isTrue);
    expect(c.state.now!.source, 'spotify');
  });

  test('modo discoteca: un rato, aunque el ajuste esté apagado', () async {
    final settings = MascotSettings();
    await settings.setMusicReactions(false);
    final container = ProviderContainer(overrides: [
      mascotSettingsProvider.overrideWithValue(settings),
    ]);
    addTearDown(container.dispose);
    final music = container.read(musicProvider.notifier);
    music.startDisco(const Duration(milliseconds: 50));
    expect(container.read(musicPlayingProvider), isTrue);
    expect(container.read(discoModeProvider), isTrue);
    expect(container.read(musicProvider).announce, 0, reason: 'sin canción');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(container.read(discoModeProvider), isFalse, reason: 'se acabó');

    music.startDisco(const Duration(minutes: 1));
    music.stopDancing();
    expect(container.read(musicPlayingProvider), isFalse);
  });

  test('la coreografía cambia cada compás', () {
    final bar = MusicDance.bar.inMilliseconds / 1000;
    final moves = [for (var i = 0; i < 4; i++) danceFrame(i * bar + 0.1).move];
    expect(moves, DanceMove.values);
    expect(danceFrame(4 * bar + 0.1).move, DanceMove.sideSteps,
        reason: 'vuelve a empezar');
    // En el giro, a mitad de compás está de espaldas.
    expect(danceFrame(2 * bar + bar / 2).scaleX, closeTo(-1, 0.01));
    // En los saltos sube bastante.
    expect(danceFrame(3 * bar + bar / 8).dy, lessThan(-10));
  });

  testWidgets('pista de discoteca solo con música', (tester) async {
    final armsSeen = <bool>{};
    Widget build(bool dancing) => MaterialApp(
          home: Center(
            child: MusicDance(
              dancing: dancing,
              builder: (_, armsUp) {
                armsSeen.add(armsUp);
                return const SizedBox.square(dimension: 160);
              },
            ),
          ),
        );
    await tester.pumpWidget(build(false));
    expect(find.byKey(const ValueKey('disco-floor')), findsNothing);
    await tester.pumpWidget(build(true));
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 66));
    }
    expect(find.byKey(const ValueKey('disco-floor')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-notes')), findsOneWidget);
    expect(armsSeen, containsAll([true, false]),
        reason: 'brazos arriba en la pose y abajo en los pasos');
    await tester.pumpWidget(build(false));
    expect(find.byKey(const ValueKey('disco-floor')), findsNothing);
  });
}
